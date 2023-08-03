// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {RegistryStorage} from "delegate-registry/src/libraries/RegistryStorage.sol";
import {RegistryHashes} from "delegate-registry/src/libraries/RegistryHashes.sol";
import {DelegateTokenStorageHelpers as StorageHelpers} from "src/libraries/DelegateTokenStorageHelpers.sol";

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
}
