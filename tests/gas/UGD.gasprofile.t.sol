// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC7579Utils, Execution } from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import { Packing } from "@openzeppelin/contracts/utils/Packing.sol";
import { UniversalGaslessDelegationHelper, UniversalGaslessDelegate } from "../UniversalGaslessDelegationHelper.sol";
import { MockCallTarget } from "../mocks/MockCallTarget.sol";
import { KillSwitch } from "../../src/KillSwitch.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { MockKillSwitch } from "../mocks/MockKillSwitch.sol";

/**
 * @title Gas Profile Scenario Interface
 * @dev Interface for gas profile scenario parameters
 */
interface IGasProfileScenario {
    // Parameters for single call test
    function getSingleCallParameters() external view returns (address target, uint256 value, bytes memory callData);

    // Parameters for batch call test
    function getBatchCallParameters(uint256 batchSize) external view returns (Execution[] memory executionBatch);

    // Optional: Return a description of the scenario
    function getScenarioDescription() external view returns (string memory);
}

/**
 * @title Universal Gasless Delegate Gas Profiling Test Suite Base
 * @dev Abstract base test suite for the UniversalGaslessDelegate contract gas profiling
 *      This abstract contract provides the common setup and helper functions
 *      for all gas profiling test scenarios
 */
abstract contract UGDGasProfileTest is Test, UniversalGaslessDelegationHelper {
    // NOTE: Inherits the relevant variable(s) from the helper contract:
    // - UniversalGaslessDelegate gaslessDelegate;
    // - IKillSwitch killswitchContract;

    address public userA;
    uint256 private userAPrivateKey;
    address public relayerForUser;
    uint256 private relayerForUserPrivateKey;
    UniversalGaslessDelegate private delegatedAccount;

    // Constants for typed signatures
    bytes32 private constant _DOMAIN_TYPEHASH = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 private constant _EXECUTION_TYPEHASH = keccak256("Execution(address target,uint256 value,bytes data)");
    bytes32 private constant _EXECUTION_AUTHORIZATION_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "AuthorizedExecutions(bytes32 mode,Execution[] calls,uint256 nonce)Execution(address target,uint256 value,bytes data)"
    );

    // Execution modes
    bytes32 internal constant SINGLE_CALL_AUTH_MODE =
        bytes32(0x0000000000007821000100000000000000000000000000000000000000000000);
    bytes32 internal constant BATCH_CALL_AUTH_MODE =
        bytes32(0x0100000000007821000100000000000000000000000000000000000000000000);
    bytes32 internal constant BATCH_CALL_SELF_MODE =
        bytes32(0x0100000000000000000000000000000000000000000000000000000000000000);

    // Pointer to the scenario implementation
    IGasProfileScenario internal scenario;

    using Packing for *;

    function setUp() public virtual {
        // Set up users with private keys
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        (relayerForUser, relayerForUserPrivateKey) = makeAddrAndKey("relayerForUser");

        // Fund accounts
        vm.deal(userA, 100 ether);
        vm.deal(relayerForUser, 100 ether);

        // Set up mock killswitch in unpaused state
        killswitchContract = new MockKillSwitch();

        // Create UniversalGaslessDelegate
        gaslessDelegate = new UniversalGaslessDelegate(address(killswitchContract));

        // Set up delegation for userA to gaslessDelegate
        delegatedAccount =
            UniversalGaslessDelegate(payable(setupDelegation(userA, userAPrivateKey, address(gaslessDelegate))));

        // Verify delegation was successful
        assertEq(address(delegatedAccount), userA, "Delegated account should be the same as the user account");

        // Scenario is set in the derived class's constructor
    }

    /**
     * @notice Test gas consumption for a single call to execute with auth
     * @dev Uses parameters from the scenario implementation
     */
    function test_gas_execute_single_call_auth() public {
        // Get parameters from the scenario
        (address target, uint256 value, bytes memory callData) = scenario.getSingleCallParameters();
        uint256 nonce = 1;

        // Calculate the signature
        bytes32 digest = _hashTypedSingleExecutionAuth(target, value, callData, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userAPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Prepare execution data
        bytes memory singleExecData = abi.encodePacked(target, value, callData);
        bytes memory opData = abi.encodePacked(nonce, signature);
        bytes memory executionData = abi.encode(singleExecData, opData);

        // Execute and measure gas
        vm.startPrank(relayerForUser);
        delegatedAccount.execute(SINGLE_CALL_AUTH_MODE, executionData);
        vm.stopPrank();
    }

    /**
     * @notice Test gas consumption for a batch execute self-call with one call in the batch
     * @dev Uses parameters from the scenario implementation
     */
    function test_gas_execute_batch_self_call_single() public {
        // Get parameters from the scenario for a single-item batch
        Execution[] memory executionBatch = scenario.getBatchCallParameters(1);

        // Encode batch execution data - no opData for self-call mode
        bytes memory executionData = ERC7579Utils.encodeBatch(executionBatch);

        // Execute and measure gas
        vm.startPrank(address(delegatedAccount)); // Must be called by the delegated EOA itself
        delegatedAccount.execute(BATCH_CALL_SELF_MODE, executionData);
        vm.stopPrank();
    }

    /**
     * @notice Test gas consumption for a batch execute with auth with one call in the batch
     * @dev Uses parameters from the scenario implementation
     */
    function test_gas_execute_batch_auth_single() public {
        // Get parameters from the scenario for a single-item batch
        Execution[] memory executionBatch = scenario.getBatchCallParameters(1);
        uint256 nonce = 2;

        // Calculate the signature
        bytes32 digest = _hashTypedBatchExecutionAuth(executionBatch, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userAPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Prepare execution data
        bytes memory batchExecData = ERC7579Utils.encodeBatch(executionBatch);
        bytes memory opData = abi.encodePacked(nonce, signature);
        bytes memory executionData = abi.encode(batchExecData, opData);

        // Execute and measure gas
        vm.startPrank(relayerForUser);
        delegatedAccount.execute(BATCH_CALL_AUTH_MODE, executionData);
        vm.stopPrank();
    }

    /**
     * @notice Test gas consumption for a batch execute with auth with 10 calls in the batch
     * @dev Uses parameters from the scenario implementation
     */
    function test_gas_execute_batch_auth_10_calls() public {
        // Get parameters from the scenario for a 10-item batch
        Execution[] memory executionBatch = scenario.getBatchCallParameters(10);
        uint256 nonce = 3;

        // Calculate the signature
        bytes32 digest = _hashTypedBatchExecutionAuth(executionBatch, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userAPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Prepare execution data
        bytes memory batchExecData = ERC7579Utils.encodeBatch(executionBatch);
        bytes memory opData = abi.encodePacked(nonce, signature);
        bytes memory executionData = abi.encode(batchExecData, opData);

        // Execute and measure gas
        vm.startPrank(relayerForUser);
        delegatedAccount.execute(BATCH_CALL_AUTH_MODE, executionData);
        vm.stopPrank();
    }

    /**
     * @notice Test gas consumption for a batch execute self-call with 10 calls in the batch
     * @dev Uses parameters from the scenario implementation
     */
    function test_gas_execute_batch_self_call_10_calls() public {
        // Get parameters from the scenario for a 10-item batch
        Execution[] memory executionBatch = scenario.getBatchCallParameters(10);

        // Encode batch execution data - no opData for self-call mode
        bytes memory executionData = ERC7579Utils.encodeBatch(executionBatch);

        // Execute and measure gas
        vm.startPrank(address(delegatedAccount)); // Must be called by the delegated EOA itself
        delegatedAccount.execute(BATCH_CALL_SELF_MODE, executionData);
        vm.stopPrank();
    }

    /**
     * @notice Test gas consumption for a batch execute with auth with 100 calls in the batch
     * @dev Uses parameters from the scenario implementation
     */
    function test_gas_execute_batch_auth_100_calls() public {
        // Get parameters from the scenario for a 100-item batch
        Execution[] memory executionBatch = scenario.getBatchCallParameters(100);
        uint256 nonce = 4;

        // Calculate the signature
        bytes32 digest = _hashTypedBatchExecutionAuth(executionBatch, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userAPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Prepare execution data
        bytes memory batchExecData = ERC7579Utils.encodeBatch(executionBatch);
        bytes memory opData = abi.encodePacked(nonce, signature);
        bytes memory executionData = abi.encode(batchExecData, opData);

        // Execute and measure gas
        vm.startPrank(relayerForUser);
        delegatedAccount.execute(BATCH_CALL_AUTH_MODE, executionData);
        vm.stopPrank();
    }

    // Helper functions for calculating typed data hashes

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(_DOMAIN_TYPEHASH, block.chainid, address(gaslessDelegate)));
    }

    function _hashTypedData(bytes32 structHash) internal view returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(_domainSeparator(), structHash);
    }

    function _hashTypedSingleExecutionAuth(
        address target,
        uint256 value,
        bytes memory data,
        uint256 nonce
    )
        internal
        view
        returns (bytes32)
    {
        // Calculate execution hash
        bytes32 seHash = keccak256(abi.encode(_EXECUTION_TYPEHASH, target, value, keccak256(data)));
        // Package as single item execution array hash
        bytes32 executionsHash = keccak256(abi.encodePacked(seHash));
        // Create final struct hash
        bytes32 structHash =
            keccak256(abi.encode(_EXECUTION_AUTHORIZATION_TYPEHASH, SINGLE_CALL_AUTH_MODE, executionsHash, nonce));

        return _hashTypedData(structHash);
    }

    function _hashTypedBatchExecutionAuth(Execution[] memory calls, uint256 nonce) internal view returns (bytes32) {
        // Hash each execution in the batch
        bytes32[] memory executionHashes = new bytes32[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            executionHashes[i] = keccak256(
                abi.encode(_EXECUTION_TYPEHASH, calls[i].target, calls[i].value, keccak256(calls[i].callData))
            );
        }

        // Create the batch hash by concatenating all execution hashes
        bytes memory encodedHashes = "";
        for (uint256 i = 0; i < executionHashes.length; i++) {
            encodedHashes = abi.encodePacked(encodedHashes, executionHashes[i]);
        }
        bytes32 executionsHash = keccak256(encodedHashes);

        // Create final struct hash
        bytes32 structHash =
            keccak256(abi.encode(_EXECUTION_AUTHORIZATION_TYPEHASH, BATCH_CALL_AUTH_MODE, executionsHash, nonce));

        return _hashTypedData(structHash);
    }
}

