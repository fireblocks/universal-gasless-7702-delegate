// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC223Receiver } from "../../src/interface/IERC223Receiver.sol";

/**
 * @title MockERC223
 * @dev A mock ERC-223 token implementation for testing purposes
 *      Inherits from OpenZeppelin's ERC20 and adds ERC-223 specific functionality
 */
contract MockERC223 is ERC20 {
    // ERC-223 specific events
    event Transfer(address indexed from, address indexed to, uint256 value, bytes data);

    constructor() ERC20("Mock ERC223 Token", "M223") { }

    /**
     * @dev ERC-223 transfer function that includes data parameter
     * @param to The recipient address
     * @param value The amount to transfer
     * @param data Additional data to pass to the recipient
     * @return success Whether the transfer succeeded
     */
    function transfer(address to, uint256 value, bytes memory data) public returns (bool success) {
        // Perform the standard ERC20 transfer
        _transfer(msg.sender, to, value);

        // If recipient is a contract, call tokenReceived
        if (_isContract(to)) {
            IERC223Receiver receiver = IERC223Receiver(to);
            bytes4 selector = receiver.tokenReceived(msg.sender, value, data);
            require(selector == bytes4(0x8943ec02), "Invalid receiver");
        }

        // Emit the ERC-223 specific event
        emit Transfer(msg.sender, to, value, data);

        return true;
    }

    /**
     * @dev Override ERC20 transfer to add ERC-223 behavior
     * @param to The recipient address
     * @param value The amount to transfer
     * @return success Whether the transfer succeeded
     */
    function transfer(address to, uint256 value) public virtual override returns (bool) {
        return transfer(to, value, "");
    }

    /**
     * @dev Override ERC20 transferFrom to add ERC-223 behavior
     * @param from The sender address
     * @param to The recipient address
     * @param value The amount to transfer
     * @return success Whether the transfer succeeded
     */
    function transferFrom(address from, address to, uint256 value) public virtual override returns (bool) {
        // First handle the allowance and perform the transfer
        uint256 currentAllowance = allowance(from, msg.sender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= value, "ERC20: insufficient allowance");
            unchecked {
                _approve(from, msg.sender, currentAllowance - value);
            }
        }

        _transfer(from, to, value);

        // If recipient is a contract, call tokenReceived
        if (_isContract(to)) {
            IERC223Receiver receiver = IERC223Receiver(to);
            bytes4 selector = receiver.tokenReceived(from, value, "");
            require(selector == bytes4(0x8943ec02), "Invalid receiver");
        }

        // Emit the ERC-223 specific event
        emit Transfer(from, to, value, "");

        return true;
    }

    /**
     * @dev Mint tokens for testing purposes
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    /**
     * @dev Check if an address is a contract
     * @param account The address to check
     * @return isContract Whether the address has code
     */
    function _isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}
