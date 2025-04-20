// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { ERC7579Utils, Execution } from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { StdChains } from "forge-std/StdChains.sol";
import { UniversalGaslessDelegationHelper, UniversalGaslessDelegate } from "./UniversalGaslessDelegationHelper.sol";
import { MockKillSwitch } from "./mocks/MockKillSwitch.sol";
// import { console2 } from "forge-std/console2.sol";

/**
 * @title UGD Fork Test
 * @dev Tests Universal Gasless Delegate with a USDC transfer on a mainnet fork
 */
contract UGDForkTest is Test, UniversalGaslessDelegationHelper {
    // Test accounts
    address public userA;
    uint256 private userAPrivateKey;
    address public relayerForUser;
    uint256 private relayerForUserPrivateKey;
    UniversalGaslessDelegate private delegatedAccount;

    // Mainnet fork ID
    uint256 private mainnetFork;

    // The specific block number to fork from
    uint256 private constant FORK_BLOCK_NUMBER = 22_122_402;

    // Mainnet USDC contract
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // A sample large USDC holder account
    address private constant USDC_HOLDER = 0x7713974908Be4BEd47172370115e8b1219F4A5f0;

    // Amount of USDC to transfer (one thousand USDC with 6 decimals)
    uint256 private constant TRANSFER_AMOUNT = 1_000_000_000;

    // Sample recipient address
    address private constant RECIPIENT = 0x0000000000000000000000000000000000001234;

    // Constants for typed signatures
    bytes32 private constant _DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 private constant _EXECUTION_TYPEHASH = keccak256("Execution(address target,uint256 value,bytes data)");
    bytes32 private constant _EXECUTION_AUTHORIZATION_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "AuthorizedExecutions(Execution[] calls,uint256 deadline,bytes32 mode,uint256 nonce,address relayer)Execution(address target,uint256 value,bytes data)"
    );

    // Execution mode for single call with authorization
    bytes32 private constant SINGLE_CALL_AUTH_MODE =
        bytes32(0x0000000000007821000100000000000000000000000000000000000000000000);

    function setUp() public {
        // Set up users with private keys
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        (relayerForUser, relayerForUserPrivateKey) = makeAddrAndKey("relayerForUser");

        // Create fork of mainnet at specific block number but don't select it yet
        // Following the best practice of using RPC aliases configured in foundry.toml (unless a mainnet RPC URL is
        // provided in the environment)
        string memory mainnetRpcUrl = vm.envOr("MAINNET_RPC_URL", StdChains.getChain("mainnet").rpcUrl);
        mainnetFork = vm.createFork(mainnetRpcUrl, FORK_BLOCK_NUMBER);
        // Create labels for the forked addresses
        vm.label(USDC, "USDC");
        vm.label(USDC_HOLDER, "LargeUsdcHolder");
    }

    /**
     * @notice Test executing a USDC transfer via the Universal Gasless Delegate on a mainnet fork
     * @dev Creates a mainnet fork and transfers USDC from a large holder account to our delegated account,
     *      then performs an authorized transfer to a recipient through the UGD
     */
    function testFork_ExecuteUSDCTransfer() external {
        // Select the mainnet fork for this test
        vm.selectFork(mainnetFork);
        assertEq(block.number, FORK_BLOCK_NUMBER, "Fork block number should match");
        // Fund accounts with ETH
        vm.deal(userA, 100 ether);
        vm.deal(relayerForUser, 100 ether);

        // Set up mock killswitch in unpaused state
        killswitchContract = new MockKillSwitch();

        // Create UniversalGaslessDelegate
        gaslessDelegate = new UniversalGaslessDelegate(address(killswitchContract));

        // Set up delegation for userA to gaslessDelegate
        delegatedAccount =
            UniversalGaslessDelegate(payable(setupDelegation(userA, userAPrivateKey, address(gaslessDelegate))));
        // Verify delegation was successful
        assertEq(address(delegatedAccount), userA, "Delegated account should be the same as the user account");

        // 1. First get some USDC for our delegated account from a large holder account
        uint256 initialHolderBalance = IERC20(USDC).balanceOf(USDC_HOLDER);
        // console2.log("USDC Holder balance:", initialHolderBalance / 1e6, "USDC");
        // Ensure the holder has enough USDC
        assertGt(initialHolderBalance, TRANSFER_AMOUNT, "Holder doesn't have enough USDC");

        // Impersonate the holder to transfer USDC to our delegated account
        vm.startPrank(USDC_HOLDER);
        IERC20(USDC).transfer(address(delegatedAccount), TRANSFER_AMOUNT);
        vm.stopPrank();

        // Verify our delegated account received the USDC
        uint256 delegatedAccountBalance = IERC20(USDC).balanceOf(address(delegatedAccount));
        assertEq(delegatedAccountBalance, TRANSFER_AMOUNT, "Delegated account did not receive USDC");
        // console2.log("Delegated account balance:", delegatedAccountBalance / 1e6, "USDC");

        // 2. Now prepare an authorized USDC transfer from our delegated account to the recipient

        // USDC transfer calldata
        bytes memory callData = abi.encodeWithSelector(
            IERC20.transfer.selector,
            RECIPIENT,
            TRANSFER_AMOUNT / 2 // Transfer half of the balance
        );

        // Create parameters for our single call
        address target = USDC;
        uint256 value = 0; // No ETH value for ERC20 transfers
        uint256 nonce = 1;
        // Add deadline and relayer parameters
        uint256 deadline = block.timestamp + 1 hours;
        address relayer = relayerForUser;
        // Calculate the EIP-712 typed data hash for signature
        bytes32 digest = _hashTypedSingleExecutionAuth(target, value, callData, nonce, deadline, relayer);

        // Sign with userA's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userAPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        // Prepare execution data
        bytes memory singleExecData = abi.encodePacked(target, value, callData);
        bytes memory opData = abi.encodePacked(nonce, deadline, signature);
        bytes memory executionData = abi.encode(singleExecData, opData);

        // Check recipient's initial balance
        uint256 initialRecipientBalance = IERC20(USDC).balanceOf(RECIPIENT);
        // Note: Would be nice if we could cool account addresses and their slots, but it's not released in forge yet

        // 3. Execute the USDC transfer via the relayer
        vm.startPrank(relayerForUser);
        delegatedAccount.execute(SINGLE_CALL_AUTH_MODE, executionData);
        vm.stopPrank();
        // 4. Verify the transfer was successful
        uint256 finalDelegatedAccountBalance = IERC20(USDC).balanceOf(address(delegatedAccount));
        uint256 finalRecipientBalance = IERC20(USDC).balanceOf(RECIPIENT);

        assertEq(finalDelegatedAccountBalance, TRANSFER_AMOUNT / 2, "Delegated account should have half the USDC");
        assertEq(finalRecipientBalance, initialRecipientBalance + TRANSFER_AMOUNT / 2, "Target did not receive USDC");
        // console2.log("Transfer successful!");
        // console2.log("Delegated account final balance:", finalDelegatedAccountBalance / 1e6, "USDC");
        // console2.log("Recipient balance:", finalRecipientBalance / 1e6, "USDC");
    }

    /**
     * @notice Helper function to calculate the EIP-712 typed data hash for a single execution with auth
     */
    function _hashTypedSingleExecutionAuth(
        address target,
        uint256 value,
        bytes memory data,
        uint256 nonce,
        uint256 deadline,
        address relayer
    )
        internal
        view
        returns (bytes32)
    {
        // Get domain separator using the implementation contract address as verifying contract
        bytes32 domainSeparator = keccak256(abi.encode(_DOMAIN_TYPEHASH, block.chainid, address(gaslessDelegate)));

        // Calculate execution hash
        bytes32 seHash = keccak256(abi.encode(_EXECUTION_TYPEHASH, target, value, keccak256(data)));

        // Package as single item execution array hash
        bytes32 executionsHash = keccak256(abi.encodePacked(seHash));

        // Create final struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                _EXECUTION_AUTHORIZATION_TYPEHASH, executionsHash, deadline, SINGLE_CALL_AUTH_MODE, nonce, relayer
            )
        );

        // Return the EIP-712 typed data hash
        return MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    }
}
