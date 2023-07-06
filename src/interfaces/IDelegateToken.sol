// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.20;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {IERC721, ERC165, ERC721TokenReceiver, ERC1155TokenReceiver} from "./ITokenInterfaces.sol";

interface IDelegateToken is IERC721, ERC721TokenReceiver, ERC1155TokenReceiver {
    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/

    error DelegateRegistryZero();
    error PrincipalTokenZero();
    error DelegateTokenHolderZero();
    error ToIsZero();
    error FromIsZero();
    error TokenAmountIsZero();

    error NotERC721Receiver(address to);

    error NotAuthorized(address caller, uint256 delegateTokenId);

    error FromNotDelegateTokenHolder(address from, address delegateTokenHolder);

    error HashMisMatch();

    error NotMinted(uint256 delegateTokenId);
    error AlreadyExisted(uint256 delegateTokenId);
    error WithdrawNotAvailable(uint256 delegateTokenId, uint256 expiry, uint256 timestamp);

    error ExpiryTimeNotInFuture(uint256 expiry, uint256 timestamp);
    error ExpiryTooLarge(uint256 expiry, uint256 maximum);
    error ExpiryTooSmall(uint256 expiry, uint256 minimum);

    error WrongAmountForType(IDelegateRegistry.DelegationType tokenType, uint256 wrongAmount);
    error InvalidTokenType(IDelegateRegistry.DelegationType tokenType);

    error InvalidFlashloan();

    /*//////////////////////////////////////////////////////////////
                      VIEW & INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    function FLASHLOAN_CALLBACK_SUCCESS() external pure returns (bytes32);
    function delegateRegistry() external view returns (address);
    function principalToken() external view returns (address);
    function baseURI() external view returns (string memory);

    function isApprovedOrOwner(address spender, uint256 id) external view returns (bool);
    function getDelegateInfo(uint256 delegateId)
        external
        view
        returns (IDelegateRegistry.DelegationType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, bytes32 rights, uint256 expiry);
    function getDelegateId(IDelegateRegistry.DelegationType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, address creator, uint96 salt)
        external
        pure
        returns (uint256);

    function contractURI() external view returns (string memory);

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

    function rescind(address from, uint256 delegateId) external;

    function withdrawTo(address to, uint256 delegateId) external;

    function flashLoan(address receiver, uint256 delegateId, bytes calldata data) external payable;

    function setBaseURI(string calldata baseURI) external;
}
