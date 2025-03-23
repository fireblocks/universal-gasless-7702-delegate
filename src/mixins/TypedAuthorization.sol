// SPDX-License-Identifier: AGPL-3.0-or-later
// SPDX-FileCopyrightText: Copyright (C) 2024 Fireblocks <support@fireblocks.com>

pragma solidity 0.8.27;

import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { IERC5267 } from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import { Execution } from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
// import { console2 } from "forge-std/console2.sol";

/**
 * @title Typed Structured Execution Authorization
 * @notice Implementation of EIP712 with the purpose of hashing typed structured data ... etc
 *
 * This contract is an implementation of EIP-712 with select elements being part of the EIP712Domain
 *
 * @dev https://eips.ethereum.org/EIPS/eip-712[EIP-712] is a standard for hashing and signing of typed structured data.
 *
 * This contract implements the EIP-712 domain separator ({_domainSeparatorV4}) that is used as part of the encoding
 * scheme, and the final step of the encoding to obtain the message digest ({_hashTypedDataV4}) that is then signed
 * via ECDSA. This contract also supports ERC-5267, but such proposal does not have a prerequisite on ERC-165 which
 * means that there is no need to signal it via a `supportsInterface` function.
 *
 * The implementation of the domain separator was designed to be as lean as possible, preserving only the chainId and
 * verifyingContract fields. It retains logic for properly updating the chain id to protect against replay attacks on
 * an eventual fork of the chain. This contract implements the version of the encoding known as "signTypedDataV4".
 *
 * This contract is derived from the OpenZeppelin Contracts implementation of EIP712 (utils/cryptography/EIP712.sol).
 */
abstract contract TypedAuthorization is IERC5267 {
    // =============================================================
    //                   CONSTANTS / IMMUTABLE
    // =============================================================

    /**
     * @notice The EIP712 domain typehash used for computing the domain separator
     * @dev Hash of the type string: "EIP712Domain(uint256 chainId,address verifyingContract)"
     */
    bytes32 private constant _DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");

    /**
     * @notice The typehash for the Execution type used in the structured data
     * @dev Hash of the type string: "Execution(address target,uint256 value,bytes data)"
     */
    bytes32 internal constant _EXECUTION_TYPEHASH = keccak256("Execution(address target,uint256 value,bytes data)");

    /**
     * @notice The typehash for the AuthorizedExecutions type used in the typed data
     * @dev Hash of the type string that combines the execution authorization with the execution data
     * This defines the structure of the typed data that will be signed for authorizing executions
     */
    bytes32 internal constant _EXECUTION_AUTHORIZATION_TYPEHASH = keccak256(
        "AuthorizedExecutions(bytes32 mode,Execution[] calls,uint256 nonce)Execution(address target,uint256 value,bytes data)"
    );

    // =============================================================
    //                      PUBLIC FUNCTIONS
    // =============================================================

    /**
     * @inheritdoc IERC5267
     */
    function eip712Domain()
        public
        view
        virtual
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
        return (
            hex"0c", // 01100
            string(hex""), // empty name
            string(hex""), // empty version
            block.chainid,
            address(this),
            bytes32(0), // empty salt
            new uint256[](0)
        );
    }

    // =============================================================
    //                     INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @notice Returns the domain separator for the current chain
     * @dev Always recalculates the domain separator to support proxy accounts
     * @return The domain separator bytes32 value
     */
    function _domainSeparatorV4() internal view returns (bytes32) {
        return keccak256(abi.encode(_DOMAIN_TYPEHASH, block.chainid, address(this)));
    }

    /**
     * @notice Given a hashed struct, returns the hash of the fully encoded EIP712 message for this domain.
     *
     * See https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct[definition of hashed struct].
     * 
     * @dev This hash can be used with {ECDSA-recover} to obtain the signer of a message
     *
     * @param structHash The hash of the struct being signed
     * @return The EIP712 typed data hash
     */
    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), structHash);
    }

    /**
     * @notice Create a hash of the fully encoded EIP712 message for a single authorized execution
     * @dev Creates a typed hash for a single execution with the given parameters
     *
     * @param mode The execution mode
     * @param target The target address
     * @param value The value to send
     * @param data The call data
     * @param nonce The nonce
     * @return The `AuthorizedExecutions` typed hash
     */
    function _hashTypedSingleExecutionAuthorization(
        bytes32 mode,
        address target,
        uint256 value,
        bytes memory data,
        uint256 nonce
    )
        internal
        view
        returns (bytes32)
    {
        // Directly calculate the execution hash for the single execution
        bytes32 seHash = keccak256(abi.encode(_EXECUTION_TYPEHASH, target, value, keccak256(data)));
        // When there's only one item, the executionsHash (plural) is just the packaged single hash
        bytes32 executionsHash = keccak256(abi.encodePacked(seHash));
        // Create the final hash including the mode and nonce
        bytes32 structHash = keccak256(abi.encode(_EXECUTION_AUTHORIZATION_TYPEHASH, mode, executionsHash, nonce));

        return _hashTypedDataV4(structHash);
    }

    /**
     * @notice Create a hash of the fully encoded EIP712 message for a batch of executions
     * @dev Creates a typed hash for multiple executions with the given parameters
     *
     * @param mode The execution mode
     * @param calls The array of executions
     * @param nonce The nonce
     * @return The `AuthorizedExecutions` typed hash
     */
    function _hashTypedBatchExecutionAuthorization(
        bytes32 mode,
        Execution[] memory calls,
        uint256 nonce
    )
        internal
        view
        returns (bytes32)
    {
        // Hash each execution in the batch
        bytes32[] memory executionHashes = new bytes32[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            executionHashes[i] = keccak256(
                abi.encode(_EXECUTION_TYPEHASH, calls[i].target, calls[i].value, keccak256(calls[i].callData))
            );
        }
        // Hash the array of execution hashes
        bytes32 executionsHash = keccak256(abi.encodePacked(executionHashes));
        // Create the final hash including the mode and nonce
        bytes32 structHash = keccak256(abi.encode(_EXECUTION_AUTHORIZATION_TYPEHASH, mode, executionsHash, nonce));

        return _hashTypedDataV4(structHash);
    }
}
