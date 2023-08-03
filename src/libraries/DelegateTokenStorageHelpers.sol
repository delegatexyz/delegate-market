// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {DelegateTokenConstants as Constants} from "src/libraries/DelegateTokenConstants.sol";
import {DelegateTokenErrors as Errors} from "src/libraries/DelegateTokenErrors.sol";

library DelegateTokenStorageHelpers {
    struct Uint256 {
        uint256 flag;
    }

    function writeApproved(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId, address approved) internal {
        uint96 expiry = uint96(delegateTokenInfo[delegateTokenId][Constants.PACKED_INFO_POSITION]);
        delegateTokenInfo[delegateTokenId][Constants.PACKED_INFO_POSITION] = (uint256(uint160(approved)) << 96) | expiry;
    }

    function writeExpiry(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId, uint256 expiry) internal {
        if (expiry > Constants.MAX_EXPIRY) revert Errors.ExpiryTooLarge(expiry, Constants.MAX_EXPIRY);
        address approved = address(uint160(delegateTokenInfo[delegateTokenId][Constants.PACKED_INFO_POSITION] >> 96));
        delegateTokenInfo[delegateTokenId][Constants.PACKED_INFO_POSITION] = (uint256(uint160(approved)) << 96) | expiry;
    }

    function writeRegistryHash(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId, bytes32 registryHash) internal {
        delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION] = uint256(registryHash);
    }

    function writeUnderlyingAmount(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId, uint256 underlyingAmount)
        internal
    {
        delegateTokenInfo[delegateTokenId][Constants.UNDERLYING_AMOUNT_POSITION] = underlyingAmount;
    }

    function readApproved(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId) internal view returns (address) {
        return address(uint160(delegateTokenInfo[delegateTokenId][Constants.PACKED_INFO_POSITION] >> 96));
    }

    function readExpiry(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId) internal view returns (uint256) {
        return uint96(delegateTokenInfo[delegateTokenId][Constants.PACKED_INFO_POSITION]);
    }

    function readRegistryHash(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId) internal view returns (bytes32) {
        return bytes32(delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION]);
    }

    function readUnderlyingAmount(mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId)
        internal
        view
        returns (uint256)
    {
        return delegateTokenInfo[delegateTokenId][Constants.UNDERLYING_AMOUNT_POSITION];
    }
}
