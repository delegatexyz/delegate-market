// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.20;

import {DelegateToken} from "src/DelegateToken.sol";
import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";

/// Harness for DelegateToken that exposes internal methods
contract DTHarness is DelegateToken {
    function exposedSlotUint256(uint256 slotNumber) external view returns (uint256 data) {
        assembly {
            data := sload(slotNumber)
        }
    }

    constructor(address delegateRegistry_, address principalToken_, string memory basURI_, address initialMetadataOwner)
        DelegateToken(delegateRegistry_, principalToken_, basURI_, initialMetadataOwner)
    {
        // Initialize info struct with test info
        uint256[3] memory testInfo = [uint256(1), uint256(2), uint256(3)];
        delegateTokenInfo[0] = testInfo;
    }

    function exposedDelegateTokenInfo(uint256 delegateTokenId, uint256 position) external view returns (uint256) {
        return delegateTokenInfo[delegateTokenId][position];
    }

    function exposedStoragePositionsMin() external pure returns (uint256) {
        return uint256(type(StoragePositions).min);
    }

    function exposedStoragePositionsMax() external pure returns (uint256) {
        return uint256(type(StoragePositions).max);
    }

    function exposedMaxExpiry() external pure returns (uint256) {
        return MAX_EXPIRY;
    }

    function exposedDelegateTokenIdAvailable() external pure returns (uint256) {
        return DELEGATE_TOKEN_ID_AVAILABLE;
    }

    function exposedDelegateTokenIdUsed() external pure returns (uint256) {
        return DELEGATE_TOKEN_ID_USED;
    }

    function exposedBalances(address delegateTokenHolder) external view returns (uint256) {
        return balances[delegateTokenHolder];
    }

    function exposedApprovals(bytes32 approveAllHash) external view returns (uint256) {
        return approvals[approveAllHash];
    }

    function exposedApproveAllDisabled() external pure returns (uint256) {
        return APPROVE_ALL_DISABLED;
    }

    function exposedApproveAllEnabled() external pure returns (uint256) {
        return APPROVE_ALL_ENABLED;
    }

    function exposedRescindAddress() external pure returns (address) {
        return RESCIND_ADDRESS;
    }

    function exposedTransferByType(
        uint256 delegateTokenId,
        bytes32 registryLocation,
        address from,
        bytes32 delegationHash,
        address to,
        IDelegateRegistry.DelegationType underlyingType,
        address underlyingContract,
        bytes32 underlyingRights
    ) external {
        _transferByType(delegateTokenId, registryLocation, from, delegationHash, to, underlyingType, underlyingContract, underlyingRights);
    }

    function exposedIsApprovedOrOwner(address spender, uint256 delegateTokenId) external view returns (bool approvedOrOwner, address delegateTokenHolder) {
        return _isApprovedOrOwner(spender, delegateTokenId);
    }

    function exposedPullAndParse(IDelegateRegistry.DelegationType underlyingType, uint256 underlyingAmount, address underlyingContract, uint256 underlyingTokenId)
        external
        returns (uint256 parsedUnderlyingAmount, uint256 parsedUnderlyingTokenId)
    {
        return _pullAndParse(underlyingType, underlyingAmount, underlyingContract, underlyingTokenId);
    }

    function exposedCreateByType(
        IDelegateRegistry.DelegationType underlyingType,
        uint256 delegateTokenId,
        address delegateTokenTo,
        uint256 underlyingAmount,
        address underlyingContract,
        bytes32 underlyingRights,
        uint256 underlyingTokenId
    ) external {
        _createByType(underlyingType, delegateTokenId, delegateTokenTo, underlyingAmount, underlyingContract, underlyingRights, underlyingTokenId);
    }

    function exposedWithdrawByType(
        address recipient,
        bytes32 registryLocation,
        uint256 delegateTokenId,
        bytes32 delegationHash,
        address delegateTokenHolder,
        IDelegateRegistry.DelegationType delegationType,
        address underlyingContract,
        bytes32 underlyingRights
    ) external {
        _withdrawByType(recipient, registryLocation, delegateTokenId, delegationHash, delegateTokenHolder, delegationType, underlyingContract, underlyingRights);
    }

    function exposedWriteApproved(uint256 delegateTokenId, address approved) external {
        _writeApproved(delegateTokenId, approved);
    }

    function exposedWriteExpiry(uint256 delegateTokenId, uint256 expiry) external {
        _writeExpiry(delegateTokenId, expiry);
    }

    function exposedReadApproved(uint256 delegateTokenId) external view returns (address) {
        return _readApproved(delegateTokenId);
    }

    function exposedReadExpiry(uint256 delegateTokenId) external view returns (uint256) {
        return _readExpiry(delegateTokenId);
    }

    function exposedBuildTokenURI(address tokenContract, uint256 delegateTokenId, uint256 expiry, address principalOwner) external view returns (string memory) {
        return _buildTokenURI(tokenContract, delegateTokenId, expiry, principalOwner);
    }
}
