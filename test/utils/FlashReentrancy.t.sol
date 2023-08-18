// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IDelegateToken, Structs as IDelegateTokenStructs} from "src/interfaces/IDelegateToken.sol";
import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {IDelegateFlashloan, Structs as IDelegateFlashloanStructs} from "src/interfaces/IDelegateFlashloan.sol";
import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";

contract FlashReentrancyTester is IDelegateFlashloan {
    IDelegateToken immutable dt;

    uint256 secondDelegateTokenId;

    constructor(address delegateTokenAddress) {
        dt = IDelegateToken(delegateTokenAddress);
    }

    function flashReentrancyTester(address tokenContract, uint256 tokenId) external {
        IERC721(tokenContract).approve(address(dt), tokenId);
        dt.create(
            IDelegateTokenStructs.DelegateInfo(
                address(42), // Sends principal token to a burn address
                IDelegateRegistry.DelegationType.ERC721,
                address(this),
                0,
                tokenContract,
                tokenId,
                "", // Default rights to enable flashloan
                block.timestamp + 1 days
            ),
            0
        );
        dt.flashloan{value: 0}(IDelegateFlashloanStructs.FlashInfo(address(this), address(this), IDelegateRegistry.DelegationType.ERC721, tokenContract, tokenId, 0, ""));
        dt.withdraw(secondDelegateTokenId);
    }

    function onFlashloan(address, IDelegateFlashloanStructs.FlashInfo calldata info) external payable returns (bytes32) {
        IERC721(info.tokenContract).approve(address(dt), info.tokenId);
        secondDelegateTokenId = dt.create(
            IDelegateTokenStructs.DelegateInfo(
                address(this), // Sends principal token to this contract
                info.tokenType,
                address(this),
                info.amount,
                info.tokenContract,
                info.tokenId,
                "",
                block.timestamp + 1 days
            ),
            1
        );
        return IDelegateFlashloan.onFlashloan.selector;
    }
}
