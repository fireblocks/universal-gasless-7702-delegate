// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { NonceBitmap } from "../src/mixins/NonceBitmap.sol";
import { NonceStorage } from "../src/library/NonceStorageStruct.sol";
import { LibErrors } from "../src/library/LibErrors.sol";

/**
 * @title NonceBitmap Test Harness
 * @notice Harness contract to expose internal functions of NonceBitmap for testing
 * @dev This contract inherits from NonceBitmap and exposes its internal functions
 */
contract NonceBitmapHarness is NonceBitmap {
    // Test storage position for nonce bitmap (hardcoded to work with assembly)
    bytes32 private constant _NONCE_STORAGE_LOCATION =
        0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

    // =============================================================
    //                   EXPOSED INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @notice Exposes the internal _useUnorderedNonce function
     * @param nonce The nonce to use
     */
    function exposed_useUnorderedNonce(uint256 nonce) external {
        _useUnorderedNonce(nonce);
    }

    /**
     * @notice Exposes the internal bitmapPositions function
     * @param nonce The nonce to get positions for
     * @return wordPos The word position
     * @return bitPos The bit position
     */
    function exposed_bitmapPositions(uint256 nonce) external pure returns (uint256 wordPos, uint256 bitPos) {
        return _bitmapPositions(nonce);
    }

    /**
     * @notice Implementation of the abstract _nonceStorage function
     * @return $ Reference to the nonce storage
     */
    function _nonceStorage() internal pure override returns (NonceStorage storage $) {
        assembly ("memory-safe") {
            $.slot := _NONCE_STORAGE_LOCATION
        }
    }
}

/**
 * @title NonceBitmap Test
 * @notice Test suite for the NonceBitmap functionality
 * @dev Tests the base NonceBitmap abstract contract functionality directly,
 *      without relying on UniversalGaslessDelegate implementation.
 */
