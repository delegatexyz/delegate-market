// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {RegistryStorage} from "delegate-registry/src/libraries/RegistryStorage.sol";
import {RegistryHashes} from "delegate-registry/src/libraries/RegistryHashes.sol";
import {DelegateTokenStorageHelpers as StorageHelpers} from "src/libraries/DelegateTokenStorageHelpers.sol";
import {DelegateTokenErrors as Errors} from "src/libraries/DelegateTokenErrors.sol";
import {IDelegateToken} from "src/interfaces/IDelegateToken.sol";

library DelegateTokenRegistryHelpers {
    /// @dev should not be called if registryHash is being modified elsewhere in the function
    function loadTokenHolder(address delegateRegistry, mapping(uint256 delegateTokenId => uint256[3] info) storage delegateTokenInfo, uint256 delegateTokenId)
        internal
        view
        returns (address delegateTokenHolder)
    {
        unchecked {
            return RegistryStorage.unpackAddress(
                IDelegateRegistry(delegateRegistry).readSlot(
                    bytes32(
                        uint256(RegistryHashes.location(bytes32(StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId))))
                            + uint256(RegistryStorage.Positions.secondPacked)
                    )
                )
            );
        } // Reasonable to not expect this to overflow
    }

    function loadTokenHolderAndContract(address delegateRegistry, bytes32 registryHash) internal view returns (address delegateTokenHolder, address underlyingContract) {
        unchecked {
            uint256 registryLocation = uint256(RegistryHashes.location(registryHash));
            //slither-disable-next-line unused-return
            (, delegateTokenHolder, underlyingContract) = RegistryStorage.unPackAddresses(
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

    function delegateERC721(address delegateRegistry, bytes32 newRegistryHash, IDelegateToken.DelegateInfo calldata delegateInfo) internal {
        if (
            IDelegateRegistry(delegateRegistry).delegateERC721(delegateInfo.delegateHolder, delegateInfo.tokenContract, delegateInfo.tokenId, delegateInfo.rights, true)
                != newRegistryHash
        ) {
            revert Errors.HashMismatch();
        }
    }

    function delegateERC20(address delegateRegistry, bytes32 newRegistryHash, IDelegateToken.DelegateInfo calldata delegateInfo) internal {
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

    function delegateERC1155(address delegateRegistry, bytes32 newRegistryHash, IDelegateToken.DelegateInfo calldata delegateInfo) internal {
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
}
