// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { UniversalGaslessDelegationHelper, UniversalGaslessDelegate } from "./UniversalGaslessDelegationHelper.sol";
import { LibErrors } from "../src/library/LibErrors.sol";
import { NonceStorage } from "../src/library/NonceStorageStruct.sol";
import "./mocks/MockKillSwitch.sol";

/**
 * @title Universal Gasless Delegate (UGD) NonceBitmap Test
 * @dev Test suite for the NonceBitmap functionality in the UniversalGaslessDelegate contract
 */
contract UGDNonceBitmapTest is Test, UniversalGaslessDelegationHelper {
    address public userA;
    uint256 private userAPrivateKey;
    UniversalGaslessDelegate private delegatedAccount;

    function setUp() public {
        // Set up user with makeAddrAndKey
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        vm.deal(userA, 10 ether);

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
    //                   POSITIVE TEST CASES
    // =============================================================

    /**
     * @dev Test that GetNonceBitmap returns the correct bitmap value
     */
    function test_GetNonceBitmap() public {
        // Initially all nonces are unused (bitmap is 0)
        assertEq(delegatedAccount.getNonceBitmap(0), 0, "Initial bitmap should be 0");

        // Use a nonce
        uint256 nonce = 5; // bit position 5 in word 0
        vm.prank(userA);
        delegatedAccount.invalidateNonce(nonce);

        // The bitmap should now have the bit at position 5 set to 1
        uint256 expectedBitmap = 1 << 5;
        assertEq(delegatedAccount.getNonceBitmap(0), expectedBitmap, "Bitmap should have bit 5 set");
    }

    /**
     * @dev Test that isNonceUsed correctly identifies used and unused nonces
     * NOTE: A Harness test for the internal function has been created. Test not removed from here for completeness.
     */
    function test_IsNonceUsed() public {
        uint256 nonce = 100; // bit position 100 in word 0

        // Initially nonce should be unused
        assertFalse(delegatedAccount.isNonceUsed(nonce), "Nonce should initially be unused");

        // Use the nonce
        vm.prank(userA);
        delegatedAccount.invalidateNonce(nonce);

        // Now the nonce should be marked as used
        assertTrue(delegatedAccount.isNonceUsed(nonce), "Nonce should be marked as used after using it");
    }

    /**
     * @dev Test invalidateNonce function
     */
    function test_InvalidateNonce() public {
        uint256 nonce = 42; // Use nonce 42

        // Initially nonce should be unused
        assertFalse(delegatedAccount.isNonceUsed(nonce), "Nonce should initially be unused");

        // Invalidate the nonce
        vm.prank(userA);
        delegatedAccount.invalidateNonce(nonce);

        // Now the nonce should be marked as used
        assertTrue(delegatedAccount.isNonceUsed(nonce), "Nonce should be marked as used after invalidation");
    }

    /**
     * @dev Test that multiple nonces can be used in the same word
     */
    function test_MultipleNoncesInSameWord() public {
        // Use multiple nonces in same word
        vm.startPrank(userA);
        delegatedAccount.invalidateNonce(10);
        delegatedAccount.invalidateNonce(20);
        delegatedAccount.invalidateNonce(30);
        vm.stopPrank();

        // Check that all are marked as used
        assertTrue(delegatedAccount.isNonceUsed(10), "Nonce 10 should be used");
        assertTrue(delegatedAccount.isNonceUsed(20), "Nonce 20 should be used");
        assertTrue(delegatedAccount.isNonceUsed(30), "Nonce 30 should be used");

        // Check bitmap has all bits set
        uint256 expectedBitmap = (1 << 10) | (1 << 20) | (1 << 30);
        assertEq(delegatedAccount.getNonceBitmap(0), expectedBitmap, "Bitmap should have bits 10, 20, and 30 set");
    }

    /**
     * @dev Test nonces across different words
     */
    function test_NoncesAcrossDifferentWords() public {
        // Use nonces in different words
        uint256 nonceInWord0 = 42; // Bit position 42 in word 0
        uint256 nonceInWord1 = (1 << 8) | 42; // Bit position 42 in word 1
        uint256 nonceInWord2 = (2 << 8) | 42; // Bit position 42 in word 2

        vm.startPrank(userA);
        delegatedAccount.invalidateNonce(nonceInWord0);
        delegatedAccount.invalidateNonce(nonceInWord1);
        delegatedAccount.invalidateNonce(nonceInWord2);
        vm.stopPrank();

        // Check that all are marked as used
        assertTrue(delegatedAccount.isNonceUsed(nonceInWord0), "Nonce in word 0 should be used");
        assertTrue(delegatedAccount.isNonceUsed(nonceInWord1), "Nonce in word 1 should be used");
        assertTrue(delegatedAccount.isNonceUsed(nonceInWord2), "Nonce in word 2 should be used");

        // Check bitmaps in each word
        uint256 expectedBit = 1 << 42;
        assertEq(delegatedAccount.getNonceBitmap(0), expectedBit, "Bitmap for word 0 should have bit 42 set");
        assertEq(delegatedAccount.getNonceBitmap(1), expectedBit, "Bitmap for word 1 should have bit 42 set");
        assertEq(delegatedAccount.getNonceBitmap(2), expectedBit, "Bitmap for word 2 should have bit 42 set");
    }

    // =============================================================
    //                   NEGATIVE TEST CASES
    // =============================================================

    /**
     * @dev Test that invalidating an already invalidated nonce reverts
     */
    function test_RevertWhen_InvalidatingAlreadyInvalidatedNonce() public {
        uint256 nonce = 123;

        // Invalidate the nonce
        vm.startPrank(userA);
        delegatedAccount.invalidateNonce(nonce);
        // Attempting to invalidate it again should revert
        vm.expectRevert(LibErrors.InvalidNonce.selector);
        delegatedAccount.invalidateNonce(nonce);
        vm.stopPrank();
    }

    /**
     * @dev Test that calling invalidateNonce from a non-self context reverts
     */
    function test_RevertWhen_InvalidatingNonceAsNonSelf() public {
        uint256 nonce = 42;

        // Try to call invalidateNonce from a different address (not the delegated account)
        vm.startPrank(address(0xdead));
        vm.expectRevert(LibErrors.UnauthorizedCaller.selector);
        delegatedAccount.invalidateNonce(nonce);
        vm.stopPrank();
    }

    /**
     * @dev Test that calling invalidateNonce directly on the implementation reverts
     */
    function test_RevertWhen_CallingInvalidateNonceOnImplementationAddress() public {
        uint256 nonce = 42;

        // Try to call invalidateNonce directly on the implementation
        vm.expectRevert(LibErrors.UnauthorizedCallContext.selector);
        gaslessDelegate.invalidateNonce(nonce);
    }

    /**
     * @dev Test that calling getNonceBitmap directly on implementation reverts
     */
    function test_RevertWhen_CallingGetNonceBitmapOnImplementationAddress() public {
        // Try to call getNonceBitmap directly on the implementation
        vm.expectRevert(LibErrors.UnauthorizedCallContext.selector);
        gaslessDelegate.getNonceBitmap(0);
    }

    /**
     * @dev Test that calling isNonceUsed directly on implementation reverts
     */
    function test_RevertWhen_CallingIsNonceUsedOnImplementationAddress() public {
        // Try to call isNonceUsed directly on the implementation
        vm.expectRevert(LibErrors.UnauthorizedCallContext.selector);
        gaslessDelegate.isNonceUsed(42);
    }

    // =============================================================
    //                       FUZZ TESTS
    // =============================================================

    /**
     * @dev Fuzz test for nonce usage
     */
    function testFuzz_NonceUsage(uint248 wordPos, uint8 bitPos) public {
        uint256 nonce = (uint256(wordPos) << 8) | bitPos;

        // Initially nonce should be unused
        assertFalse(delegatedAccount.isNonceUsed(nonce), "Nonce should initially be unused");

        // Use the nonce
        vm.prank(userA);
        delegatedAccount.invalidateNonce(nonce);

        // Now should be marked as used
        assertTrue(delegatedAccount.isNonceUsed(nonce), "Nonce should be marked as used after using it");

        // Check bitmap has the correct bit set
        uint256 expectedBit = 1 << bitPos;
        assertEq(
            delegatedAccount.getNonceBitmap(wordPos) & expectedBit,
            expectedBit,
            "Bitmap should have the correct bit set"
        );
    }
}
