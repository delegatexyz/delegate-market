// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.17;

import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

contract MockERC721 is ERC721 {
    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {}

    function tokenURI(uint256) public view virtual override returns (string memory) {}

    function mint(address to, uint256 tokenId) public virtual {
        _mint(to, tokenId);
    }

    function burn(uint256 tokenId) public virtual {
        _burn(tokenId);
    }

    function safeMint(address to, uint256 tokenId) public virtual {
        _safeMint(to, tokenId);
    }

    function safeMint(
        address to,
        uint256 tokenId,
        bytes memory data
    ) public virtual {
        _safeMint(to, tokenId, data);
    }
}

contract MockERC721Metadata is MockERC721 {
    using Strings for uint256;
    string baseURI;

    constructor(string memory _name, string memory _symbol, string memory _baseURI) MockERC721(_name, _symbol) {
        baseURI = _baseURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return string.concat(baseURI, tokenId.toString());
    }
}

