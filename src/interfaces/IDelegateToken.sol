// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.20;

enum TokenType {
    NONE,
    ERC721,
    ERC20,
    ERC1155
}

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

interface IDelegateToken is IERC721 {
    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidSignature();
    error WithdrawNotAvailable();
    error UnderlyingMissing();
    error NotExtending();
    error NoRights();
    error NotContract();
    error InvalidFlashloan();
    error NonceTooLarge();
    error InvalidTokenType();
    error WrongAmount();
    error ExpiryTimeNotInFuture();
    error ExpiryTooLarge();
    error AlreadyExisted();

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                      VIEW & INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    function baseURI() external view returns (string memory);

    function delegateRegistry() external view returns (address);
    function principalToken() external view returns (address);

    function getDelegateInfo(uint256 delegateId)
        external
        view
        returns (TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, bytes32 rights, uint256 expiry);

    /*//////////////////////////////////////////////////////////////
                         CREATE METHODS
    //////////////////////////////////////////////////////////////*/

    function create(
        address ldRecipient,
        address principalRecipient,
        TokenType tokenType,
        address tokenContract,
        uint256 tokenId,
        uint256 tokenAmount,
        bytes32 rights,
        uint256 expiry,
        uint96 nonce
    ) external payable returns (uint256);

    function extend(uint256 delegateId, uint256 expiryValue) external;

    function withdrawTo(address to, uint256 delegateId) external;

    /*//////////////////////////////////////////////////////////////
                         REDEEM METHODS
    //////////////////////////////////////////////////////////////*/

    function burn(uint256 delegateId) external;

    /*//////////////////////////////////////////////////////////////
                       FLASHLOAN METHODS
    //////////////////////////////////////////////////////////////*/

    function flashLoan(address receiver, uint256 delegateId, bytes calldata data) external payable;
}
