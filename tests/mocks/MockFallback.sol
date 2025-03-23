// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

/**
 * @title MockFallback
 * @dev A simple mock contract to test fallback functions
 * @dev This contract is used to test the fallback functionality in some scenarios
 */
contract MockFallback {
    // Fallback function to handle ether transfers
    receive() external payable {
        // Logic for handling ether transfers
    }

    // Fallback function to handle calls to non-existent functions
    fallback() external payable {
        // Logic for handling calls to non-existent functions
    }
}
