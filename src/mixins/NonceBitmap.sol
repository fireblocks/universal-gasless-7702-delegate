// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: Copyright (C) 2025 Fireblocks <support@fireblocks.com>
pragma solidity 0.8.27;

import { NonceStorage } from "../library/NonceStorageStruct.sol";
import { LibErrors } from "../library/LibErrors.sol";

/**
 * @title NonceBitmap
 * @notice This contract manages unordered nonces using a Bitmap approach to efficiently store and track nonce usage.
 * @dev Provides functionality for managing, querying, and finding the next available nonce
 * @dev Some of these are helper functions for offchain querying and finding the next nonce
 * @dev Adapted from https://github.com/flood-protocol/permit2-nonce-finder/blob/master/src/Permit2NonceFinder.sol
 */
abstract contract NonceBitmap {
    // =============================================================
    //                          FUNCTIONS
    // =============================================================

    // ========================= EXTERNAL ==========================

    /**
     * @notice This function marks a nonce as used
     * @dev This function is used to invalidate a nonce
     *
     * Calling Conditions:
     * - The nonce must not be already marked as used
     * - The caller must be the owner of the contract
     * @param nonce The nonce to invalidate
     */
    function invalidateNonce(uint256 nonce) external virtual;

    /**
     * @notice Returns the nonce bitmap at a given word position
     * @param wordPos The word position to check
     * @return The nonce bitmap at the given position
     */
    function getNonceBitmap(uint256 wordPos) public view virtual returns (uint256) {
        return _nonceStorage().nonceBitmap[wordPos];
    }

    /**
     * @notice This function checks if a nonce is already used
     * @dev Checks whether a nonce has been flipped in the bitmap
     * @param nonce The nonce to check
     * @return True if the nonce has been used, false otherwise
     */
    function isNonceUsed(uint256 nonce) public view virtual returns (bool) {
        (uint256 wordPos, uint256 bitPos) = bitmapPositions(nonce);
        uint256 bit = 1 << bitPos;
        return _nonceStorage().nonceBitmap[wordPos] & bit != 0;
    }

    /**
     * @notice Finds the next valid nonce, starting from 0
     * @dev Do not use this function if you intend to assign nonces sequentially in a high-throughput setting, without
     *      a nonce manager, as it may lead to dirty reads where the returned nonce might be already used by the time
     *      you use it.
     *
     * WARNING:
     * This is function is intended to be called from off-chain (e.g. via an RPC) without any gas fees. Developers
     * should keep in mind that this function has an unbounded cost, and using it as part of a state-changing function
     * may render the function uncallable as it could consume too much gas to fit in a block.
     *
     * @return nonce The first valid nonce starting from 0
     */
    function nextNonce() public view virtual returns (uint256 nonce) {
        nonce = _nextNonce(0, 0);
    }

    /**
     * @notice Finds the next valid nonce "after" from a given nonce. This can be helpful if you're signing multiple
     * nonces in a row and need the next nonce to sign but the start one is still valid.
     *
     * @dev The return value will not be strictly "after" the given nonce, if all the next nonce values until the end
     * of the nonce space are used. In which case it wraps around from the beginning of the nonce space until the next
     * valid nonce value is found.
     *
     * WARNING:
     * This is function is intended to be called from off-chain (e.g. via an RPC) without any gas fees. Developers
     * should keep in mind that this function has an unbounded cost, and using it as part of a state-changing function
     * may render the function uncallable as it could consume too much gas to fit in a block.
     *
     * @param start The nonce to start from
     * @return nonce The first valid nonce "after" the given nonce
     */
    function nextNonceAfter(uint256 start) public view virtual returns (uint256 nonce) {
        // Check if word is at max value to prevent overflow
        if (start == type(uint256).max) {
            // If we're at the max word and position, wrap back to the beginning
            return _nextNonce(0, 0);
        }
        uint248 word = uint248(start >> 8);
        uint8 pos = uint8(start);
        if (pos == type(uint8).max) {
            // If the position is 255, we need to move to the next word
            word++;
            pos = 0;
        } else {
            // Otherwise, we just move to the next position
            pos++;
        }
        nonce = _nextNonce(word, pos);
    }

    // ========================= INTERNAL ==========================

    /**
     * @notice This represents the function signature to be used when accessing the Nonce Storage
     * @dev Returns storage reference for nonce bitmap
     * @return $ Storage reference to the nonce bitmap
     */
    function _nonceStorage() internal pure virtual returns (NonceStorage storage $);

    /**
     * @notice Sets the nonce to used
     * @dev Checks whether a nonce is taken and sets the bit at the bit position in the bitmap
     *
     * Calling Conditions:
     * - The nonce must not have been previously used
     *
     * @param nonce The nonce to spend
     */
    function _useUnorderedNonce(uint256 nonce) internal {
        (uint256 wordPos, uint256 bitPos) = bitmapPositions(nonce);
        uint256 bit = 1 << bitPos;
        uint256 flipped = _nonceStorage().nonceBitmap[wordPos] ^= bit;

        if (flipped & bit == 0) revert LibErrors.InvalidNonce();
    }

    /**
     * @notice Finds the next valid nonce, starting from a given word and position
     * @dev This function could technically result in an infinite loop if all the nonces are used, but in practice
     *      this is unlikely to happen as we don't provide functions to invalidate nonce ranges.
     *
     * Note it wraps around from the beginning of the nonce space if the `start` nonce value is at the end of the
     * nonce space.
     *
     * @param word Word to start looking from
     * @param pos Position inside the word to start looking from
     * @return nonce The next valid nonce
     */
    function _nextNonce(uint248 word, uint8 pos) internal view returns (uint256 nonce) {
        while (true) {
            uint256 bitmap = _nonceStorage().nonceBitmap[word];

            // Check if position is the last bit in the word
            if (pos == type(uint8).max) {
                // If we're at the maximum word value, wrap around to word 0
                if (word == type(uint248).max) {
                    word = 0;
                } else {
                    // Otherwise increment the word
                    ++word;
                }
                pos = 0;
                continue;
            }
            if (pos != 0) {
                // If the position is not 0, we need to shift the bitmap to ignore the bits before position
                bitmap = bitmap >> pos;
            }
            // Find the first zero bit in the bitmap
            while (bitmap & 1 == 1) {
                bitmap = bitmap >> 1;
                ++pos;
            }

            return _nonceFromWordAndPos(word, pos);
        }
    }

    /**
     * @notice Constructs a nonce from a word and a position inside the word
     * @param word The word containing the nonce
     * @param pos The position of the nonce inside the word
     * @return nonce The nonce constructed from the word and position
     */
    function _nonceFromWordAndPos(uint248 word, uint8 pos) internal pure returns (uint256 nonce) {
        // The last 248 bits of the word are the nonce bits
        nonce = uint256(word) << 8;
        // The first 8 bits of the word are the position inside the word
        nonce |= pos;
    }

    // ========================== PRIVATE ==========================

    /**
     * @notice Returns the index of the bitmap and the bit position within the bitmap
     * @param nonce The nonce to get the associated word and bit positions
     * @return wordPos The word position or index into the nonceBitmap
     * @return bitPos The bit position
     * @dev The first 248 bits of the nonce value is the index of the desired bitmap
     * @dev The last 8 bits of the nonce value is the position of the bit in the bitmap
     */
    function bitmapPositions(uint256 nonce) private pure returns (uint256 wordPos, uint256 bitPos) {
        wordPos = uint248(nonce >> 8);
        bitPos = uint8(nonce);
    }
}
