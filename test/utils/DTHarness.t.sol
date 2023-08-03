// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

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

    function exposedBalances(address delegateTokenHolder) external view returns (uint256) {
        return balances[delegateTokenHolder];
    }

    function exposedTransferByType(address from, uint256 delegateTokenId, address to, bytes32 registryHash, address underlyingContract) external {
        _transferByType(from, delegateTokenId, to, registryHash, underlyingContract);
    }

    function exposedCreateByType(DelegateInfo calldata delegateInfo, uint256 delegateTokenId) external {
        _createByType(delegateInfo, delegateTokenId);
    }

    function exposedWithdrawByType(address recipient, uint256 delegateTokenId, address delegateTokenHolder, bytes32 registryHash, address underlyingContract) external {
        _withdrawByType(recipient, delegateTokenId, delegateTokenHolder, registryHash, underlyingContract);
    }

    function exposedBuildTokenURI(address tokenContract, uint256 delegateTokenId, uint256 expiry, address principalOwner) external view returns (string memory) {
        return _buildTokenURI(tokenContract, delegateTokenId, expiry, principalOwner);
    }
}
