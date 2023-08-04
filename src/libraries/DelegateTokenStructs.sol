// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";

library DelegateTokenStructs {
    struct Uint256 {
        uint256 flag;
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
