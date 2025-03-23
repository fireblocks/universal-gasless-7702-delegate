// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.27;

import { IERC7821 } from "../../src/interface/IERC7821.sol";

/**
 * @title UGDNonReceiverMock
 * @dev A mock UGD contract that does not implement ERC721 receiving capabilities
 */
contract UGDNonReceiverMock is IERC7821 {
    address public immutable killswitchContract;

    constructor(address _killswitchContract) {
        require(_killswitchContract != address(0), "Invalid killswitch address");
        killswitchContract = _killswitchContract;
    }

    function execute(bytes32 mode, bytes calldata executionData) external payable {
        // Empty implementation for testing
    }

    function supportsExecutionMode(bytes32) external pure returns (bool) {
        return true;
    }
}
