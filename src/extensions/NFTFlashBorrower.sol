// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC721} from "../interfaces/ITokenInterfaces.sol";
import {INFTFlashBorrower} from "../interfaces/INFTFlashBorrower.sol";

/// @notice Example flash loan integration, does nothing but you could insert airdrop claiming here
contract NFTFlashBorrower is INFTFlashBorrower {
    /// @notice The contract to receive flashloans from
    address public immutable delegateToken;

    error NotDelegateToken();

    constructor(address delegateToken_) {
        if (delegateToken_ == address(0)) revert NotDelegateToken();
        delegateToken = delegateToken_;
    }

    /**
     * @inheritdoc INFTFlashBorrower
     */
    function onFlashLoan(address, address token, uint256 id, bytes calldata) external payable returns (bytes32) {
        require(msg.sender == delegateToken, "untrusted flashloan sender");
        require(IERC721(token).ownerOf(id) == address(this), "flashloan failed");
        IERC721(token).approve(delegateToken, id);
        return keccak256("INFTFlashBorrower.onFlashLoan");
    }
}
