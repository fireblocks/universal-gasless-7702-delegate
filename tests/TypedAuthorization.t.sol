// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { TypedAuthorization } from "../src/mixins/TypedAuthorization.sol";
import { Execution } from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title TypedAuthorization Test Harness
 * @notice Harness contract to expose internal functions of TypedAuthorization for testing
 * @dev A similar test file on a different framework and language such as Wagmi (TypeScript) would give more confidence
 *      in the correctness of the implementation, as separate hashing and signing libraries would be used.
 * @dev This contract inherits from TypedAuthorization and exposes its internal functions
 */
contract TypedAuthorizationHarness is TypedAuthorization {
    // =============================================================
    //                   EXPOSED INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @notice Implementation of the _verifyingContractAddress function
     * @return The address of this contract to be used as the verifying contract
     */
    function _verifyingContractAddress() internal view virtual override returns (address) {
        return address(this);
    }

    /**
     * @notice Exposes the internal _domainSeparatorV4 function
     * @return The domain separator for the current chain
     */
    function exposed_domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Exposes the internal _hashTypedDataV4 function
     * @param structHash The hash of the struct being signed
     * @return The EIP712 typed data hash
     */
    function exposed_hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }

    /**
     * @notice Exposes the internal _hashTypedSingleExecutionAuthorization function
     * @param mode The execution mode
     * @param target The target address
     * @param value The value to send
     * @param data The call data
     * @param nonce The nonce
     * @return The `AuthorizedExecutions` typed hash
     */
    function exposed_hashTypedSingleExecutionAuthorization(
        bytes32 mode,
        address target,
        uint256 value,
        bytes memory data,
        uint256 nonce
    )
        external
        view
        returns (bytes32)
    {
        return _hashTypedSingleExecutionAuthorization(mode, target, value, data, nonce);
    }

    /**
     * @notice Exposes the internal _hashTypedBatchExecutionAuthorization function
     * @param mode The execution mode
     * @param calls The array of executions
     * @param nonce The nonce
     * @return The `AuthorizedExecutions` typed hash
     */
    function exposed_hashTypedBatchExecutionAuthorization(
        bytes32 mode,
        Execution[] memory calls,
        uint256 nonce
    )
        external
        view
        returns (bytes32)
    {
        return _hashTypedBatchExecutionAuthorization(mode, calls, nonce);
    }

    /**
     * @notice Helper function to create an Execution struct
     * @param target The target address
     * @param value The value to send
     * @param data The call data
     * @return An Execution struct
     */
    function createExecution(
        address target,
        uint256 value,
        bytes memory data
    )
        external
        pure
        returns (Execution memory)
    {
        return Execution({ target: target, value: value, callData: data });
    }
}

/**
 * @title TypedAuthorization Test
 * @notice Test suite for the TypedAuthorization functionality
 */
