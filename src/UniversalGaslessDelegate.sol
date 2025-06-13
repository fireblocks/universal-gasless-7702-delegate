// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: Copyright (C) 2025 Fireblocks <support@fireblocks.com>
pragma solidity 0.8.27;

import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import {
    ERC7579Utils,
    Execution,
    Mode,
    CallType,
    ExecType,
    ModeSelector
} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import { IERC7821 } from "./interface/IERC7821.sol";
import { TokenReceiver } from "./mixins/TokenReceiver.sol";
import { TypedAuthorization } from "./mixins/TypedAuthorization.sol";
import { NonceBitmap } from "./mixins/NonceBitmap.sol";
import { NonceStorage } from "./library/NonceStorageStruct.sol";
import { LibErrors } from "./library/LibErrors.sol";
import { IKillSwitch } from "./interface/IKillSwitch.sol";

/**
 * @title UniversalGaslessDelegate
 * @notice An EIP-7702 compatible delegate contract for enabling gasless transactions through delegation. This
 *         contract implements a pattern where logic can execute on behalf of users who have signed authorized payload.
 *
 * @dev Implements flexible standards such as EIP-7821 to enhance the EOA experience with contract functionality. It
 *      allows third parties to submit transactions for execution on behalf of users (i.e. gasless operations), as
 *      long as users have provided the necessary authorization.
 *
 * Core Features:
 * - Leverages on EIP-7702 for delegate-based transaction execution
 * - Supports EIP-7579/EIP-7821 execution modes for single and batch transactions (see {supportsExecutionMode})
 * - Integrates EIP-712 typed data signing for structured transaction authorization
 * - Implements unordered nonces for authorization replay protection
 * - Provides ERC-1271 signature validation compatibility for existing protocols
 * - Includes token receiver capabilities (ERC-721, ERC-1155, and ERC-223)
 * - Emergency pause functionality via KillSwitch contract
 *
 * @custom:security-contact support@fireblocks.com
 */
