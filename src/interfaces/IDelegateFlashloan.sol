// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";

interface IDelegateFlashloan {
    /**
     * @dev Receive a delegate flashloan.
     * @param initiator The initiator of the delegate flashloan.
     * @param delegationType The type of delegation contract, e.g. ERC20.
     * @param underlyingContract The contract of the underlying being loaned.
     * @param underlyingTokenId The tokenId of the underlying being loaned, if applicable.
     * @param flashAmount The amount being lent, if applicable.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     * @return The keccak256 hash of "IDelegateFlashloan.onFlashloan"
     */
    function onFlashloan(
        address initiator,
        IDelegateRegistry.DelegationType delegationType,
        address underlyingContract,
        uint256 underlyingTokenId,
        uint256 flashAmount,
        bytes calldata data
    ) external payable returns (bytes32);
}
