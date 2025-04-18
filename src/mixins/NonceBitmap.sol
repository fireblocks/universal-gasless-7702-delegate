// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: Copyright (C) 2025 Fireblocks <support@fireblocks.com>
pragma solidity 0.8.27;

import { NonceStorage } from "../library/NonceStorageStruct.sol";
import { LibErrors } from "../library/LibErrors.sol";

/**
 * @title NonceBitmap
 * @notice This contract manages unordered nonces using a Bitmap approach to efficiently store and track nonce usage.
 * @dev Provides functionality for managing and querying nonces
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
     * @return bitmap The nonce bitmap at the given position
     */
    function getNonceBitmap(uint248 wordPos) public view virtual returns (uint256 bitmap) {
        return _nonceStorage().nonceBitmap[wordPos];
    }

    /**
     * @notice This function checks if a nonce is already used
     * @dev Checks whether a nonce has been flipped in the bitmap
     * @param nonce The nonce to check
     * @return isUsed True if the nonce has been used, false otherwise
     */
    function isNonceUsed(uint256 nonce) public view virtual returns (bool isUsed) {
        (uint256 wordPos, uint256 bitPos) = bitmapPositions(nonce);
        uint256 bit = 1 << bitPos;
        return _nonceStorage().nonceBitmap[wordPos] & bit != 0;
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
