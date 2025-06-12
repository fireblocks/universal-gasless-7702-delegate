// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: Copyright (C) 2025 Fireblocks <support@fireblocks.com>
pragma solidity 0.8.27;

/**
 * @title IERC223Receiver
 * @notice Interface for contracts capable of receiving ERC-223 tokens
 * @dev Contracts that can receive ERC-223 tokens must implement this interface.
 *      This prevents accidental token deposits to incompatible contracts.
 */
interface IERC223Receiver {
    /**
     * @notice Handle the receipt of ERC-223 tokens
     * @dev This function is called by ERC-223 token contracts when tokens are transferred to this contract.
     *      The function must return the specific magic value to confirm successful handling.
     *
     * @param from The address which previously owned the tokens
     * @param value The amount of tokens transferred
     * @param data Transaction metadata or additional data sent with the transfer
     * @return The magic value 0x8943ec02 to confirm successful handling
     */
    function tokenReceived(address from, uint256 value, bytes calldata data) external returns (bytes4);
}
