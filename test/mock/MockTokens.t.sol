// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {ERC721} from "openzeppelin/token/ERC721/ERC721.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {ERC1155} from "openzeppelin/token/ERC1155/ERC1155.sol";

contract MockERC721 is ERC721("Mock ERC721", "MOCK721") {
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

    function tokenURI(uint256 id) public pure override returns (string memory) {
        return string(bytes.concat("Mock erc721 tokenURI for token id: ", abi.encode(id)));
    }
}

contract MockERC20 is ERC20("Mock ERC20", "MOCK20") {
    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract MockERC1155 is ERC1155("Mock ERC1155") {
    function mint(address recipient, uint256 id, uint256 amount, bytes calldata data) external {
        _mint(recipient, id, amount, data);
    }

    function uri(uint256 id) public pure override returns (string memory) {
        return string(bytes.concat("Mock erc1155 tokenURI for token id: ", abi.encode(id)));
    }
}
