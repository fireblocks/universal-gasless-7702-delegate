// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { UniversalGaslessDelegate } from "../src/UniversalGaslessDelegate.sol";
import { UniversalGaslessDelegationHelper } from "./UniversalGaslessDelegationHelper.sol";
import { LibErrors } from "../src/library/LibErrors.sol";
import { ERC7579Utils, Execution } from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import { MockKillSwitch } from "./mocks/MockKillSwitch.sol";
import { MockCallTarget } from "./mocks/MockCallTarget.sol";

/**
 * @title UniversalGaslessDelegateHarness
 * @dev Test harness for internal functions of UniversalGaslessDelegate
 */
contract UniversalGaslessDelegateHarness is UniversalGaslessDelegate {
    constructor(address _killswitchContract) UniversalGaslessDelegate(_killswitchContract) { }

    /**
     * @notice Library function wrapper for ERC7579Utils.decodeBatch
     * @dev Exposes ERC7579Utils.decodeBatch for testing purposes
     * @param executionCalldata The encoded batch execution data
     */
    function lib_ERC7579UtilsDecodeBatch(bytes calldata executionCalldata)
        external
        pure
        returns (Execution[] memory executionBatch)
    {
        return ERC7579Utils.decodeBatch(executionCalldata);
    }

    /**
     * @notice Expose internal function for testing
     */
    function exposed_executionModeId(bytes32 mode) external pure returns (ExecutionModeId) {
        return _executionModeId(mode);
    }

    /**
     * @notice Expose internal function for testing
     */
    function exposed_determineExecutionModeRevertCause(bytes32 mode) external pure {
        _determineExecutionModeRevertCause(mode);
    }

    /**
     * @notice Expose internal function for testing batch execution data extraction
     */
    function exposed_extractBatchExecAndOpData(bytes calldata executionData)
        external
        pure
        returns (bytes calldata batchExecutionData, bytes calldata opData)
    {
        return _extractBatchExecAndOpData(executionData);
    }

    /**
     * @notice Expose internal function for testing single execution data extraction
     */
    function exposed_extractSingleExecAndOpData(bytes calldata executionData)
        external
        pure
        returns (bytes calldata singleExecutionData, bytes calldata opData)
    {
        return _extractSingleExecAndOpData(executionData);
    }

    /**
     * @notice Expose internal function for testing
     */
    function exposed_decodeOpData(bytes calldata opData)
        external
        pure
        returns (uint256 nonce, uint256 deadline, bytes memory signature)
    {
        return _decodeOpData(opData);
    }

    /**
     * @notice Expose internal function for testing call execution
     */
    function exposed_call(address target, uint256 value, bytes calldata data) external {
        return _call(target, value, data);
    }
}

/**
 * @title UGD ExecutionModeUtils Test
 * @dev Test suite for execution mode identification, opData extraction and decoding functions
 */