contract TypedAuthorizationTest is Test {
    TypedAuthorizationHarness public harness;
    bytes32 public constant MODE_ANY = keccak256("anything");

    // Known EIP-712 domain separator components
    bytes32 private constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 private constant EXECUTION_TYPEHASH = keccak256("Execution(address target,uint256 value,bytes data)");
    bytes32 private constant EXECUTION_AUTHORIZATION_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "AuthorizedExecutions(bytes32 mode,Execution[] calls,uint256 nonce)Execution(address target,uint256 value,bytes data)"
    );

    function setUp() public {
        harness = new TypedAuthorizationHarness();
    }

    // =============================================================
    //                      DOMAIN SEPARATOR TESTS
    // =============================================================

    /**
     * @notice Test that the domain separator is calculated correctly
     */
    function test_DomainSeparator_CalculatesCorrectly() public view {
        // Expected domain separator calculation: keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid,
        // address(harness)))
        bytes32 expectedDomainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(harness)));

        // Get the actual domain separator from the harness
        bytes32 actualDomainSeparator = harness.exposed_domainSeparatorV4();

        // Assert that they match
        assertEq(actualDomainSeparator, expectedDomainSeparator, "Domain separator should match expected value");
    }

    /**
     * @notice Test domain separator when deployed on a different chain
     */
    function test_DomainSeparator_DifferentChain() public {
        // Get the domain separator on the current chain
        bytes32 initialDomainSeparator = harness.exposed_domainSeparatorV4();

        // Simulate a different chain ID
        uint256 newChainId = block.chainid + 1;
        vm.chainId(newChainId);

        // Get the domain separator after changing the chain ID
        bytes32 newDomainSeparator = harness.exposed_domainSeparatorV4();

        // Verify that the domain separator changes when the chain ID changes
        assertTrue(initialDomainSeparator != newDomainSeparator, "Domain separator should change if chain ID changes");

        // Calculate the expected domain separator for the new chain ID
        bytes32 expectedDomainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, newChainId, address(harness)));

        // Verify that the new domain separator is calculated correctly
        assertEq(
            newDomainSeparator, expectedDomainSeparator, "Domain separator on new chain should match expected value"
        );
    }

    /**
     * @notice Test that the domain separator is:
     * - different for different contract addresses, and
     * - cached as long as the chain ID is the same
     */
    function test_DomainSeparator_DifferentAddressAndCache() public {
        // Get the domain separator from the first harness
        bytes32 separator = harness.exposed_domainSeparatorV4();

        // Create a second instance
        TypedAuthorizationHarness harness2 = new TypedAuthorizationHarness();
        bytes32 secondHarnessSeparator = harness2.exposed_domainSeparatorV4();

        // Assert that the domain separators are different due to different (deployed) contract addresses
        assertTrue(
            separator != secondHarnessSeparator,
            "Domain separators should be different for different contract addresses"
        );

        // Change the chain ID
        uint256 newChainId = block.chainid + 1;
        vm.chainId(newChainId);
        // Calculate the expected separator for the new chain ID on the first harness
        bytes32 expectedNewSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, newChainId, address(harness)));

        // Get the domain separator again from the first harness
        bytes32 separatorNewChain = harness.exposed_domainSeparatorV4();
        // It should be different now (cache miss, recalculation)
        assertTrue(separator != separatorNewChain, "Domain separator should be recalculated for a different chain ID");

        assertEq(
            separatorNewChain,
            expectedNewSeparator,
            "New domain separator should match expected value after chain ID change"
        );
    }

    /**
     * @notice Test the EIP712Domain function
     */
    function test_Eip712DomainReturnsCorrectValues() public view {
        // Call the eip712Domain function
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = harness.eip712Domain();

        // Verify the returned values
        // fields_binary= (0) salt, (1) chainId, (1) verifyingContract, (0) version, (0) name
        assertEq(fields, hex"0c", "Fields should be 0c (01100)");
        assertEq(name, "", "Name should be empty");
        assertEq(version, "", "Version should be empty");
        assertEq(chainId, block.chainid, "ChainId should match current chain");
        assertEq(verifyingContract, address(harness), "VerifyingContract should be the harness address");
        assertEq(salt, bytes32(0), "Salt should be empty");
        assertEq(extensions.length, 0, "Extensions should be empty");
    }

    // =============================================================
    //                      TYPED DATA HASH TESTS
    // =============================================================

    /**
     * @notice Test that _hashTypedDataV4 correctly hashes typed data
     */
    function test_HashTypedDataV4_HashesCorrectly() public view {
        // Create a struct hash to use for testing
        bytes32 structHash = keccak256("test struct hash");

        // Get the domain separator
        bytes32 domainSeparator = harness.exposed_domainSeparatorV4();

        // Calculate the expected typed data hash using MessageHashUtils
        bytes32 expectedHash = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        // Get the actual typed data hash from the harness
        bytes32 actualHash = harness.exposed_hashTypedDataV4(structHash);

        // Assert that they match
        assertEq(actualHash, expectedHash, "Typed data hash should match expected value");
    }

    /**
     * @notice Test that single execution authorization is hashed correctly
     */
    function test_HashTypedSingleExecution_HashesCorrectly() public view {
        // Test parameters
        bytes32 mode = MODE_ANY;
        address target = address(0x1234);
        uint256 value = 1 ether;
        bytes memory data = abi.encodeWithSignature("test()");
        uint256 nonce = 42;

        // Calculate the expected hash manually
        bytes32 executionHash = keccak256(abi.encode(EXECUTION_TYPEHASH, target, value, keccak256(data)));
        bytes32 executionsHash = keccak256(abi.encodePacked(executionHash));
        bytes32 structHash = keccak256(abi.encode(EXECUTION_AUTHORIZATION_TYPEHASH, mode, executionsHash, nonce));
        bytes32 domainSeparator = harness.exposed_domainSeparatorV4();
        bytes32 expectedHash = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        // Get the actual hash from the harness
        bytes32 actualHash = harness.exposed_hashTypedSingleExecutionAuthorization(mode, target, value, data, nonce);

        // Assert that they match
        assertEq(actualHash, expectedHash, "Single execution hash should match expected value");
    }

    /**
     * @notice Test that batch execution authorization is hashed correctly
     */
    function test_HashTypedBatchExecution_HashesCorrectly() public view {
        // Create test parameters
        bytes32 mode = MODE_ANY;
        uint256 nonce = 42;

        // Create test executions
        Execution[] memory executions = new Execution[](3);
        executions[0] = harness.createExecution(address(0x1234), 1 ether, abi.encodeWithSignature("test1()"));
        executions[1] =
            harness.createExecution(address(0x5678), 0.5 ether, abi.encodeWithSignature("test2(uint256)", 123));
        executions[2] =
            harness.createExecution(address(0x9ABC), 0, abi.encodeWithSignature("test3(address)", address(0xDEF0)));

        // Calculate the expected hash manually
        bytes32[] memory executionHashes = new bytes32[](executions.length);
        for (uint256 i = 0; i < executions.length; i++) {
            executionHashes[i] = keccak256(
                abi.encode(
                    EXECUTION_TYPEHASH, executions[i].target, executions[i].value, keccak256(executions[i].callData)
                )
            );
        }
        bytes32 executionsHash = keccak256(abi.encodePacked(executionHashes));
        bytes32 structHash = keccak256(abi.encode(EXECUTION_AUTHORIZATION_TYPEHASH, mode, executionsHash, nonce));
        bytes32 domainSeparator = harness.exposed_domainSeparatorV4();
        bytes32 expectedHash = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        // Get the actual hash from the harness
        bytes32 actualHash = harness.exposed_hashTypedBatchExecutionAuthorization(mode, executions, nonce);

        // Assert that they match
        assertEq(actualHash, expectedHash, "Batch execution hash should match expected value");
    }

    /**
     * @notice Test that empty values produce a non-zero hash
     */
    function test_HashTypedBatchExecution_EmptyBatch() public view {
        // Create test parameters
        bytes32 mode = hex"";
        uint256 nonce = 0;

        // Create an empty array of executions
        Execution[] memory executions = new Execution[](0);

        // Get the hash from the harness
        bytes32 hash = harness.exposed_hashTypedBatchExecutionAuthorization(mode, executions, nonce);

        // The hash should be a valid bytes32 value
        assertTrue(hash != bytes32(0), "Empty batch hash should not be zero");
    }

    /**
     * @notice Test that single execution in a batch matches the single execution function
     */
    function test_HashTypedBatchExecution_MatchesSingleExecution() public view {
        // Test parameters
        bytes32 mode = MODE_ANY;
        address target = address(0x1234);
        uint256 value = 1 ether;
        bytes memory data = abi.encodeWithSignature("test()");
        uint256 nonce = 42;

        // Create a batch with a single execution
        Execution[] memory executions = new Execution[](1);
        executions[0] = harness.createExecution(target, value, data);

        // Get the hashes from both functions
        bytes32 singleHash = harness.exposed_hashTypedSingleExecutionAuthorization(mode, target, value, data, nonce);
        bytes32 batchHash = harness.exposed_hashTypedBatchExecutionAuthorization(mode, executions, nonce);

        // The hashes should be the same
        assertEq(singleHash, batchHash, "Single execution hash should match batch execution hash with one execution");
    }
}
