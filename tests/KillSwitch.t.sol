// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { KillSwitch } from "../src/KillSwitch.sol";
// import { KillSwitch } from "../src/flattened/KillSwitch.flat.sol";

contract KillSwitchTest is Test {
    // Contract instance
    KillSwitch internal killSwitch;

    // Test accounts
    address internal killswitchOwner;
    address internal nonOwner;
    address internal zeroAddress = address(0);

    // Events from the contract to test
    event Paused(address account);
    event Unpaused(address account);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        // Create test accounts with labels
        killswitchOwner = makeAddr("killswitchOwner");
        nonOwner = makeAddr("nonOwner");

        // Deploy the KillSwitch contract with owner
        killSwitch = new KillSwitch(killswitchOwner);
    }

    // =============================================
    //             CONSTRUCTOR TESTS
    // =============================================

    function test_constructsCorrectly() public view {
        // Check that the owner has been set correctly
        assertEq(killSwitch.owner(), killswitchOwner, "Owner should be set correctly");

        // Check that initial state is unpaused
        assertFalse(killSwitch.paused(), "Initial state should be unpaused");
    }

    function test_RevertIf_constructWithZeroAddress() public {
        // Attempt to deploy with zero address should revert
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", zeroAddress));
        new KillSwitch(zeroAddress);
    }

    // =============================================
    //                PAUSE TESTS
    // =============================================

    function test_pauseAsOwner() public {
        // Owner should be able to pause the contract
        vm.prank(killswitchOwner);

        // Expect the Paused event to be emitted with the owner address
        vm.expectEmit(true, false, false, false);
        emit Paused(killswitchOwner);

        killSwitch.pause();

        // Verify the contract is paused
        assertTrue(killSwitch.paused(), "Contract should be paused");
    }

    function test_RevertWhen_pauseAsNonOwner() public {
        // Non-owner should not be able to pause the contract
        vm.prank(nonOwner);

        // Should revert with OwnableUnauthorizedAccount error
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        killSwitch.pause();

        // Verify the contract is still unpaused
        assertFalse(killSwitch.paused(), "Contract should remain unpaused");
    }

    function test_RevertIf_pauseWhenAlreadyPaused() public {
        // First pause the contract as owner
        vm.prank(killswitchOwner);
        killSwitch.pause();

        // Attempt to pause again should revert with EnforcedPause error
        vm.prank(killswitchOwner);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        killSwitch.pause();
    }

    // =============================================
    //               UNPAUSE TESTS
    // =============================================

    function test_unpauseAsOwnerWhenPaused() public {
        // First pause the contract
        vm.prank(killswitchOwner);
        killSwitch.pause();

        // Now unpause the contract as owner
        vm.prank(killswitchOwner);

        // Expect the Unpaused event to be emitted with the owner address
        vm.expectEmit(true, false, false, false);
        emit Unpaused(killswitchOwner);

        killSwitch.unpause();

        // Verify the contract is unpaused
        assertFalse(killSwitch.paused(), "Contract should be unpaused");
    }

    function test_RevertIf_unpauseAsNonOwner() public {
        // First pause the contract
        vm.prank(killswitchOwner);
        killSwitch.pause();

        // Non-owner should not be able to unpause the contract
        vm.prank(nonOwner);

        // Should revert with OwnableUnauthorizedAccount error
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        killSwitch.unpause();

        // Verify the contract is still paused
        assertTrue(killSwitch.paused(), "Contract should remain paused");
    }

    function test_RevertIf_unpauseWhenAlreadyUnpaused() public {
        // Contract starts unpaused, so attempting to unpause should revert
        vm.prank(killswitchOwner);
        vm.expectRevert(abi.encodeWithSignature("ExpectedPause()"));
        killSwitch.unpause();
    }

    // =============================================
    //               PAUSED TESTS
    // =============================================

    function test_pausedReturnsFalseWhenNotPaused() public view {
        // By default the contract is not paused
        assertFalse(killSwitch.paused(), "paused() should return false when not paused");
    }

    function test_pausedReturnsTrueWhenPaused() public {
        // Pause the contract first
        vm.prank(killswitchOwner);
        killSwitch.pause();

        // Verify paused() returns true
        assertTrue(killSwitch.paused(), "paused() should return true when paused");
    }

    // =============================================
    //             OWNERSHIP TESTS
    // =============================================

    function test_transferOwnershipAsOwner() public {
        address newOwner = makeAddr("newOwner");
        // Owner should be able to transfer ownership
        vm.prank(killswitchOwner);

        // Expect OwnershipTransferred event
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(killswitchOwner, newOwner);

        killSwitch.transferOwnership(newOwner);

        // Check ownership has been transferred
        assertEq(killSwitch.owner(), newOwner, "Owner should be updated to the new address");
    }

    function test_RevertWhen_transferOwnershipAsNonOwner() public {
        // Non-owner attempting to transfer ownership should revert
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        killSwitch.transferOwnership(nonOwner);

        // Check ownership remains intact
        assertEq(killSwitch.owner(), killswitchOwner, "Owner should remain unchanged");
    }

    function test_renounceOwnershipWhenPaused() public {
        // First pause the contract
        vm.prank(killswitchOwner);
        killSwitch.pause();

        // Owner should be able to renounce ownership when paused
        vm.prank(killswitchOwner);

        // Expect OwnershipTransferred event
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(killswitchOwner, zeroAddress);

        killSwitch.renounceOwnership();

        // Verify ownership has been renounced
        assertEq(killSwitch.owner(), zeroAddress, "Owner should be zero address after renouncing");
    }

    function test_renounceOwnershipWhenNotPaused() public {
        // Contract is not paused by default
        assertFalse(killSwitch.paused(), "Contract should not be paused");

        // Owner should be able to renounce ownership even when not paused
        vm.prank(killswitchOwner);

        // Expect OwnershipTransferred event
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(killswitchOwner, zeroAddress);

        killSwitch.renounceOwnership();

        // Verify ownership has been renounced
        assertEq(killSwitch.owner(), zeroAddress, "Owner should be zero address after renouncing");
    }

    function test_RevertIf_renounceOwnershipAsNonOwner() public {
        // Non-owner should not be able to renounce ownership
        vm.prank(nonOwner);

        // Should revert with OwnableUnauthorizedAccount error
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        killSwitch.renounceOwnership();

        // Check ownership remains intact
        assertEq(killSwitch.owner(), killswitchOwner, "Owner should remain unchanged");
    }

    function test_RevertIf_pauseAfterRenouncingOwnership() public {
        // First pause the contract
        vm.prank(killswitchOwner);
        killSwitch.pause();
        // Renounce ownership
        vm.prank(killswitchOwner);
        killSwitch.renounceOwnership();

        // Verify that pause() now reverts (no owner)
        vm.prank(killswitchOwner); // Using the former owner
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", killswitchOwner));
        killSwitch.pause();
    }

    function test_RevertIf_unpauseAfterRenouncingOwnership() public {
        // First pause the contract
        vm.prank(killswitchOwner);
        killSwitch.pause();
        // Renounce ownership
        vm.prank(killswitchOwner);
        killSwitch.renounceOwnership();

        // Verify that unpause() now reverts (no owner)
        vm.prank(killswitchOwner); // Using the former owner
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", killswitchOwner));
        killSwitch.unpause();
    }

    function test_pausedRespondsAfterRenouncingOwnership() public {
        // First pause the contract
        vm.prank(killswitchOwner);
        killSwitch.pause();

        // Renounce ownership
        vm.prank(killswitchOwner);
        killSwitch.renounceOwnership();

        // Verify paused() still works after renouncing ownership
        assertTrue(killSwitch.paused(), "Contract should remain paused after renouncing ownership");
    }

    // =============================================
    //                   OTHER
    // =============================================

    function test_RevertIf_receivingEther() public {
        // Fund the test account with some ether
        vm.deal(nonOwner, 1 ether);

        vm.prank(nonOwner);
        vm.expectRevert();
        (bool revertsAsExpected,) = address(killSwitch).call{ value: 0.1 ether }("");
        // status set as per Foundry book: Usage with low-level calls
        assertTrue(revertsAsExpected, "expectRevert: call did not revert");
        // Verify the contract balance remains zero
        assertEq(address(killSwitch).balance, 0, "Contract should not hold any ether");
    }
}
