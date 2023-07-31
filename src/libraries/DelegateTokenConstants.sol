// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

library DelegateTokenConstants {
    /// @notice Standardizes rescind address
    /// @dev should not be zero address
    address internal constant RESCIND_ADDRESS = address(1);

    /// @dev Use this to syntactically store the max of the expiry
    uint256 internal constant MAX_EXPIRY = type(uint96).max;

    ///////////// Info positions /////////////

    /// @dev Standardizes storage positions of delegateInfo mapping data
    /// @dev must start at zero and end at 2
    uint256 internal constant REGISTRY_HASH_POSITION = 0;
    uint256 internal constant PACKED_INFO_POSITION = 1; // PACKED (address approved, uint96 expiry)
    uint256 internal constant UNDERLYING_AMOUNT_POSITION = 2; // Not used by 721 delegations

    ///////////// ID FLags /////////////

    /// @dev Standardizes registryHash storage flags to prevent double-creation and griefing
    /// @dev ID_AVAILABLE should be zero since this is the default for a storage slot
    uint256 internal constant ID_AVAILABLE = 0;
    uint256 internal constant ID_USED = 1;

    ///////////// Callback FLags /////////////

    /// @dev all callback flags should be non zero to reduce storage read / write costs
    /// @dev all callback flags should be unique
    /// Principle Token callbacks
    uint256 internal constant MINT_NOT_AUTHORIZED = 1;
    uint256 internal constant MINT_AUTHORIZED = 2;
    uint256 internal constant BURN_NOT_AUTHORIZED = 3;
    uint256 internal constant BURN_AUTHORIZED = 4;
    /// 721 / 1155 callbacks
    uint256 internal constant ERC1155_NOT_PULLED = 5;
    uint256 internal constant ERC1155_PULLED = 6;
    uint256 internal constant ERC721_NOT_PULLED = 7;
    uint256 internal constant ERC721_PULLED = 8;
}