contract NonceBitmapTest is Test {
    NonceBitmapHarness public harness;

    function setUp() public {
        harness = new NonceBitmapHarness();
    }

    // =============================================================
    //                   POSITIVE TEST CASES
    // =============================================================

    /**
     * @notice Test that GetNonceBitmap returns the correct bitmap value
     */
    function test_GetNonceBitmap() public {
        // Initially all nonces are unused (bitmap is 0)
        assertEq(harness.getNonceBitmap(0), 0, "Initial bitmap should be 0");

        // Use a nonce
        uint256 nonce = 5; // bit position 5 in word 0
        harness.exposed_useUnorderedNonce(nonce);

        // The bitmap should now have the bit at position 5 set to 1
        uint256 expectedBitmap = 1 << 5;
        assertEq(harness.getNonceBitmap(0), expectedBitmap, "Bitmap should have bit 5 set");
    }

    /**
     * @notice Test that isNonceUsed correctly identifies used and unused nonces
     */
    function test_IsNonceUsed() public {
        uint256 nonce = 100; // bit position 100 in word 0

        // Initially nonce should be unused
        assertFalse(harness.isNonceUsed(nonce), "Nonce should initially be unused");

        // Use the nonce
        harness.exposed_useUnorderedNonce(nonce);

        // Now the nonce should be marked as used
        assertTrue(harness.isNonceUsed(nonce), "Nonce should be marked as used after using it");
    }

    /**
     * @notice Test invalidateNonce function (the base implementation)
     */
    function test_InvalidateNonce() public {
        uint256 nonce = 42; // Use nonce 42

        // Initially nonce should be unused
        assertFalse(harness.isNonceUsed(nonce), "Nonce should initially be unused");

        // Invalidate the nonce using the base implementation
        harness.invalidateNonce(nonce);

        // Now the nonce should be marked as used
        assertTrue(harness.isNonceUsed(nonce), "Nonce should be marked as used after invalidation");
    }

    /**
     * @notice Test that multiple nonces can be used in the same word
     */
    function test_MultipleNoncesInSameWord() public {
        // Use multiple nonces in same word
        harness.exposed_useUnorderedNonce(10);
        harness.exposed_useUnorderedNonce(20);
        harness.exposed_useUnorderedNonce(30);

        // Check that all are marked as used
        assertTrue(harness.isNonceUsed(10), "Nonce 10 should be used");
        assertTrue(harness.isNonceUsed(20), "Nonce 20 should be used");
        assertTrue(harness.isNonceUsed(30), "Nonce 30 should be used");

        // Check bitmap has all bits set
        uint256 expectedBitmap = (1 << 10) | (1 << 20) | (1 << 30);
        assertEq(harness.getNonceBitmap(0), expectedBitmap, "Bitmap should have bits 10, 20, and 30 set");
    }

    /**
     * @notice Test nonces across different words
     */
    function test_NoncesAcrossDifferentWords() public {
        // Use nonces in different words
        uint256 nonceInWord0 = 42; // Bit position 42 in word 0
        uint256 nonceInWord1 = (1 << 8) | 42; // Bit position 42 in word 1
        uint256 nonceInWord2 = (2 << 8) | 42; // Bit position 42 in word 2

        harness.exposed_useUnorderedNonce(nonceInWord0);
        harness.exposed_useUnorderedNonce(nonceInWord1);
        harness.exposed_useUnorderedNonce(nonceInWord2);

        // Check that all are marked as used
        assertTrue(harness.isNonceUsed(nonceInWord0), "Nonce in word 0 should be used");
        assertTrue(harness.isNonceUsed(nonceInWord1), "Nonce in word 1 should be used");
        assertTrue(harness.isNonceUsed(nonceInWord2), "Nonce in word 2 should be used");

        // Check bitmaps in each word
        uint256 expectedBit = 1 << 42;
        assertEq(harness.getNonceBitmap(0), expectedBit, "Bitmap for word 0 should have bit 42 set");
        assertEq(harness.getNonceBitmap(1), expectedBit, "Bitmap for word 1 should have bit 42 set");
        assertEq(harness.getNonceBitmap(2), expectedBit, "Bitmap for word 2 should have bit 42 set");
    }

    /**
     * @notice Test that the bitmap positions are calculated correctly
     */
    function test_BitmapPositions() public view {
        // Test various nonce values
        (uint256 wordPos1, uint256 bitPos1) = harness.exposed_bitmapPositions(42);
        assertEq(wordPos1, 0, "Word position should be 0 for nonce 42");
        assertEq(bitPos1, 42, "Bit position should be 42 for nonce 42");

        (uint256 wordPos2, uint256 bitPos2) = harness.exposed_bitmapPositions(256);
        assertEq(wordPos2, 1, "Word position should be 1 for nonce 256");
        assertEq(bitPos2, 0, "Bit position should be 0 for nonce 256");

        // Test a large nonce value
        uint256 largeNonce = (12_345 << 8) | 67;
        (uint256 wordPos3, uint256 bitPos3) = harness.exposed_bitmapPositions(largeNonce);
        assertEq(wordPos3, 12_345, "Word position should be 12345 for large nonce");
        assertEq(bitPos3, 67, "Bit position should be 67 for large nonce");
    }

    /**
     * @notice Test the consistency between _useUnorderedNonce and invalidateNonce
     */
    function test_InvalidateNonceMatchesUseUnorderedNonce() public {
        // Create two identical bitmaps
        uint256 nonce1 = 123;
        uint256 nonce2 = 456;

        // Use nonce1 with _useUnorderedNonce
        harness.exposed_useUnorderedNonce(nonce1);

        // Use nonce2 with invalidateNonce
        harness.invalidateNonce(nonce2);

        // Both should be marked as used
        assertTrue(harness.isNonceUsed(nonce1), "Nonce1 should be used after _useUnorderedNonce");
        assertTrue(harness.isNonceUsed(nonce2), "Nonce2 should be used after invalidateNonce");

        // Internal state effect should be the same
        (uint256 wordPos1, uint256 bitPos1) = harness.exposed_bitmapPositions(nonce1);
        (uint256 wordPos2, uint256 bitPos2) = harness.exposed_bitmapPositions(nonce2);

        uint256 bit1 = 1 << bitPos1;
        uint256 bit2 = 1 << bitPos2;

        if (wordPos1 == wordPos2) {
            // If both nonces are in the same word, check that both bits are set
            uint256 expectedBitmap = bit1 | bit2;
            assertEq(harness.getNonceBitmap(uint248(wordPos1)), expectedBitmap, "Bitmap should have both bits set");
        } else {
            // If in different words, check each separately
            assertEq(harness.getNonceBitmap(uint248(wordPos1)) & bit1, bit1, "Bitmap for word1 should have bit1 set");
            assertEq(harness.getNonceBitmap(uint248(wordPos2)) & bit2, bit2, "Bitmap for word2 should have bit2 set");
        }
    }

    // =============================================================
    //                   NEGATIVE TEST CASES
    // =============================================================

    /**
     * @notice Test that invalidating an already invalidated nonce reverts
     */
    function test_RevertWhen_InvalidatingAlreadyInvalidatedNonce() public {
        uint256 nonce = 123;

        // Invalidate the nonce
        harness.invalidateNonce(nonce);

        // Attempting to invalidate it again should revert
        vm.expectRevert(LibErrors.InvalidNonce.selector);
        harness.invalidateNonce(nonce);
    }

    /**
     * @notice Test that using an already used nonce with _useUnorderedNonce reverts
     */
    function test_RevertWhen_UsingAlreadyUsedNonce() public {
        uint256 nonce = 123;

        // Use the nonce
        harness.exposed_useUnorderedNonce(nonce);

        // Attempting to use it again should revert
        vm.expectRevert(LibErrors.InvalidNonce.selector);
        harness.exposed_useUnorderedNonce(nonce);
    }

    /**
     * @notice Test that using an already invalidated nonce with _useUnorderedNonce reverts
     */
    function test_RevertWhen_UsingInvalidatedNonce() public {
        uint256 nonce = 123;

        // Invalidate the nonce
        harness.invalidateNonce(nonce);

        // Attempting to use it again should revert
        vm.expectRevert(LibErrors.InvalidNonce.selector);
        harness.exposed_useUnorderedNonce(nonce);
    }

    /**
     * @notice Test that invalidating an already used nonce reverts
     */
    function test_RevertWhen_InvalidatingUsedNonce() public {
        uint256 nonce = 123;

        // Use the nonce
        harness.exposed_useUnorderedNonce(nonce);

        // Attempting to invalidate it again should revert
        vm.expectRevert(LibErrors.InvalidNonce.selector);
        harness.invalidateNonce(nonce);
    }
}