contract UGDExecutionModeUtilsTest is Test, UniversalGaslessDelegationHelper {
    UniversalGaslessDelegateHarness private harness;

    function setUp() public {
        // Set up mock killswitch
        killswitchContract = new MockKillSwitch();

        // Create test harness with the mock killswitch
        harness = new UniversalGaslessDelegateHarness(address(killswitchContract));
    }

    // =============================================================
    //                  EXECUTION MODE ID TESTS
    // =============================================================

    /**
     * @notice Test that supported execution modes are correctly identified
     */
    function test_ExecutionModeId_Supported() public view {
        // Mode 1: Single call with Auth mode
        // CallType = (0x00), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x78210001), ModePayload = ANY
        bytes32 supportedMode1 = bytes32(uint256(0x00000000000078210001) << 8 * 22);
        // Mode 2: Batch call with Auth mode
        // CallType = (0x01), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x78210001), ModePayload = ANY
        bytes32 supportedMode2 = bytes32(uint256(0x01000000000078210001) << 8 * 22);
        // Mode 3: Batch call with Default mode
        // CallType = (0x01), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x00000000), ModePayload = ANY
        bytes32 supportedMode3 = bytes32(uint256(0x01000000000000000000) << 8 * 22);

        // Call the exposed internal function for all supported modes
        UniversalGaslessDelegate.ExecutionModeId modeId1 = harness.exposed_executionModeId(supportedMode1);
        UniversalGaslessDelegate.ExecutionModeId modeId2 = harness.exposed_executionModeId(supportedMode2);
        UniversalGaslessDelegate.ExecutionModeId modeId3 = harness.exposed_executionModeId(supportedMode3);

        // Verify the mode IDs are correct
        assertEq(uint8(modeId1), 1, "Mode 1 (Single call with Auth) should return ID 1");
        assertEq(uint8(modeId2), 2, "Mode 2 (Batch call with Auth) should return ID 2");
        assertEq(uint8(modeId3), 3, "Mode 3 (Batch call with Default) should return ID 3");
    }

    /**
     * @notice Test that unsupported execution modes are correctly identified
     */
    function test_ExecutionModeId_Unsupported() public view {
        // Create unsupported execution modes
        bytes32 unsupportedMode1 = bytes32(uint256(0x02000000000078210001) << 8 * 22); // Unsupported call type (0x02)
        bytes32 unsupportedMode2 = bytes32(uint256(0x00010000000078210001) << 8 * 22); // Unsupported exec type (0x01)
        bytes32 unsupportedMode3 = bytes32(uint256(0x00000000000012345678) << 8 * 22); // Unsupported mode selector
            // (0x12345678)

        // Test each unsupported mode
        UniversalGaslessDelegate.ExecutionModeId modeId1 = harness.exposed_executionModeId(unsupportedMode1);
        UniversalGaslessDelegate.ExecutionModeId modeId2 = harness.exposed_executionModeId(unsupportedMode2);
        UniversalGaslessDelegate.ExecutionModeId modeId3 = harness.exposed_executionModeId(unsupportedMode3);

        // Verify all unsupported modes return ExecutionModeId.INVALID (0)
        assertEq(uint8(modeId1), 0, "Unsupported mode 1 should return ExecutionModeId.INVALID");
        assertEq(uint8(modeId2), 0, "Unsupported mode 2 should return ExecutionModeId.INVALID");
        assertEq(uint8(modeId3), 0, "Unsupported mode 3 should return ExecutionModeId.INVALID");
    }

    /**
     * @notice Test that the function correctly identifies unsupported call types
     */
    function test_RevertWhen_DetermineExecutionModeRevertCause_UnsupportedCallType() public {
        // Create a mode with unsupported call type (0x02)
        bytes32 unsupportedCallTypeMode = bytes32(hex"02000000000078210001");

        // Expect revert with UnsupportedCallType error
        vm.expectRevert(abi.encodeWithSelector(ERC7579Utils.ERC7579UnsupportedCallType.selector, bytes1(0x02)));
        harness.exposed_determineExecutionModeRevertCause(unsupportedCallTypeMode);
    }

    /**
     * @notice Test that the function correctly identifies unsupported exec types
     */
    function test_RevertWhen_DetermineExecutionModeRevertCause_UnsupportedExecType() public {
        // Create a mode with unsupported exec type (0x01)
        // Call type (0x00) is valid, but exec type (0x01) is invalid
        bytes32 unsupportedExecTypeMode = bytes32(hex"00010000000078210001");

        // Expect revert with UnsupportedExecType error
        vm.expectRevert(abi.encodeWithSelector(ERC7579Utils.ERC7579UnsupportedExecType.selector, bytes1(0x01)));
        harness.exposed_determineExecutionModeRevertCause(unsupportedExecTypeMode);
    }

    /**
     * @notice Test that the function correctly identifies unsupported mode selectors
     */
    function test_RevertWhen_DetermineExecutionModeRevertCause_UnsupportedModeSelector() public {
        // Create a mode with unsupported mode selector (0x12345678)
        // Call type (0x00) and exec type (0x00) are valid, but mode selector is invalid
        bytes32 unsupportedModeSelectorMode = bytes32(hex"00000000000012345678");

        // Expect revert with UnsupportedModeSelector error
        vm.expectRevert(abi.encodeWithSelector(LibErrors.UnsupportedModeSelector.selector, bytes4(hex"12345678")));
        harness.exposed_determineExecutionModeRevertCause(unsupportedModeSelectorMode);
    }

    /**
     * @notice Test that the function reverts with the default UnsupportedExecutionMode
     * for other error cases (this serves as a fallback test)
     */
    function test_RevertWhen_DetermineExecutionModeRevertCause_DefaultError() public {
        // This mode has valid call type (0x00), exec type (0x00), and valid mode selector options,
        // but has some invalid data in the unused section
        bytes32 otherInvalidMode = bytes32(hex"0000555555557821000100000000000000000000000000000000000000000000");

        // Expect revert with default UnsupportedExecutionMode error
        vm.expectRevert(LibErrors.UnsupportedExecutionMode.selector);
        harness.exposed_determineExecutionModeRevertCause(otherInvalidMode);
    }

    // =============================================================
    //                  EXECUTION DATA EXTRACTION TESTS
    // =============================================================

    /**
     * @notice Test extracting executionData when only calls data is provided
     */
    function test_ExtractBatchExecAndOpData_OnlyCalls() public view {
        // Create execution data with only calls (no opData)
        address target = address(0x1234);
        uint256 value = 0.1 ether;
        bytes memory callData = abi.encodeWithSignature("doSomething()");

        // Create array of Execution structs
        Execution[] memory calls = new Execution[](1);
        calls[0] = Execution({ target: target, value: value, callData: callData });

        bytes memory executionData = abi.encode(calls);

        // Call exposed function to extract OpData
        (bytes memory extractedCalls, bytes memory extractedOpData) =
            harness.exposed_extractBatchExecAndOpData(executionData);

        // Verify results - extractedCalls should contain the entire array encoding
        assertEq(extractedOpData.length, 0, "Extracted opData should be empty");

        // Verify we can decode the extracted calls using ERC7579Utils.decodeBatch (the original)
        // The extractedCalls should be the raw array data that can be directly decoded
        Execution[] memory decodedCalls = harness.lib_ERC7579UtilsDecodeBatch(extractedCalls);
        assertEq(decodedCalls.length, 1, "Should have one call");
        assertEq(decodedCalls[0].target, target, "Target should match");
        assertEq(decodedCalls[0].value, value, "Value should match");
        assertEq(keccak256(decodedCalls[0].callData), keccak256(callData), "CallData should match");
    }

    /**
     * @notice Test extracting batch execution data with multiple calls
     */
    function test_ExtractBatchExecAndOpData_MultipleCalls() public view {
        // Create execution data with multiple calls (no opData)
        Execution[] memory calls = new Execution[](3);
        calls[0] = Execution({
            target: address(0x1234),
            value: 0.1 ether,
            callData: abi.encodeWithSignature("transfer(address,uint256)", address(0x5678), 100)
        });
        calls[1] = Execution({
            target: address(0x5678),
            value: 0,
            callData: abi.encodeWithSignature("approve(address,uint256)", address(0x9ABC), 200)
        });
        calls[2] = Execution({
            target: address(0x9ABC),
            value: 0.2 ether,
            callData: abi.encodeWithSignature("swap(uint256,uint256)", 100, 200)
        });

        bytes memory executionData = abi.encode(calls);

        // Call exposed function to extract
        (bytes memory extractedCalls, bytes memory extractedOpData) =
            harness.exposed_extractBatchExecAndOpData(executionData);

        // Verify results
        assertEq(extractedOpData.length, 0, "Extracted opData should be empty");

        // Verify we can decode the extracted calls
        vm.breakpoint("a");
        Execution[] memory decodedCalls = harness.lib_ERC7579UtilsDecodeBatch(extractedCalls);
        vm.breakpoint("b");
        assertEq(decodedCalls.length, 3, "Should have three calls");

        // Verify each call
        for (uint256 i = 0; i < 3; i++) {
            assertEq(
                decodedCalls[i].target, calls[i].target, string.concat("Target (", vm.toString(i), ") should match")
            );
            assertEq(decodedCalls[i].value, calls[i].value, string.concat("Value (", vm.toString(i), ") should match"));
            assertEq(
                keccak256(decodedCalls[i].callData),
                keccak256(calls[i].callData),
                string.concat("CallData (", vm.toString(i), ") should match")
            );
        }
    }

    /**
     * @notice Test extracting executionData when both calls and opData are provided
     */
    function test_ExtractBatchExecAndOpData_CallsAndOpData() public view {
        // Create execution data with both calls and opData
        address target = address(0x5678);
        uint256 value = 0.2 ether;
        bytes memory callData = abi.encodeWithSignature("doSomething()");

        // Create array of Execution structs
        Execution[] memory calls = new Execution[](1);
        calls[0] = Execution({ target: target, value: value, callData: callData });

        // Create proper opData with nonce, deadline, and signature
        uint256 nonce = 12_345;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = new bytes(65);
        bytes memory opData = abi.encodePacked(nonce, deadline, signature);
        // EIP-7821 compliance means we pass both the array (calls) and the bytes (opData) to the encoder
        bytes memory executionData = abi.encode(calls, opData);

        // Call exposed function to extract OpData
        (bytes memory extractedCalls, bytes memory extractedOpData) =
            harness.exposed_extractBatchExecAndOpData(executionData);

        // Verify we can decode the extracted calls using ERC7579Utils.decodeBatch (the original)
        Execution[] memory decodedCalls = harness.lib_ERC7579UtilsDecodeBatch(extractedCalls);
        assertEq(decodedCalls.length, 1, "Should have one call");
        assertEq(decodedCalls[0].target, target, "Target should match");
        assertEq(decodedCalls[0].value, value, "Value should match");
        assertEq(keccak256(decodedCalls[0].callData), keccak256(callData), "CallData should match");

        // Verify opData
        assertEq(extractedOpData.length, 129, "OpData should be 129 bytes");
        assertEq(keccak256(extractedOpData), keccak256(opData), "Extracted opData should match original opData");
    }

    /**
     * @notice Test extracting executionData when first offset is less than 32 (fails with ExecutionDataExtractionError)
     */
    function test_RevertWhen_ExtractBatchExecAndOpData_LowFirstOffset() public {
        // Create invalid execution data with first offset < 32
        bytes memory invalidData = new bytes(64);
        // Set the first 32 bytes (offset) to a value less than 32 to trigger the revert
        assembly {
            // Set offset to 16, which is less than the required minimum of 32
            mstore(add(invalidData, 32), 16)
        }

        // Call should revert with ExecutionDataExtractionError
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractBatchExecAndOpData(invalidData);
    }

    /**
     * @notice Test extracting executionData with non-ABI encoded data (fails with ExecutionDataExtractionError)
     */
    function test_RevertWhen_ExtractBatchExecAndOpData_NonAbiEncoded() public {
        // Create invalid execution data (not valid ABI encoding)
        bytes memory invalidData = abi.encodePacked(bytes4(0x12345678));

        // Call should revert with ExecutionDataExtractionError
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractBatchExecAndOpData(invalidData);
    }

    /**
     * @notice Test extracting executionData with double encoding over calls
     */
    function test_RevertWhen_ExtractBatchExecAndOpData_DoubleAbiEncoded() public {
        // Create execution data with both calls and opData
        address target = address(0x5678);
        uint256 value = 0.2 ether;
        bytes memory callData = abi.encodeWithSignature("doSomething()");

        // Create array of Execution structs
        Execution[] memory calls = new Execution[](1);
        calls[0] = Execution({ target: target, value: value, callData: callData });

        // Create proper opData with nonce, deadline, and signature
        uint256 nonce = 12_345;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = new bytes(65);
        bytes memory opData = abi.encodePacked(nonce, deadline, signature);

        // Create execution data that encodes the calls array into bytes, before encoding it along with opData
        bytes memory invalidExecutionData = abi.encode(abi.encode(calls), opData);

        // Call exposed function to extract invalidExecutionData and OpData
        (bytes memory extractedCalls, bytes memory extractedOpData) =
            harness.exposed_extractBatchExecAndOpData(invalidExecutionData);

        // Verify opData
        assertEq(extractedOpData.length, 129, "OpData should be 129 bytes");
        assertEq(keccak256(extractedOpData), keccak256(opData), "Extracted opData should match original opData");

        // Call should revert with ERC7579DecodingError
        vm.expectRevert(ERC7579Utils.ERC7579DecodingError.selector);
        harness.lib_ERC7579UtilsDecodeBatch(extractedCalls);
    }

    /**
     * @notice Test extracting executionData with second offset less than 64 (fails with ExecutionDataExtractionError)
     */
    function test_RevertWhen_ExtractBatchExecAndOpData_LowSecondOffset() public {
        // Create execution data with both items but invalid second offset
        // First create a valid batch execution and opData
        Execution[] memory calls = new Execution[](1);
        calls[0] = Execution({ target: address(0x1234), value: 0, callData: "" });

        uint256 nonce = 12_345;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = new bytes(65);
        bytes memory opData = abi.encodePacked(nonce, deadline, signature);

        bytes memory executionData = abi.encode(calls, opData);

        // Modify the second offset to be less than 64
        assembly {
            // The second offset starts at position 64 (after length prefix and first offset)
            mstore(add(executionData, 64), 32) // Should be at least 64
        }

        // Call should revert with ExecutionDataExtractionError
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractBatchExecAndOpData(executionData);
    }

    /**
     * @notice Test extracting executionData with second offset exceeding data length (fails with
     * ExecutionDataExtractionError)
     */
    function test_RevertWhen_ExtractBatchExecAndOpData_ExcessiveOffset() public {
        // Create execution data with two offsets but second offset beyond data length
        Execution[] memory calls = new Execution[](1);
        calls[0] = Execution({ target: address(0x1234), value: 0, callData: "" });

        uint256 nonce = 12_345;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = new bytes(65);
        bytes memory opData = abi.encodePacked(nonce, deadline, signature);

        bytes memory executionData = abi.encode(calls, opData);

        // Modify the second offset to point beyond the total length
        uint256 dataLength = executionData.length;
        assembly {
            // Set the second offset to a value beyond the data length
            mstore(add(executionData, 64), add(dataLength, 100))
        }

        // Call should revert with ExecutionDataExtractionError
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractBatchExecAndOpData(executionData);
    }

    /**
     * @notice Test extracting single execution data with opData
     */
    function test_ExtractSingleExecAndOpData_WithOpData() public view {
        // Create single execution data with opData
        // For single calls: abi.encode(abi.encodePacked(target, value, callData), opData)
        address target = address(0x5678);
        uint256 value = 0.2 ether;
        bytes memory callData = abi.encodeWithSignature("doSomething()");

        // Pack the execution data
        bytes memory packedExecutionData = abi.encodePacked(target, value, callData);

        // Create proper opData with nonce, deadline, and signature
        uint256 nonce = 12_345;
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = new bytes(65);
        bytes memory opData = abi.encodePacked(nonce, deadline, signature);

        // Encode as per SINGLE_CALL_OPDATA_AUTH format
        bytes memory executionData = abi.encode(packedExecutionData, opData);

        // Call exposed function to extract
        (bytes memory extractedSingleData, bytes memory extractedOpData) =
            harness.exposed_extractSingleExecAndOpData(executionData);

        // Verify extracted data
        assertEq(keccak256(extractedSingleData), keccak256(packedExecutionData), "Extracted single data should match");
        assertEq(extractedOpData.length, 129, "OpData should be 129 bytes");
        assertEq(keccak256(extractedOpData), keccak256(opData), "Extracted opData should match original opData");
    }

    /**
     * @notice Test extracting single call with no opData
     */
    function test_RevertWhen_ExtractSingleExecAndOpData_7579SingleCallDefaultModeSelectorEncoding() public {
        // Create single execution data as per EIP-7579 single call encoding
        // For such call type and default execution mode: abi.encodePacked(target, value, callData)
        address target = address(0x5678);
        uint256 value = 1000 ether;
        bytes memory callData = abi.encodeWithSignature("doSomething()");

        // Pack the execution data
        bytes memory packedExecutionData = abi.encodePacked(target, value, callData);

        // Call should revert with ExecutionDataExtractionError because it lacks opData
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractSingleExecAndOpData(packedExecutionData);

        // Craft an execution data that attempts to bypass the length checks
        // For such call type and default execution mode: abi.encodePacked(target, value, callData)
        bytes32 fakecOffset = bytes32(uint256(0x40));
        bytes32 fakeOpDataOffset = bytes32(uint256(0x40));

        // Pack the execution data
        bytes memory packedExecutionData2 = abi.encodePacked(fakecOffset, fakeOpDataOffset, callData);

        // Call should revert with ExecutionDataExtractionError because it lacks opData
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractSingleExecAndOpData(packedExecutionData2);

        // Craft an execution data that attempts to bypass the bounds checks
        bytes32 firstWord = bytes32(uint256(0x40));
        bytes32 secondWord = bytes32(uint256(0x40));

        // Pack the execution data
        bytes memory callData3 = abi.encodeWithSelector(bytes4(0x00000000), bytes28(uint224(0x34)));
        bytes memory packedExecutionData3 = abi.encodePacked(firstWord, secondWord, callData3);

        // Call should revert with ExecutionDataExtractionError because it lacks opData
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractSingleExecAndOpData(packedExecutionData3);
    }

    /**
     * @notice Test extracting single execution data with first offset less than 64
     */
    function test_RevertWhen_ExtractSingleExecAndOpData_LowFirstOffset() public {
        // Create invalid execution data with first offset < 64
        bytes memory invalidData = new bytes(96);
        // Set the first offset to 32 (less than required 64)
        assembly {
            mstore(add(invalidData, 32), 32)
        }

        // Call should revert with ExecutionDataExtractionError
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractSingleExecAndOpData(invalidData);
    }

    /**
     * @notice Test extracting single execution data with second offset less than 64
     */
    function test_RevertWhen_ExtractSingleExecAndOpData_LowSecondOffset() public {
        // Create execution data that would have valid first offset but invalid second
        address target = address(0x1234);
        uint256 value = 0;
        bytes memory callData = "";
        bytes memory packedData = abi.encodePacked(target, value, callData);
        bytes memory opData = abi.encodePacked(uint256(123), uint256(456), new bytes(65));
        bytes memory executionData = abi.encode(packedData, opData);

        // Modify the second offset to be less than 64
        assembly {
            mstore(add(executionData, 64), 32) // Should be at least 64
        }

        // Call should revert with ExecutionDataExtractionError
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractSingleExecAndOpData(executionData);
    }

    /**
     * @notice Test extracting single execution data with second offset exceeding data length
     */
    function test_RevertWhen_ExtractSingleExecAndOpData_ExcessiveOffset() public {
        // Create valid single execution data
        address target = address(0x1234);
        uint256 value = 0;
        bytes memory callData = "";
        bytes memory packedData = abi.encodePacked(target, value, callData);
        bytes memory opData = abi.encodePacked(uint256(123), uint256(456), new bytes(65));
        bytes memory executionData = abi.encode(packedData, opData);

        // Modify the second offset to exceed data length
        uint256 dataLength = executionData.length;
        assembly {
            mstore(add(executionData, 64), add(dataLength, 100))
        }

        // Call should revert with ExecutionDataExtractionError
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractSingleExecAndOpData(executionData);
    }

    // =============================================================
    //                       CALL TESTS
    // =============================================================

    /**
     * @notice Test calling a valid contract with data and ETH
     */
    function test_Call_SuccessWithValueAndData() public {
        // Deploy mock call target
        MockCallTarget target = new MockCallTarget();

        // Prepare call data
        bytes memory callData = abi.encodeWithSignature("returnUint(uint256)", 42);
        uint256 callValue = 0.1 ether;

        // Fund the harness contract
        vm.deal(address(harness), 1 ether);

        // Execute the call through harness
        harness.exposed_call(address(target), callValue, callData);

        // Verify results
        assertEq(target.storedValue(), callValue, "Target should receive the ETH value");
        assertEq(target.receivedValue(), callValue, "Target should record the correct received value");
        assertEq(address(target).balance, callValue, "Target balance should be updated");
    }

    /**
     * @notice Test calling a contract that returns no data
     */
    function test_Call_SuccessWithEmptyReturn() public {
        // Deploy mock call target
        MockCallTarget target = new MockCallTarget();

        // Prepare call data for fallback function (doesn't return data)
        bytes memory callData = hex"deadbeef"; // Random data for fallback
        uint256 callValue = 0.1 ether;

        // Fund the harness contract
        vm.deal(address(harness), 1 ether);

        // Execute the call through harness
        harness.exposed_call(address(target), callValue, callData);

        // Verify results
        assertEq(target.storedValue(), callValue, "Target should receive the ETH value");
        assertEq(target.receivedValue(), callValue, "Target should record the correct received value");
        assertEq(address(target).balance, callValue, "Target balance should be updated");

        // Verify lastData contains our callData
        assertEq(keccak256(target.lastData()), keccak256(callData), "Target should receive the correct call data");
    }

    /**
     * @notice Test calling a non-contract address with value and data
     * @dev This test checks that "value with memo" transfers to EOAs is a valid execution
     */
    function test_Call_NonContractAddressWithValue() public {
        // Create an EOA (not a contract)
        address payable nonContract = payable(address(0x1234));
        // Record initial balance
        uint256 initialBalance = nonContract.balance;

        // Prepare call data
        bytes memory callData = bytes("dosomething");
        uint256 callValue = 0.1 ether;
        // Fund the harness contract
        vm.deal(address(harness), 1 ether);

        // Execute the call through harness - should succeed
        harness.exposed_call(nonContract, callValue, callData);

        // Verify results
        assertEq(nonContract.balance, initialBalance + callValue, "Recipient should receive the ETH");
    }

    /**
     * @notice Test calling a non-contract address with zero value doesn't revert
     */
    function test_Call_NonContractAddressWithZeroValue() public {
        // Create an EOA (not a contract)
        address payable nonContract = payable(address(0x1234));

        // Prepare call data
        bytes memory callData = hex"deadbeef";
        uint256 callValue = 0; // No value

        // This call should not revert
        bool callFailed = true;
        try harness.exposed_call(nonContract, callValue, callData) {
            // Call succeeded
            callFailed = false;
        } catch {
            callFailed = true;
        }

        // Assert that the call was successful
        assertTrue(!callFailed, "Call to non-contract address with zero value should not revert");
    }

    /**
     * @notice Test sending ETH to an EOA with empty calldata
     */
    function test_Call_SendEthToEOA() public {
        // Create an EOA (not a contract)
        address payable recipient = payable(address(0x1234));

        // Record initial balance
        uint256 initialBalance = recipient.balance;

        // Prepare empty call data (simple ETH transfer)
        bytes memory callData = "";
        uint256 callValue = 0.5 ether;

        // Fund the harness contract
        vm.deal(address(harness), 1 ether);

        // Execute the call through harness - should succeed with empty calldata
        harness.exposed_call(recipient, callValue, callData);

        // Verify results
        assertEq(recipient.balance, initialBalance + callValue, "Recipient should receive the ETH");
    }

    /**
     * @notice Test calling a contract that reverts
     */
    function test_RevertWhen_Call_ContractReverts() public {
        // Deploy mock call target
        MockCallTarget target = new MockCallTarget();

        // Make target revert on calls
        target.setShouldRevert(true);

        // Prepare call data
        bytes memory callData = hex"deadbeef";
        uint256 callValue = 0.1 ether;

        // Fund the harness contract
        vm.deal(address(harness), 1 ether);

        // Expect revert with target's revert message
        vm.expectRevert("MockCallTarget: reverted as requested");
        harness.exposed_call(address(target), callValue, callData);
    }

    // =============================================================
    //                  OP DATA DECODING TESTS
    // =============================================================

    /**
     * @notice Test decoding valid opData with nonce, deadline and signature
     */
    function test_DecodeOpData_Valid() public view {
        // Create valid opData (32 bytes nonce + 32 bytes deadline + 65 bytes signature)
        uint256 expectedNonce = 12_345;
        uint256 expectedDeadline = block.timestamp + 1 hours;
        bytes memory signature = new bytes(65);
        for (uint256 i = 0; i < 65; i++) {
            signature[i] = bytes1(uint8(i));
        }

        bytes memory opData = abi.encodePacked(expectedNonce, expectedDeadline, signature);

        // Call exposed function to decode opData
        (uint256 decodedNonce, uint256 decodedDeadline, bytes memory decodedSignature) =
            harness.exposed_decodeOpData(opData);

        // Verify results
        assertEq(decodedNonce, expectedNonce, "Decoded nonce should match expected");
        assertEq(decodedDeadline, expectedDeadline, "Decoded deadline should match expected");
        assertEq(keccak256(decodedSignature), keccak256(signature), "Decoded signature should match expected");
    }

    /**
     * @notice Test decoding invalid opData (wrong length)
     */
    function test_RevertWhen_DecodeOpData_InvalidLength() public {
        // Create invalid opData (wrong length)
        bytes memory invalidOpData = new bytes(50); // Not at least 129 bytes

        // Call should revert with OpDataDecodingError
        vm.expectRevert(LibErrors.OpDataDecodingError.selector);
        harness.exposed_decodeOpData(invalidOpData);
    }
}
