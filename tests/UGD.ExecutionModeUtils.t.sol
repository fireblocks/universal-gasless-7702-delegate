// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { UniversalGaslessDelegate } from "../src/UniversalGaslessDelegate.sol";
import { UniversalGaslessDelegationHelper } from "./UniversalGaslessDelegationHelper.sol";
import { LibErrors } from "../src/library/LibErrors.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC7579Utils } from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import { MockKillSwitch } from "./mocks/MockKillSwitch.sol";
import { MockCallTarget } from "./mocks/MockCallTarget.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title UniversalGaslessDelegateHarness
 * @dev Test harness for internal functions of UniversalGaslessDelegate
 */
contract UniversalGaslessDelegateHarness is UniversalGaslessDelegate {
    constructor(address _killswitchContract) UniversalGaslessDelegate(_killswitchContract) { }

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
     * @notice Expose internal function for testing
     */
    function exposed_extractExecAndOpData(bytes calldata executionData)
        external
        pure
        returns (bytes memory singleOrBatchExecutionData, bytes memory opData)
    {
        return _extractExecAndOpData(executionData);
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
    function exposed_call(address target, uint256 value, bytes calldata data) external returns (bytes memory) {
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
    function test_ExtractExecAndOpData_OnlyCalls() public view {
        // Create execution data with only calls (no opData)
        bytes memory callsData = abi.encode("test call data");
        bytes memory executionData = abi.encode(callsData);

        // Call exposed function to extract OpData
        (bytes memory extractedCalls, bytes memory extractedOpData) =
            harness.exposed_extractExecAndOpData(executionData);

        // Verify results
        assertEq(keccak256(extractedCalls), keccak256(callsData), "Extracted calls should match original calls");
        assertEq(extractedOpData.length, 0, "Extracted opData should be empty");
    }

    /**
     * @notice Test extracting executionData when both calls and opData are provided
     */
    function test_ExtractExecAndOpData_CallsAndOpData() public view {
        // Create execution data with both calls and opData
        bytes memory callsData = abi.encode("test call data");
        bytes memory opData = abi.encode(uint256(123), "signature");
        bytes memory executionData = abi.encode(callsData, opData);

        // Call exposed function to extract OpData
        (bytes memory extractedCalls, bytes memory extractedOpData) =
            harness.exposed_extractExecAndOpData(executionData);

        // Verify results
        assertEq(keccak256(extractedCalls), keccak256(callsData), "Extracted calls should match original calls");
        assertEq(keccak256(extractedOpData), keccak256(opData), "Extracted opData should match original opData");
    }

    /**
     * @notice Test extracting executionData when first offset is less than 32 (fails with ExecutionDataExtractionError)
     */
    function test_RevertWhen_ExtractExecAndOpData_LowFirstOffset() public {
        // Create invalid execution data with first offset < 32
        bytes memory invalidData = new bytes(64);
        // Set the first 32 bytes (offset) to a value less than 32 to trigger the revert
        assembly {
            // Set offset to 16, which is less than the required minimum of 32
            mstore(add(invalidData, 32), 16)
        }

        // Call should revert with ExecutionDataExtractionError
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractExecAndOpData(invalidData);
    }

    /**
     * @notice Test extracting executionData with non-ABI encoded data (fails with ExecutionDataExtractionError)
     */
    function test_RevertWhen_ExtractExecAndOpData_NonAbiEncoded() public {
        // Create invalid execution data (not valid ABI encoding)
        bytes memory invalidData = abi.encodePacked(bytes4(0x12345678));

        // Call should revert with ExecutionDataExtractionError
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractExecAndOpData(invalidData);
    }

    /**
     * @notice Test extracting executionData with second offset less than 64 (fails with ExecutionDataExtractionError)
     */
    function test_RevertWhen_ExtractExecAndOpData_LowSecondOffset() public {
        // Create execution data with both items but invalid second offset
        // First create normal encoding with two items
        bytes memory callsData = abi.encode("test call data");
        bytes memory opData = abi.encode("test op data");
        bytes memory executionData = abi.encode(callsData, opData);

        // Modify the second offset to be less than 64
        assembly {
            // The second offset starts at position 64 (after length prefix and first offset)
            mstore(add(executionData, 64), 32) // Should be at least 64
        }

        // Call should revert with ExecutionDataExtractionError
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractExecAndOpData(executionData);
    }

    /**
     * @notice Test extracting executionData with second offset exceeding data length (fails with
     * ExecutionDataExtractionError)
     */
    function test_RevertWhen_ExtractExecAndOpData_ExcessiveOffset() public {
        // Create execution data with two offsets but second offset beyond data length
        bytes memory callsData = abi.encode("test call data");
        bytes memory opData = abi.encode("test op data");
        bytes memory executionData = abi.encode(callsData, opData);

        // Modify the second offset to point beyond the total length
        uint256 dataLength = executionData.length;
        assembly {
            // Set the second offset to a value beyond the data length
            mstore(add(executionData, 64), add(dataLength, 100))
        }

        // Call should revert with ExecutionDataExtractionError
        vm.expectRevert(LibErrors.ExecutionDataExtractionError.selector);
        harness.exposed_extractExecAndOpData(executionData);
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
        bytes memory returnData = harness.exposed_call(address(target), callValue, callData);

        // Decode the return data
        uint256 returnedValue = abi.decode(returnData, (uint256));

        // Verify results
        assertEq(returnedValue, 42, "Call should return the correct value");
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
        bytes memory returnData = harness.exposed_call(address(target), callValue, callData);

        // Verify results
        assertEq(returnData.length, 0, "Return data should be empty");
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
        bytes memory returnData = harness.exposed_call(nonContract, callValue, callData);

        // Verify results
        assertEq(returnData.length, 0, "Return data should be empty");
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

        // Execute the call through harness - should not revert with zero value
        bytes memory returnData = harness.exposed_call(nonContract, callValue, callData);

        // Verify return data is empty
        assertEq(returnData.length, 0, "Return data should be empty");
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
        bytes memory returnData = harness.exposed_call(recipient, callValue, callData);

        // Verify results
        assertEq(returnData.length, 0, "Return data should be empty");
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
