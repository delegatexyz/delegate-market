// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.4;

import {IDelegateRegistry, DelegateTokenErrors as Errors, DelegateTokenStructs as Structs} from "src/libraries/DelegateTokenLib.sol";
import {IERC1155} from "openzeppelin/token/ERC1155/IERC1155.sol";
import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

library DelegateTokenTransferHelpers {
    /// 1155 callbacks
    uint256 internal constant ERC1155_NOT_PULLED = 5;
    uint256 internal constant ERC1155_PULLED = 6;

    function checkAndPullByType(Structs.Uint256 storage erc1155Pulled, Structs.DelegateInfo calldata delegateInfo) internal {
        if (delegateInfo.tokenType == IDelegateRegistry.DelegationType.ERC721) {
            checkERC721BeforePull(delegateInfo.amount, delegateInfo.tokenContract, delegateInfo.tokenId);
            pullERC721AfterCheck(delegateInfo.tokenContract, delegateInfo.tokenId);
        } else if (delegateInfo.tokenType == IDelegateRegistry.DelegationType.ERC20) {
            checkERC20BeforePull(delegateInfo.amount, delegateInfo.tokenContract, delegateInfo.tokenId);
            pullERC20AfterCheck(delegateInfo.tokenContract, delegateInfo.amount);
        } else if (delegateInfo.tokenType == IDelegateRegistry.DelegationType.ERC1155) {
            checkERC1155BeforePull(erc1155Pulled, delegateInfo.amount);
            pullERC1155AfterCheck(erc1155Pulled, delegateInfo.amount, delegateInfo.tokenContract, delegateInfo.tokenId);
        } else {
            revert Errors.InvalidTokenType(delegateInfo.tokenType);
        }
    }

    /// @dev Should revert for a typical 20 / 1155, and pass for a typical 721
    function checkERC721BeforePull(uint256 underlyingAmount, address underlyingContract, uint256 underlyingTokenId) internal view {
        if (underlyingAmount != 0) {
            revert Errors.WrongAmountForType(IDelegateRegistry.DelegationType.ERC721, underlyingAmount);
        }
        if (IERC721(underlyingContract).ownerOf(underlyingTokenId) != msg.sender) {
            revert Errors.CallerNotOwnerOrInvalidToken();
        }
    }

    function pullERC721AfterCheck(address underlyingContract, uint256 underlyingTokenId) internal {
        IERC721(underlyingContract).transferFrom(msg.sender, address(this), underlyingTokenId);
    }

    /// @dev Should revert for a typical 721 / 1155 and pass for a typical 20
    function checkERC20BeforePull(uint256 underlyingAmount, address underlyingContract, uint256 underlyingTokenId) internal view {
        if (underlyingTokenId != 0) {
            revert Errors.WrongTokenIdForType(IDelegateRegistry.DelegationType.ERC20, underlyingTokenId);
        }
        if (underlyingAmount == 0) {
            revert Errors.WrongAmountForType(IDelegateRegistry.DelegationType.ERC20, underlyingAmount);
        }
        if (IERC20(underlyingContract).allowance(msg.sender, address(this)) < underlyingAmount) {
            revert Errors.InsufficientAllowanceOrInvalidToken();
        }
    }

    function pullERC20AfterCheck(address underlyingContract, uint256 pullAmount) internal {
        SafeERC20.safeTransferFrom(IERC20(underlyingContract), msg.sender, address(this), pullAmount);
    }

    function checkERC1155BeforePull(Structs.Uint256 storage erc1155Pulled, uint256 pullAmount) internal {
        if (pullAmount == 0) revert Errors.WrongAmountForType(IDelegateRegistry.DelegationType.ERC1155, pullAmount);
        if (erc1155Pulled.flag == ERC1155_NOT_PULLED) {
            erc1155Pulled.flag = ERC1155_PULLED;
        } else {
            revert Errors.ERC1155Pulled();
        }
    }

    function pullERC1155AfterCheck(Structs.Uint256 storage erc1155Pulled, uint256 pullAmount, address underlyingContract, uint256 underlyingTokenId) internal {
        IERC1155(underlyingContract).safeTransferFrom(msg.sender, address(this), underlyingTokenId, pullAmount, "");
        if (erc1155Pulled.flag == ERC1155_PULLED) {
            revert Errors.ERC1155NotPulled();
        }
    }

    function checkERC1155Pulled(Structs.Uint256 storage erc1155Pulled, address operator) internal returns (bool) {
        if (erc1155Pulled.flag == ERC1155_PULLED && address(this) == operator) {
            erc1155Pulled.flag = ERC1155_NOT_PULLED;
            return true;
        }
        return false;
    }

    function revertInvalidERC1155PullCheck(Structs.Uint256 storage erc1155PullAuthorization, address operator) internal {
        if (!checkERC1155Pulled(erc1155PullAuthorization, operator)) revert Errors.ERC1155PullNotRequested(operator);
    }
}
