// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

enum ExpiryType {
    // NONE,
    RELATIVE,
    ABSOLUTE
}

struct Rights {
    address tokenContract;
    uint40 expiry;
    uint56 nonce;
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

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    event RightsCreated(uint256 indexed baseDelegateId, uint56 indexed nonce, uint40 expiry);
    event RightsExtended(uint256 indexed baseDelegateId, uint56 indexed nonce, uint40 previousExpiry, uint40 newExpiry);
    event RightsBurned(uint256 indexed baseDelegateId, uint56 indexed nonce);
    event UnderlyingWithdrawn(uint256 indexed baseDelegateId, uint56 indexed nonce, address to);

    /*//////////////////////////////////////////////////////////////
                      VIEW & INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    function baseURI() external view returns (string memory);

    function DELEGATION_REGISTRY() external view returns (address);
    function PRINCIPAL_TOKEN() external view returns (address);

    function getRights(address tokenContract, uint256 tokenId) external view returns (uint256 baseDelegateId, uint256 activeDelegateId, Rights memory rights);
    function getRights(uint256 delegateId) external view returns (uint256 baseDelegateId, uint256 activeDelegateId, Rights memory rights);

    function getBaseDelegateId(address tokenContract, uint256 tokenId) external pure returns (uint256);
    function getExpiry(ExpiryType expiryType, uint256 expiryValue) external view returns (uint40);

    /*//////////////////////////////////////////////////////////////
                         CREATE METHODS
    //////////////////////////////////////////////////////////////*/

    function createUnprotected(
        address ldRecipient,
        address principalRecipient,
        address tokenContract,
        uint256 tokenId,
        ExpiryType expiryType,
        uint256 expiryValue
    ) external payable returns (uint256);

    function create(address ldRecipient, address principalRecipient, address tokenContract, uint256 tokenId, ExpiryType expiryType, uint256 expiryValue)
        external
        payable
        returns (uint256);

    function extend(uint256 delegateId, ExpiryType expiryType, uint256 expiryValue) external;

    /*//////////////////////////////////////////////////////////////
                         REDEEM METHODS
    //////////////////////////////////////////////////////////////*/

    function burn(uint256 delegateId) external;
    function burnWithPermit(address from, uint256 delegateId, bytes calldata sig) external;

    function withdrawTo(address to, uint56 nonce, address tokenContract, uint256 tokenId) external;

    /*//////////////////////////////////////////////////////////////
                       FLASHLOAN METHODS
    //////////////////////////////////////////////////////////////*/

    function flashLoan(address receiver, uint256 delegateId, address tokenContract, uint256 tokenId, bytes calldata data) external;
}

interface IDelegateToken is IERC721, IDelegateTokenBase {}
