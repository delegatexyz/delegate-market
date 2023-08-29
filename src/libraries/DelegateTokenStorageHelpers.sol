// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.4;

import {DelegateTokenErrors as Errors, DelegateTokenStructs as Structs} from "src/libraries/DelegateTokenLib.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";

library DelegateTokenStorageHelpers {
    /// @dev Use this to syntactically store the max of the expiry
    uint256 internal constant MAX_EXPIRY = type(uint96).max;

    ///////////// ID Flags /////////////

    /// @dev Standardizes registryHash storage flags to prevent double-creation and griefing
    /// @dev ID_AVAILABLE should be zero since this is the default for a storage slot
    uint256 internal constant ID_AVAILABLE = 0;
    uint256 internal constant ID_USED = 1;

    ///////////// Info positions /////////////

    /// @dev Standardizes storage positions of delegateInfo mapping data
    /// @dev must start at zero and end at 2
    uint256 internal constant REGISTRY_HASH_POSITION = 0;
    uint256 internal constant PACKED_INFO_POSITION = 1; // PACKED (address approved, uint96 expiry)
    uint256 internal constant UNDERLYING_AMOUNT_POSITION = 2; // Not used by 721 delegations

    ///////////// Callback Flags /////////////

    /// @dev all callback flags should be non zero to reduce storage read / write costs
    /// @dev all callback flags should be unique
    /// Principal Token callbacks
    uint256 internal constant MINT_NOT_AUTHORIZED = 1;
    uint256 internal constant MINT_AUTHORIZED = 2;
    uint256 internal constant BURN_NOT_AUTHORIZED = 3;
    uint256 internal constant BURN_AUTHORIZED = 4;

    /// @dev should preserve the expiry in the lower 96 bits in storage, and update the upper 160 bits with approved address
    function writeApproved(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId, address approved) internal {
        uint96 expiry = uint96(delegateTokenInfo[delegateTokenId][PACKED_INFO_POSITION]);
        delegateTokenInfo[delegateTokenId][PACKED_INFO_POSITION] = (uint256(uint160(approved)) << 96) | expiry;
    }

    /// @dev should preserve approved in the upper 160 bits, and update the lower 96 bits with expiry
    /// @dev should revert if expiry exceeds 96 bits
    function writeExpiry(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId, uint256 expiry) internal {
        if (expiry > MAX_EXPIRY) revert Errors.ExpiryTooLarge();
        address approved = address(uint160(delegateTokenInfo[delegateTokenId][PACKED_INFO_POSITION] >> 96));
        delegateTokenInfo[delegateTokenId][PACKED_INFO_POSITION] = (uint256(uint160(approved)) << 96) | expiry;
    }

    function writeRegistryHash(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId, bytes32 registryHash) internal {
        delegateTokenInfo[delegateTokenId][REGISTRY_HASH_POSITION] = uint256(registryHash);
    }

    function writeUnderlyingAmount(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId, uint256 underlyingAmount)
        internal
    {
        delegateTokenInfo[delegateTokenId][UNDERLYING_AMOUNT_POSITION] = underlyingAmount;
    }

    function incrementBalance(mapping(address delegateTokenHolder => uint256 balance) storage balances, address delegateTokenHolder) internal {
        unchecked {
            ++balances[delegateTokenHolder];
        } // Infeasible that this will overflow
    }

    function decrementBalance(mapping(address delegateTokenHolder => uint256 balance) storage balances, address delegateTokenHolder) internal {
        unchecked {
            --balances[delegateTokenHolder];
        } // Reasonable to expect this not to underflow
    }

    /// @notice helper function for burning a principal token
    /// @dev must revert if burnAuthorized is not set to BURN_NOT_AUTHORIZED flag
    function burnPrincipal(address principalToken, Structs.Uint256 storage principalBurnAuthorization, uint256 delegateTokenId) internal {
        if (principalBurnAuthorization.flag == BURN_NOT_AUTHORIZED) {
            principalBurnAuthorization.flag = BURN_AUTHORIZED;
            PrincipalToken(principalToken).burn(msg.sender, delegateTokenId);
            principalBurnAuthorization.flag = BURN_NOT_AUTHORIZED;
            return;
        }
        revert Errors.BurnAuthorized();
    }

    /// @notice helper function for minting a principal token
    /// @dev must revert if mintAuthorized has already been set to MINT_AUTHORIZED flag
    function mintPrincipal(address principalToken, Structs.Uint256 storage principalMintAuthorization, address principalRecipient, uint256 delegateTokenId) internal {
        if (principalMintAuthorization.flag == MINT_NOT_AUTHORIZED) {
            principalMintAuthorization.flag = MINT_AUTHORIZED;
            PrincipalToken(principalToken).mint(principalRecipient, delegateTokenId);
            principalMintAuthorization.flag = MINT_NOT_AUTHORIZED;
            return;
        }
        revert Errors.MintAuthorized();
    }

    /// @dev must revert if delegate token did not call burn on the Principal Token for the delegateTokenId
    /// @dev must revert if principal token is not the caller
    function checkBurnAuthorized(address principalToken, Structs.Uint256 storage principalBurnAuthorization) internal view {
        principalIsCaller(principalToken);
        if (principalBurnAuthorization.flag == BURN_AUTHORIZED) return;
        revert Errors.BurnNotAuthorized();
    }

    /// @dev must revert if delegate token did not call burn on the Principal Token for the delegateTokenId
    /// @dev must revert if principal token is not the caller
    function checkMintAuthorized(address principalToken, Structs.Uint256 storage principalMintAuthorization) internal view {
        principalIsCaller(principalToken);
        if (principalMintAuthorization.flag == MINT_AUTHORIZED) return;
        revert Errors.MintNotAuthorized();
    }

    /// @notice helper function to revert if caller is not Principal Token
    /// @dev must revert if msg.sender is not the principal token
    function principalIsCaller(address principalToken) internal view {
        if (msg.sender == principalToken) return;
        revert Errors.CallerNotPrincipalToken();
    }

    function revertAlreadyExisted(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId) internal view {
        if (delegateTokenInfo[delegateTokenId][REGISTRY_HASH_POSITION] == ID_AVAILABLE) return;
        revert Errors.AlreadyExisted(delegateTokenId);
    }

    function revertNotOperator(mapping(address account => mapping(address operator => bool enabled)) storage accountOperator, address account) internal view {
        if (msg.sender == account || accountOperator[account][msg.sender]) return;
        revert Errors.NotOperator(msg.sender, account);
    }

    function readApproved(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId) internal view returns (address) {
        return address(uint160(delegateTokenInfo[delegateTokenId][PACKED_INFO_POSITION] >> 96));
    }

    function readExpiry(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId) internal view returns (uint256) {
        return uint96(delegateTokenInfo[delegateTokenId][PACKED_INFO_POSITION]);
    }

    function readRegistryHash(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId) internal view returns (bytes32) {
        return bytes32(delegateTokenInfo[delegateTokenId][REGISTRY_HASH_POSITION]);
    }

    function readUnderlyingAmount(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId)
        internal
        view
        returns (uint256)
    {
        return delegateTokenInfo[delegateTokenId][UNDERLYING_AMOUNT_POSITION];
    }

    function revertNotApprovedOrOperator(
        mapping(address account => mapping(address operator => bool enabled)) storage accountOperator,
        mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo,
        address account,
        uint256 delegateTokenId
    ) internal view {
        if (msg.sender == account || accountOperator[account][msg.sender] || msg.sender == readApproved(delegateTokenInfo, delegateTokenId)) return;
        revert Errors.NotApproved(msg.sender, delegateTokenId);
    }

    /// @dev should only revert if expiry has not expired AND caller is not the delegateTokenHolder AND not approved for the delegateTokenId AND not an operator for
    /// delegateTokenHolder
    function revertInvalidWithdrawalConditions(
        mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo,
        mapping(address account => mapping(address operator => bool enabled)) storage accountOperator,
        uint256 delegateTokenId,
        address delegateTokenHolder
    ) internal view {
        //slither-disable-next-line timestamp
        if (block.timestamp < readExpiry(delegateTokenInfo, delegateTokenId)) {
            if (delegateTokenHolder == msg.sender || msg.sender == readApproved(delegateTokenInfo, delegateTokenId) || accountOperator[delegateTokenHolder][msg.sender]) {
                return;
            }
            revert Errors.WithdrawNotAvailable(delegateTokenId, readExpiry(delegateTokenInfo, delegateTokenId), block.timestamp);
        }
    }

    function revertNotMinted(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId) internal view {
        uint256 registryHash = delegateTokenInfo[delegateTokenId][REGISTRY_HASH_POSITION];
        if (registryHash == ID_AVAILABLE || registryHash == ID_USED) {
            revert Errors.NotMinted(delegateTokenId);
        }
    }

    /// @dev does not read from storage, make sure the registryHash of the corresponding delegateTokenId is passed to have the intended effect
    function revertNotMinted(bytes32 registryHash, uint256 delegateTokenId) internal pure {
        if (uint256(registryHash) == ID_AVAILABLE || uint256(registryHash) == ID_USED) {
            revert Errors.NotMinted(delegateTokenId);
        }
    }
}
