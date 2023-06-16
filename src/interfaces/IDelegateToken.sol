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

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    event RightsCreated(uint256 indexed baseDelegateId, uint256 indexed nonce, uint256 expiry);
    event RightsExtended(uint256 indexed baseDelegateId, uint256 indexed nonce, uint256 previousExpiry, uint256 newExpiry);
    event RightsBurned(uint256 indexed baseDelegateId, uint256 indexed nonce);
    event UnderlyingWithdrawn(uint256 indexed baseDelegateId, uint256 indexed nonce, address to);

    /*//////////////////////////////////////////////////////////////
                      VIEW & INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    function baseURI() external view returns (string memory);

    function DELEGATION_REGISTRY() external view returns (address);
    function PRINCIPAL_TOKEN() external view returns (address);

    function getRights(address tokenContract, uint256 tokenId)
        external
        view
        returns (uint256 baseDelegateId, uint256 activeDelegateId, ViewRights memory rights);
    function getRights(uint256 delegateId) external view returns (uint256 baseDelegateId, uint256 activeDelegateId, ViewRights memory rights);

    function getBaseDelegateId(address tokenContract, uint256 tokenId) external pure returns (uint256);
    function getExpiry(ExpiryType expiryType, uint256 expiryValue) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                         CREATE METHODS
    //////////////////////////////////////////////////////////////*/

    function createUnprotected(
        address ldRecipient,
        address principalRecipient,
        address tokenContract,
        TokenType tokenType,
        uint256 tokenId,
        ExpiryType expiryType,
        uint256 expiryValue
    ) external payable returns (uint256);

    function create(address ldRecipient, address principalRecipient, address tokenContract, TokenType tokenType, uint256 tokenId, ExpiryType expiryType, uint256 expiryValue)
        external
        payable
        returns (uint256);

    function extend(uint256 delegateId, ExpiryType expiryType, uint256 expiryValue) external;

    /*//////////////////////////////////////////////////////////////
                         REDEEM METHODS
    //////////////////////////////////////////////////////////////*/

    function burn(uint256 delegateId) external;
    function burnWithPermit(address from, uint256 delegateId, bytes calldata sig) external;

    function withdrawTo(address to, address tokenContract, uint256 tokenId) external;

    /*//////////////////////////////////////////////////////////////
                       FLASHLOAN METHODS
    //////////////////////////////////////////////////////////////*/

    function flashLoan(address receiver, uint256 delegateId, address tokenContract, uint256 tokenId, bytes calldata data) external payable;
}

interface IDelegateToken is IERC721, IDelegateTokenBase {}
