// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { Packing } from "@openzeppelin/contracts/utils/Packing.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { UniversalGaslessDelegationHelper, UniversalGaslessDelegate } from "./UniversalGaslessDelegationHelper.sol";
import { MockKillSwitch } from "./mocks/MockKillSwitch.sol";
import "./mocks/UGDNonReceiverMock.sol";

/**
 * @title MockERC721
 * @dev A simple ERC721 implementation for testing
 */
contract MockERC721 is ERC721 {
    uint256 private _nextTokenId;

    constructor() ERC721("MockNFT", "MNFT") { }

    function safeMint(address to) public returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }
}

/**
 * @title MockERC1155
 * @dev A simple ERC1155 implementation for testing
 */
contract MockERC1155 is ERC1155 {
    constructor() ERC1155("https://mock-uri.com/{id}.json") { }

    function mint(address to, uint256 id, uint256 amount) public {
        _mint(to, id, amount, "");
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts) public {
        _mintBatch(to, ids, amounts, "");
    }
}

/**
 * @title Universal Gasless Delegate (UGD) Token Receiver Test
 * @dev Test suite for the UniversalGaslessDelegate contract, specifically for receiving ERC721 and ERC1155 tokens
 */
contract UGDTokenReceiverTest is Test, UniversalGaslessDelegationHelper {
    address public userA;
    uint256 private userAPrivateKey;
    MockERC721 public mockNFT;
    MockERC1155 public mockERC1155;
    UGDNonReceiverMock public ugdNonReceiver;

    //NOTE: Inherits the relevant variable(s) from the helper contract:
    // - UniversalGaslessDelegate gaslessDelegate;

    function setUp() public {
        // Set up user with makeAddrAndKey
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        vm.deal(userA, 10 ether);

        // Set up mock killswitch
        killswitchContract = new MockKillSwitch();
        // Create UniversalGaslessDelegate
        gaslessDelegate = new UniversalGaslessDelegate(address(killswitchContract));
        // Create non-receiver UGD mock
        ugdNonReceiver = new UGDNonReceiverMock(address(killswitchContract));
        // Deploy mock NFT contract
        mockNFT = new MockERC721();
        // Deploy mock ERC1155 contract
        mockERC1155 = new MockERC1155();
    }

    /**
     * @dev Test that a regular account can receive an ERC721 token
     */
    function test_UserCanReceiveERC721() public {
        // Mint NFT to userA
        uint256 tokenId = mockNFT.safeMint(userA);

        // Verify userA has the token
        assertEq(mockNFT.ownerOf(tokenId), userA);
        assertEq(mockNFT.balanceOf(userA), 1);
    }

    /**
     * @dev Test that a delegated account can receive an ERC721 token via safeMint
     */
    function test_DelegatedUserCanReceiveERC721() public {
        // Set up delegation for userA
        address delegatedUser = setupDelegation(userA, userAPrivateKey, address(gaslessDelegate));

        // First verify the account is properly delegated
        assertDelegated(delegatedUser, address(gaslessDelegate));

        // Safe mint NFT to the delegated account
        uint256 tokenId = mockNFT.safeMint(delegatedUser);

        // Verify delegated account has the token
        assertEq(mockNFT.ownerOf(tokenId), delegatedUser);
        assertEq(mockNFT.balanceOf(delegatedUser), 1);
    }

    /**
     * @dev Test that delegation to a non-receiver UniversalGaslessDelegate implementation fails when receiving
     * ERC721 via safeMint
     */
    function test_RevertWhen_DelegatedToNonReceiverReceivesSafeERC721() public {
        // Create a new user for this test
        (address userB, uint256 userBPrivateKey) = makeAddrAndKey("userB");
        vm.deal(userB, 10 ether);

        // Set up delegation to the non-receiver implementation
        address delegatedUser = setupDelegation(userB, userBPrivateKey, address(ugdNonReceiver));

        // Verify the account is properly delegated
        assertDelegated(delegatedUser, address(ugdNonReceiver));
        // This should revert as the implementation doesn't support the IERC721Receiver interface
        vm.expectRevert();
        mockNFT.safeMint(delegatedUser);
    }

    // =============================================================
    //                   ERC1155 TOKEN TESTS
    // =============================================================

    /**
     * @dev Test that a regular account can receive an ERC1155 token
     */
    function test_UserCanReceiveERC1155() public {
        // Mint token ID 1 with amount 10 to userA
        uint256 tokenId = 1;
        uint256 amount = 10;
        mockERC1155.mint(userA, tokenId, amount);

        // Verify userA has the tokens
        assertEq(mockERC1155.balanceOf(userA, tokenId), amount);
    }

    /**
     * @dev Test that a delegated account can receive an ERC1155 token
     */
    function test_DelegatedUserCanReceiveERC1155() public {
        // Set up delegation for userA
        address delegatedUser = setupDelegation(userA, userAPrivateKey, address(gaslessDelegate));

        // First verify the account is properly delegated
        assertDelegated(delegatedUser, address(gaslessDelegate));

        // Mint token ID 1 with amount 10 to the delegated account through safe transfer
        uint256 tokenId = 1;
        uint256 amount = 10;

        // Use safeMint directly on the delegated account
        mockERC1155.mint(delegatedUser, tokenId, amount);

        // Verify delegated account has the tokens
        assertEq(mockERC1155.balanceOf(delegatedUser, tokenId), amount);
    }

    /**
     * @dev Test that a delegated account can receive batch ERC1155 tokens
     */
    function test_DelegatedUserCanReceiveBatchERC1155() public {
        // Set up delegation for userA
        address delegatedUser = setupDelegation(userA, userAPrivateKey, address(gaslessDelegate));
        // First verify the account is properly delegated
        assertDelegated(delegatedUser, address(gaslessDelegate));

        // Prepare batch data
        uint256[] memory ids = new uint256[](3);
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10;
        amounts[1] = 20;
        amounts[2] = 30;

        // Batch mint to delegated account
        mockERC1155.mintBatch(delegatedUser, ids, amounts);

        // Verify delegated account has the tokens
        for (uint256 i = 0; i < ids.length; i++) {
            assertEq(mockERC1155.balanceOf(delegatedUser, ids[i]), amounts[i]);
        }
    }

    /**
     * @dev Test that delegation to a non-receiver implementation fails when receiving ERC1155 via safe transfer
     */
    function test_RevertWhen_DelegatedToNonReceiverReceivesERC1155() public {
        // Create a new user for this test
        (address userB, uint256 userBPrivateKey) = makeAddrAndKey("userB");
        vm.deal(userB, 10 ether);

        // Set up delegation to the non-receiver implementation
        address delegatedUser = setupDelegation(userB, userBPrivateKey, address(ugdNonReceiver));
        // Verify the account is properly delegated
        assertDelegated(delegatedUser, address(ugdNonReceiver));

        uint256 tokenId = 1;
        uint256 amount = 10;

        // This should revert as the implementation doesn't support the IERC1155Receiver interface
        vm.expectRevert();
        mockERC1155.mint(delegatedUser, tokenId, amount);
    }

    // =============================================================
    //                       FUZZ TESTS
    // =============================================================
}
