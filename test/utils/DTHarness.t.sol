// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {DelegateToken, Structs} from "src/DelegateToken.sol";
import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";

/// Harness for DelegateToken that exposes internal methods
contract DTHarness is DelegateToken {
    function exposedSlotUint256(uint256 slotNumber) external view returns (uint256 data) {
        assembly {
            data := sload(slotNumber)
        }
    }

    constructor(Structs.DelegateTokenParameters memory parameters) DelegateToken(parameters) {
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
}
