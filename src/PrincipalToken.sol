// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IDelegateToken} from "src/interfaces/IDelegateToken.sol";

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {MarketMetadata} from "src/MarketMetadata.sol";

/// @notice A simple NFT that doesn't store any user data itself, being tightly linked to the more stateful Delegate
/// Token.
/// @notice The holder of the PT is eligible to reclaim the escrowed NFT when the DT expires or is burned.
contract PrincipalToken is ERC721("PrincipalToken", "PT") {
    address public immutable delegateToken;
    address public immutable marketMetadata;

    error DelegateTokenZero();
    error MarketMetadataZero();
    error CallerNotDelegateToken();
    error NotApproved(address spender, uint256 id);

    constructor(address setDelegateToken, address setMarketMetadata) {
        if (setDelegateToken == address(0)) revert DelegateTokenZero();
        delegateToken = setDelegateToken;
        if (setMarketMetadata == address(0)) revert MarketMetadataZero();
        marketMetadata = setMarketMetadata;
    }

    function _checkDelegateTokenCaller() internal view {
        if (msg.sender != delegateToken) revert CallerNotDelegateToken();
    }

    /// @notice exposes _mint method
    /// @dev must revert if caller is not delegate token
    /// @dev must revert if delegate token has not authorized the mint
    function mint(address to, uint256 id) external {
        _checkDelegateTokenCaller();
        _mint(to, id);
        IDelegateToken(delegateToken).mintAuthorizedCallback();
    }

    /// @notice exposes _burn method
    /// @dev must revert if spender fails isApprovedOrOwner for the token
    /// @dev must revert if caller is not delegate token
    /// @dev must revert if delegate token has not authorized the burn
    function burn(address spender, uint256 id) external {
        if (!_isApprovedOrOwner(spender, id)) revert NotApproved(spender, id);
        _checkDelegateTokenCaller();
        _burn(id);
        IDelegateToken(delegateToken).burnAuthorizedCallback();
    }

    /// @notice exposes _isApprovedOrOwner method
    function isApprovedOrOwner(address account, uint256 id) external view returns (bool) {
        return _isApprovedOrOwner(account, id);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        _requireMinted(id);
        return MarketMetadata(marketMetadata).principalTokenURI(delegateToken, id);
    }
}
