// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";

interface IDelegateFlashloan {
    /**
     * @dev Receive a delegate flashloan.
     * @param initiator caller of the flashloan
     * @param flashInfo struct
     * @return The keccak256 hash of "IDelegateFlashloan.onFlashloan"
     */
    function onFlashloan(address initiator, FlashInfo calldata flashInfo) external payable returns (bytes32);

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
