// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {INFTFlashBorrower} from "../interfaces/INFTFlashBorrower.sol";

/// @notice Example flash loan integration, does nothing but you could insert airdrop claiming here
contract NFTFlashBorrower is INFTFlashBorrower {
    /// @notice The contract to receive flashloans from
    address public immutable delegateToken;

    constructor(address _delegateToken) {
        delegateToken = _delegateToken;
    }

    /**
     * @inheritdoc INFTFlashBorrower
     */
    function onFlashLoan(address, address token, uint256 id, bytes calldata) external payable returns (bytes32) {
        require(msg.sender == delegateToken, "untrusted flashloan sender");
        require(ERC721(token).ownerOf(id) == address(this), "flashloan failed");
        ERC721(token).approve(delegateToken, id);
        return keccak256("INFTFlashBorrower.onFlashLoan");
    }
}