/**
 * @title Zero Value Null Address Scenario
 * @dev Implements a scenario for calls to the null address with zero value
 */
contract ZeroValueNullAddressScenario is IGasProfileScenario {
    function getSingleCallParameters()
        external
        pure
        override
        returns (address target, uint256 value, bytes memory callData)
    {
        return (address(0), 0, "");
    }

    function getBatchCallParameters(uint256 batchSize)
        external
        pure
        override
        returns (Execution[] memory executionBatch)
    {
        executionBatch = new Execution[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            executionBatch[i] = Execution(address(0), 0, "");
        }
        return executionBatch;
    }

    function getScenarioDescription() external pure override returns (string memory) {
        return "Calls to the null address with zero value";
    }
}

/**
 * @title Multiple Targets Scenario
 * @dev Implements a scenario for calls to multiple different addresses with zero value
 */
contract MultipleTargetsScenario is IGasProfileScenario {
    function getSingleCallParameters()
        external
        pure
        override
        returns (address target, uint256 value, bytes memory callData)
    {
        return (address(uint160(0x1234)), 0, "");
    }

    function getBatchCallParameters(uint256 batchSize)
        external
        pure
        override
        returns (Execution[] memory executionBatch)
    {
        executionBatch = new Execution[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            // Create a deterministic but varied address for each call
            address target = address(uint160(0x1000 + i));
            executionBatch[i] = Execution(target, 0, "");
        }
        return executionBatch;
    }

    function getScenarioDescription() external pure override returns (string memory) {
        return "Calls to multiple different addresses with zero value";
    }
}

/**
 * @title Zero Value Null Address Gas Profile Tests
 * @dev Tests gas consumption for calls to the null address with zero value
 */
contract ZeroValueNullAddressTest is UGDGasProfileTest {
    constructor() {
        // Set the scenario for this test contract
        scenario = new ZeroValueNullAddressScenario();
    }
}

/**
 * @title Multiple Targets Gas Profile Tests
 * @dev Tests gas consumption for calls to multiple different target addresses
 */
contract MultipleTargetsTest is UGDGasProfileTest {
    constructor() {
        // Set the scenario for this test contract
        scenario = new MultipleTargetsScenario();
    }
}
