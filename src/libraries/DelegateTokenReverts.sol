// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {DelegateTokenErrors as Errors} from "src/libraries/DelegateTokenErrors.sol";
import {DelegateTokenConstants as Constants} from "src/libraries/DelegateTokenConstants.sol";
import {DelegateTokenStorageHelpers as StorageHelpers} from "src/libraries/DelegateTokenStorageHelpers.sol";
import {IERC721Receiver} from "openzeppelin/token/ERC721/IERC721Receiver.sol";

library DelegateTokenReverts {
    function notERC721Receiver(address from, address to, uint256 delegateTokenId, bytes calldata data) internal {
        if (to.code.length != 0 && IERC721Receiver(to).onERC721Received(msg.sender, from, delegateTokenId, data) != IERC721Receiver.onERC721Received.selector) {
            revert Errors.NotERC721Receiver(to);
        }
    }

    function notERC721Receiver(address from, address to, uint256 delegateTokenId) internal {
        if (to.code.length != 0 && IERC721Receiver(to).onERC721Received(msg.sender, from, delegateTokenId, "") != IERC721Receiver.onERC721Received.selector) {
            revert Errors.NotERC721Receiver(to);
        }
    }

    function alreadyExisted(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId) internal view {
        if (delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION] != Constants.ID_AVAILABLE) revert Errors.AlreadyExisted(delegateTokenId);
    }

    function notApprovedOrOperator(
        mapping(address account => mapping(address operator => bool enabled)) storage accountOperator,
        mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo,
        address account,
        uint256 delegateTokenId
    ) internal view {
        if (!(msg.sender == account || accountOperator[account][msg.sender] || msg.sender == StorageHelpers.readApproved(delegateTokenInfo, delegateTokenId))) {
            revert Errors.NotAuthorized(msg.sender, delegateTokenId);
        }
    }

    function notOperator(mapping(address account => mapping(address operator => bool enabled)) storage accountOperator, address account, uint256 delegateTokenId)
        internal
        view
    {
        if (!(msg.sender == account || accountOperator[account][msg.sender])) {
            revert Errors.NotAuthorized(msg.sender, delegateTokenId);
        }
    }

    function notMinted(bytes32 registryHash, uint256 delegateTokenId) internal pure {
        if (uint256(registryHash) == Constants.ID_AVAILABLE || uint256(registryHash) == Constants.ID_USED) revert Errors.NotMinted(delegateTokenId);
    }

    function toIsZero(address to) internal pure {
        if (to == address(0)) revert Errors.ToIsZero();
    }
}
