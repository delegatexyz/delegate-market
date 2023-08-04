// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.4;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";

library DelegateTokenErrors {
    error DelegateRegistryZero();
    error PrincipalTokenZero();
    error DelegateTokenZero();
    error DelegateTokenHolderZero();
    error InitialMetadataOwnerZero();
    error ToIsZero();
    error FromIsZero();
    error TokenAmountIsZero();

    error NotERC721Receiver(address to);
    error InvalidERC721TransferOperator(address operator, address expectedOperator);
    error ERC1155PullNotRequested(address operator);
    error BatchERC1155TransferUnsupported();

    error InsufficientAllowanceOrInvalidToken();
    error CallerNotOwnerOrInvalidToken();

    error NotOperator(address caller, address account);
    error NotApproved(address caller, uint256 delegateTokenId);

    error FromNotDelegateTokenHolder(address from, address delegateTokenHolder);

    error HashMismatch();

    error NotMinted(uint256 delegateTokenId);
    error AlreadyExisted(uint256 delegateTokenId);
    error WithdrawNotAvailable(uint256 delegateTokenId, uint256 expiry, uint256 timestamp);

    error ExpiryTimeNotInFuture(uint256 expiry, uint256 timestamp);
    error ExpiryTooLarge(uint256 expiry, uint256 maximum);
    error ExpiryTooSmall(uint256 expiry, uint256 minimum);

    error WrongAmountForType(IDelegateRegistry.DelegationType tokenType, uint256 wrongAmount);
    error WrongTokenIdForType(IDelegateRegistry.DelegationType tokenType, uint256 wrongTokenId);
    error InvalidTokenType(IDelegateRegistry.DelegationType tokenType);

    error ERC721FlashUnavailable(uint256 tokenId);
    error ERC20FlashAmountUnavailable(uint256 flashAmount, uint256 amountAvailable);
    error ERC1155FlashAmountUnavailable(uint256 tokenId, uint256 flashAmount, uint256 amountAvailable);

    error BurnNotAuthorized();
    error MintNotAuthorized();
    error CallerNotPrincipalToken();
    error CallerNotDelegateToken();
    error BurnAuthorized();
    error MintAuthorized();

    error ERC1155Pulled();
    error ERC1155NotPulled();
}
