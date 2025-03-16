// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: Copyright (C) 2025 Fireblocks <support@fireblocks.com>
pragma solidity ^0.8.27;

import {IERC7821} from "./interface/IERC7821.sol";
// import { console2 } from "forge-std/console2.sol";
/**
 * @title UniversalGaslessDelegate
 * @notice An EIP-7702 compatible delegate contract ...
 * @dev Implements ....
 *
 * It supports EIP-7579/EIP-7821 execution modes.
 * It also acknowledges ERC-1271 signature validation which is required for compatibility with existing protocols and
 */
contract UniversalGaslessDelegate is IERC7821 {
    // =============================================================
    //                           STRUCTS
    // =============================================================

    // /**
    //  * @dev Structure for execution data as per EIP-7579
    //  */
    // struct Execution {
    //     address target;
    //     uint256 value;
    //     bytes callData;
    // }

    // =============================================================
    //                  CONSTANTS / IMMUTABLE
    // =============================================================

    // =============================================================
    //                          STATE STORAGE
    // =============================================================

    // TODO: Proper type and Natspec
    /// @dev KillSwitch contract reference
    address public immutable killswitchContract;

    // =============================================================
    //                           EVENTS
    // =============================================================

    // =============================================================
    //                          MODIFIERS
    // =============================================================

    // =============================================================
    //                          FUNCTIONS
    // =============================================================

    /**
     * @dev Initializes the delegate contract with the killswitch contract
     * address
     * @param _killswitchContract Address of the killswitch contract
     */
    constructor(address _killswitchContract) {
        require(_killswitchContract != address(0), "Invalid killswitch address");
        killswitchContract = _killswitchContract;

        // Initialize EIP-712 domain separator
        // DOMAIN_SEPARATOR = keccak256("");
    }

    // =============================================================
    //                       EXTERNAL FUNCTIONS
    // =============================================================

    // TODO: Proper Natspec
    /**
     * @dev Executes the calls in `executionData`.
     * Reverts and bubbles up error if any call fails.
     *
     * `executionData` encoding:
     * - If `opData` is empty, `executionData` is simply `abi.encode(calls)`.
     * - Else, `executionData` is `abi.encode(calls, opData)`.
     *   See: https://eips.ethereum.org/EIPS/eip-7579
     *
     * Supported modes:
     * - `bytes32(0x01000000000000000000...)`: does not support optional `opData`.
     * - `bytes32(0x01000000000078210001...)`: supports optional `opData`.
     *
     * Authorization checks:
     * - If `opData` is empty, the implementation SHOULD require that
     *   `msg.sender == address(this)`.
     * - If `opData` is not empty, the implementation SHOULD use the signature
     *   encoded in `opData` to determine if the caller can perform the execution.
     *
     * `opData` may be used to store additional data for authentication,
     * paymaster data, gas limits, etc.
     */
    function execute(bytes32 mode, bytes calldata executionData) external payable {
        // Check if the killswitch is paused
        require(!IKillSwitch(killswitchContract).isPaused(), "Contract is paused");

        // Decode the execution data according to the mode

        // Perform the caller / signature check if required by the mode

        // Execute the call
    }

    // TODO: Proper Natspec
    /**
     * @dev This function is provided for frontends to detect support.
     * Only returns true for:
     * - CallType = Single (0x00), ExecType = Revert on failure (0x00), 
     *   ModeSelector = Authorization via `opData` (0x78210001), Unused = EMPTY, ModePayload = ANY
     */
    function supportsExecutionMode(bytes32 mode) external pure returns (bool) {
        // Check if the mode is supported. Only checks the first 10 bytes of the mode
        bytes10 execModeMinusPayload = bytes10(mode);
        if (execModeMinusPayload == bytes10(0x00000000000078210001)) {
            return true;
        }
        // if (mode == bytes10(0x01000000000000000000) || mode == bytes10(0x01000000000078210001)) {
        //     return true;
        // }
        return false;
    }

    // =============================================================
    //                       INTERNAL FUNCTIONS
    // =============================================================

}
// =============================================================
//                     EXTERNAL INTERFACES
// =============================================================

// TODO: Proper Natspec. Placeholder. Might remain in this file or be moved to a separate file
/**
 * @dev Interface for the KillSwitch contract
 */

interface IKillSwitch {
    function isPaused() external view returns (bool);
    function pause() external;
    function unpause() external;
}
