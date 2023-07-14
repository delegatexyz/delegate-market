// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IDelegateToken} from "src/interfaces/IDelegateToken.sol";
import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";
import {INFTFlashBorrower} from "src/interfaces/INFTFlashBorrower.sol";

contract FlashReentrancyTester is INFTFlashBorrower {
    IDelegateToken immutable dt;

    uint256 secondDelegateTokenId;

    constructor(address delegateTokenAddress) {
        dt = IDelegateToken(delegateTokenAddress);
    }

    function flashReentrancyTester(address tokenContract, uint256 tokenId) external {
        IERC721(tokenContract).approve(address(dt), tokenId);
        uint256 firstDelegateTokenId = dt.create(
            IDelegateToken.DelegateInfo(
                address(42), // Sends principal token to a burn address
                IDelegateRegistry.DelegationType.ERC721,
                address(this),
                1,
                tokenContract,
                tokenId,
                "", // Default rights to enable flashloan
                1 days
            ),
            0
        );
        dt.flashLoan{value: 0}(address(this), firstDelegateTokenId, "");
        dt.withdraw(msg.sender, secondDelegateTokenId);
    }

    function onFlashLoan(address, address tokenContract, uint256 tokenId, bytes calldata) external payable returns (bytes32) {
        IERC721(tokenContract).approve(address(dt), tokenId);
        secondDelegateTokenId = dt.create(
            IDelegateToken.DelegateInfo(
                address(this), // Sends principal token to this contract
                IDelegateRegistry.DelegationType.ERC721,
                address(this),
                1,
                tokenContract,
                tokenId,
                "",
                1 days
            ),
            1
        );
        return dt.flashLoanCallBackSuccess();
    }
}
