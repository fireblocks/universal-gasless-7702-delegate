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
        mockKillswitchContract = address(new MockKillSwitch());

        // Create UniversalGaslessDelegate
        gaslessDelegate = new UniversalGaslessDelegate(mockKillswitchContract);

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
     * NOTE: Can be replaced with a Harness test of the internal function. This applies to many
     * of the tests in this file.
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
     * @dev Test nextNonce returns the correct next available nonce
     */
    function test_NextNonce() public {
        // Initially nextNonce should be 0
        assertEq(delegatedAccount.nextNonce(), 0, "Initial nextNonce should be 0");

        // Use nonce 0
        vm.prank(userA);
        delegatedAccount.invalidateNonce(0);

        // nextNonce should now be 1
        assertEq(delegatedAccount.nextNonce(), 1, "nextNonce should be 1 after using nonce 0");

        // Use nonce 1 and 2
        vm.startPrank(userA);
        delegatedAccount.invalidateNonce(1);
        delegatedAccount.invalidateNonce(2);
        vm.stopPrank();

        // nextNonce should now be 3
        assertEq(delegatedAccount.nextNonce(), 3, "nextNonce should be 3 after using nonces 0, 1, and 2");
    }

    /**
     * @dev Test nextNonceAfter returns the correct next available nonce after a given nonce
     */
    function test_NextNonceAfter() public {
        // Use nonces 5, 6, and 8
        vm.startPrank(userA);
        delegatedAccount.invalidateNonce(5);
        delegatedAccount.invalidateNonce(6);
        delegatedAccount.invalidateNonce(8);
        vm.stopPrank();

        // Next nonce after 4 should be 7 (since 5 and 6 are used)
        assertEq(delegatedAccount.nextNonceAfter(4), 7, "Next nonce after 4 should be 7");

        // Next nonce after 7 should be 9 (since 8 is used)
        assertEq(delegatedAccount.nextNonceAfter(7), 9, "Next nonce after 7 should be 9");
    }

    /**
     * @dev Test nextNonceAfter handles wraparound to next word correctly
     */
    function test_NextNonceAfter_WordWraparound() public {
        // Use the last nonce in word 0
        uint256 lastNonceInWord0 = 0x00ff; // Position 255 in word 0
        vm.prank(userA);
        delegatedAccount.invalidateNonce(lastNonceInWord0);

        // Next nonce after the last in word 0 should be the first in word 1
        uint256 firstNonceInWord1 = 0x0100; // Position 0 in word 1
        assertEq(
            delegatedAccount.nextNonceAfter(lastNonceInWord0),
            firstNonceInWord1,
            "Next nonce after last in word 0 should be first in word 1"
        );
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

    /**
     * @dev Test finding next nonce when a full word is used
     */
    function test_NextNonceWithPartialWordUsed() public {
        // Fill up a word with used nonces (using a smaller number of positions)
        uint256 wordPos = 5;
        vm.startPrank(userA);

        // Fill just 32 positions for test
        for (uint256 i = 0; i < 32; i++) {
            uint256 nonce = (wordPos << 8) | i;
            delegatedAccount.invalidateNonce(nonce);
        }
        vm.stopPrank();

        // The bitmap should have the right pattern of bits set
        uint256 expectedBitmap = (1 << 32) - 1; // All bits set from 0 to 31
        assertEq(
            delegatedAccount.getNonceBitmap(wordPos) & expectedBitmap,
            expectedBitmap,
            "Bitmap should have the expected bits set"
        );

        // The next nonce should be position 32 in this word
        uint256 expectedNextNonce = (wordPos << 8) | 32;
        assertEq(
            delegatedAccount.nextNonceAfter((wordPos << 8) | 31),
            expectedNextNonce,
            "Next nonce should be the first unused position after the filled section"
        );
    }

    /**
     * @dev Test finding next nonce when a full word is used
     */
    function test_NextNonceWithFullWord() public {
        vm.startPrank(userA);
        // Fill an entire word with used nonces
        uint256 wordPos = 5;
        for (uint256 i = 0; i < 256; i++) {
            uint256 nonce = (wordPos << 8) | i;
            delegatedAccount.invalidateNonce(nonce);
        }
        vm.stopPrank();

        // The bitmap for word 5 should now be all 1's
        assertEq(delegatedAccount.getNonceBitmap(wordPos), type(uint256).max, "Bitmap should be all 1's");

        // The next nonce should be in the next word
        uint256 expectedNextNonce = ((wordPos + 1) << 8) | 0; // First position in next word

        // Get the next nonce after the last nonce in the full word
        uint256 lastNonceInFullWord = (wordPos << 8) | 255;
        uint256 actualNextNonce = delegatedAccount.nextNonceAfter(lastNonceInFullWord);

        assertEq(actualNextNonce, expectedNextNonce, "Next nonce should be in the next word");
    }

    /**
     * @dev Test nextNonce behavior with mixed usage pattern
     */
    function test_NextNonceMixedUsage() public {
        // Create a pattern with gaps
        vm.startPrank(userA);
        delegatedAccount.invalidateNonce(1);
        delegatedAccount.invalidateNonce(3);
        delegatedAccount.invalidateNonce(5);
        vm.stopPrank();

        // nextNonce should find the first gap (0)
        assertEq(delegatedAccount.nextNonce(), 0, "First available nonce should be 0");

        // Use nonce 0
        vm.prank(userA);
        delegatedAccount.invalidateNonce(0);

        // nextNonce should now find the next gap (2)
        assertEq(delegatedAccount.nextNonce(), 2, "Next available nonce should be 2");

        // Use several more nonces to create a more complex pattern
        vm.startPrank(userA);
        delegatedAccount.invalidateNonce(2);
        delegatedAccount.invalidateNonce(4);
        vm.stopPrank();

        // nextNonce should now find 6
        assertEq(delegatedAccount.nextNonce(), 6, "Next available nonce should be 6");
    }

    /**
     * @dev Test nextNonceAfter behavior with mixed usage pattern
     */
    function test_NextNonceAfterMixedUsage() public {
        // Create a pattern with gaps
        vm.startPrank(userA);
        delegatedAccount.invalidateNonce(1);
        delegatedAccount.invalidateNonce(3);
        delegatedAccount.invalidateNonce(type(uint256).max);
        vm.stopPrank();

        // nextNonce should find the first gap (0)
        assertEq(delegatedAccount.nextNonce(), 0, "First available nonce should be 0");

        // Use nonce 0
        vm.prank(userA);
        delegatedAccount.invalidateNonce(0);

        // nextNonceAfter should wrap around and find the next gap (2)
        // start nonce value MAX_UINT256 - 1 is still valid
        assertEq(delegatedAccount.nextNonceAfter(type(uint256).max - 1), 2, "Next available nonce should be 2");
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
    
    /**
     * @dev Test that calling nextNonce directly on implementation reverts
     */
    function test_RevertWhen_CallingNextNonceOnImplementationAddress() public {
        // Try to call nextNonce directly on the implementation
        vm.expectRevert(LibErrors.UnauthorizedCallContext.selector);
        gaslessDelegate.nextNonce();
    }
    
    /**
     * @dev Test that calling nextNonceAfter directly on implementation reverts
     */
    function test_RevertWhen_CallingNextNonceAfterOnImplementationAddress() public {
        // Try to call nextNonceAfter directly on the implementation
        vm.expectRevert(LibErrors.UnauthorizedCallContext.selector);
        gaslessDelegate.nextNonceAfter(42);
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

    /**
     * @dev Test for nextNonceAfter behavior with fuzzed input
     */
    function testFuzz_NextNonceAfter(uint248 wordPos, uint8 bitPos) public {
        // Use a specific nonce
        uint256 nonce = (uint256(wordPos) << 8) | bitPos;

        vm.prank(userA);
        delegatedAccount.invalidateNonce(nonce);

        uint256 nna = delegatedAccount.nextNonceAfter(nonce);
        // If we're at position 255, the next nonce would be in the next word
        if (bitPos == 255) {
            uint256 expectedNextNonce = (uint256(wordPos) + 1) << 8; // First position in next word
            assertEq(nna, expectedNextNonce, "Next nonce after bit 255 should be in next word");
        }

        // Confirm the returned nonce is greater than our original nonce, unless it's the maximum possible nonce value
        if (wordPos != type(uint248).max) {
            assertTrue(nna > nonce, "Next nonce should be greater than the given nonce");
        }
        // Confirm the returned nonce is valid (not already used)
        assertFalse(delegatedAccount.isNonceUsed(nna), "Found nonce should not already be used");
    }
}
