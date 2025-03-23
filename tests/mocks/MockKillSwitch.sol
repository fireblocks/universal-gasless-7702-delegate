// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

/**
 * @title MockKillSwitch
 * @dev A simple mock implementation of the KillSwitch interface for testing purposes
 */
contract MockKillSwitch {
    bool public isPaused;

    function pause() external {
        isPaused = true;
    }

    function unpause() external {
        isPaused = false;
    }

    function paused() external view returns (bool) {
        return isPaused;
    }
}
