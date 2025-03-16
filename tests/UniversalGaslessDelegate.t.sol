// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC7579Utils, CallType, ExecType, Mode } from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import { Packing } from "@openzeppelin/contracts/utils/Packing.sol";
import "../src/UniversalGaslessDelegate.sol"; // Adjust path if necessary

contract UniversalGaslessDelegateTest is Test {
    UniversalGaslessDelegate gaslessDelegate;
    address mockKillswitchContract;

    using Packing for *;

    function setUp() public {
        mockKillswitchContract = address(0x123);
        gaslessDelegate = new UniversalGaslessDelegate(mockKillswitchContract);
    }

    function test_constructsCorrectly() public view {
        // Test that the killswitch contract address has been set correctly
        assertEq(
            gaslessDelegate.killswitchContract(),
            mockKillswitchContract,
            "Killswitch contract address should be set correctly"
        );
    }

    // TODO: Edit all of the tests here to work in the context of the Delegated EOA, instead of the delegate contract.
    // ONLY in the context of the Delegated EOA do most of the functions and their expecations/results make sense.

    function test_supportsSingleNonRevertingOpDataAuthExecutionMode() public view {
        // Construct the execution mode. Signal that noise in payload is allowed.
        // CallType = (0x00), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x78210001), ModePayload = ANY
        bytes32 mode = bytes32(0x00000000000078210001FAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFA);

        bool isSupported = gaslessDelegate.supportsExecutionMode(mode);
        assertTrue(isSupported, "The mode should be supported");
    }


    // =============================================================
    //                       FUZZ TESTS
    // =============================================================

    /**
     * @dev Fuzz test that considers the different components in EIP-7579 execution mode.
     */
    function testFuzz_supportsExecutionMode(
        bytes1 fuzzCallType,
        bytes1 fuzzExecType,
        bytes4 fuzzUnused,
        bytes4 fuzzModeSelector,
        bytes22 fuzzModePayload
    )
        external
        view
    {
        // Construct the execution mode
        bytes32 mode = fuzzCallType.pack_1_1(fuzzExecType).pack_2_4(fuzzUnused).pack_6_4(fuzzModeSelector).pack_10_22(
            fuzzModePayload
        );
        bytes32 modeWithAnyPayload = mode & 0xFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000000000000000;
        // Construct a list of allowed modes
        bytes32[] memory allowedModes = new bytes32[](1);
        // CallType = (0x00), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x78210001), ModePayload = ANY
        allowedModes[0] = bytes32(0x0000000000007821000100000000000000000000000000000000000000000000);
        // Exclude expected positive cases
        vm.assume(modeWithAnyPayload != allowedModes[0]);
        // && ...
        // Check if the constructed mode is supported
        bool isSupported = gaslessDelegate.supportsExecutionMode(mode);
        assertFalse(isSupported, "The mode should not be supported");
        // Log the result
        console2.log("Fuzz Test - Execution Mode: ");
        console2.logBytes32(mode);
        console2.log("Is Supported: ", isSupported);
    }
}
