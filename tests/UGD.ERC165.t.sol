// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC7821 } from "../src/interface/IERC7821.sol";
import { UniversalGaslessDelegationHelper, UniversalGaslessDelegate } from "./UniversalGaslessDelegationHelper.sol";
import { LibErrors } from "../src/library/LibErrors.sol";
import "./mocks/MockKillSwitch.sol";
import "./mocks/UGDNonReceiverMock.sol";

/**
 * @title Universal Gasless Delegate (UGD) ERC165 Interface Support Test
 * @dev Test suite for verifying that an EOA Delegated to UGD correctly implements ERC165 interface detection
 * and only reports supporting the expected interfaces. The UGD implementation should not report ERC165 support
 * for any interfaces
 */
contract UGDERC165Test is Test, UniversalGaslessDelegationHelper {
    address public userA;
    uint256 private userAPrivateKey;

    // Interface IDs
    bytes4 private constant IERC165_INTERFACE_ID = hex"01ffc9a7"; // From EIP-165
    bytes4 private constant IERC721_RECEIVER_INTERFACE_ID = hex"150b7a02"; // From EIP-721
    bytes4 private constant IERC1155_RECEIVER_INTERFACE_ID = hex"4e2312e0"; // From EIP-1155
    // ERC-1271 does not have a strict requirement for ERC165 support. Nevertheless, we add it.
    bytes4 private constant IERC1271_INTERFACE_ID = type(IERC1271).interfaceId;
    // EIP-7821 does not have strict requirement for ERC165 support. Nevertheless, we add it.
    bytes4 private constant IERC7821_INTERFACE_ID = type(IERC7821).interfaceId;

    // Interface ID that shouldn't be supported
    bytes4 private constant UNSUPPORTED_INTERFACE_ID = bytes4(0);

    function setUp() public {
        // Set up mock killswitch
        mockKillswitchContract = address(new MockKillSwitch());

        // Create UniversalGaslessDelegate
        gaslessDelegate = new UniversalGaslessDelegate(mockKillswitchContract);

        // Set up a user with private key
        (userA, userAPrivateKey) = makeAddrAndKey("delegatingUserA");
        vm.deal(userA, 10 ether);

        // Set up delegation for userA to gaslessDelegate
        address delegatedAccount = setupDelegation(userA, userAPrivateKey, address(gaslessDelegate));
        assertEq(delegatedAccount, userA, "Delegated account should be the same as the user account");
    }

    /**
     * @dev Test that delegated account supports the IERC165 interface
     */
    function test_DelegatedSupportsIERC165Interface() public view {
        this.assertDelegated(userA, address(gaslessDelegate));
        // Call supportsInterface on the delegated account
        (bool success, bytes memory data) =
            userA.staticcall(abi.encodeWithSelector(IERC165.supportsInterface.selector, IERC165_INTERFACE_ID));

        assertTrue(success, "Call to supportsInterface should succeed");
        bool supported = abi.decode(data, (bool));
        assertTrue(supported, "Delegated account should support IERC165 interface");
    }

    /**
     * @dev Test that delegated account supports the IERC721Receiver interface
     */
    function test_DelegatedSupportsIERC721ReceiverInterface() public view {
        this.assertDelegated(userA, address(gaslessDelegate));
        // Call supportsInterface on the delegated account
        (bool success, bytes memory data) =
            userA.staticcall(abi.encodeWithSelector(IERC165.supportsInterface.selector, IERC721_RECEIVER_INTERFACE_ID));

        assertTrue(success, "Call to supportsInterface should succeed");
        bool supported = abi.decode(data, (bool));
        assertTrue(supported, "Delegated account should support IERC721Receiver interface");
    }

    /**
     * @dev Test that delegated account supports the IERC1155Receiver interface
     */
    function test_DelegatedSupportsIERC1155ReceiverInterface() public view {
        this.assertDelegated(userA, address(gaslessDelegate));
        // Call supportsInterface on the delegated account
        bool res = IERC165(userA).supportsInterface(IERC1155_RECEIVER_INTERFACE_ID);
        // Check result
        assertTrue(res, "Delegated account should support IERC1155Receiver interface");
    }

    /**
     * @dev Test that delegated account supports the IERC1271 interface
     */
    function test_DelegatedSupportsIERC1271() public view {
        this.assertDelegated(userA, address(gaslessDelegate));
        // Call supportsInterface on the delegated account
        (bool success, bytes memory data) =
            userA.staticcall(abi.encodeWithSelector(IERC165.supportsInterface.selector, IERC1271_INTERFACE_ID));

        assertTrue(success, "Call to supportsInterface should succeed");
        bool supported = abi.decode(data, (bool));
        assertTrue(supported, "Delegated account should support IERC1271 interface");
    }

    /**
     * @dev Test that delegated account does not support the IERC7821 interface via ERC165
     */
    function test_DelegatedSupportsIERC7821() public view {
        // Call supportsInterface on the delegated account
        (bool success, bytes memory data) =
            userA.staticcall(abi.encodeWithSelector(IERC165.supportsInterface.selector, IERC7821_INTERFACE_ID));

        assertTrue(success, "Call to supportsInterface should succeed");
        bool supported = abi.decode(data, (bool));
        assertTrue(supported, "Delegated account should report support for IERC7821 via ERC165");
    }

    /**
     * @dev Test that delegated account does not support an invalid interface
     * TODO: fuzz potential (low)
     */
    function test_DelegatedDoesNotSupportInvalidInterface() public view {
        // Call supportsInterface on the delegated account
        (bool success, bytes memory data) =
            userA.staticcall(abi.encodeWithSelector(IERC165.supportsInterface.selector, UNSUPPORTED_INTERFACE_ID));

        assertTrue(success, "Call to supportsInterface should succeed");
        bool supported = abi.decode(data, (bool));
        assertFalse(supported, "Delegated account should not support invalid interface");
    }

    /**
     * @dev Test that the UGD implementation address does not support token interfaces
     * TODO: fuzz potential (low)
     */
    function test_ImplementationAddrDoesNotSupportERC165() public {
        bool res = false;
        // Test for IERC721Receiver
        vm.expectRevert(LibErrors.UnauthorizedCallContext.selector);
        res = gaslessDelegate.supportsInterface(IERC721_RECEIVER_INTERFACE_ID);
        // Test for IERC1155Receiver
        vm.expectRevert(LibErrors.UnauthorizedCallContext.selector);
        res = gaslessDelegate.supportsInterface(IERC1155_RECEIVER_INTERFACE_ID);
        // Test for IERC1271
        vm.expectRevert(LibErrors.UnauthorizedCallContext.selector);
        gaslessDelegate.supportsInterface(IERC1271_INTERFACE_ID);
    }
}
