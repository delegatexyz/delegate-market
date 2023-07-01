// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.20;

interface IERC721 {
    function ownerOf(uint256 tokenId) external returns (address owner);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

interface IERC1155 {
    function safeTransferFrom(address from, address to, uint256 tokenId, uint256 amount, bytes memory data) external;
}
