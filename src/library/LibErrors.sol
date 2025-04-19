// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: Copyright (C) 2025 Fireblocks <support@fireblocks.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity ^0.8.27;

/**
 * @title Errors Library
 * @author Fireblocks
 * @notice The Errors Library provides error messages for the Fireblocks ecosystem of smart contracts.
 */
library LibErrors {
    /**
     * @notice This error indicates that a signature has expired
     * @dev Indicates that current block timestamp is past the deadline
     */
    error ExpiredSignature(uint256 deadline);

    /**
     * @notice This error indicates that a nonce has already been used.
     * @dev The nonce has already been used for this account.
     */
    error InvalidNonce();

    /**
     * @notice This error indicates that a address provided does not implement a required interface.
     * @dev Indicates that a contract does not implement a required interface.
     */
    error InvalidImplementation();

    /**
     * @notice This error indicates that there was an error decoding the opData parameter.
     * @dev Indicates that there was an error decoding the operation data (opData).
     */
    error OpDataDecodingError();

    /**
     * @notice This error indicates that there was an error extracting data from the execution payload.
     * @dev Indicates that there was an error decoding the execution payload based on an expected structure.
     */
    error ExecutionDataExtractionError();

    /**
     * @notice This error indicates that a call to the `execute` function on the same Delegate EOA was attempted, from
     * the context of a running `execute` function. This would indicate a reentrant call, and therefore is blocked.
     * @dev Thrown when a reentrant call is detected.
     */
    error ReentrantCall();

    /**
     * @notice This error indicates that the function caller is not the expected. For example, not the EOA itself.
     * @dev Indicates that the function caller is not the expected address.
     */
    error UnauthorizedCaller();

    /**
     * @notice This error indicates that a call is being invoked in the wrong target. For example, the implementation
     * contract instead of the Delegated EOA address.
     * @dev Indicates that the call is from an unauthorized context, such as a direct call to the
     * implementation contract.
     */
    error UnauthorizedCallContext();

    /**
     * @notice This error indicates that an execution request was rejected due to invalid authorization.
     * @dev Thrown when an execution request fails signature verification checks.
     *
     * This can occur when:
     *   - The signature provided cannot be attributed to the expected signer (the EOA that has performed an EIP-7702
     *     delegation to this contract)
     *   - The provided signature does not match the given execution payload
     *   - The `opData` component was present and non-zero but the mode provided does not support it
     */
    error UnauthorizedExecution();

    /**
     * @notice This error indicates that the requested execution mode is not supported by the contract.
     * @dev Thrown when an execution request uses an execution mode configuration that is not
     *      recognized or supported by the contract. This is a general error when the specific
     *      component causing the unsupported mode cannot be determined.
     *
     * See also:
     *   - {UnsupportedModeSelector}: For more specific errors related to mode selectors
     *   - {ERC7579UnsupportedCallType}: For errors related to call types
     *   - {ERC7579UnsupportedExecType}: For errors related to execution types
     */
    error UnsupportedExecutionMode();

    /**
     * @notice This error indicates that the execution mode selector is not supported by the contract.
     * @dev Indicates that the execution mode selector is not supported by the contract.
     * @param modeSelector The function selector that was not recognized as a valid mode.
     */
    error UnsupportedModeSelector(bytes4 modeSelector);

    // ==================== IMPORTED ERRORS ====================
    // These are errors that are observed in inherited contracts
    // or libraries and therefore are known to be thrown by the
    // contract. They are collated here for developer convenience.
    // =========================================================

    /**
     * @notice This error indicates that the operation failed because the contract is paused.
     * @dev The operation failed because the contract is paused.
     *
     * Moved into a library to avoid the need for a contract to inherit/import from {Pausable}. This error is original
     * from OpenZeppelin's {Pausable} contract:
     * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Pausable.sol
     */
    error EnforcedPause();

    /**
     * @notice This error indicates that an ERC7579 execute "call type" is not supported.
     * @dev Thrown when an unsupported call type is used in an EIP-7579 execution mode.
     * @param callType The unsupported call type byte.
     */
    error ERC7579UnsupportedCallType(bytes1 callType);

    /**
     * @notice This error indicates that an ERC7579 execute "execution type" is not supported.
     * @dev Thrown when an unsupported exec type is used in an EIP-7579 execution mode.
     * @param execType The unsupported execution type byte.
     */
    error ERC7579UnsupportedExecType(bytes1 execType);
}
