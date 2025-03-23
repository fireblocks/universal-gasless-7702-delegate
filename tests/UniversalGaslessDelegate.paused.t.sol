// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { UniversalGaslessDelegationHelper, UniversalGaslessDelegate } from "./UniversalGaslessDelegationHelper.sol";
import { MockKillSwitch } from "./mocks/MockKillSwitch.sol";
import { IKillSwitch } from "../src/interface/IKillSwitch.sol";
import { LibErrors } from "../src/library/LibErrors.sol";

/**
 * @title Universal Gasless Delegate Paused Tests
 * @dev Test suite for the UniversalGaslessDelegate contract in paused state
 */
contract UniversalGaslessDelegatePausedTest is Test, UniversalGaslessDelegationHelper {
    // Test-specific variables
    address public userA;
    uint256 private userAPrivateKey;

    function setUp() public {
        // Set up a user with private key
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        vm.deal(userA, 10 ether);

        // Set up a standard killswitch for the helper
        mockKillswitchContract = address(new MockKillSwitch());

        // Create standard UniversalGaslessDelegate (needed for the helper)
        gaslessDelegate = new UniversalGaslessDelegate(mockKillswitchContract);

        // Pause killswitch specifically for this set of tests
        IKillSwitch(mockKillswitchContract).pause();
    }

    // =============================================================
    //                   NEGATIVE TEST CASES
    // =============================================================

    // 
    /**
     * TODO Turn this into an invariant test as now it is possible to call invalidateNonce while paused, but only
     * from the EOA directly (tx.origin)
     */
    // function test_RevertWhen_InvalidatingNonceWhilePaused() public {
    //     // Set up delegation for userA
    //     address payable delegatedUser = payable(setupDelegation(userA, userAPrivateKey, address(gaslessDelegate)));
    //     // Verify the account is properly delegated
    //     assertDelegated(userA, address(gaslessDelegate));
    //     assertTrue(MockKillSwitch(mockKillswitchContract).paused(), "Killswitch should be paused for this test");
    //     uint256 nonce = 1; // Using an arbitrary nonce value

    //     // Attempt to call invalidateNonce through the delegated user
    //     vm.startPrank(delegatedUser);

    //     // The call should revert with the EnforcedPause error because the contract is paused
    //     vm.expectRevert(LibErrors.EnforcedPause.selector);
    //     UniversalGaslessDelegate(delegatedUser).invalidateNonce(nonce);

    //     vm.stopPrank();
    // }

    // =============================================================
    //                VALUE RECEPTION WHILE PAUSED TESTS
    // =============================================================

    // TODO: Also assert that the Delegated EOA also reports isPaused() == true
    function test_canReceiveEtherWhilePaused() public {
        // Set up delegation for userA
        address delegatedUser = setupDelegation(userA, userAPrivateKey, address(gaslessDelegate));

        // First verify the account is properly delegated
        assertDelegated(delegatedUser, address(gaslessDelegate));
        // Verify the killswitch is actually paused
        assertTrue(MockKillSwitch(mockKillswitchContract).paused(), "Killswitch should be paused for this test");

        // Send ETH directly to the delegated account
        uint256 sendAmount = 1 ether;
        uint256 balanceBefore = address(delegatedUser).balance;

        (bool success,) = delegatedUser.call{ value: sendAmount }("");

        assertTrue(success, "ETH transfer should succeed even when killswitch is paused");
        assertEq(
            address(delegatedUser).balance,
            balanceBefore + sendAmount,
            "Delegated account should receive the ETH even when paused"
        );
    }

    function test_canReceiveEtherWithDataWhilePaused() public {
        // Set up delegation for userA
        address delegatedUser = setupDelegation(userA, userAPrivateKey, address(gaslessDelegate));

        // First verify the account is properly delegated
        assertDelegated(delegatedUser, address(gaslessDelegate));
        // Verify the killswitch is actually paused
        assertTrue(MockKillSwitch(mockKillswitchContract).paused(), "Killswitch should be paused for this test");

        // Send ETH with arbitrary data to trigger the fallback function
        uint256 sendAmount = 1 ether;
        uint256 balanceBefore = address(delegatedUser).balance;

        // Create arbitrary calldata (simulating "memo" or confused interface call)
        bytes memory arbitraryData = abi.encode("This is a memo for the transaction");

        (bool success,) = delegatedUser.call{ value: sendAmount }(arbitraryData);

        assertTrue(success, "ETH transfer with data should succeed even when killswitch is paused");
        assertEq(
            address(delegatedUser).balance,
            balanceBefore + sendAmount,
            "Delegated account should receive the ETH via fallback even when paused"
        );
    }

    /**
     * @notice Test that execute function reverts when the delegate is paused
     */
    function test_RevertWhen_ExecuteWhilePaused() public {
        // Set up delegation for userA to gaslessDelegate
        UniversalGaslessDelegate delegatedAccount = 
            UniversalGaslessDelegate(payable(setupDelegation(userA, userAPrivateKey, address(gaslessDelegate))));

        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));
        // Verify the killswitch is actually paused
        assertTrue(MockKillSwitch(mockKillswitchContract).paused(), "Killswitch should be paused for this test");

        // Set up execution parameters - using a simple mode and empty execution data
        bytes32 mode = bytes32(uint256(0x00000000000078210001) << 22 * 8); 
        bytes memory executionData = abi.encode(bytes("dummy data"));
        
        // Call should revert with EnforcedPause
        vm.expectRevert(LibErrors.EnforcedPause.selector);
        delegatedAccount.execute(mode, executionData);
    }
}
