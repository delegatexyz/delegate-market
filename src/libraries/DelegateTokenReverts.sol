// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {DelegateTokenErrors as Errors} from "src/libraries/DelegateTokenErrors.sol";
import {DelegateTokenConstants as Constants} from "src/libraries/DelegateTokenConstants.sol";
import {DelegateTokenStructs as Structs} from "src/libraries/DelegateTokenStructs.sol";
import {IERC721Receiver} from "openzeppelin/token/ERC721/IERC721Receiver.sol";

library DelegateTokenReverts {
    function onInvalidERC721ReceiverCallback(address from, address to, uint256 delegateTokenId, bytes calldata data) internal {
        if (to.code.length != 0 && IERC721Receiver(to).onERC721Received(msg.sender, from, delegateTokenId, data) != IERC721Receiver.onERC721Received.selector) {
            revert Errors.NotERC721Receiver(to);
        }
    }

    function onInvalidERC721ReceiverCallback(address from, address to, uint256 delegateTokenId) internal {
        if (to.code.length != 0 && IERC721Receiver(to).onERC721Received(msg.sender, from, delegateTokenId, "") != IERC721Receiver.onERC721Received.selector) {
            revert Errors.NotERC721Receiver(to);
        }
    }

    function alreadyExisted(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId) internal view {
        if (delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION] != Constants.ID_AVAILABLE) revert Errors.AlreadyExisted(delegateTokenId);
    }

    function notOperator(mapping(address account => mapping(address operator => bool enabled)) storage accountOperator, address account) internal view {
        if (!(msg.sender == account || accountOperator[account][msg.sender])) {
            revert Errors.NotOperator(msg.sender, account);
        }
    }

    function invalidExpiry(uint256 expiry) internal view {
        if (expiry < block.timestamp) revert Errors.ExpiryTimeNotInFuture(expiry, block.timestamp);
        if (expiry > Constants.MAX_EXPIRY) revert Errors.ExpiryTooLarge(expiry, Constants.MAX_EXPIRY);
    }

    function invalidERC721TransferOperator(address operator) internal view {
        if (address(this) != operator) revert Errors.InvalidERC721TransferOperator(operator, address(this));
    }

    function notMinted(bytes32 registryHash, uint256 delegateTokenId) internal pure {
        if (uint256(registryHash) == Constants.ID_AVAILABLE || uint256(registryHash) == Constants.ID_USED) revert Errors.NotMinted(delegateTokenId);
    }

    function toIsZero(address to) internal pure {
        if (to == address(0)) revert Errors.ToIsZero();
    }

    function delegateTokenHolderZero(address delegateTokenHolder) internal pure {
        if (delegateTokenHolder == address(0)) revert Errors.DelegateTokenHolderZero();
    }

    function fromNotDelegateTokenHolder(address from, address delegateTokenHolder) internal pure {
        if (from != delegateTokenHolder) revert Errors.FromNotDelegateTokenHolder(from, delegateTokenHolder);
    }

    function batchERC1155TransferUnsupported() internal pure {
        revert Errors.BatchERC1155TransferUnsupported();
    }
}
