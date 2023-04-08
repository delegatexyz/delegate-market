// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {ERC721} from "solmate/tokens/ERC721.sol";

contract MockERC721 is ERC721("Mock ERC721", "MOCK") {
    uint256 public nextId;

    constructor(uint256 startId) {
        nextId = startId;
    }

    function mintNext(address recipient) external returns (uint256 newId) {
        _mint(recipient, newId = nextId++);
    }

    function mint(address recipient, uint256 tokenId) external {
        _mint(recipient, tokenId);
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }
}
