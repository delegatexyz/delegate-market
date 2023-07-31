// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IDelegateToken} from "src/interfaces/IDelegateToken.sol";
import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";
import {IDelegateFlashloan} from "src/interfaces/IDelegateFlashloan.sol";

contract FlashReentrancyTester is IDelegateFlashloan {
    IDelegateToken immutable dt;

    uint256 secondDelegateTokenId;

    constructor(address delegateTokenAddress) {
        dt = IDelegateToken(delegateTokenAddress);
    }

    function flashReentrancyTester(address tokenContract, uint256 tokenId) external {
        IERC721(tokenContract).approve(address(dt), tokenId);
        dt.create(
            IDelegateToken.DelegateInfo(
                address(42), // Sends principal token to a burn address
                IDelegateRegistry.DelegationType.ERC721,
                address(this),
                0,
                tokenContract,
                tokenId,
                "", // Default rights to enable flashloan
                1 days
            ),
            0
        );
        dt.flashloan{value: 0}(address(this), address(this), IDelegateRegistry.DelegationType.ERC721, tokenContract, tokenId, "");
        dt.withdraw(msg.sender, secondDelegateTokenId);
    }

    function onFlashloan(address, IDelegateRegistry.DelegationType, address underlyingContract, uint256 underlyingTokenId, uint256, bytes calldata)
        external
        payable
        returns (bytes32)
    {
        IERC721(underlyingContract).approve(address(dt), underlyingTokenId);
        secondDelegateTokenId = dt.create(
            IDelegateToken.DelegateInfo(
                address(this), // Sends principal token to this contract
                IDelegateRegistry.DelegationType.ERC721,
                address(this),
                0,
                underlyingContract,
                underlyingTokenId,
                "",
                1 days
            ),
            1
        );
        return IDelegateFlashloan.onFlashloan.selector;
    }
}
