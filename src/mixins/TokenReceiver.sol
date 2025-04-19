// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: Copyright (C) 2025 Fireblocks <support@fireblocks.com>
pragma solidity 0.8.27;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/**
 * @title TokenReceiver
 * @notice This helper contract implements the necessary methods to successfully receive ERC1155 and ERC721 tokens.
 *         It is used as a base contract for accounts that need to handle token transfers.
 *
 * @dev This contract implements:
 *   - the {IERC1155Receiver} interface allowing it to receive ERC1155 tokens
 *   - the {IERC721Receiver} interface allowing it to receive ERC721 tokens
 *   - the EIP-165 standard for interface detection of the same and the two above interfaces
 *
 * @custom:security-contact support@fireblocks.com
 */
abstract contract TokenReceiver is ERC721Holder, ERC1155Holder {
    /**
     * @notice This function can be queried to check if the contract implements a specific interface
     * @dev Interface detection as per ERC-165 standard
     *
     * Returns true when `interfaceId` is either:
     *   - the {IERC721Receiver} interface id
     *   - the {IERC1155Receiver} interface id (checked in ERC1155Holder)
     *   - the {IERC165} interface id (checked in ERC1155Holder -> ERC165)
     *
     * @param interfaceId The interface identifier to check
     * @return isSupported True if the contract supports `interfaceId`
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool isSupported) {
        return interfaceId == type(IERC721Receiver).interfaceId || super.supportsInterface(interfaceId);
    }
}
