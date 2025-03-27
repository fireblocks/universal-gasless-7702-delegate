// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { IKillSwitch } from "../../src/interface/IKillSwitch.sol";
/**
 * @title MockKillSwitch
 * @dev A simple mock implementation of the KillSwitch interface for testing purposes
 */

contract MockKillSwitch is IKillSwitch {
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
