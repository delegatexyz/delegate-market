// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

enum ExpiryType
// NONE,
{
    RELATIVE,
    ABSOLUTE
}

enum TokenType {
    NONE,
    ERC721,
    ERC20,
    ERC1155
}

// For returning data only, do not store with this
struct ViewRights {
    address tokenContract;
    uint256 expiry;
    uint256 nonce;
    uint256 tokenId;
}

interface IDelegateTokenBase {
    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidSignature();
    error InvalidExpiryType();
    error ExpiryTimeNotInFuture();
    error WithdrawNotAvailable();
    error UnderlyingMissing();
    error NotExtending();
    error NoRights();
    error NotContract();
    error InvalidFlashloan();
    error NonceTooLarge();
    error ExpiryTooLarge();
    error InvalidTokenType();
    error ZeroAmount();

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/


    /*//////////////////////////////////////////////////////////////
                      VIEW & INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    function baseURI() external view returns (string memory);

    function DELEGATE_REGISTRY() external view returns (address);
    function PRINCIPAL_TOKEN() external view returns (address);

    function getExpiry(ExpiryType expiryType, uint256 expiryValue) external view returns (uint256);

    function getRightsInfo(uint256 delegateId) external view returns (TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, uint256 expiry, uint256 nonce);

    /*//////////////////////////////////////////////////////////////
                         CREATE METHODS
    //////////////////////////////////////////////////////////////*/

    function createUnprotected(
        address ldRecipient,
        address principalRecipient,
        TokenType tokenType,
        address tokenContract,
        uint256 tokenId,
        uint256 tokenAmount,
        ExpiryType expiryType,
        uint256 expiryValue,
        uint96 nonce
    ) external payable returns (uint256);

    function create(
        address ldRecipient,
        address principalRecipient,
        TokenType tokenType,
        address tokenContract,
        uint256 tokenId,
        uint256 tokenAmount,
        ExpiryType expiryType,
        uint256 expiryValue,
        uint96 nonce
    ) external payable returns (uint256);

    function extend(uint256 delegateId, ExpiryType expiryType, uint256 expiryValue) external;

    /*//////////////////////////////////////////////////////////////
                         REDEEM METHODS
    //////////////////////////////////////////////////////////////*/

    function burn(uint256 delegateId) external;
    function burnWithPermit(address from, uint256 delegateId, bytes calldata sig) external;

    /*//////////////////////////////////////////////////////////////
                       FLASHLOAN METHODS
    //////////////////////////////////////////////////////////////*/

    function flashLoan(address receiver, uint256 delegateId, bytes calldata data) external payable;
}

interface IDelegateToken is IERC721, IDelegateTokenBase {}
