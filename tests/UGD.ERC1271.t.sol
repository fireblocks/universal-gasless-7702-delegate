// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { UniversalGaslessDelegationHelper, UniversalGaslessDelegate } from "./UniversalGaslessDelegationHelper.sol";
import { LibErrors } from "../src/library/LibErrors.sol";
import { MockKillSwitch } from "./mocks/MockKillSwitch.sol";

/**
 * @title Universal Gasless Delegate (UGD) ERC1271 Implementation Test
 * @dev Test suite for verifying that an EOA Delegated to UGD correctly validates signatures
 * per the ERC-1271 standard.
 */
contract UGDERC1271Test is Test, UniversalGaslessDelegationHelper {
    address public userA;
    uint256 private userAPrivateKey;
    address public delegatedAccount;

    // Constants
    bytes4 internal constant ERC1271_MAGIC_VALUE = IERC1271.isValidSignature.selector;
    bytes4 internal constant ERC1271_INVALID_VALUE = 0xffffffff;

    // Test message and hash
    string internal constant TEST_MESSAGE = "ERC1271 test message";
    bytes32 internal constant TEST_MESSAGE_HASH = keccak256(abi.encodePacked(TEST_MESSAGE));

    function setUp() public {
        // Set up mock killswitch
        killswitchContract = new MockKillSwitch();

        // Create UniversalGaslessDelegate
        gaslessDelegate = new UniversalGaslessDelegate(address(killswitchContract));

        // Set up a user with private key
        (userA, userAPrivateKey) = makeAddrAndKey("delegatingUserA");
        vm.deal(userA, 10 ether);

        // Set up delegation for userA to gaslessDelegate
        delegatedAccount = setupDelegation(userA, userAPrivateKey, address(gaslessDelegate));
        assertEq(delegatedAccount, userA, "Delegated account should be the same as the user account");
    }

    /**
     * @dev Test that a valid signature from the delegated account is correctly validated
     */
    function test_ValidSignature() public view {
        // Create a valid signature using the userA private key
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(TEST_MESSAGE_HASH);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userAPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Call isValidSignature on the delegated account
        (bool success, bytes memory data) = delegatedAccount.staticcall(
            abi.encodeWithSelector(IERC1271.isValidSignature.selector, ethSignedMessageHash, signature)
        );

        assertTrue(success, "Call to isValidSignature should succeed");
        bytes4 returnedValue = abi.decode(data, (bytes4));
        assertEq(returnedValue, ERC1271_MAGIC_VALUE, "Should return the ERC1271 magic value for valid signatures");
    }

    // =============================================================
    //                NEGATIVE TEST CASES
    // =============================================================

    /**
     * @dev Test that an invalid signature is correctly rejected
     */
    function test_InvalidSignature() public view {
        // Create an invalid signature by using the wrong private key
        uint256 wrongPrivateKey = 0xCAFE;
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(TEST_MESSAGE_HASH);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, ethSignedMessageHash);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        // Call isValidSignature on the delegated account
        (bool success, bytes memory data) = delegatedAccount.staticcall(
            abi.encodeWithSelector(IERC1271.isValidSignature.selector, ethSignedMessageHash, invalidSignature)
        );

        assertTrue(success, "Call to isValidSignature should succeed even with invalid signature");
        bytes4 returnedValue = abi.decode(data, (bytes4));
        assertEq(returnedValue, ERC1271_INVALID_VALUE, "Should return the invalid value for invalid signatures");
    }

    /**
     * @dev Test that a tampered message hash is correctly rejected
     */
    function test_TamperedMessageHash() public view {
        // Create a valid signature for the original message
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(TEST_MESSAGE_HASH);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userAPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Use a different message hash when verifying
        bytes32 differentHash =
            MessageHashUtils.toEthSignedMessageHash(keccak256(abi.encodePacked("Different message")));

        // Call isValidSignature with the tampered hash
        (bool success, bytes memory data) = delegatedAccount.staticcall(
            abi.encodeWithSelector(IERC1271.isValidSignature.selector, differentHash, signature)
        );

        assertTrue(success, "Call to isValidSignature should succeed");
        bytes4 returnedValue = abi.decode(data, (bytes4));
        assertEq(returnedValue, ERC1271_INVALID_VALUE, "Should return the invalid value for tampered message hash");
    }

    /**
     * @dev Test that an empty signature is correctly rejected
     */
    function test_EmptySignature() public view {
        // Create an empty signature
        bytes memory emptySignature = new bytes(0);

        // Call isValidSignature with empty signature
        (bool success, bytes memory data) = delegatedAccount.staticcall(
            abi.encodeWithSelector(
                IERC1271.isValidSignature.selector,
                MessageHashUtils.toEthSignedMessageHash(TEST_MESSAGE_HASH),
                emptySignature
            )
        );

        assertTrue(success, "Call to isValidSignature should succeed");
        bytes4 returnedValue = abi.decode(data, (bytes4));
        assertEq(returnedValue, ERC1271_INVALID_VALUE, "Should return the invalid value for empty signature");
    }

    /**
     * @dev Test that a malformed signature (wrong length) is correctly rejected
     */
    function test_MalformedSignature() public view {
        // Create a malformed signature (wrong length)
        bytes memory malformedSignature = new bytes(60); // Not 65 bytes

        // Call isValidSignature with malformed signature
        (bool success, bytes memory data) = delegatedAccount.staticcall(
            abi.encodeWithSelector(
                IERC1271.isValidSignature.selector,
                MessageHashUtils.toEthSignedMessageHash(TEST_MESSAGE_HASH),
                malformedSignature
            )
        );

        assertTrue(success, "Call to isValidSignature should succeed");
        bytes4 returnedValue = abi.decode(data, (bytes4));
        assertEq(returnedValue, ERC1271_INVALID_VALUE, "Should return the invalid value for malformed signature");
    }

    /**
     * @dev Test that calling isValidSignature directly on the implementation fails
     */
    function test_RevertWhen_CallingImplementationDirectly() public {
        // Create a valid signature
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(TEST_MESSAGE_HASH);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userAPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Try to call isValidSignature directly on the implementation
        vm.expectRevert(LibErrors.UnauthorizedCallContext.selector);
        IERC1271(address(gaslessDelegate)).isValidSignature(ethSignedMessageHash, signature);
    }
}
