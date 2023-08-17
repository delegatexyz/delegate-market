// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.4;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {IDelegateFlashloan} from "src/interfaces/IDelegateFlashloan.sol";
import {IERC721Receiver} from "openzeppelin/token/ERC721/IERC721Receiver.sol";

library DelegateTokenStructs {
    struct Uint256 {
        uint256 flag;
    }

    struct DelegateTokenParameters {
        address delegateRegistry;
        address principalToken;
        address marketMetadata;
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
        address receiver; // The address to receive the loaned assets.
        address delegateHolder; // The holder of the delegation.
        IDelegateRegistry.DelegationType tokenType; // The type of contract, e.g. ERC20.
        address tokenContract; // The contract of the underlying being loaned.
        uint256 tokenId; // The tokenId of the underlying being loaned, if applicable.
        uint256 amount; // The amount being lent, if applicable.
        bytes data; // Arbitrary data structure, intended to contain user-defined parameters.
    }
}

library DelegateTokenConstants {
    /// @dev Use this to syntactically store the max of the expiry
    uint256 internal constant MAX_EXPIRY = type(uint96).max;

    ///////////// Info positions /////////////

    /// @dev Standardizes storage positions of delegateInfo mapping data
    /// @dev must start at zero and end at 2
    uint256 internal constant REGISTRY_HASH_POSITION = 0;
    uint256 internal constant PACKED_INFO_POSITION = 1; // PACKED (address approved, uint96 expiry)
    uint256 internal constant UNDERLYING_AMOUNT_POSITION = 2; // Not used by 721 delegations

    ///////////// ID Flags /////////////

    /// @dev Standardizes registryHash storage flags to prevent double-creation and griefing
    /// @dev ID_AVAILABLE should be zero since this is the default for a storage slot
    uint256 internal constant ID_AVAILABLE = 0;
    uint256 internal constant ID_USED = 1;

    ///////////// Callback Flags /////////////

    /// @dev all callback flags should be non zero to reduce storage read / write costs
    /// @dev all callback flags should be unique
    /// Principal Token callbacks
    uint256 internal constant MINT_NOT_AUTHORIZED = 1;
    uint256 internal constant MINT_AUTHORIZED = 2;
    uint256 internal constant BURN_NOT_AUTHORIZED = 3;
    uint256 internal constant BURN_AUTHORIZED = 4;
    /// 1155 callbacks
    uint256 internal constant ERC1155_NOT_PULLED = 5;
    uint256 internal constant ERC1155_PULLED = 6;
}

library DelegateTokenErrors {
    error DelegateRegistryZero();
    error PrincipalTokenZero();
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
        if (IDelegateFlashloan(info.receiver).onFlashloan{value: msg.value}(msg.sender, info) != IDelegateFlashloan.onFlashloan.selector) {
            revert IDelegateFlashloan.InvalidFlashloan();
        }
    }

    function revertOnInvalidERC721ReceiverCallback(address from, address to, uint256 delegateTokenId, bytes calldata data) internal {
        if (to.code.length != 0 && IERC721Receiver(to).onERC721Received(msg.sender, from, delegateTokenId, data) != IERC721Receiver.onERC721Received.selector) {
            revert DelegateTokenErrors.NotERC721Receiver(to);
        }
    }

    function revertOnInvalidERC721ReceiverCallback(address from, address to, uint256 delegateTokenId) internal {
        if (to.code.length != 0 && IERC721Receiver(to).onERC721Received(msg.sender, from, delegateTokenId, "") != IERC721Receiver.onERC721Received.selector) {
            revert DelegateTokenErrors.NotERC721Receiver(to);
        }
    }

    function revertInvalidExpiry(uint256 expiry) internal view {
        //slither-disable-next-line timestamp
        if (expiry < block.timestamp) revert DelegateTokenErrors.ExpiryTimeNotInFuture(expiry, block.timestamp);
        if (expiry > DelegateTokenConstants.MAX_EXPIRY) revert DelegateTokenErrors.ExpiryTooLarge(expiry, DelegateTokenConstants.MAX_EXPIRY);
    }

    function revertInvalidERC721TransferOperator(address operator) internal view {
        if (address(this) != operator) revert DelegateTokenErrors.InvalidERC721TransferOperator(operator, address(this));
    }

    function revertNotMinted(bytes32 registryHash, uint256 delegateTokenId) internal pure {
        if (uint256(registryHash) == DelegateTokenConstants.ID_AVAILABLE || uint256(registryHash) == DelegateTokenConstants.ID_USED) {
            revert DelegateTokenErrors.NotMinted(delegateTokenId);
        }
    }

    function revertToIsZero(address to) internal pure {
        if (to == address(0)) revert DelegateTokenErrors.ToIsZero();
    }

    function revertDelegateTokenHolderZero(address delegateTokenHolder) internal pure {
        if (delegateTokenHolder == address(0)) revert DelegateTokenErrors.DelegateTokenHolderZero();
    }

    function revertFromNotDelegateTokenHolder(address from, address delegateTokenHolder) internal pure {
        if (from != delegateTokenHolder) revert DelegateTokenErrors.FromNotDelegateTokenHolder(from, delegateTokenHolder);
    }

    function revertBatchERC1155TransferUnsupported() internal pure {
        revert DelegateTokenErrors.BatchERC1155TransferUnsupported();
    }

    function delegateId(address caller, uint256 salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(caller, salt)));
    }
}
