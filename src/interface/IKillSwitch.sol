// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: Copyright (C) 2025 Fireblocks <support@fireblocks.com>
pragma solidity 0.8.27;

/**
 * @title IKillSwitch
 * @notice Interface for the KillSwitch contract
 * @dev Defines the standard functions for a KillSwitch that can pause and unpause system functionality
 */
interface IKillSwitch {
    // =============================================================
    //                          FUNCTIONS
    // =============================================================

    /**
     * @notice Pauses delegate contract operations for all delegated EOAs
     */
    function pause() external;

    /**
     * @notice Resumes normal operation of delegated EOAs
     */
    function unpause() external;

    /**
     * @notice Checks if the delegate contract functionality is paused
     * @return True if the contract is paused, false otherwise
     */
    function paused() external view returns (bool);
}
