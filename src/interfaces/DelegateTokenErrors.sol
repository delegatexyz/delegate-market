// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.4;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";

interface DelegateTokenErrors {
    error DelegateRegistryZero();
    error PrincipalTokenZero();
    error DelegateTokenZero();
    error DelegateTokenHolderZero();
    error InitialMetadataOwnerZero();
    error ToIsZero();
    error FromIsZero();
    error TokenAmountIsZero();

    error NotERC721Receiver(address to);

    error InsufficientAllowanceOrInvalidToken();

    error NotAuthorized(address caller, uint256 delegateTokenId);

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

    error InvalidFlashloan();

    error BurnNotAuthorized();
    error MintNotAuthorized();
    error CallerNotPrincipalToken();
    error CallerNotDelegateToken();
    error BurnAuthorized();
    error MintAuthorized();

    error ERC721Pulled();
    error ERC721NotPulled();
    error ERC1155Pulled();
    error ERC1155NotPulled();
}
