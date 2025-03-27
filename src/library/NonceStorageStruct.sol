// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: Copyright (C) 2025 Fireblocks <support@fireblocks.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity 0.8.27;

// =============================================================
//                           STRUCTS
// =============================================================

/**
 * @notice Storage structure for nonce bitmap that helps prevent replay attacks of off-chain signatures
 * @dev This structure is used to track used nonces in a memory-efficient way using a bitmap
 *
 * The `@custom:storage-location` tag is to be defined by the implementing contract.
 */
struct NonceStorage {
    /**
     * @notice Unordered nonces with a bitmap. The key of the mapping is the "nonce value".
     * @dev The first 248 bits of the nonce value is the index of the desired bitmap
     * @dev The last 8 bits of the nonce value is the position of the bit in the bitmap
     */
    mapping(uint256 => uint256) nonceBitmap;
}
