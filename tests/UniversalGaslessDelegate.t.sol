// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { ERC7579Utils, Execution } from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import { Packing } from "@openzeppelin/contracts/utils/Packing.sol";
import { UniversalGaslessDelegationHelper, UniversalGaslessDelegate } from "./UniversalGaslessDelegationHelper.sol";
import { MockKillSwitch } from "./mocks/MockKillSwitch.sol";
import { MockFallback } from "./mocks/MockFallback.sol";
import { MockCallTarget } from "./mocks/MockCallTarget.sol";
import { KillSwitch } from "../src/KillSwitch.sol";
import { LibErrors } from "../src/library/LibErrors.sol";
import { IERC7821 } from "../src/interface/IERC7821.sol";

/**
 * @title Universal Gasless Delegate Test
 * @dev Test suite for the UniversalGaslessDelegate contract
 */
contract UniversalGaslessDelegateTest is Test, UniversalGaslessDelegationHelper {
    // NOTE: Inherits the relevant variable(s) from the helper contract:
    // - UniversalGaslessDelegate gaslessDelegate;
    // - address mockKillswitchContract;

    address public userA;
    uint256 private userAPrivateKey;
    UniversalGaslessDelegate private delegatedAccount;
    address private pausedMockKillswitchContract;

    using Packing for *;

    function setUp() public {
        // Set up a user with private key
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        vm.deal(userA, 10 ether);

        // Set up mock killswitch in unpaused state
        mockKillswitchContract = address(new MockKillSwitch());

        // Set up a paused mock killswitch
        pausedMockKillswitchContract = address(new MockKillSwitch());
        MockKillSwitch(pausedMockKillswitchContract).pause();

        // Create UniversalGaslessDelegate with unpaused killswitch
        gaslessDelegate = new UniversalGaslessDelegate(mockKillswitchContract);
        // Set up delegation for userA to gaslessDelegate
        delegatedAccount =
            UniversalGaslessDelegate(payable(setupDelegation(userA, userAPrivateKey, address(gaslessDelegate))));
        assertEq(address(delegatedAccount), userA, "Delegated account should be the same as the user account");
    }

    function test_constructsCorrectly() public view {
        // Test that the killswitch contract address has been set correctly
        assertEq(
            address(gaslessDelegate.killswitchContract()),
            mockKillswitchContract,
            "Killswitch contract address should be set correctly"
        );
    }

    function test_RevertWhen_ConstructingWithPausedKillswitch() public {
        vm.expectRevert(LibErrors.InvalidImplementation.selector);
        new UniversalGaslessDelegate(pausedMockKillswitchContract);
    }

    function test_RevertWhen_AddressIsNotKillswitch() public {
        address notKillSwitchContract;
        // Set up a non-killswitch contract address
        notKillSwitchContract = address(new MockFallback());
        vm.expectRevert();
        new UniversalGaslessDelegate(notKillSwitchContract);
    }

    function test_supportsSingleNonRevertingOpDataAuthExecutionMode() public view {
        // First verify the account is properly delegated
        assertDelegated(userA, address(gaslessDelegate));

        // Construct the execution mode. Signal that noise in payload is allowed.
        // CallType = (0x00), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x78210001), ModePayload = ANY
        bytes32 mode = bytes32(0x00000000000078210001FAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFAFA);

        // Call supportsExecutionMode directly on the delegated account
        bool isSupported = IERC7821(delegatedAccount).supportsExecutionMode(mode);
        assertTrue(isSupported, "The mode should be supported");
    }

    function test_supportsBatchNonRevertingOpDataAuthExecutionMode() public view {
        // First verify the account is properly delegated
        assertDelegated(userA, address(gaslessDelegate));

        // Construct the execution mode.
        // CallType = (0x01), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x78210001), ModePayload = ANY
        // Mode ID 2: Batch call with Auth mode selector
        bytes32 mode = bytes32(0x0100000000007821000100000000000000000000000000000000000000000000);

        // Call supportsExecutionMode directly on the delegated account
        bool isSupported = IERC7821(delegatedAccount).supportsExecutionMode(mode);
        assertTrue(isSupported, "The mode should be supported");
    }

    function test_supportsBatchNonRevertingDefaultModeExecutionMode() public view {
        // First verify the account is properly delegated
        assertDelegated(userA, address(gaslessDelegate));

        // Construct the execution mode.
        // CallType = (0x01), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x00000000), ModePayload = ANY
        // Mode ID 3: Batch call with Empty mode selector
        bytes32 mode = bytes32(0x0100000000000000000000000000000000000000000000000000000000000000);

        // Call supportsExecutionMode directly on the delegated account
        bool isSupported = IERC7821(delegatedAccount).supportsExecutionMode(mode);
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
        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));

        // Construct the execution mode
        bytes32 mode = fuzzCallType.pack_1_1(fuzzExecType).pack_2_4(fuzzUnused).pack_6_4(fuzzModeSelector).pack_10_22(
            fuzzModePayload
        );
        bytes32 modeWithAnyPayload = mode & 0xFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000000000000000;
        // Construct a list of allowed modes
        bytes32[] memory allowedModes = new bytes32[](3);
        // Mode 1: CallType = (0x00), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x78210001), ModePayload = ANY
        allowedModes[0] = bytes32(0x0000000000007821000100000000000000000000000000000000000000000000);
        // Mode 2: CallType = (0x01), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x78210001), ModePayload = ANY
        allowedModes[1] = bytes32(0x0100000000007821000100000000000000000000000000000000000000000000);
        // Mode 3: CallType = (0x01), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x00000000), ModePayload = ANY
        allowedModes[2] = bytes32(0x0100000000000000000000000000000000000000000000000000000000000000);
        // Exclude expected positive cases
        vm.assume(
            modeWithAnyPayload != allowedModes[0] && modeWithAnyPayload != allowedModes[1]
                && modeWithAnyPayload != allowedModes[2]
        );

        // Call supportsExecutionMode directly on the delegated account
        bool isSupported = IERC7821(delegatedAccount).supportsExecutionMode(mode);
        assertFalse(isSupported, "The mode should not be supported");
    }

    // =============================================================
    //                     VALUE RECEPTION TESTS
    // =============================================================

    function test_canReceiveEther() public {
        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));

        // Send ETH directly to the delegated account
        uint256 sendAmount = 1 ether;
        uint256 balanceBefore = address(delegatedAccount).balance;

        (bool success,) = address(delegatedAccount).call{ value: sendAmount }("");

        assertTrue(success, "ETH transfer should succeed");
        assertEq(address(delegatedAccount).balance, balanceBefore + sendAmount, "Should have received the ETH");
    }

    function test_canReceiveEtherWithData() public {
        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));

        // Send ETH with arbitrary data to trigger the fallback function
        uint256 sendAmount = 1 ether;
        uint256 balanceBefore = address(delegatedAccount).balance;

        // Create arbitrary calldata (simulating "memo" or confused interface call)
        bytes memory arbitraryData = abi.encode("This is a memo for the transaction");

        (bool success,) = address(delegatedAccount).call{ value: sendAmount }(arbitraryData);

        assertTrue(success, "ETH transfer with data should succeed");
        assertEq(
            address(delegatedAccount).balance,
            balanceBefore + sendAmount,
            "Delegated account should receive the ETH via fallback"
        );
    }

    function test_execute_withValidSignature() public {
        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));

        // Deploy a mock target contract to call
        MockCallTarget mockTarget = new MockCallTarget();
        vm.deal(address(mockTarget), 0);

        // Set up execution parameters
        address target = address(mockTarget);
        uint256 value = 0.1 ether;
        bytes memory callData = abi.encodeWithSelector(MockCallTarget.returnUint.selector, 42);

        // Construct the execution mode - Single call type with Auth (Mode ID = 1)
        // CallType = (0x00), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x78210001), ModePayload = 0
        bytes32 mode = bytes32(hex"00000000000078210001");

        // Set up a nonce for this operation
        uint256 nonce = 123;

        // Calculate the digest for signing using the same algorithm as in
        // TypedAuthorization._hashTypedSingleExecutionAuthorization
        // Step 0: Get domain separator components
        bytes32 domainTypehash = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator = keccak256(abi.encode(domainTypehash, block.chainid, address(delegatedAccount)));
        // Step 1: Calculate the execution hash for the single execution
        bytes32 executionTypehash = keccak256("Execution(address target,uint256 value,bytes data)");
        bytes32 seHash = keccak256(abi.encode(executionTypehash, target, value, keccak256(callData)));
        // Step 2: Package as single item execution array hash
        bytes32 executionsHash = keccak256(abi.encodePacked(seHash));
        // Step 3: Create the final struct hash including the mode and nonce
        bytes32 authorizationTypehash = keccak256(
            "AuthorizedExecutions(bytes32 mode,Execution[] calls,uint256 nonce)Execution(address target,uint256 value,bytes data)"
        );
        bytes32 structHash = keccak256(abi.encode(authorizationTypehash, mode, executionsHash, nonce));
        // Step 4: Create the final digest
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        // Sign the digest with userA's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userAPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Encode opData (nonce + signature)
        bytes memory opData = abi.encodePacked(abi.encode(nonce), signature);

        // Encode executionData
        bytes memory singleExecData = abi.encodePacked(target, value, callData); // as per EIP-7579
        bytes memory executionData = abi.encode(singleExecData, opData);

        // Fund the delegated user
        vm.deal(address(delegatedAccount), 1 ether);

        // Check initial balances
        uint256 initialTargetBalance = address(mockTarget).balance;
        uint256 initialDelegatedBalance = address(delegatedAccount).balance;

        // Execute the transaction
        vm.startPrank(address(0xdead)); // Use any address as the caller
        vm.expectEmit(true, true, true, true);
        emit MockCallTarget.Called(userA, value, callData);
        delegatedAccount.execute(mode, executionData);
        vm.stopPrank();

        // Verify the correct state changes
        assertEq(address(mockTarget).balance, initialTargetBalance + value, "Target should have received ETH");
        assertEq(
            address(delegatedAccount).balance, initialDelegatedBalance - value, "Delegated EOA should have sent ETH"
        );

        // Verify the mock contract received the correct data and returned the expected value
        assertEq(mockTarget.storedValue(), value, "Target should have recorded the value");
        assertEq(mockTarget.lastData(), callData, "Target should have received the correct calldata");
    }

    function test_RevertWhen_DirectlyCallingReceiveOnImplementation() public {
        // Record the initial balance
        uint256 initialBalance = address(gaslessDelegate).balance;

        // Try to send ETH directly to the implementation contract (should fail)
        (bool success,) = address(gaslessDelegate).call{ value: 1 ether }("");

        assertFalse(success, "Direct ETH transfer to implementation should fail");
        assertEq(
            address(gaslessDelegate).balance, initialBalance, "Implementation contract balance should remain unchanged"
        );
    }

    function test_RevertWhen_DirectlyCallingFallbackOnImplementation() public {
        // Record the initial balance
        uint256 initialBalance = address(gaslessDelegate).balance;

        // Try to send ETH with data directly to the implementation contract (should fail)
        bytes memory arbitraryData = abi.encode("This should fail");
        (bool success,) = address(gaslessDelegate).call{ value: 1 ether }(arbitraryData);

        assertFalse(success, "Direct ETH transfer with data to implementation should fail");
        assertEq(
            address(gaslessDelegate).balance, initialBalance, "Implementation contract balance should remain unchanged"
        );
    }

    function test_execute_withValidSignature_batchMode() public {
        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));

        // Deploy multiple mock target contracts to call
        MockCallTarget mockTarget1 = new MockCallTarget();
        MockCallTarget mockTarget2 = new MockCallTarget();
        vm.deal(address(mockTarget1), 0);
        vm.deal(address(mockTarget2), 0);

        // Set up execution parameters for first call
        address target1 = address(mockTarget1);
        uint256 value1 = 0.05 ether;
        bytes memory callData1 = abi.encodeWithSelector(MockCallTarget.returnUint.selector, 42);

        // Set up execution parameters for second call
        address target2 = address(mockTarget2);
        uint256 value2 = 0.03 ether;
        bytes memory callData2 = abi.encodeWithSelector(MockCallTarget.returnUint.selector, 24);

        // Construct the execution mode - Batch call type with Auth (Mode ID = 2)
        // CallType = (0x01), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x78210001), ModePayload = 0
        bytes32 mode = bytes32(0x0100000000007821000100000000000000000000000000000000000000000000);

        // Set up a nonce for this operation
        uint256 nonce = 456;

        // Create execution batch array
        Execution[] memory executionBatch = new Execution[](2);
        executionBatch[0] = Execution(target1, value1, callData1);
        executionBatch[1] = Execution(target2, value2, callData2);

        // Calculate the digest for signing using the same algorithm as in
        // TypedAuthorization._hashTypedBatchExecutionAuthorization
        // Step 0: Get domain separator components
        bytes32 domainTypehash = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator = keccak256(abi.encode(domainTypehash, block.chainid, address(delegatedAccount)));
        // Step 1: Calculate execution hashes for each call in the batch
        bytes32 executionTypehash = keccak256("Execution(address target,uint256 value,bytes data)");
        bytes32[] memory executionHashes = new bytes32[](executionBatch.length);
        for (uint256 i = 0; i < executionBatch.length; i++) {
            executionHashes[i] = keccak256(abi.encode(
                executionTypehash,
                executionBatch[i].target,
                executionBatch[i].value,
                keccak256(executionBatch[i].callData)
            ));
        }
        // Step 2: Create the batch hash
        bytes memory encodedHashes = "";
        for (uint256 i = 0; i < executionHashes.length; i++) {
            encodedHashes = abi.encodePacked(encodedHashes, executionHashes[i]);
        }
        bytes32 executionsHash = keccak256(encodedHashes);
        // Step 3: Create the final struct hash including the mode and nonce
        bytes32 authorizationTypehash = keccak256(
            "AuthorizedExecutions(bytes32 mode,Execution[] calls,uint256 nonce)Execution(address target,uint256 value,bytes data)"
        );
        bytes32 structHash = keccak256(abi.encode(authorizationTypehash, mode, executionsHash, nonce));
        // Step 4: Create the final digest
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        // Sign the digest with userA's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userAPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Encode opData (nonce + signature)
        bytes memory opData = abi.encodePacked(abi.encode(nonce), signature);

        // Encode batch execution data
        bytes memory batchExecData = ERC7579Utils.encodeBatch(executionBatch);
        bytes memory executionData = abi.encode(batchExecData, opData);

        // Fund the delegated user
        vm.deal(address(delegatedAccount), 1 ether);

        // Check initial balances
        uint256 initialTarget1Balance = address(mockTarget1).balance;
        uint256 initialTarget2Balance = address(mockTarget2).balance;
        uint256 initialDelegatedBalance = address(delegatedAccount).balance;

        // Execute the transaction
        vm.startPrank(address(0xdead)); // Use any address as the caller
        
        // Expect events for both calls
        vm.expectEmit(true, true, true, true, address(mockTarget1));
        emit MockCallTarget.Called(userA, value1, callData1);
        vm.expectEmit(true, true, true, true, address(mockTarget2));
        emit MockCallTarget.Called(userA, value2, callData2);
        
        delegatedAccount.execute(mode, executionData);
        vm.stopPrank();

        // Verify the correct state changes
        assertEq(address(mockTarget1).balance, initialTarget1Balance + value1, "Target1 should have received ETH");
        assertEq(address(mockTarget2).balance, initialTarget2Balance + value2, "Target2 should have received ETH");
        assertEq(
            address(delegatedAccount).balance, 
            initialDelegatedBalance - value1 - value2, 
            "Delegated EOA should have sent total ETH"
        );
        
        // Verify the nonce was marked as used
        assertTrue(delegatedAccount.isNonceUsed(nonce), "Nonce should be marked as used");
    }

    function test_execute_selfCall_batchMode() public {
        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));

        // Deploy multiple mock target contracts to call
        MockCallTarget mockTarget1 = new MockCallTarget();
        MockCallTarget mockTarget2 = new MockCallTarget();
        vm.deal(address(mockTarget1), 0);
        vm.deal(address(mockTarget2), 0);

        // Set up execution parameters for first call
        address target1 = address(mockTarget1);
        uint256 value1 = 0.05 ether;
        bytes memory callData1 = abi.encodeWithSelector(MockCallTarget.returnUint.selector, 42);
        // Set up execution parameters for second call
        address target2 = address(mockTarget2);
        uint256 value2 = 0.03 ether;
        bytes memory callData2 = abi.encodeWithSelector(MockCallTarget.returnUint.selector, 24);
        // Construct the execution mode - Batch call with Default mode selector (Mode ID = 3)
        // CallType = (0x01), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x00000000), ModePayload = 0
        bytes32 mode = bytes32(0x0100000000000000000000000000000000000000000000000000000000000000);

        // Create execution batch array
        Execution[] memory executionBatch = new Execution[](2);
        executionBatch[0] = Execution(target1, value1, callData1);
        executionBatch[1] = Execution(target2, value2, callData2);

        // Encode batch execution data - no opData for this mode
        bytes memory executionData = ERC7579Utils.encodeBatch(executionBatch);

        // Fund the delegated user
        vm.deal(address(delegatedAccount), 1 ether);

        // Check initial balances
        uint256 initialTarget1Balance = address(mockTarget1).balance;
        uint256 initialTarget2Balance = address(mockTarget2).balance;
        uint256 initialDelegatedBalance = address(delegatedAccount).balance;

        // Execute the transaction - must be called by the delegated EOA itself
        vm.startPrank(address(delegatedAccount)); // Must be called by the delegated EOA itself
        
        // Expect events for both calls
        vm.expectEmit(true, true, true, true, address(mockTarget1));
        emit MockCallTarget.Called(userA, value1, callData1);
        vm.expectEmit(true, true, true, true, address(mockTarget2));
        emit MockCallTarget.Called(userA, value2, callData2);
        
        delegatedAccount.execute(mode, executionData);
        vm.stopPrank();

        // Verify the correct state changes
        assertEq(address(mockTarget1).balance, initialTarget1Balance + value1, "Target1 should have received ETH");
        assertEq(address(mockTarget2).balance, initialTarget2Balance + value2, "Target2 should have received ETH");
        assertEq(
            address(delegatedAccount).balance, 
            initialDelegatedBalance - value1 - value2, 
            "Delegated EOA should have sent total ETH"
        );
    }
    
    function test_RevertWhen_DirectlyCallingExecuteOnImplementation() public {
        // Construct the execution mode
        bytes32 mode = bytes32(hex"00000000000078210001");

        // Create empty execution data
        bytes memory executionData = abi.encode("dummy data");

        // Attempt to call execute directly on the implementation contract
        vm.expectRevert(LibErrors.UnauthorizedCallContext.selector);
        gaslessDelegate.execute(mode, executionData);
    }

    function test_RevertWhen_ExecuteWithUnsupportedCallType() public {
        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));

        // Construct an unsupported execution mode
        // This mode will result in modeId 0 because it doesn't match any of the supported patterns
        bytes32 unsupportedMode = bytes32(hex"ff000000000000000000"); // Use unsupported callType (0xff) = delegatecall

        // Create dummy execution data
        bytes memory executionData = abi.encode("dummy data");

        // Execution should revert with ERC7579UnsupportedCallType
        vm.expectRevert(abi.encodeWithSelector(ERC7579Utils.ERC7579UnsupportedCallType.selector, bytes1(0xff)));
        delegatedAccount.execute(unsupportedMode, executionData);
    }

    function test_RevertWhen_ExecuteWithUnsupportedExecType() public {
        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));

        // Construct a mode with unsupported exec type (0x01)
        // Call type (0x00) is valid, but exec type (0x01) is invalid
        bytes32 unsupportedMode = bytes32(hex"00010000000078210001");

        // Create dummy execution data
        bytes memory executionData = abi.encode("dummy data");

        // Execution should revert with UnsupportedExecType error
        vm.expectRevert(abi.encodeWithSelector(ERC7579Utils.ERC7579UnsupportedExecType.selector, bytes1(0x01)));
        delegatedAccount.execute(unsupportedMode, executionData);
    }

    function test_RevertWhen_ExecuteWithUnsupportedModeSelector() public {
        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));

        // Construct a mode with unsupported mode selector (0x12345678)
        // Call type (0x00) and exec type (0x00) are valid, but mode selector is invalid
        bytes32 unsupportedMode = bytes32(hex"000000000000123456780000000000000000000000000000000000000000");

        // Create dummy execution data
        bytes memory executionData = abi.encode("dummy data");

        // Execution should revert with UnsupportedModeSelector error
        vm.expectRevert(abi.encodeWithSelector(LibErrors.UnsupportedModeSelector.selector, bytes4(hex"12345678")));
        delegatedAccount.execute(unsupportedMode, executionData);
    }

    function test_RevertWhen_ExecuteWithInvalidSignature_SingleMode() public {
        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));

        // Deploy a mock target contract to call
        MockCallTarget mockTarget = new MockCallTarget();
        vm.deal(address(mockTarget), 0);

        // Set up execution parameters
        address target = address(mockTarget);
        uint256 value = 0.1 ether;
        bytes memory callData = abi.encodeWithSelector(MockCallTarget.returnUint.selector, 42);

        // Construct the execution mode - Single call type with Auth (Mode ID = 1)
        bytes32 mode = bytes32(0x0000000000007821000100000000000000000000000000000000000000000000);

        // Set up a nonce for this operation
        uint256 nonce = 789;

        // Calculate the digest for signing using the same algorithm as in
        // TypedAuthorization._hashTypedSingleExecutionAuthorization
        // Step 1: Calculate the execution hash for the single execution
        bytes32 executionTypehash = keccak256("Execution(address target,uint256 value,bytes data)");
        bytes32 seHash = keccak256(abi.encode(executionTypehash, target, value, keccak256(callData)));
        // Step 2: Package as single item execution array hash
        bytes32 executionsHash = keccak256(abi.encodePacked(seHash));
        // Step 3: Create the final struct hash including the mode and nonce
        bytes32 authorizationTypehash = keccak256(
            "AuthorizedExecutions(bytes32 mode,Execution[] calls,uint256 nonce)Execution(address target,uint256 value,bytes data)"
        );
        bytes32 structHash = keccak256(abi.encode(authorizationTypehash, mode, executionsHash, nonce));
        // Step 4: Get domain separator components
        bytes32 domainTypehash = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator = keccak256(abi.encode(domainTypehash, block.chainid, address(delegatedAccount)));
        // Step 5: Create the final digest
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        // Sign with a DIFFERENT private key than the delegated EOA's
        ( , uint256 wrongPrivateKey ) = makeAddrAndKey("wrongSigner");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        // Encode opData with invalid signature
        bytes memory opData = abi.encodePacked(abi.encode(nonce), invalidSignature);

        // Encode executionData for single call
        bytes memory singleExecData = abi.encodePacked(target, value, callData);
        bytes memory executionData = abi.encode(singleExecData, opData);

        // Fund the delegated user
        vm.deal(address(delegatedAccount), 1 ether);

        // Execute the transaction with invalid signature should revert
        vm.startPrank(address(0xdead));
        
        // The exact revert error will depend on how _isValidRawSignature is used
        // This would typically be a signature validation error
        vm.expectRevert(LibErrors.UnauthorizedExecution.selector);
        delegatedAccount.execute(mode, executionData);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_ExecuteWithInvalidSignature_BatchMode() public {
        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));

        // Deploy multiple mock target contracts to call
        MockCallTarget mockTarget1 = new MockCallTarget();
        MockCallTarget mockTarget2 = new MockCallTarget();
        vm.deal(address(mockTarget1), 0);
        vm.deal(address(mockTarget2), 0);

        // Set up execution parameters
        address target1 = address(mockTarget1);
        uint256 value1 = 0.05 ether;
        bytes memory callData1 = abi.encodeWithSelector(MockCallTarget.returnUint.selector, 42);
        address target2 = address(mockTarget2);
        uint256 value2 = 0.03 ether;
        bytes memory callData2 = abi.encodeWithSelector(MockCallTarget.returnUint.selector, 24);

        // Construct the execution mode - Batch call type with Auth (Mode ID = 2)
        bytes32 mode = bytes32(0x0100000000007821000100000000000000000000000000000000000000000000);

        // Set up a nonce for this operation
        uint256 nonce = 987;

        // Create execution batch array
        Execution[] memory executionBatch = new Execution[](2);
        executionBatch[0] = Execution(target1, value1, callData1);
        executionBatch[1] = Execution(target2, value2, callData2);

        // Calculate the digest for signing
        // Step 1: Calculate execution hashes for each call in the batch
        bytes32 executionTypehash = keccak256("Execution(address target,uint256 value,bytes data)");
        bytes32[] memory executionHashes = new bytes32[](executionBatch.length);
        for (uint256 i = 0; i < executionBatch.length; i++) {
            executionHashes[i] = keccak256(abi.encode(
                executionTypehash,
                executionBatch[i].target,
                executionBatch[i].value,
                keccak256(executionBatch[i].callData)
            ));
        }
        // Step 2: Create the batch hash
        bytes memory encodedHashes = "";
        for (uint256 i = 0; i < executionHashes.length; i++) {
            encodedHashes = abi.encodePacked(encodedHashes, executionHashes[i]);
        }
        bytes32 executionsHash = keccak256(encodedHashes);
        // Step 3: Create the final struct hash
        bytes32 authorizationTypehash = keccak256(
            "AuthorizedExecutions(bytes32 mode,Execution[] calls,uint256 nonce)Execution(address target,uint256 value,bytes data)"
        );
        bytes32 structHash = keccak256(abi.encode(authorizationTypehash, mode, executionsHash, nonce));
        // Step 4: Create the domain separator
        bytes32 domainTypehash = keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator = keccak256(abi.encode(domainTypehash, block.chainid, address(delegatedAccount)));
        // Step 5: Create the final digest
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        // Tamper with the digest to create an invalid signature
        bytes32 tamperedDigest = keccak256(abi.encodePacked(digest, "tamper"));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userAPrivateKey, tamperedDigest);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        // Encode opData with invalid signature
        bytes memory opData = abi.encodePacked(abi.encode(nonce), invalidSignature);

        // Encode batch execution data
        bytes memory batchExecData = ERC7579Utils.encodeBatch(executionBatch);
        bytes memory executionData = abi.encode(batchExecData, opData);

        // Fund the delegated user
        vm.deal(address(delegatedAccount), 1 ether);

        // Execute the transaction with invalid signature should revert
        vm.startPrank(address(0xdead));

        vm.expectRevert(LibErrors.UnauthorizedExecution.selector);
        delegatedAccount.execute(mode, executionData);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_ExecuteSelfCallBatchModeFromUnauthorizedCaller() public {
        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));

        // Construct the execution mode - Batch call with Default mode selector (Mode ID = 3)
        // CallType = (0x01), ExecType = (0x00), Unused = EMPTY, ModeSelector = (0x00000000), ModePayload = 0
        bytes32 mode = bytes32(0x0100000000000000000000000000000000000000000000000000000000000000);

        // Create dummy batch execution
        Execution[] memory executionBatch = new Execution[](1);
        executionBatch[0] = Execution(address(0x1234), 0.1 ether, "");
        
        // Encode batch execution data - no opData for this mode
        bytes memory executionData = ERC7579Utils.encodeBatch(executionBatch);

        // Call from a different address (not the delegated EOA itself)
        vm.startPrank(address(0xdead));
        
        // Execution should revert with UnauthorizedCaller error
        vm.expectRevert(LibErrors.UnauthorizedCaller.selector);
        delegatedAccount.execute(mode, executionData);
        
        vm.stopPrank();
    }
    
    function test_RevertWhen_ExecuteWithUnsupportedModeLikeSingleSelfCall() public {
        // First verify the account is properly delegated
        assertDelegated(address(delegatedAccount), address(gaslessDelegate));

        // Construct a mode with unsupported mode, single self-call
        // Call type (0x00) is valid, but exec type (0x00) is valid, not with default mode selector
        bytes32 unsupportedMode = bytes32(hex"00000000000000000000");

        // Create dummy execution data
        bytes memory executionData = abi.encode("dummy data");

        // Execution should revert with UnsupportedModeSelector error
        vm.expectRevert(LibErrors.UnsupportedExecutionMode.selector);
        delegatedAccount.execute(unsupportedMode, executionData);
    }
}