contract UniversalGaslessDelegate is IERC1271, IERC7821, NonceBitmap, TokenReceiver, TypedAuthorization {
    // =============================================================
    //                  CONSTANTS / IMMUTABLE
    // =============================================================

    /**
     * @notice The address of the implementation contract
     * @dev This is used to detect direct calls to the implementation contract. It is set to the address of the
     *      implementation contract at deployment time.
     */
    address private immutable __implementation = address(this); // solhint-disable-line immutable-vars-naming

    /**
     * @dev Storage location for the nonce bitmap. Derived from performing the following operation:
     * keccak256(abi.encode(uint256(keccak256("fireblocks.global.security.nonces")) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 private constant _NONCE_STORAGE_LOCATION =
        0xb035242b6a1b64fd1e2d869c03a3cc0e80fe7f55db29c2560bab38e489fab700;

    /**
     * @notice Reference to the KillSwitch contract that can pause the Universal Gasless Delegate functionality
     * @dev This immutable reference points to a contract implementing the IKillSwitch interface
     *      that can pause operations in case of emergencies. The contract is checked for validity
     *      and unpaused status during construction.
     */
    IKillSwitch private immutable _KILLSWITCH_CONTRACT;

    /**
     * @notice Enumeration of the different execution modes supported by the contract
     * @dev These values correspond to the execution modes defined in {supportsExecutionMode}, with INVALID as the
     *      default 0 state
     *
     * Supported execution modes are detailed in the table below:
     *
     * ```
     *      +------------------+----------+----------+------------+-------------------+-------------+
     *      | Mode ID          | CallType | ExecType | Unused     | ModeSelector      | ModePayload |
     *      |                  | (1 byte) | (1 byte) | (4 bytes)  | (4 bytes)         | (22 bytes)  |
     *      +------------------+----------+----------+------------+-------------------+-------------+
     *      | SINGLE_CALL_     | 0x00     | 0x00     | 0x00000000 | 0x78210001        | ANY         |
     *      | OPDATA_AUTH  (1) | (Single) | (Revert) | (Empty)    | (Auth via opData) |             |
     *      +------------------+----------+----------+------------+-------------------+-------------+
     *      | BATCH_CALL_      | 0x01     | 0x00     | 0x00000000 | 0x78210001        | ANY         |
     *      | OPDATA_AUTH  (2) | (Batch)  | (Revert) | (Empty)    | (Auth via opData) |             |
     *      +------------------+----------+----------+------------+-------------------+-------------+
     *      | BATCH_CALL       | 0x01     | 0x00     | 0x00000000 | 0x00000000        | ANY         |
     *      |              (3) | (Batch)  | (Revert) | (Empty)    | (Default)         |             |
     *      +------------------+----------+----------+------------+-------------------+-------------+
     * ```
     *
     * Mode Descriptions:
     * - INVALID (0): Represents an invalid/unsupported execution mode
     * - SINGLE_CALL_OPDATA_AUTH (1): Single call with authorization via **required** opData.
     * - BATCH_CALL_OPDATA_AUTH (2): Batch call with authorization via optional opData.
     * - BATCH_CALL (3): Batch call with self-call authorization.
     *
     * Note that since opData is optional for mode BATCH_CALL_OPDATA_AUTH, it will fall back
     * to `msg.sender` verification when opData is not provided. A mode for Single `CallType` without opData
     * is not supported under the premise that in such scenarios, the EOA should be making the call
     * traditionally and not through the delegate contract.
     */
    enum ExecutionModeId {
        // 0: Invalid mode
        INVALID,
        // 1: CallType = Single (0x00), ExecType = Revert on failure (0x00), ModeSelector = opData auth (0x78210001)
        SINGLE_CALL_OPDATA_AUTH,
        // 2: CallType = Batch (0x01), ExecType = Revert on failure (0x00), ModeSelector = opData auth (0x78210001)
        BATCH_CALL_OPDATA_AUTH,
        // 3: CallType = Batch (0x01), ExecType = Revert on failure (0x00), ModeSelector = Default (0x00000000)
        BATCH_CALL
    }

    // =============================================================
    //                          STATE STORAGE
    //
    // This contract follows ERC-7201 for Namespaced storage
    // Global storage:
    // - See {_NONCE_STORAGE_LOCATION} for NonceStorage
    // =============================================================

    // =============================================================
    //                           EVENTS
    // =============================================================

    // =============================================================
    //                          MODIFIERS
    // =============================================================

    /**
     * @notice This modifier is used to ensure that the function is called through a proxy, which in the EIP-7702
     *         context means that the function is called on a Delegated EOA.
     * @dev Prevents direct calls to the implementation.
     */
    modifier onlyProxy() {
        if (address(this) == __implementation) revert LibErrors.UnauthorizedCallContext();
        _;
    }

    /**
     * @notice Restricts function access to calls originating solely from the contract itself
     * @dev Reverts with {LibErrors.UnauthorizedCaller} if msg.sender is not the Delegated EOA itself, in either the
     * EOA or contract context.
     */
    modifier onlySelf() {
        if (msg.sender != address(this)) revert LibErrors.UnauthorizedCaller();
        _;
    }

    /**
     * @notice This modifier ensures that the contract is not paused via the KillSwitch
     * @dev Reverts if the KillSwitch contract indicates the system is paused
     *      This modifier is used to protect state-modifying functions from being executed during
     *      emergency situations.
     */
    modifier whenNotPaused() {
        if (_KILLSWITCH_CONTRACT.paused()) revert LibErrors.EnforcedPause();
        _;
    }

    // =============================================================
    //                          FUNCTIONS
    // =============================================================

    /**
     * @notice Initializes the 7702 delegate implementation contract
     *
     * @dev Calling Conditions:
     *
     * - `killswitchContract` must not be the zero address
     * - `killswitchContract` must implement {IKillSwitch}
     * - `killswitchContract` must not be in paused state
     *
     * Reverts with:
     * - no error data (i.e. standard `revert()`) if the contract does not return a bool value on the
     *   static-call to `paused()`
     * - `InvalidImplementation()` if the contract is paused
     * @param killswitchContract Address of the killswitch contract
     */
    constructor(address killswitchContract) TypedAuthorization() {
        _KILLSWITCH_CONTRACT = IKillSwitch(killswitchContract);
        // check if it is a valid IKillSwitch contract that is not paused
        require(!_KILLSWITCH_CONTRACT.paused(), LibErrors.InvalidImplementation());
    }

    // ==================== EXTERNAL AND PUBLIC ====================

    /**
     * @notice Allows direct ETH transfers to the contract
     * @dev Executed when the contract receives a plain ETH transfer (empty calldata)
     *
     * Calling Conditions:
     * - The function should be called in the context of the Delegated EOA. Calling it directly on the implementation
     *   address will revert due to the `onlyProxy` check.
     */
    receive() external payable onlyProxy { }

    /**
     * @notice Handles non-matching function calls with ETH value
     * @dev Executed when the contract receives a call with non-empty calldata that doesn't match any function.
     *      Ensures backward compatibility with EOA-like behavior for receiving transactions with arbitrary calldata,
     *      like strings on a "value with memo" pattern.
     *
     * Calling Conditions:
     * - The function should be called in the context of the Delegated EOA. Calling it directly on the implementation
     *   address will revert due to the `onlyProxy` check.
     *
     * NOTE: Using payable fallback functions for receiving Ether is not recommended, since when calldata is present,
     * the fallback is invoked and would not fail for interface confusions on the part of the sender. This fallback
     * exists primarily to ensure backward compatibility with standard EOA behavior.
     */
    fallback() external payable onlyProxy { }

    /**
     * @notice Executes one or more calls on behalf of this Delegated EOA, supporting both single and batch operations
     * with an optional authorization mechanism. The caller can be either the Delegated EOA itself, or another account
     * provided that the latter has a valid signature for the execution(s) to be made.
     *
     * @dev Processes execution requests according to the EIP-7579 and EIP-7821 specification, which define the mode
     * format and execution data structure. This function supports three different execution modes as detailed in
     * {supportsExecutionMode}.
     *
     * The `executionData` parameter should follow these encoding rules:
     *   - For SINGLE_CALL_OPDATA_AUTH: `abi.encode(abi.encodePacked(target, value, callData), opData)`
     *   - For BATCH_CALL_OPDATA_AUTH with opData present: `abi.encode(calls, opData)`
     *   - For BATCH_CALL and BATCH_CALL_OPDATA_AUTH without opData present (self-call): `abi.encode(calls)`
     *   - `opData` represents the bytes produced by `abi.encodePacked(nonce, deadline, signature)`
     *   - `calls` represents an array of `Execution` structs
     *
     * Authorization flow:
     *
     * 1. For modes with opData authorization (SINGLE_CALL_OPDATA_AUTH and BATCH_CALL_OPDATA_AUTH):
     *   - Calculate authorization digest using EIP-712 typed data signing
     *   - Verify the signature has not expired (current block timestamp <= deadline)
     *   - Validate that the nonce is not already used
     *   - Verify the caller matches the relayer in the signed authorization
     *   - Verify signature matches the Delegated EOA's
     * 2. For BATCH_CALL, or BATCH_CALL_OPDATA_AUTH when opData is not present:
     *    - Verify caller is the Delegated EOA itself (`msg.sender == address(this)`)
     *
     * Note: This implementation does NOT perform the target replacement gas optimization listed in EIP-7821.
     * Explicitly, {_call} will NOT replace `address(0)` with `address(this)` as the `target` parameter.
     *
     * Note: The ERC7579Utils.decodeBatch function performs validation and will throw
     * {ERC7579DecodingError} if the input is not properly formatted.
     *
     * Calling Conditions:
     * - The function should be called in the context of the Delegated EOA. Calling it directly on the implementation
     *   address will revert. (checked by `onlyProxy`)
     * - The implementation contract should not be paused. (checked by `whenNotPaused`)
     * - If the target of the execution is the Delegated EOA itself, it can only call the `invalidateNonce` function.
     *
     * @param mode The execution mode that defines how the execution data should be processed
     * @param executionData The encoded execution data and optional authorization data (opData)
     */
    function execute(bytes32 mode, bytes calldata executionData) external payable whenNotPaused onlyProxy {
        // Decode the execution data according to the mode
        ExecutionModeId modeId = _executionModeId(mode);
        // Revert if mode is not supported
        if (modeId == ExecutionModeId.INVALID) _determineExecutionModeRevertCause(mode);

        bytes calldata opData;
        if (modeId == ExecutionModeId.SINGLE_CALL_OPDATA_AUTH) {
            bytes calldata singleExecutionData;
            (singleExecutionData, opData) = _extractSingleExecAndOpData(executionData);
            require(opData.length != 0, LibErrors.UnauthorizedExecution());

            // Decode opData to extract nonce, deadline and signature
            (uint256 nonce, uint256 deadline, bytes calldata signature) = _decodeOpData(opData);
            // Check if signature has expired
            require(block.timestamp <= deadline, LibErrors.ExpiredSignature(deadline));
            // Use the nonce
            _useUnorderedNonce(nonce);

            // Decode single execution from packed data
            (address target, uint256 value, bytes calldata callData) = ERC7579Utils.decodeSingle(singleExecutionData);

            // Create AuthorizedExecutions EIP712 hash and verify signature
            bytes32 sDigest =
                _hashTypedSingleExecutionAuthorization(mode, target, value, callData, nonce, deadline, msg.sender);
            require(address(this) == ECDSA.recover(sDigest, signature), LibErrors.UnauthorizedExecution());

            // Execute the call
            _call(target, value, callData);
            return;
        }

        // Handle batch modes (BATCH_CALL_OPDATA_AUTH and BATCH_CALL)
        bytes calldata batchExecutionData;
        (batchExecutionData, opData) = _extractBatchExecAndOpData(executionData);

        if (opData.length != 0) {
            // BATCH_CALL_OPDATA_AUTH with opData
            // BATCH_CALL mode does not support an opData component
            if (modeId == ExecutionModeId.BATCH_CALL) revert LibErrors.UnauthorizedExecution();

            // Decode opData to extract nonce, deadline and signature
            (uint256 nonce, uint256 deadline, bytes calldata signature) = _decodeOpData(opData);
            // Check if signature has expired
            require(block.timestamp <= deadline, LibErrors.ExpiredSignature(deadline));
            // Use the nonce
            _useUnorderedNonce(nonce);

            // Decode batch execution data
            Execution[] calldata executionBatch = ERC7579Utils.decodeBatch(batchExecutionData);

            // Create AuthorizedExecutions EIP712 hash and verify signature
            bytes32 bDigest = _hashTypedBatchExecutionAuthorization(mode, executionBatch, nonce, deadline, msg.sender);
            require(address(this) == ECDSA.recover(bDigest, signature), LibErrors.UnauthorizedExecution());

            // Execute the batch calls
            _execBatch(executionBatch);
        } else {
            // BATCH_CALL or BATCH_CALL_OPDATA_AUTH without opData (self-call)
            require(msg.sender == address(this), LibErrors.UnauthorizedCaller());

            // Decode batch execution data directly from executionData
            Execution[] calldata executionBatch = ERC7579Utils.decodeBatch(batchExecutionData);
            // Execute the batch calls
            _execBatch(executionBatch);
        }
    }

    /**
     * @notice This function marks a nonce as used
     * @dev This function is used to invalidate a nonce
     *
     * Calling Conditions:
     * - The caller must be the Delegated EOA or the contract itself (checked by `onlySelf`)
     * - If the contract context is paused, the call must come from the Delegated EOA directly
     *
     * Reverts with {LibErrors.InvalidNonce} if the nonce has already been used.
     *
     * @param nonce The nonce to invalidate
     */
    function invalidateNonce(uint256 nonce) external override onlyProxy onlySelf {
        _useUnorderedNonce(nonce);
    }

    /**
     * @notice Returns the fields and values that describe the domain separator to be used as part of EIP-712
     * signatures verified by this contract.
     *
     * @dev This function overrides {TypedAuthorization.eip712Domain()} to ensure it can only be called in the context
     * of a delegated EOA (via proxy). Calling it directly on the implementation address will revert with
     * {LibErrors.UnauthorizedCallContext}.
     */
    function eip712Domain()
        public
        view
        virtual
        override
        onlyProxy
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        return super.eip712Domain();
    }

    /**
     * @inheritdoc NonceBitmap
     */
    function getNonceBitmap(uint248 wordPos) public view override onlyProxy returns (uint256 bitmap) {
        return super.getNonceBitmap(wordPos);
    }

    /**
     * @inheritdoc NonceBitmap
     */
    function isNonceUsed(uint256 nonce) public view override onlyProxy returns (bool isUsed) {
        return super.isNonceUsed(nonce);
    }

    /**
     * @notice This function provides a standard method for external contracts to validate a signature for a given
     *         hash, ensuring that such signatures have been created by the Delegated EOA.
     *
     * It also provides legacy (pre EIP-7702) compatibility with the ERC-1271 standard for signature validation, where
     * protocols might choose to validate signatures using this function, if they find in their logic that it is the
     * way to do it where the account has code.
     *
     * @dev Validates if the provided signature is valid for the given data hash and attributable to the Delegated EOA.
     *      This function is provided for compliance with the ERC-1271 standard for signature validation.
     *
     * Calling Conditions:
     *
     * - The function should be called in the context of the Delegated EOA. Calling it directly on the implementation
     *   address will revert.
     *
     * @param _hash Hash of the data to be signed
     * @param _signature Signature byte array associated with the hash
     * @return magicValue The function selector if signature is valid, or 0xffffffff if invalid
     */
    function isValidSignature(
        bytes32 _hash,
        bytes calldata _signature
    )
        external
        view
        whenNotPaused
        onlyProxy
        returns (bytes4 magicValue)
    {
        if (_isValidRawSignature(_hash, _signature)) {
            return IERC1271.isValidSignature.selector;
        } else {
            return 0xffffffff;
        }
    }

    /**
     * @notice Returns whether the delegate contract is currently paused
     * @dev This function checks the pause state of the KillSwitch contract. Unlike most functions,
     *      it can be called both on the implementation contract and on delegated EOAs, as it should convey the same
     * meaning. It signals if delegate implementation is safe to use.
     *
     * @return isPausedState True if the contract is paused via the KillSwitch, false otherwise
     */
    function isPaused() external view returns (bool isPausedState) {
        return _KILLSWITCH_CONTRACT.paused();
    }

    /**
     * @notice This function is provided for frontends to detect support. It checks if the contract supports
     *         a specific execution mode.
     *
     * @dev Determines whether the contract supports the specified execution mode.
     *      See {ExecutionModeId} for mode layout and definitions.
     *
     * @param mode The fully-qualified execution mode to check
     * @return isSupported True if the mode is supported, false otherwise
     */
    function supportsExecutionMode(bytes32 mode) external pure returns (bool isSupported) {
        return _executionModeId(mode) != ExecutionModeId.INVALID;
    }

    /**
     * @notice This function can be queried to check if the contract implements a specific interface
     * @dev Interface detection as per ERC-165 standard
     *
     * Calling Conditions:
     *
     * - The function should be called in the context of the Delegated EOA. Calling it directly on the implementation
     *   address will revert.
     *
     * @param interfaceId The interface identifier to check
     * @return isSupported True when `interfaceId` is either:
     *   - the {IERC7821} interface id
     *   - the {IERC1271} interface id
     *   - the {IERC721Receiver} interface id (checked in TokenReceiver)
     *   - the {IERC223Receiver} interface id (checked in TokenReceiver)
     *   - the {IERC1155Receiver} interface id (checked in ERC1155Holder)
     *   - the {IERC165} interface id (checked in ERC1155Holder -> ERC165)
     */
    function supportsInterface(bytes4 interfaceId) public view override onlyProxy returns (bool isSupported) {
        return interfaceId == type(IERC7821).interfaceId || interfaceId == type(IERC1271).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // ========================= INTERNAL ==========================

    /**
     * @notice This function calls the target with specified value and data. It is multipurpose and can be used for
     *         both invoking a function on target contract or for sending ETH to non-contract addresses.
     * @dev Performs a low-level call to the target contract and verifies the result.
     *
     * Note: This function prevents reentrancy when the target is the Delegated EOA. Following a whitelist pattern,
     * the only function selector allowed in this situation is the `invalidateNonce` function. If any other function,
     * for example `execute`, is called, it will revert with a `ReentrantCall` error.
     *
     * Calling Conditions:
     *
     * - The call to perform does not constitute a reentrant call to the execute function.
     *
     * @param target The address of the contract to call
     * @param value The amount of ETH to send with the call
     * @param data The calldata to send to the target
     */
    function _call(address target, uint256 value, bytes calldata data) internal {
        // Reject any calls to self that are not the invalidateNonce function
        if (target == address(this) && data.length >= 4 && bytes4(data[:4]) != this.invalidateNonce.selector) {
            revert LibErrors.ReentrantCall();
        }
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        Address.verifyCallResult(success, returndata);
    }

    /**
     * @notice Internal function that executes a batch of calls sequentially
     * @dev Processes an array of Execution structs, calling each target with the specified value and calldata.
     *      This function ensures each call is processed in sequence and bubbles up any errors from failed calls.
     *
     * Security considerations:
     * - All calls are made in the context of the Delegated EOA (address(this))
     * - This is an internal function without authorization checks
     *
     * @param executionBatch An array of Execution structs containing target addresses, values, and calldata
     */
    function _execBatch(Execution[] calldata executionBatch) internal {
        for (uint256 i = 0; i < executionBatch.length; ++i) {
            _call(executionBatch[i].target, executionBatch[i].value, executionBatch[i].callData);
        }
    }

    /**
     * @notice Identifies the type of execution mode
     * @dev Analyzes the execution mode and returns the {ExecutionModeId} identifier. See {ExecutionModeId} for mode
     *      layout and definitions.
     *
     * @param mode The execution mode to analyze
     * @return The enum value representing the execution mode type/identifier
     */
    function _executionModeId(bytes32 mode) internal pure returns (ExecutionModeId) {
        // Check if the mode is supported. Only checks the first 10 bytes of the mode
        bytes10 execModeMinusPayload = bytes10(mode);
        if (execModeMinusPayload == bytes10(0x00000000000078210001)) {
            return ExecutionModeId.SINGLE_CALL_OPDATA_AUTH;
        }
        if (execModeMinusPayload == bytes10(0x01000000000078210001)) {
            return ExecutionModeId.BATCH_CALL_OPDATA_AUTH;
        }
        if (execModeMinusPayload == bytes10(0x01000000000000000000)) {
            return ExecutionModeId.BATCH_CALL;
        }
        return ExecutionModeId.INVALID;
    }

    /**
     * @notice Provides a custom error (if possible) to convey information when an execution mode is not supported
     * @dev Analyzes the components of an execution mode and reverts with a specific error message
     * based on which component is invalid.
     *
     * Reverts with:
     * - {ERC7579UnsupportedCallType} if CallType is neither Single (0x00) nor Batch (0x01)
     * - {ERC7579UnsupportedExecType} if ExecType is not Revert (0x00)
     * - {UnsupportedModeSelector} if ModeSelector is neither Auth (0x78210001) nor Default (0x00000000)
     * - {UnsupportedExecutionMode} for any other unsupported mode configuration
     *
     * @param mode The execution mode to analyze for the revert cause
     */
    function _determineExecutionModeRevertCause(bytes32 mode) internal pure {
        // Extract the components from the mode
        (CallType callType, ExecType execType, ModeSelector modeSelector,) = ERC7579Utils.decodeMode(Mode.wrap(mode));

        // Check for callType being 0x00 (Single) or 0x01 (Batch)
        if (!(callType == ERC7579Utils.CALLTYPE_SINGLE || callType == ERC7579Utils.CALLTYPE_BATCH)) {
            revert ERC7579Utils.ERC7579UnsupportedCallType(callType);
        }
        // Check for execType being 0x00 (Revert on failure)
        if (!(execType == ERC7579Utils.EXECTYPE_DEFAULT)) {
            revert ERC7579Utils.ERC7579UnsupportedExecType(execType);
        }
        // Check for modeSelector being 0x78210001 (Auth via opData) or 0x00000000 (Default)
        if (!(modeSelector == ModeSelector.wrap(0x78210001) || modeSelector == ModeSelector.wrap(0x00000000))) {
            revert LibErrors.UnsupportedModeSelector(ModeSelector.unwrap(modeSelector));
        }
        // Revert with default error for other causes
        revert LibErrors.UnsupportedExecutionMode();
    }

    /**
     * @notice Extracts execution data for batch operations (with or without opData)
     * @dev Decodes executionData to separate the calls from the optional `opData`. Handles BATCH_CALL_OPDATA_AUTH
     *      and BATCH_CALL modes.
     *
     * For batch calls, the expected encoding follows EIP-7821:
     * - Without opData: abi.encode(calls) where calls is Execution[]
     * - With opData: abi.encode(calls, opData) where both are at the same encoding level
     *
     * Here, we perform low-level ABI-decoding with the intent of:
     *   - gracefully handling structural errors that otherwise would result in a generic revert
     *   - maintaining calldata references
     *
     * @param executionData The encoded execution data passed to execute()
     * @return batchExecutionData The extracted batch execution data (includes pointer to array)
     * @return opData The extracted operation data (empty if not provided)
     */
    function _extractBatchExecAndOpData(bytes calldata executionData)
        internal
        pure
        returns (bytes calldata batchExecutionData, bytes calldata opData)
    {
        uint256 cOffset;
        assembly {
            cOffset := calldataload(executionData.offset)
        }

        if (cOffset < 32) revert LibErrors.ExecutionDataExtractionError();

        if (cOffset >= 64) {
            // Two dynamic types: abi.encode(calls, opData)
            uint256 oOffset;
            assembly {
                oOffset := calldataload(add(executionData.offset, 0x20))
            }
            if (oOffset < 64 || oOffset >= executionData.length) revert LibErrors.ExecutionDataExtractionError();

            assembly {
                // Extract calls array data (EIP-7821 format)
                // The data including array offset up until the start of opData.
                // The ERC7599Utils.decodeBatch expects the first word to be a pointer to the array length,
                // which is at the start of executionData.
                batchExecutionData.offset := executionData.offset
                batchExecutionData.length := oOffset
                // Extract opData
                let oPos := add(executionData.offset, oOffset)
                opData.offset := add(oPos, 0x20)
                opData.length := calldataload(oPos)
            }
        } else {
            // Single dynamic type: abi.encode(calls)
            assembly {
                batchExecutionData.offset := executionData.offset
                batchExecutionData.length := executionData.length
                opData.length := 0
            }
        }
    }

    /**
     * @notice Extracts execution data for single call operations with opData
     * @dev Decodes executionData to separate the call from the mandatory `opData`. Handles
     *      SINGLE_CALL_OPDATA_AUTH mode.
     *
     * Here, we perform low-level ABI-decoding of dynamic types with the intent of:
     *   - gracefully handling structural errors that otherwise would result in a generic revert
     *   - maintaining calldata references
     *
     * The expected encoding is abi.encode(abi.encodePacked(target, value, callData), opData)
     *
     * Reverts with {LibErrors.ExecutionDataExtractionError} if offsets, lengths or bounds are invalid.
     *
     * @param executionData The encoded execution data passed to execute()
     * @return singleExecutionData The extracted single execution data (bytes type)
     * @return opData The extracted operation data
     */
    function _extractSingleExecAndOpData(bytes calldata executionData)
        internal
        pure
        returns (bytes calldata singleExecutionData, bytes calldata opData)
    {
        // Need at least 64 bytes for two offsets
        if (executionData.length < 64) revert LibErrors.ExecutionDataExtractionError();

        uint256 cOffset;
        uint256 oOffset;
        assembly {
            cOffset := calldataload(executionData.offset)
            oOffset := calldataload(add(executionData.offset, 0x20))
        }

        // Validate offsets and ensure we can read 32-byte length fields
        if (cOffset < 64 || oOffset < 64) revert LibErrors.ExecutionDataExtractionError();
        if (cOffset + 32 > executionData.length || oOffset + 32 > executionData.length) {
            revert LibErrors.ExecutionDataExtractionError();
        }

        // Extract packed single execution data (bytes type)
        uint256 cLength;
        assembly {
            let cPos := add(executionData.offset, cOffset)
            cLength := calldataload(cPos)
            singleExecutionData.offset := add(cPos, 0x20)
            singleExecutionData.length := cLength
        }

        // singleExecutionData must be at least 20 + 32 bytes long (address + value)
        if (singleExecutionData.length < 52) revert LibErrors.ExecutionDataExtractionError();

        // Extract opData
        uint256 oLength;
        assembly {
            let oPos := add(executionData.offset, oOffset)
            oLength := calldataload(oPos)
            opData.offset := add(oPos, 0x20)
            opData.length := oLength
        }

        // Validate that the lengths don't cause out-of-bounds access
        if (cOffset + 32 + cLength > executionData.length || oOffset + 32 + oLength > executionData.length) {
            revert LibErrors.ExecutionDataExtractionError();
        }
    }

    /**
     * @notice Decodes the `opData` parameter, extracting the nonce, deadline and signature components
     * @dev Parses the opData byte array to extract the nonce, deadline and ECDSA signature according to an expected
     *      packed format.
     *
     * The opData is expected to be in ABI packed encoding format:
     *  - 32 bytes for nonce
     *  - 32 bytes for deadline
     *  - 65 bytes for signature (r, s, v)
     *
     * Reverts with {LibErrors.OpDataDecodingError} if opData is not at least 129 bytes.
     *
     * @param opData The data containing nonce, deadline and signature
     * @return nonce The extracted nonce value used for replay protection
     * @return deadline The timestamp after which the signature is no longer valid
     * @return signature The extracted 65-byte ECDSA signature
     */
    function _decodeOpData(bytes calldata opData)
        internal
        pure
        returns (uint256 nonce, uint256 deadline, bytes calldata signature)
    {
        // opData must contain a nonce, deadline and a signature, for a total of 129 bytes
        require(opData.length == 129, LibErrors.OpDataDecodingError());

        // Extract nonce from the first 32 bytes
        nonce = uint256(bytes32(opData[:32]));
        // Extract deadline from the next 32 bytes
        deadline = uint256(bytes32(opData[32:64]));
        // Extract signature from the remaining bytes
        signature = opData[64:];
    }

    /**
     * @notice Verifies if a signature is valid for a given hash in the context of the Delegated EOA, supporting any
     * ECDSA signature flow including EIP-712.
     *
     * @dev Internal implementation for signature validation, reusable to support ERC1271 compatibility and any ECDSA
     * signature verification requirements, including EIP-712 signatures.
     *
     * Note this function does not perform any nonce-validity checks.
     *
     * Signature Validity Conditions:
     *
     * - The signature does not derive the `address(0)`.
     * - The signature has invalid length.
     * - The signature has an S value that is in the lower half order
     * - The signature must derive `address(this)`.
     *
     * @param _hash The hash of the data that was signed
     * @param _signature A 65-byte ECDSA signature produced by the signer
     * @return isValid true if the signature is valid, false otherwise
     */
    function _isValidRawSignature(bytes32 _hash, bytes calldata _signature) internal view returns (bool isValid) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(_hash, _signature);
        return address(this) == recovered && err == ECDSA.RecoverError.NoError;
    }

    /**
     * @notice Returns the storage reference for the nonce bitmap used in replay protection
     * @dev Uses ERC-7201 pattern for avoiding storage collisions with namespaced, structured nonce storage
     * @custom:storage-location erc7201:fireblocks.global.security.nonces
     * @return $ The reference to the {NonceStorage} struct in storage
     */
    function _nonceStorage() internal pure override returns (NonceStorage storage $) {
        assembly ("memory-safe") {
            $.slot := _NONCE_STORAGE_LOCATION
        }
    }

    /**
     * @notice Returns the address of the verifying contract to be used in the EIP712 domain separator
     * @dev The verifyingContract used is the address of the implementation contract, set during deployment, to prevent
     *      replay attacks if an EOA re-delegates to a different implementation.
     * @return verifyingContract The address of the implementation contract
     */
    function _verifyingContractAddress() internal view override returns (address verifyingContract) {
        // During the construction phase, the value of `__implementation` might be empty, which is not a valid
        // verifying contract. Therefore, we coalesce to the eventual implementation address.
        return __implementation == address(0) ? address(this) : __implementation;
    }
}
