// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.4;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {IDelegateFlashloan} from "src/interfaces/IDelegateFlashloan.sol";
import {IERC721Receiver} from "openzeppelin/token/ERC721/IERC721Receiver.sol";

library DelegateTokenStructs {
    struct Uint256 {
        uint256 flag;
    }

    /// @notice Struct for creating delegate tokens and returning their information
    struct DelegateInfo {
        address principalHolder;
        IDelegateRegistry.DelegationType tokenType;
        address delegateHolder;
        uint256 amount;
        address tokenContract;
        uint256 tokenId;
        bytes32 rights;
        uint256 expiry;
    }

    struct FlashInfo {
        address receiver; // The address to receive the loaned assets
        address delegateHolder; // The holder of the delegation
        IDelegateRegistry.DelegationType tokenType; // The type of contract, e.g. ERC20
        address tokenContract; // The contract of the underlying being loaned
        uint256 tokenId; // The tokenId of the underlying being loaned, if applicable
        uint256 amount; // The amount being lent, if applicable
        bytes data; // Arbitrary data structure, intended to contain user-defined parameters
    }
}

library DelegateTokenErrors {
    error DelegateRegistryZero();
    error PrincipalTokenZero();
    error DelegateTokenHolderZero();
    error MarketMetadataZero();
    error ToIsZero();

    error NotERC721Receiver();
    error InvalidERC721TransferOperator();
    error ERC1155PullNotRequested(address operator);
    error BatchERC1155TransferUnsupported();

    error InsufficientAllowanceOrInvalidToken();
    error CallerNotOwnerOrInvalidToken();

    error NotOperator(address caller, address account);
    error NotApproved(address caller, uint256 delegateTokenId);

    error FromNotDelegateTokenHolder();

    error HashMismatch();

    error NotMinted(uint256 delegateTokenId);
    error AlreadyExisted(uint256 delegateTokenId);
    error WithdrawNotAvailable(uint256 delegateTokenId, uint256 expiry, uint256 timestamp);

    error ExpiryInPast();
    error ExpiryTooLarge();
    error ExpiryTooSmall();

    error WrongAmountForType(IDelegateRegistry.DelegationType tokenType, uint256 wrongAmount);
    error WrongTokenIdForType(IDelegateRegistry.DelegationType tokenType, uint256 wrongTokenId);
    error InvalidTokenType(IDelegateRegistry.DelegationType tokenType);

    error ERC721FlashUnavailable();
    error ERC20FlashAmountUnavailable();
    error ERC1155FlashAmountUnavailable();

    error BurnNotAuthorized();
    error MintNotAuthorized();
    error CallerNotPrincipalToken();
    error BurnAuthorized();
    error MintAuthorized();

    error ERC1155Pulled();
    error ERC1155NotPulled();
}

library DelegateTokenHelpers {
    function revertOnCallingInvalidFlashloan(DelegateTokenStructs.FlashInfo calldata info) internal {
        if (IDelegateFlashloan(info.receiver).onFlashloan{value: msg.value}(msg.sender, info) == IDelegateFlashloan.onFlashloan.selector) return;
        revert IDelegateFlashloan.InvalidFlashloan();
    }

    function revertOnInvalidERC721ReceiverCallback(address from, address to, uint256 delegateTokenId, bytes calldata data) internal {
        if (to.code.length == 0 || IERC721Receiver(to).onERC721Received(msg.sender, from, delegateTokenId, data) == IERC721Receiver.onERC721Received.selector) return;
        revert DelegateTokenErrors.NotERC721Receiver();
    }

    function revertOnInvalidERC721ReceiverCallback(address from, address to, uint256 delegateTokenId) internal {
        if (to.code.length == 0 || IERC721Receiver(to).onERC721Received(msg.sender, from, delegateTokenId, "") == IERC721Receiver.onERC721Received.selector) return;
        revert DelegateTokenErrors.NotERC721Receiver();
    }

    /// @dev won't revert if expiry is too large (i.e. > type(uint96).max)
    function revertOldExpiry(uint256 expiry) internal view {
        //slither-disable-next-line timestamp
        if (expiry > block.timestamp) return;
        revert DelegateTokenErrors.ExpiryInPast();
    }

    function delegateIdNoRevert(address caller, uint256 salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(caller, salt)));
    }
}
