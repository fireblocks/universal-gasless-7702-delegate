// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.27;

/**
 * @title MockCallTarget
 * @dev Mock contract for testing call functionality
 */
contract MockCallTarget {
    uint256 public storedValue;
    bytes public lastData;
    uint256 public receivedValue;
    bool public shouldRevert;
    bytes public returnData;

    event Called(address sender, uint256 value, bytes data);

    // Constructor to set initial state
    constructor() {
        storedValue = 0;
        shouldRevert = false;
    }

    // Function to set if the contract should revert on calls
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    // Function to set what data the contract should return
    function setReturnData(bytes calldata _returnData) external {
        returnData = _returnData;
    }

    // Fallback function to handle generic calls
    fallback() external payable {
        if (shouldRevert) {
            revert("MockCallTarget: reverted as requested");
        }

        // Store received data and value
        lastData = msg.data;
        receivedValue = msg.value;
        storedValue += msg.value;

        // Emit event for tracking
        emit Called(msg.sender, msg.value, msg.data);
    }

    // Function that returns a uint value
    function returnUint(uint256 _value) external payable returns (uint256) {
        lastData = msg.data;
        receivedValue = msg.value;
        storedValue += msg.value;

        emit Called(msg.sender, msg.value, msg.data);

        return _value;
    }

    // Receive function to handle plain ETH transfers
    receive() external payable {
        if (shouldRevert) {
            revert("MockCallTarget: reverted as requested");
        }

        // Store received value
        receivedValue = msg.value;
        storedValue += msg.value;

        // Emit event for tracking
        emit Called(msg.sender, msg.value, "");
    }
}
