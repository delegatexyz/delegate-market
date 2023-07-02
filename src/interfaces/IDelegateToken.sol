// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.20;

import {IDelegateRegistry} from "../delegateRegistry/IDelegateRegistry.sol";
import {IERC721, ERC721TokenReceiver, ERC1155TokenReceiver} from "./ITokenInterfaces.sol";

interface IDelegateToken is IERC721, ERC721TokenReceiver, ERC1155TokenReceiver {
    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotDelegateRegistry();
    error NotPrincipalToken();
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
    error ToIsZero();
    error FromNotOwner();
    error NotAuthorized();
    error NotMinted();
    error InvalidDelegateTokenHolder();
    error NotERC721Receiver();

    /*//////////////////////////////////////////////////////////////
                      VIEW & INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    function baseURI() external view returns (string memory);

    function delegateRegistry() external view returns (address);
    function principalToken() external view returns (address);

    function getDelegateInfo(uint256 delegateId)
        external
        view
        returns (IDelegateRegistry.DelegationType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, bytes32 rights, uint256 expiry);

    /*//////////////////////////////////////////////////////////////
                         STATE CHANGING
    //////////////////////////////////////////////////////////////*/

    function create(
        address ldRecipient,
        address principalRecipient,
        IDelegateRegistry.DelegationType delegationType,
        address tokenContract,
        uint256 tokenId,
        uint256 tokenAmount,
        bytes32 rights,
        uint256 expiry,
        uint96 nonce
    ) external payable returns (uint256);

    function extend(uint256 delegateId, uint256 expiryValue) external;

    function withdrawTo(address to, uint256 delegateId) external;

    function burn(uint256 delegateId) external;

    function flashLoan(address receiver, uint256 delegateId, bytes calldata data) external payable;
}
