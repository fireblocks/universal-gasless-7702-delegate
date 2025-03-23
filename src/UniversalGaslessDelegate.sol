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
// import { console2 } from "forge-std/console2.sol";
/**
 * @title UniversalGaslessDelegate
 * @notice An EIP-7702 compatible delegate contract for enabling gasless transactions through delegation. This 
 *         contract implements a pattern where logic can execute on behalf of users who have signed authorized payload.
 * 
 * @dev Implements flexible standards such as EIP-7821 to enhance the EOA experience with contract functionality. It 
 *      allows third partides to submit transactions for execution on behalf of users (i.e. gasless operations), as
 *      long as users have provided the necessary authorization.
 *      
 * Core Features:
 * - Leverages on EIP-7702 for delegate-based transaction execution
 * - Supports EIP-7579/EIP-7821 execution modes for single and batch transactions (see {supportsExecutionMode})
 * - Integrates EIP-712 typed data signing for structured transaction authorization
 * - Implements unordered nonces for authorization replay protection
 * - Provides ERC-1271 signature validation compatibility for existing protocols
 * - Includes token receiver capabilities (ERC-721 and ERC-1155)
 * - Emergency pause functionality via KillSwitch contract
 */
contract UniversalGaslessDelegate is IERC1271, IERC7821, NonceBitmap, TokenReceiver, TypedAuthorization {
    using ERC7579Utils for bytes32;
    using ERC7579Utils for Mode;
    using ERC7579Utils for CallType;
    using ERC7579Utils for ExecType;

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

    address private immutable __implementation = address(this);

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
    IKillSwitch public immutable killswitchContract;

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
        if (killswitchContract.paused()) revert LibErrors.EnforcedPause();
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
     * - `_killswitchContract` must not be the zero address
     * - `_killswitchContract` must implement {IKillSwitch}
     * - `_killswitchContract` must not be in paused state
     *
     * Reverts with:
     * - no error data (i.e. standard `revert()`) if the contract does not return a bool value on the
     *   static-call to `paused()`
     * - `InvalidImplementation()` if the contract is paused
     * @param _killswitchContract Address of the killswitch contract
     */
    constructor(address _killswitchContract) {
        killswitchContract = IKillSwitch(_killswitchContract);
        // check if it is a valid IKillSwitch contract that is not paused
        require(killswitchContract.paused() == false, LibErrors.InvalidImplementation());

        // Initialize EIP-712 domain separator
        // DOMAIN_SEPARATOR = keccak256("");
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
     * with an optional authorization mechanism. The caller can be either the Delegated EOA itself or another account
     * provided that the latter has a valid signature for the execution(s) to be made.
     *
     * @dev Processes execution requests according to the EIP-7579 and EIP-7821 specification, which define the mode
     * format and execution data structure. This function supports three different execution modes as detailed in
     * {supportsExecutionMode}.
     *
     * The `executionData` parameter follows EIP-7821 encoding rules. Refer to {_extractExecAndOpData} for the meaning
     * of "calls":
     *   - For modes with opData authorization (modeId 1 and 2): `abi.encode(calls, opData)` where `opData` contains
     *     nonce and signature
     *   - For self-call mode (modeId 3): `abi.encode(calls)` with no opData
     *
     * Authorization flow:
     * 1. For modes with opData authorization (modeId 1 and 2):
     *   - Calculate authorization digest using EIP-712 typed data signing
     *   - Validate that the nonce is not already used
     *   - Verify signature matches the Delegated EOA's
     *
     * 2. For self-call mode (modeId 3):
     *    - Verify caller is the delegated EOA itself (msg.sender == address(this))
     *
     * Calling Conditions:
     * - The function should be called in the context of the Delegated EOA. Calling it directly on the implementation
     *   address will revert. (checked by `onlyProxy`)
     * - The implementation contract should not be paused. (checked by `whenNotPaused`)
     *
     * Note: The ERC7579Utils.decodeBatch function performs validation and will throw
     * {ERC7579DecodingError} if the input is not properly formatted.
     *
     * @param mode The execution mode that defines how the execution data should be processed
     * @param executionData The encoded execution data and optional authorization data (opData)
     */
    function execute(bytes32 mode, bytes calldata executionData) external payable whenNotPaused onlyProxy {
        // Decode the execution data according to the mode
        uint8 modeId = _executionModeId(mode);

        // Revert if mode is not supported
        if (modeId == 0) _determineExecutionModeRevertCause(mode);

        // Handle different execution modes that expect opData
        if (modeId < 3) {
            // Extract single-or-batch execution data and opData for authorization
            bytes calldata sobExecutionData;
            bytes calldata opData;
            (sobExecutionData, opData) = _extractExecAndOpData(executionData);
            // Decode opData to extract nonce and signature
            (uint256 nonce, bytes calldata signature) = _decodeOpData(opData);
            // irrespective of single or batch, the nonce is always used on modes 1 and 2
            _useUnorderedNonce(nonce);
            if (modeId == 1) {
                // Perform authentication using opData and execute single call
                (address target, uint256 value, bytes calldata callData) = ERC7579Utils.decodeSingle(sobExecutionData);
                // create AuthorizedExecutions EIP712 hash
                bytes32 sDigest = _hashTypedSingleExecutionAuthorization(mode, target, value, callData, nonce);
                //validate signature
                require(address(this) == ECDSA.recover(sDigest, signature), LibErrors.UnauthorizedExecution());
                // Execute the call
                _call(target, value, callData);
                return;
            }
            // modeId == 2
            // Perform authentication using opData and execute batch calls
            Execution[] calldata executionBatch = ERC7579Utils.decodeBatch(sobExecutionData);
            // create AuthorizedExecutions EIP712 hash
            bytes32 bDigest = _hashTypedBatchExecutionAuthorization(mode, executionBatch, nonce);
            //validate signature
            require(address(this) == ECDSA.recover(bDigest, signature), LibErrors.UnauthorizedExecution());
            // Execute the batch calls
            _execBatch(executionBatch);
            return;
        } else if (modeId == 3) {
            // For this mode, the caller must be the Delegated EOA itself (onlySelf)
            if (msg.sender != address(this)) revert LibErrors.UnauthorizedCaller();
            // Batch call type with Empty mode selector (0x01 + 0x00000000)
            // In this case, executionData is expected to contain abi encoded calls only, no opData
            Execution[] calldata executionBatch = ERC7579Utils.decodeBatch(executionData);
            // Execute the batch calls
            _execBatch(executionBatch);
            return;
        }
    }

    /**
     * @notice This function marks a nonce as used
     * @dev This function is used to invalidate a nonce
     *
     * Calling Conditions:
     * - The nonce must not be already marked as used
     * - The caller must be the owner of the contract
     * - If the contract context is paused, the call must come from the Delegated EOA directly
     * @param nonce The nonce to invalidate
     */
    function invalidateNonce(uint256 nonce) external virtual override onlyProxy onlySelf {
        _useUnorderedNonce(nonce);
    }

    /**
     * @inheritdoc NonceBitmap
     */
    function getNonceBitmap(uint256 wordPos) public view virtual override onlyProxy returns (uint256) {
        return super.getNonceBitmap(wordPos);
    }

    /**
     * @inheritdoc NonceBitmap
     */
    function isNonceUsed(uint256 nonce) public view virtual override onlyProxy returns (bool) {
        return super.isNonceUsed(nonce);
    }

    /**
     * @inheritdoc NonceBitmap
     */
    function nextNonce() public view virtual override onlyProxy returns (uint256 nonce) {
        return super.nextNonce();
    }

    /**
     * @inheritdoc NonceBitmap
     */
    function nextNonceAfter(uint256 start) public view virtual override onlyProxy returns (uint256 nonce) {
        return super.nextNonceAfter(start);
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
     * @notice This function is provided for frontends to detect support. It checks if the contract supports
     *         a specific execution mode.
     *
     * @dev Determines whether the contract supports the specified execution mode. Supported execution modes are
     *      detailed in the table below:
     *
     *      +----+----------+----------+------------+-------------------+-------------+
     *      | Id | CallType | ExecType | Unused     | ModeSelector      | ModePayload |
     *      |    | (1 byte) | (1 byte) | (4 bytes)  | (4 bytes)         | (22 bytes)  |
     *      +----+----------+----------+------------+-------------------+-------------+
     *      | 1  | 0x00     | 0x00     | 0x00000000 | 0x78210001        | ANY         |
     *      |    | (Single) | (Revert) | (Empty)    | (Auth via opData) |             |
     *      +----+----------+----------+------------+-------------------+-------------+
     *      | 2  | 0x01     | 0x00     | 0x00000000 | 0x78210001        | ANY         |
     *      |    | (Batch)  | (Revert) | (Empty)    | (Auth via opData) |             |
     *      +----+----------+----------+------------+-------------------+-------------+
     *      | 3  | 0x01     | 0x00     | 0x00000000 | 0x00000000        | ANY         |
     *      |    | (Batch)  | (Revert) | (Empty)    | (Default)         |             |
     *      +----+----------+----------+------------+-------------------+-------------+
     *
     * @param mode The fully-qualified execution mode to check
     * @return True if the mode is supported, false otherwise
     */
    function supportsExecutionMode(bytes32 mode) external pure returns (bool) {
        return _executionModeId(mode) != 0;
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
     * @return True when `interfaceId` is either:
     *   - the {IERC7821} interface id
     *   - the {IERC1271} interface id
     *   - the {IERC721Receiver} interface id (checked in TokenReceiver)
     *   - the {IERC1155Receiver} interface id (checked in ERC1155Holder)
     *   - the {IERC165} interface id (checked in ERC1155Holder -> ERC165)
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override onlyProxy returns (bool) {
        return interfaceId == type(IERC7821).interfaceId || interfaceId == type(IERC1271).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // ========================= INTERNAL ==========================

    /**
     * @notice This function calls the target with specified value and data. It is multipurpose and can be used for
     *         both invoking a function on target contract or for sending ETH to non-contract addresses.
     * @dev Performs a low-level call to the target contract and verifies the result.
     *
     * Note: To prevent loss of funds, we check that target is a contract if all of the following are true:
     * - the call was successful, AND
     * - the return data is empty, AND
     * - calldata was not empty, AND
     * - there is value being sent
     *
     * Calling Conditions:
     *
     * - When sending value, the target must be a contract if the call has data attached to it
     *   and call is successful, but returns no data.
     *
     * @param target The address of the contract to call
     * @param value The amount of ETH to send with the call
     * @param data The calldata to send to the target
     * @return The returndata from the call if successful
     */
    function _call(address target, uint256 value, bytes calldata data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        // Check value safeguard measure
        if (success && returndata.length == 0 && data.length > 0 && value > 0 && target.code.length == 0) {
            revert Address.AddressEmptyCode(target);
        }
        return Address.verifyCallResult(success, returndata);
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
     * @dev Analyzes the execution mode and returns an identifier that indicates support:
     *      - Returns 0 if the mode is not supported
     *      - Returns 1 for CallType = Single (0x00), ExecType = Revert on failure (0x00), Unused = EMPTY,
     *          ModeSelector = Authorization via `opData` (0x78210001), ModePayload = ANY
     *      - Returns 2 for supported Batch call type mode with auth (0x01 + 0x78210001)
     *      - Returns 3 for supported Batch call type mode with default auth (0x01 + 0x00000000)
     *
     * @param mode The execution mode to analyze
     * @return An identifier for the execution mode type (0 = unsupported)
     */
    function _executionModeId(bytes32 mode) internal pure returns (uint8) {
        // Check if the mode is supported. Only checks the first 10 bytes of the mode
        bytes10 execModeMinusPayload = bytes10(mode);
        if (execModeMinusPayload == bytes10(0x00000000000078210001)) {
            return 1;
        }
        if (execModeMinusPayload == bytes10(0x01000000000078210001)) {
            return 2;
        }
        if (execModeMinusPayload == bytes10(0x01000000000000000000)) {
            return 3;
        }
        return 0;
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
        (CallType callType, ExecType execType, ModeSelector modeSelector,) = Mode.wrap(mode).decodeMode();

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
     * @notice Extracts single/batch execution data and optional opData from `executionData`
     * @dev Decodes executionData to separate the call(s) from the optional `opData` according to EIP-7821.
     *
     * The function determines if opData is present by examining the offset values. Here, we perform low-level
     * ABI-decoding of dynamic types with the intent of:
     *   - gracefully handling structural errors that otherwise would result in a generic revert
     *   - maintaining calldata references
     *
     * The function determines if opData is present by examining the offset values:
     * - If only one dynamic type is present, only `singleOrBatchExecutionData` will be relevant, as `opData` is
     *   set to empty
     * - If two dynamic typed values are present, both execution data and opData are extracted
     *
     * Reverts:
     * - with {LibErrors.ExecutionDataExtractionError} if offsets are invalid
     *
     * @param executionData The encoded execution data passed to execute()
     * @return singleOrBatchExecutionData The extracted singleOrBatchExecutionData data
     * @return opData The extracted operation data (empty if not provided)
     */
    function _extractExecAndOpData(bytes calldata executionData)
        internal
        pure
        returns (bytes calldata singleOrBatchExecutionData, bytes calldata opData)
    {
        // Default opData to empty
        opData = executionData[executionData.length:executionData.length];

        // Read the primary offset in a local variable first
        uint256 cOffset;
        assembly {
            cOffset := calldataload(executionData.offset)
        }

        if (cOffset < 32) revert LibErrors.ExecutionDataExtractionError();

        assembly {
            let cPos := add(executionData.offset, cOffset)
            singleOrBatchExecutionData.offset := add(cPos, 0x20)
            singleOrBatchExecutionData.length := calldataload(cPos)
        }

        // If the first offset is 64, we have a second item for opData
        if (cOffset >= 64) {
            uint256 oOffset;
            assembly {
                oOffset := calldataload(add(executionData.offset, 0x20))
            }
            // Revert if the offset is invalid
            if (oOffset < 64 || oOffset >= executionData.length) revert LibErrors.ExecutionDataExtractionError();

            assembly {
                let oPos := add(executionData.offset, oOffset)
                opData.offset := add(oPos, 0x20)
                opData.length := calldataload(oPos)
            }
        }
    }

    /**
     * @notice Decodes the `opData` parameter to extract the nonce and signature components
     * @dev Parses the opData byte array to extract a nonce value and ECDSA signature according to an expected packed
     *      format.
     *
     * The opData is expected to have an ABI packed mode:
     *   - First 32 bytes: ABI-encoded uint256 nonce
     *   - Next 65 bytes: ECDSA signature (r, s, v format)
     *
     * Calling Conditions:
     *   - `opData` has exactly the expected length (97 bytes). Reverts with {LibErrors.OpDataDecodingError} otherwise.
     *
     * @param opData The operation data containing nonce and signature
     * @return nonce The extracted nonce value used for replay protection
     * @return signature The extracted 65-byte ECDSA signature
     */
    function _decodeOpData(bytes calldata opData) internal pure returns (uint256 nonce, bytes calldata signature) {
        // Verify that the opData is exactly 97 bytes long (32 bytes for nonce + 65 bytes for signature)
        require(opData.length == 97, LibErrors.OpDataDecodingError());

        // Extract nonce from the first 32 bytes
        nonce = abi.decode(opData[:32], (uint256));
        // Extract signature from the last 65 bytes
        uint256 signatureStart = opData.length - 65;
        signature = opData[signatureStart:];
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
     * @return true if the signature is valid, false otherwise
     */
    function _isValidRawSignature(bytes32 _hash, bytes calldata _signature) internal view virtual returns (bool) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(_hash, _signature);
        return address(this) == recovered && err == ECDSA.RecoverError.NoError;
    }

    /**
     * @notice This function is used to get the namespaced, structured nonce storage
     * @dev This function is used to get the nonce storage pointer
     * @custom:storage-location erc7201:fireblocks.global.security.nonces
     * @return $ The reference to the {NonceStorage} struct in storage
     */
    function _nonceStorage() internal pure virtual override returns (NonceStorage storage $) {
        assembly ("memory-safe") {
            $.slot := _NONCE_STORAGE_LOCATION
        }
    }
}
