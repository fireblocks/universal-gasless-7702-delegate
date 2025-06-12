// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { UniversalGaslessDelegationHelper, UniversalGaslessDelegate } from "./UniversalGaslessDelegationHelper.sol";
import { LibErrors } from "../src/library/LibErrors.sol";
import { MockKillSwitch } from "./mocks/MockKillSwitch.sol";

/**
 * @title Universal Gasless Delegate (UGD) TypedAuthorization Test
 * @dev Test suite for the TypedAuthorization functionality in a delegated EOA context
 */
contract UGDTypedAuthorizationTest is Test, UniversalGaslessDelegationHelper {
    address public userA;
    uint256 private userAPrivateKey;
    UniversalGaslessDelegate private delegatedAccount;
    address public userB;
    uint256 private userBPrivateKey;
    address public nonDelegatedAccount;

    function setUp() public {
        // Set up users with makeAddrAndKey
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        vm.deal(userA, 10 ether);

        (userB, userBPrivateKey) = makeAddrAndKey("userB");
        vm.deal(userB, 10 ether);

        // Create a non-delegated account for comparison
        nonDelegatedAccount = userB;

        // Set up mock killswitch
        killswitchContract = new MockKillSwitch();

        // Create UniversalGaslessDelegate
        gaslessDelegate = new UniversalGaslessDelegate(address(killswitchContract));

        // Set up delegation for userA to gaslessDelegate
        delegatedAccount =
            UniversalGaslessDelegate(payable(setupDelegation(userA, userAPrivateKey, address(gaslessDelegate))));
        assertEq(address(delegatedAccount), userA, "Delegated account should be the same as the user account");
    }

    // =============================================================
    //                    EIP-712 DOMAIN TESTS
    // =============================================================

    /**
     * @notice Test that the eip712Domain function returns correct values in a delegated context
     */
    function test_Eip712Domain_DelegatedContext() public {
        // Get eip712Domain info from the delegated account
        vm.prank(address(0)); // Use a random sender to ensure it doesn't matter who calls
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = delegatedAccount.eip712Domain();

        // Verify the returned values
        assertEq(fields, hex"0c", "Fields should be 0c (01100)"); // chainId + verifyingContract
        assertEq(name, "", "Name should be empty");
        assertEq(version, "", "Version should be empty");
        assertEq(chainId, block.chainid, "ChainId should match current chain");
        assertEq(verifyingContract, address(gaslessDelegate), "VerifyingContract should be the impl. address");
        assertEq(salt, bytes32(0), "Salt should be empty");
        assertEq(extensions.length, 0, "Extensions should be empty");
    }

    /**
     * @notice Test that the eip712Domain function reverts when called directly on the implementation contract
     */
    function test_RevertsIf_CallingEip712DomainOnImplementation() public {
        vm.expectRevert(LibErrors.UnauthorizedCallContext.selector);
        gaslessDelegate.eip712Domain();
    }

    /**
     * @notice Test that different delegated accounts use the same implementation contract address
     */
    function test_Eip712Domain_DifferentDelegatedAccounts() public {
        // Create a second delegated account
        address userC;
        uint256 userCPrivateKey;
        (userC, userCPrivateKey) = makeAddrAndKey("userC");
        vm.deal(userC, 10 ether);

        UniversalGaslessDelegate delegatedAccountC =
            UniversalGaslessDelegate(payable(setupDelegation(userC, userCPrivateKey, address(gaslessDelegate))));

        // Get eip712Domain info from both delegated accounts
        vm.prank(address(0));
        (,,,, address verifyingContractA,,) = delegatedAccount.eip712Domain();

        vm.prank(address(0));
        (,,,, address verifyingContractC,,) = delegatedAccountC.eip712Domain();

        // Verify that the verifying contracts are the same (both point to the implementation)
        assertEq(
            verifyingContractA,
            address(gaslessDelegate),
            "First account's verifying contract should be the implementation"
        );
        assertEq(
            verifyingContractC,
            address(gaslessDelegate),
            "Second account's verifying contract should be the implementation"
        );
        assertEq(
            verifyingContractA,
            verifyingContractC,
            "Verifying contracts should be the same for all accounts delegating to the same implementation"
        );
    }

    /**
     * @notice Test domain in a forked chain scenario
     */
    function test_Eip712Domain_DifferentChain() public {
        // Get eip712Domain info on the current chain
        vm.prank(address(0));
        (,,, uint256 originalChainId, address originalContract,,) = delegatedAccount.eip712Domain();

        // Simulate a different chain ID
        uint256 newChainId = block.chainid + 1;
        vm.chainId(newChainId);

        // Get the domain info after changing the chain ID
        vm.prank(address(0));
        (,,, uint256 newDomainChainId, address newDomainContract,,) = delegatedAccount.eip712Domain();

        // Verify that the chain ID has changed but the verifying contract remains the same
        assertEq(originalChainId, block.chainid - 1, "Original chain ID should match initial chain ID");
        assertEq(newDomainChainId, newChainId, "New domain chain ID should match new chain ID");
        assertEq(
            originalContract,
            address(gaslessDelegate),
            "Original verifying contract should be the implementation contract"
        );
        assertEq(
            newDomainContract,
            address(gaslessDelegate),
            "New domain verifying contract should still be the implementation contract"
        );
    }
}
