// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.20;

interface IERC721 {
    event Transfer(address indexed, address indexed, uint256 indexed);
    event Approval(address indexed, address indexed, uint256 indexed);
    event ApprovalForAll(address indexed, address indexed, bool);

    function balanceOf(address) external view returns (uint256);
    function ownerOf(uint256) external view returns (address);
    function safeTransferFrom(address, address, uint256, bytes memory) external;
    function safeTransferFrom(address, address, uint256) external;
    function transferFrom(address, address, uint256) external;
    function approve(address, uint256) external;
    function setApprovalForAll(address, bool) external;
    function getApproved(uint256) external view returns (address);
    function isApprovedForAll(address, address) external view returns (bool);
}

interface ERC721Metadata {
    function name() external view returns (string memory _name);
    function symbol() external view returns (string memory _symbol);
    function tokenURI(uint256 _tokenId) external view returns (string memory);
}

interface ERC721TokenReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4);
}

interface IERC1155 {
    event TransferSingle(address indexed, address indexed, address indexed, uint256, uint256);
    event TransferBatch(address indexed, address indexed, address indexed, uint256[], uint256[]);
    event ApprovalForAll(address indexed, address indexed, bool);
    event URI(string, uint256 indexed);

    function safeTransferFrom(address, address, uint256, uint256, bytes calldata) external;
    function safeBatchTransferFrom(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external;
    function balanceOf(address, uint256) external view returns (uint256);
    function balanceOfBatch(address[] calldata, uint256[] calldata) external view returns (uint256[] memory);
    function setApprovalForAll(address, bool) external;
    function isApprovedForAll(address, address) external view returns (bool);
}

interface ERC1155TokenReceiver {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4);
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external returns (bytes4);
}

interface ERC165 {
    function supportsInterface(bytes4 interfaceID) external view returns (bool);
}
