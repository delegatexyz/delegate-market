// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {RegistryStorage} from "delegate-registry/src/libraries/RegistryStorage.sol";
import {RegistryHashes} from "delegate-registry/src/libraries/RegistryHashes.sol";
import {DelegateTokenErrors as Errors} from "src/libraries/DelegateTokenErrors.sol";
import {DelegateTokenStructs as Structs} from "src/libraries/DelegateTokenStructs.sol";

library DelegateTokenRegistryHelpers {
    function loadTokenHolder(address delegateRegistry, bytes32 registryHash) internal view returns (address delegateTokenHolder) {
        unchecked {
            return RegistryStorage.unpackAddress(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(RegistryHashes.location(registryHash)) + uint256(RegistryStorage.Positions.secondPacked)))
            );
        }
    }

    function loadContract(address delegateRegistry, bytes32 registryHash) internal view returns (address underlyingContract) {
        unchecked {
            uint256 registryLocation = uint256(RegistryHashes.location(registryHash));
            //slither-disable-next-line unused-return
            (,, underlyingContract) = RegistryStorage.unpackAddresses(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(registryLocation + uint256(RegistryStorage.Positions.firstPacked))),
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(registryLocation + uint256(RegistryStorage.Positions.secondPacked)))
            );
        }
    }

    function loadTokenHolderAndContract(address delegateRegistry, bytes32 registryHash) internal view returns (address delegateTokenHolder, address underlyingContract) {
        unchecked {
            uint256 registryLocation = uint256(RegistryHashes.location(registryHash));
            //slither-disable-next-line unused-return
            (, delegateTokenHolder, underlyingContract) = RegistryStorage.unpackAddresses(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(registryLocation + uint256(RegistryStorage.Positions.firstPacked))),
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(registryLocation + uint256(RegistryStorage.Positions.secondPacked)))
            );
        }
    }

    function loadFrom(address delegateRegistry, bytes32 registryHash) internal view returns (address) {
        unchecked {
            return RegistryStorage.unpackAddress(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(RegistryHashes.location(registryHash)) + uint256(RegistryStorage.Positions.firstPacked)))
            );
        }
    }

    function loadAmount(address delegateRegistry, bytes32 registryHash) internal view returns (uint256) {
        unchecked {
            return
                uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(RegistryHashes.location(registryHash)) + uint256(RegistryStorage.Positions.amount))));
        }
    }

    function loadRights(address delegateRegistry, bytes32 registryHash) internal view returns (bytes32) {
        unchecked {
            return IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(RegistryHashes.location(registryHash)) + uint256(RegistryStorage.Positions.rights)));
        }
    }

    function loadTokenId(address delegateRegistry, bytes32 registryHash) internal view returns (uint256) {
        unchecked {
            return uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(RegistryHashes.location(registryHash)) + uint256(RegistryStorage.Positions.tokenId)))
            );
        }
    }

    function calculateDecreasedAmount(address delegateRegistry, bytes32 registryHash, uint256 decreaseAmount) internal view returns (uint256) {
        unchecked {
            return uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(RegistryHashes.location(registryHash)) + uint256(RegistryStorage.Positions.amount)))
            ) - decreaseAmount;
        }
    }

    function calculateIncreasedAmount(address delegateRegistry, bytes32 registryHash, uint256 increaseAmount) internal view returns (uint256) {
        unchecked {
            return uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(RegistryHashes.location(registryHash)) + uint256(RegistryStorage.Positions.amount)))
            ) + increaseAmount;
        }
    }

    function revertERC721FlashUnavailable(address delegateRegistry, Structs.FlashInfo calldata info) internal view {
        // We touch registry directly to check for active delegation of the respective hash, as bubbling up to contract
        // and all delegations is not required
        // Important to notice that we cannot rely on this method for the fungibles since delegate token doesn't ever
        // delete the fungible delegations
        if (
            loadFrom(delegateRegistry, RegistryHashes.erc721Hash(address(this), "", info.delegateHolder, info.tokenId, info.tokenContract)) != address(this)
                && loadFrom(delegateRegistry, RegistryHashes.erc721Hash(address(this), "flashloan", info.delegateHolder, info.tokenId, info.tokenContract)) != address(this)
        ) {
            revert Errors.ERC721FlashUnavailable(info.tokenId);
        }
    }

    function revertERC20FlashAmountUnavailable(address delegateRegistry, Structs.FlashInfo calldata info) internal view {
        uint256 availableAmount = 0;
        unchecked {
            // We sum the delegation amounts for "flashloan" and "" rights since liquid delegate doesn't allow double
            // spending for different rights
            availableAmount = loadAmount(delegateRegistry, RegistryHashes.erc20Hash(address(this), "flashloan", info.delegateHolder, info.tokenContract))
                + loadAmount(delegateRegistry, RegistryHashes.erc20Hash(address(this), "", info.delegateHolder, info.tokenContract));
        } // Unreasonable that this block will overflow
        if (info.amount > availableAmount) revert Errors.ERC20FlashAmountUnavailable(info.amount, availableAmount);
    }

    function revertERC1155FlashAmountUnavailable(address delegateRegistry, Structs.FlashInfo calldata info) internal view {
        uint256 availableAmount = 0;
        unchecked {
            availableAmount = loadAmount(delegateRegistry, RegistryHashes.erc1155Hash(address(this), "flashloan", info.delegateHolder, info.tokenId, info.tokenContract))
                + loadAmount(delegateRegistry, RegistryHashes.erc1155Hash(address(this), "", info.delegateHolder, info.tokenId, info.tokenContract));
        } // Unreasonable that this will overflow
        if (info.amount > availableAmount) {
            revert Errors.ERC1155FlashAmountUnavailable(info.tokenId, info.amount, availableAmount);
        }
    }

    function transferERC721(
        address delegateRegistry,
        bytes32 registryHash,
        address from,
        bytes32 newRegistryHash,
        address to,
        bytes32 underlyingRights,
        address underlyingContract,
        uint256 underlyingTokenId
    ) internal {
        if (
            IDelegateRegistry(delegateRegistry).delegateERC721(from, underlyingContract, underlyingTokenId, underlyingRights, false) != registryHash
                || IDelegateRegistry(delegateRegistry).delegateERC721(to, underlyingContract, underlyingTokenId, underlyingRights, true) != newRegistryHash
        ) revert Errors.HashMismatch();
    }

    function transferERC20(
        address delegateRegistry,
        bytes32 registryHash,
        address from,
        bytes32 newRegistryHash,
        address to,
        uint256 underlyingAmount,
        bytes32 underlyingRights,
        address underlyingContract
    ) internal {
        if (
            IDelegateRegistry(delegateRegistry).delegateERC20(
                from, underlyingContract, calculateDecreasedAmount(delegateRegistry, registryHash, underlyingAmount), underlyingRights, true
            ) != bytes32(registryHash)
                || IDelegateRegistry(delegateRegistry).delegateERC20(
                    to, underlyingContract, calculateIncreasedAmount(delegateRegistry, newRegistryHash, underlyingAmount), underlyingRights, true
                ) != newRegistryHash
        ) {
            revert Errors.HashMismatch();
        }
    }

    function transferERC1155(
        address delegateRegistry,
        bytes32 registryHash,
        address from,
        bytes32 newRegistryHash,
        address to,
        uint256 underlyingAmount,
        bytes32 underlyingRights,
        address underlyingContract,
        uint256 underlyingTokenId
    ) internal {
        if (
            IDelegateRegistry(delegateRegistry).delegateERC1155(
                from, underlyingContract, underlyingTokenId, calculateDecreasedAmount(delegateRegistry, registryHash, underlyingAmount), underlyingRights, true
            ) != registryHash
                || IDelegateRegistry(delegateRegistry).delegateERC1155(
                    to, underlyingContract, underlyingTokenId, calculateIncreasedAmount(delegateRegistry, newRegistryHash, underlyingAmount), underlyingRights, true
                ) != newRegistryHash
        ) revert Errors.HashMismatch();
    }

    function delegateERC721(address delegateRegistry, bytes32 newRegistryHash, Structs.DelegateInfo calldata delegateInfo) internal {
        if (
            IDelegateRegistry(delegateRegistry).delegateERC721(delegateInfo.delegateHolder, delegateInfo.tokenContract, delegateInfo.tokenId, delegateInfo.rights, true)
                != newRegistryHash
        ) {
            revert Errors.HashMismatch();
        }
    }

    function delegateERC20(address delegateRegistry, bytes32 newRegistryHash, Structs.DelegateInfo calldata delegateInfo) internal {
        if (
            IDelegateRegistry(delegateRegistry).delegateERC20(
                delegateInfo.delegateHolder,
                delegateInfo.tokenContract,
                calculateIncreasedAmount(delegateRegistry, newRegistryHash, delegateInfo.amount),
                delegateInfo.rights,
                true
            ) != newRegistryHash
        ) {
            revert Errors.HashMismatch();
        }
    }

    function delegateERC1155(address delegateRegistry, bytes32 newRegistryHash, Structs.DelegateInfo calldata delegateInfo) internal {
        if (
            IDelegateRegistry(delegateRegistry).delegateERC1155(
                delegateInfo.delegateHolder,
                delegateInfo.tokenContract,
                delegateInfo.tokenId,
                calculateIncreasedAmount(delegateRegistry, newRegistryHash, delegateInfo.amount),
                delegateInfo.rights,
                true
            ) != newRegistryHash
        ) revert Errors.HashMismatch();
    }

    function revokeERC721(
        address delegateRegistry,
        bytes32 registryHash,
        address delegateTokenHolder,
        address underlyingContract,
        uint256 underlyingTokenId,
        bytes32 underlyingRights
    ) internal {
        if (IDelegateRegistry(delegateRegistry).delegateERC721(delegateTokenHolder, underlyingContract, underlyingTokenId, underlyingRights, false) != registryHash) {
            revert Errors.HashMismatch();
        }
    }

    function revokeERC20(
        address delegateRegistry,
        bytes32 registryHash,
        address delegateTokenHolder,
        address underlyingContract,
        uint256 underlyingAmount,
        bytes32 underlyingRights
    ) internal {
        if (
            IDelegateRegistry(delegateRegistry).delegateERC20(
                delegateTokenHolder, underlyingContract, calculateDecreasedAmount(delegateRegistry, registryHash, underlyingAmount), underlyingRights, true
            ) != registryHash
        ) revert Errors.HashMismatch();
    }

    function revokeERC1155(
        address delegateRegistry,
        bytes32 registryHash,
        address delegateTokenHolder,
        address underlyingContract,
        uint256 underlyingTokenId,
        uint256 underlyingAmount,
        bytes32 underlyingRights
    ) internal {
        if (
            IDelegateRegistry(delegateRegistry).delegateERC1155(
                delegateTokenHolder,
                underlyingContract,
                underlyingTokenId,
                calculateDecreasedAmount(delegateRegistry, registryHash, underlyingAmount),
                underlyingRights,
                true
            ) != registryHash
        ) revert Errors.HashMismatch();
    }
}
