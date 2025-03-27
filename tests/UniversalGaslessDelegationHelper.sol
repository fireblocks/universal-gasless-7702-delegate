// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { CommonBase } from "forge-std/Base.sol";
import { StdAssertions } from "forge-std/StdAssertions.sol";
import { Vm } from "forge-std/Vm.sol";
import { UniversalGaslessDelegate } from "../src/UniversalGaslessDelegate.sol";
import { IKillSwitch } from "../src/interface/IKillSwitch.sol";

/**
 * @title UniversalGaslessDelegationHelper
 * @dev A helper contract for testing EIP-7702 delegations in a Foundry test environment
 */
abstract contract UniversalGaslessDelegationHelper is CommonBase, StdAssertions {
    /// @notice Holds a signed EIP-7702 authorization for an authority account to delegate to an implementation
    // struct SignedDelegation {
    //     uint8 v; // The y-parity of the recovered secp256k1 signature (0 or 1)
    //     bytes32 r; // First 32 bytes of the signature
    //     bytes32 s; // Second 32 bytes of the signature
    //     uint64 nonce; // The current nonce of the authority account at signing time
    //     address implementation; // Address of the contract implementation that will be delegated to
    // }

    UniversalGaslessDelegate gaslessDelegate;
    IKillSwitch killswitchContract;

    /**
     * @dev Sets up a delegation for an EOA to use a specific implementation
     * @param user Address of the EOA that will delegate
     * @param privateKey Private key of the EOA
     * @param implementation Address of the implementation contract to delegate to
     * @return The EOA address (for chaining)
     */
    function setupDelegation(address user, uint256 privateKey, address implementation) public returns (address) {
        // Sign and attach delegation for the user
        vm.startPrank(user);
        vm.signAndAttachDelegation(implementation, privateKey);
        vm.stopPrank();

        // Verify delegation was successful
        bytes memory code = address(user).code;
        require(code.length > 0, "Delegation failed: no code written to user account");

        return user;
    }

    /**
     * @dev Creates a signed delegation for an EOA without attaching it immediately
     * @param privateKey Private key of the EOA
     * @param implementation Address of the implementation contract to delegate to
     * @return signedDelegation The signed delegation that can be attached later
     */
    // function createSignedDelegation(
    //     uint256 privateKey,
    //     address implementation
    // ) public returns (Vm.SignedDelegation memory) {
    //     return vm.signDelegation(implementation, privateKey);
    // }

    /**
     * @dev Attaches a previously signed delegation to an EOA
     * @param signedDelegation The signed delegation to attach
     */
    // function attachDelegation(Vm.SignedDelegation memory signedDelegation) public {
    //     vm.attachDelegation(signedDelegation);
    // }

    /**
     * @dev Helper function to set up an account with ETH balance and delegate to an implementation
     * @param privateKey The private key of the account
     * @param implementation The implementation contract address
     * @param initialBalance The initial ETH balance to set
     * @return The account address
     */
    function setupAccountWithDelegation(
        uint256 privateKey,
        address implementation,
        uint256 initialBalance
    )
        public
        returns (address)
    {
        address account = vm.addr(privateKey);

        // Fund the account with ETH
        vm.deal(account, initialBalance);

        // Set up delegation
        setupDelegation(account, privateKey, implementation);

        return account;
    }

    /**
     * @dev Helper function to execute an operation through a delegated EOA
     * @param executor The address that will execute the transaction
     * @param delegatedEOA The address of the delegated EOA
     * @param target The target contract to call
     * @param value The ETH value to send
     * @param callData The calldata to execute
     * @return success Whether the call was successful
     * @return returnData The data returned by the call
     */
    // function executeAsDelegated(
    //     address executor,
    //     address delegatedEOA,
    //     address target,
    //     uint256 value,
    //     bytes memory callData
    // ) public returns (bool success, bytes memory returnData) {
    //     vm.startPrank(executor);
    //     (success, returnData) = delegatedEOA.call(
    //         abi.encodePacked(bytes4(keccak256("execute(address,uint256,bytes)")),
    //         abi.encode(target, value, callData))
    //     );
    //     vm.stopPrank();
    //     return (success, returnData);
    // }

    /**
     * @dev Verifies that an account has been properly delegated
     * @param account The account to check
     * @param implementation The expected implementation address
     */
    function assertDelegated(address account, address implementation) public view {
        bytes memory code = address(account).code;
        require(code.length > 0, "Account is not delegated");

        // EIP-7702 prefix is 0xef0100 followed by the implementation address
        bytes memory expectedPrefix = hex"ef0100";
        bytes memory actualCode = account.code;

        // Check prefix
        for (uint256 i = 0; i < 3; i++) {
            require(actualCode[i] == expectedPrefix[i], "Invalid delegation prefix");
        }
        // Check implementation address
        address recoveredImplementation;
        assembly {
            recoveredImplementation := mload(add(actualCode, 23))
        }

        assertEq(recoveredImplementation, implementation, "Implementation address mismatch");
    }
}
