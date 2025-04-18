// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: Copyright (C) 2025 Fireblocks <support@fireblocks.com>
pragma solidity 0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IKillSwitch } from "./interface/IKillSwitch.sol";

/**
 * @title KillSwitch
 * @notice A simple contract that manages a paused state. When embedded in a Delegate contract as a point of reference,
 * it can effectively pause delegate contract operations for all delegated EOAs for the observing implementation.
 * @dev Implements pause functionality with owner-only access controls for emergency situations
 */
contract KillSwitch is IKillSwitch, Ownable, Pausable {
    // =============================================================
    //                           EVENTS
    //
    // Events are inherited from Pausable and Ownable contracts:
    //   - Paused(address account)
    //   - Unpaused(address account)
    //   - OwnershipTransferred(address indexed previousOwner, address indexed newOwner)
    // =============================================================

    // =============================================================
    //                          FUNCTIONS
    // =============================================================

    /**
     * @notice Creates a new KillSwitch contract with the provided `initialOwner` address as the initial owner.
     * @dev The initial state is unpaused.
     * @param initialOwner The address of the initial owner of the contract.
     */
    constructor(address initialOwner) Ownable(initialOwner) { }

    /**
     * @notice This function will change the paused state of the contract to true.
     *
     * @dev Calling Conditions:
     *
     * - The caller must be the owner of the contract
     * - The contract must not be paused
     *
     * This function emits a {Paused} event indicating which account triggered the pause.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice This function will change the paused state of the contract to false.
     *
     * Only use this function when it is safe to resume normal operation of delegated EOAs.
     *
     * @dev Calling Conditions:
     *
     * - The caller must be the owner of the contract
     * - The contract must be paused
     *
     * This function emits an {Unpaused} event indicating which account triggered the unpause.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice This function is used to check if functionality should be paused
     * @dev This view function can be called by any address at any time
     * @return isPausedState True if the contract is paused, false otherwise
     */
    function paused() public view virtual override(IKillSwitch, Pausable) returns (bool isPausedState) {
        return super.paused();
    }
}
