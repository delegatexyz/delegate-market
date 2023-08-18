// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IDelegateRegistry, BaseLiquidDelegateTest, DelegateTokenStructs} from "test/base/BaseLiquidDelegateTest.t.sol";
import {DelegateTokenErrors} from "src/libraries/DelegateTokenLib.sol";
import {DelegateTokenRegistryHelpers as Helpers} from "src/libraries/DelegateTokenRegistryHelpers.sol";

contract CalldataHarness {
    function revertERC721FlashUnavailable(address delegateRegistry, DelegateTokenStructs.FlashInfo calldata info) external view {
        Helpers.revertERC721FlashUnavailable(delegateRegistry, info);
    }

    function revertERC20FlashAmountUnavailable(address delegateRegistry, DelegateTokenStructs.FlashInfo calldata info) external view {
        Helpers.revertERC20FlashAmountUnavailable(delegateRegistry, info);
    }

    function revertERC1155FlashAmountUnavailable(address delegateRegistry, DelegateTokenStructs.FlashInfo calldata info) external view {
        Helpers.revertERC1155FlashAmountUnavailable(delegateRegistry, info);
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
    ) external {
        Helpers.transferERC721({
            delegateRegistry: address(delegateRegistry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: newRegistryHash,
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingTokenId: underlyingTokenId
        });
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
    ) external {
        Helpers.transferERC20({
            delegateRegistry: address(delegateRegistry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: newRegistryHash,
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: underlyingAmount
        });
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
    ) external {
        Helpers.transferERC1155({
            delegateRegistry: address(delegateRegistry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: newRegistryHash,
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: underlyingAmount,
            underlyingTokenId: underlyingTokenId
        });
    }

    function delegateERC721(address delegateRegistry, bytes32 newRegistryHash, DelegateTokenStructs.DelegateInfo calldata delegateInfo) external {
        Helpers.delegateERC721(delegateRegistry, newRegistryHash, delegateInfo);
    }

    function delegateERC20(address delegateRegistry, bytes32 newRegistryHash, DelegateTokenStructs.DelegateInfo calldata delegateInfo) external {
        Helpers.delegateERC20(delegateRegistry, newRegistryHash, delegateInfo);
    }

    function delegateERC1155(address delegateRegistry, bytes32 newRegistryHash, DelegateTokenStructs.DelegateInfo calldata delegateInfo) external {
        Helpers.delegateERC1155(delegateRegistry, newRegistryHash, delegateInfo);
    }

    function revokeERC721(
        address delegateRegistry,
        bytes32 registryHash,
        address delegateTokenHolder,
        address underlyingContract,
        uint256 underlyingTokenId,
        bytes32 underlyingRights
    ) external {
        Helpers.revokeERC721(delegateRegistry, registryHash, delegateTokenHolder, underlyingContract, underlyingTokenId, underlyingRights);
    }

    function revokeERC20(
        address delegateRegistry,
        bytes32 registryHash,
        address delegateTokenHolder,
        address underlyingContract,
        uint256 underlyingAmount,
        bytes32 underlyingRights
    ) external {
        Helpers.revokeERC20(delegateRegistry, registryHash, delegateTokenHolder, underlyingContract, underlyingAmount, underlyingRights);
    }

    function revokeERC1155(
        address delegateRegistry,
        bytes32 registryHash,
        address delegateTokenHolder,
        address underlyingContract,
        uint256 underlyingTokenId,
        uint256 underlyingAmount,
        bytes32 underlyingRights
    ) external {
        Helpers.revokeERC1155(delegateRegistry, registryHash, delegateTokenHolder, underlyingContract, underlyingTokenId, underlyingAmount, underlyingRights);
    }
}

contract DelegateTokenRegistryHelpersTest is Test, BaseLiquidDelegateTest {
    CalldataHarness harness;

    function setUp() public {
        harness = new CalldataHarness();
    }

    function testLoadTokenHolderAll(address from, address to, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateAll(to, rights, true);
        vm.stopPrank();
        assertEq(to, Helpers.loadTokenHolder(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateAll(to, rights, false), hash);
        vm.stopPrank();
        assertEq(address(0), Helpers.loadTokenHolder(address(registry), hash));
    }

    function testLoadTokenHolderContract(address from, address to, address contract_, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateContract(to, contract_, rights, true);
        vm.stopPrank();
        assertEq(to, Helpers.loadTokenHolder(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateContract(to, contract_, rights, false), hash);
        vm.stopPrank();
        assertEq(address(0), Helpers.loadTokenHolder(address(registry), hash));
    }

    function testLoadTokenHolderERC721(address from, address to, address contract_, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC721(to, contract_, tokenId, rights, true);
        vm.stopPrank();
        assertEq(to, Helpers.loadTokenHolder(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC721(to, contract_, tokenId, rights, false), hash);
        vm.stopPrank();
        assertEq(address(0), Helpers.loadTokenHolder(address(registry), hash));
    }

    function testLoadTokenHolderERC20(address from, address to, address contract_, uint256 amount, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC20(to, contract_, amount, rights, true);
        vm.stopPrank();
        assertEq(to, Helpers.loadTokenHolder(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC20(to, contract_, amount, rights, false), hash);
        vm.stopPrank();
        assertEq(address(0), Helpers.loadTokenHolder(address(registry), hash));
    }

    function testLoadTokenHolderERC1155(address from, address to, address contract_, uint256 amount, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC1155(to, contract_, tokenId, amount, rights, true);
        vm.stopPrank();
        assertEq(to, Helpers.loadTokenHolder(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC1155(to, contract_, tokenId, amount, rights, false), hash);
        vm.stopPrank();
        assertEq(address(0), Helpers.loadTokenHolder(address(registry), hash));
    }

    function testLoadContractAll(address from, address to, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateAll(to, rights, true);
        vm.stopPrank();
        assertEq(address(0), Helpers.loadContract(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateAll(to, rights, false), hash);
        vm.stopPrank();
        assertEq(address(0), Helpers.loadContract(address(registry), hash));
    }

    function testLoadContractContract(address from, address to, address contract_, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateContract(to, contract_, rights, true);
        vm.stopPrank();
        assertEq(contract_, Helpers.loadContract(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateContract(to, contract_, rights, false), hash);
        vm.stopPrank();
        assertEq(address(0), Helpers.loadContract(address(registry), hash));
    }

    function testLoadContractERC721(address from, address to, address contract_, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC721(to, contract_, tokenId, rights, true);
        vm.stopPrank();
        assertEq(contract_, Helpers.loadContract(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC721(to, contract_, tokenId, rights, false), hash);
        vm.stopPrank();
        assertEq(address(0), Helpers.loadContract(address(registry), hash));
    }

    function testLoadContractERC20(address from, address to, address contract_, uint256 amount, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC20(to, contract_, amount, rights, true);
        vm.stopPrank();
        assertEq(contract_, Helpers.loadContract(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC20(to, contract_, amount, rights, false), hash);
        vm.stopPrank();
        assertEq(address(0), Helpers.loadContract(address(registry), hash));
    }

    function testLoadContractERC1155(address from, address to, address contract_, uint256 amount, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC1155(to, contract_, tokenId, amount, rights, true);
        vm.stopPrank();
        assertEq(contract_, Helpers.loadContract(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC1155(to, contract_, tokenId, amount, rights, false), hash);
        vm.stopPrank();
        assertEq(address(0), Helpers.loadContract(address(registry), hash));
    }

    function testLoadTokenHolderAndContractAll(address from, address to, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateAll(to, rights, true);
        vm.stopPrank();
        (address loadedHolder, address loadedContract) = Helpers.loadTokenHolderAndContract(address(registry), hash);
        assertEq(loadedHolder, to);
        assertEq(loadedContract, address(0));
        vm.startPrank(from);
        assertEq(registry.delegateAll(to, rights, false), hash);
        vm.stopPrank();
        (loadedHolder, loadedContract) = Helpers.loadTokenHolderAndContract(address(registry), hash);
        assertEq(loadedHolder, address(0));
        assertEq(loadedContract, address(0));
    }

    function testLoadTokenHolderAndContractContract(address from, address to, address contract_, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateContract(to, contract_, rights, true);
        vm.stopPrank();
        (address loadedHolder, address loadedContract) = Helpers.loadTokenHolderAndContract(address(registry), hash);
        assertEq(loadedHolder, to);
        assertEq(loadedContract, contract_);
        vm.startPrank(from);
        assertEq(registry.delegateContract(to, contract_, rights, false), hash);
        vm.stopPrank();
        (loadedHolder, loadedContract) = Helpers.loadTokenHolderAndContract(address(registry), hash);
        assertEq(loadedHolder, address(0));
        assertEq(loadedContract, address(0));
    }

    function testLoadTokenHolderAndContractERC721(address from, address to, address contract_, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC721(to, contract_, tokenId, rights, true);
        vm.stopPrank();
        (address loadedHolder, address loadedContract) = Helpers.loadTokenHolderAndContract(address(registry), hash);
        assertEq(loadedHolder, to);
        assertEq(loadedContract, contract_);
        vm.startPrank(from);
        assertEq(registry.delegateERC721(to, contract_, tokenId, rights, false), hash);
        vm.stopPrank();
        (loadedHolder, loadedContract) = Helpers.loadTokenHolderAndContract(address(registry), hash);
        assertEq(loadedHolder, address(0));
        assertEq(loadedContract, address(0));
    }

    function testLoadTokenHolderAndContractERC20(address from, address to, address contract_, uint256 amount, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC20(to, contract_, amount, rights, true);
        vm.stopPrank();
        (address loadedHolder, address loadedContract) = Helpers.loadTokenHolderAndContract(address(registry), hash);
        assertEq(loadedHolder, to);
        assertEq(loadedContract, contract_);
        vm.startPrank(from);
        assertEq(registry.delegateERC20(to, contract_, amount, rights, false), hash);
        vm.stopPrank();
        (loadedHolder, loadedContract) = Helpers.loadTokenHolderAndContract(address(registry), hash);
        assertEq(loadedHolder, address(0));
        assertEq(loadedContract, address(0));
    }

    function testLoadTokenHolderAndContractERC1155(address from, address to, address contract_, uint256 amount, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC1155(to, contract_, tokenId, amount, rights, true);
        vm.stopPrank();
        (address loadedHolder, address loadedContract) = Helpers.loadTokenHolderAndContract(address(registry), hash);
        assertEq(loadedHolder, to);
        assertEq(loadedContract, contract_);
        vm.startPrank(from);
        assertEq(registry.delegateERC1155(to, contract_, tokenId, amount, rights, false), hash);
        vm.stopPrank();
        (loadedHolder, loadedContract) = Helpers.loadTokenHolderAndContract(address(registry), hash);
        assertEq(loadedHolder, address(0));
        assertEq(loadedContract, address(0));
    }

    function testLoadFromAll(address from, address to, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateAll(to, rights, true);
        vm.stopPrank();
        assertEq(from, Helpers.loadFrom(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateAll(to, rights, false), hash);
        vm.stopPrank();
        assertEq(address(1), Helpers.loadFrom(address(registry), hash));
    }

    function testLoadFromContract(address from, address to, address contract_, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateContract(to, contract_, rights, true);
        vm.stopPrank();
        assertEq(from, Helpers.loadFrom(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateContract(to, contract_, rights, false), hash);
        vm.stopPrank();
        assertEq(address(1), Helpers.loadFrom(address(registry), hash));
    }

    function testLoadFromERC721(address from, address to, address contract_, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC721(to, contract_, tokenId, rights, true);
        vm.stopPrank();
        assertEq(from, Helpers.loadFrom(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC721(to, contract_, tokenId, rights, false), hash);
        vm.stopPrank();
        assertEq(address(1), Helpers.loadFrom(address(registry), hash));
    }

    function testLoadFromERC20(address from, address to, address contract_, uint256 amount, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC20(to, contract_, amount, rights, true);
        vm.stopPrank();
        assertEq(from, Helpers.loadFrom(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC20(to, contract_, amount, rights, false), hash);
        vm.stopPrank();
        assertEq(address(1), Helpers.loadFrom(address(registry), hash));
    }

    function testLoadFromERC1155(address from, address to, address contract_, uint256 amount, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC1155(to, contract_, tokenId, amount, rights, true);
        vm.stopPrank();
        assertEq(from, Helpers.loadFrom(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC1155(to, contract_, tokenId, amount, rights, false), hash);
        vm.stopPrank();
        assertEq(address(1), Helpers.loadFrom(address(registry), hash));
    }

    function testLoadAmountAll(address from, address to, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateAll(to, rights, true);
        vm.stopPrank();
        assertEq(0, Helpers.loadAmount(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateAll(to, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadAmount(address(registry), hash));
    }

    function testLoadAmountContract(address from, address to, address contract_, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateContract(to, contract_, rights, true);
        vm.stopPrank();
        assertEq(0, Helpers.loadAmount(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateContract(to, contract_, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadAmount(address(registry), hash));
    }

    function testLoadAmountERC721(address from, address to, address contract_, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC721(to, contract_, tokenId, rights, true);
        vm.stopPrank();
        assertEq(0, Helpers.loadAmount(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC721(to, contract_, tokenId, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadAmount(address(registry), hash));
    }

    function testLoadAmountERC20(address from, address to, address contract_, uint256 amount, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC20(to, contract_, amount, rights, true);
        vm.stopPrank();
        assertEq(amount, Helpers.loadAmount(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC20(to, contract_, amount, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadAmount(address(registry), hash));
    }

    function testLoadAmountERC1155(address from, address to, address contract_, uint256 amount, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC1155(to, contract_, tokenId, amount, rights, true);
        vm.stopPrank();
        assertEq(amount, Helpers.loadAmount(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC1155(to, contract_, tokenId, amount, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadAmount(address(registry), hash));
    }

    function testLoadRightsAll(address from, address to, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateAll(to, rights, true);
        vm.stopPrank();
        assertEq(rights, Helpers.loadRights(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateAll(to, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadRights(address(registry), hash));
    }

    function testLoadRightsContract(address from, address to, address contract_, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateContract(to, contract_, rights, true);
        vm.stopPrank();
        assertEq(rights, Helpers.loadRights(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateContract(to, contract_, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadRights(address(registry), hash));
    }

    function testLoadRightsERC721(address from, address to, address contract_, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC721(to, contract_, tokenId, rights, true);
        vm.stopPrank();
        assertEq(rights, Helpers.loadRights(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC721(to, contract_, tokenId, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadRights(address(registry), hash));
    }

    function testLoadRightsERC20(address from, address to, address contract_, uint256 amount, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC20(to, contract_, amount, rights, true);
        vm.stopPrank();
        assertEq(rights, Helpers.loadRights(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC20(to, contract_, amount, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadRights(address(registry), hash));
    }

    function testLoadRightsERC1155(address from, address to, address contract_, uint256 amount, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC1155(to, contract_, tokenId, amount, rights, true);
        vm.stopPrank();
        assertEq(rights, Helpers.loadRights(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC1155(to, contract_, tokenId, amount, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadRights(address(registry), hash));
    }

    function testLoadTokenIdAll(address from, address to, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateAll(to, rights, true);
        vm.stopPrank();
        assertEq(0, Helpers.loadTokenId(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateAll(to, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadTokenId(address(registry), hash));
    }

    function testLoadTokenIdContract(address from, address to, address contract_, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateContract(to, contract_, rights, true);
        vm.stopPrank();
        assertEq(0, Helpers.loadTokenId(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateContract(to, contract_, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadTokenId(address(registry), hash));
    }

    function testLoadTokenIdERC721(address from, address to, address contract_, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC721(to, contract_, tokenId, rights, true);
        vm.stopPrank();
        assertEq(tokenId, Helpers.loadTokenId(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC721(to, contract_, tokenId, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadTokenId(address(registry), hash));
    }

    function testLoadTokenIdERC20(address from, address to, address contract_, uint256 amount, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC20(to, contract_, amount, rights, true);
        vm.stopPrank();
        assertEq(0, Helpers.loadTokenId(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC20(to, contract_, amount, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadTokenId(address(registry), hash));
    }

    function testLoadTokenIdERC1155(address from, address to, address contract_, uint256 amount, uint256 tokenId, bytes32 rights) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC1155(to, contract_, tokenId, amount, rights, true);
        vm.stopPrank();
        assertEq(tokenId, Helpers.loadTokenId(address(registry), hash));
        vm.startPrank(from);
        assertEq(registry.delegateERC1155(to, contract_, tokenId, amount, rights, false), hash);
        vm.stopPrank();
        assertEq(0, Helpers.loadTokenId(address(registry), hash));
    }

    function testCalculateDecreasedAmountAll(address from, address to, bytes32 rights, uint256 decreaseAmount) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateAll(to, rights, true);
        vm.stopPrank();
        uint256 expectedDecreasedAmount;
        unchecked {
            expectedDecreasedAmount = 0 - decreaseAmount;
        }
        assertEq(expectedDecreasedAmount, Helpers.calculateDecreasedAmount(address(registry), hash, decreaseAmount));
        vm.startPrank(from);
        assertEq(registry.delegateAll(to, rights, false), hash);
        vm.stopPrank();
        unchecked {
            expectedDecreasedAmount = 0 - decreaseAmount;
        }
        assertEq(expectedDecreasedAmount, Helpers.calculateDecreasedAmount(address(registry), hash, decreaseAmount));
    }

    function testCalculateDecreasedAmountContract(address from, address to, address contract_, bytes32 rights, uint256 decreaseAmount) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateContract(to, contract_, rights, true);
        vm.stopPrank();
        uint256 expectedDecreasedAmount;
        unchecked {
            expectedDecreasedAmount = 0 - decreaseAmount;
        }
        assertEq(expectedDecreasedAmount, Helpers.calculateDecreasedAmount(address(registry), hash, decreaseAmount));
        vm.startPrank(from);
        assertEq(registry.delegateContract(to, contract_, rights, false), hash);
        vm.stopPrank();
        unchecked {
            expectedDecreasedAmount = 0 - decreaseAmount;
        }
        assertEq(expectedDecreasedAmount, Helpers.calculateDecreasedAmount(address(registry), hash, decreaseAmount));
    }

    function testCalculateDecreasedAmountERC721(address from, address to, address contract_, uint256 tokenId, bytes32 rights, uint256 decreaseAmount) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC721(to, contract_, tokenId, rights, true);
        vm.stopPrank();
        uint256 expectedDecreasedAmount;
        unchecked {
            expectedDecreasedAmount = 0 - decreaseAmount;
        }
        assertEq(expectedDecreasedAmount, Helpers.calculateDecreasedAmount(address(registry), hash, decreaseAmount));
        vm.startPrank(from);
        assertEq(registry.delegateERC721(to, contract_, tokenId, rights, false), hash);
        vm.stopPrank();
        unchecked {
            expectedDecreasedAmount = 0 - decreaseAmount;
        }
        assertEq(expectedDecreasedAmount, Helpers.calculateDecreasedAmount(address(registry), hash, decreaseAmount));
    }

    function testCalculateDecreasedAmountERC20(address from, address to, address contract_, uint256 amount, bytes32 rights, uint256 decreaseAmount) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC20(to, contract_, amount, rights, true);
        vm.stopPrank();
        uint256 expectedDecreasedAmount;
        unchecked {
            expectedDecreasedAmount = amount - decreaseAmount;
        }
        assertEq(expectedDecreasedAmount, Helpers.calculateDecreasedAmount(address(registry), hash, decreaseAmount));
        vm.startPrank(from);
        assertEq(registry.delegateERC20(to, contract_, amount, rights, false), hash);
        vm.stopPrank();
        unchecked {
            expectedDecreasedAmount = 0 - decreaseAmount;
        }
        assertEq(expectedDecreasedAmount, Helpers.calculateDecreasedAmount(address(registry), hash, decreaseAmount));
    }

    function testCalculateDecreasedAmountERC1155(address from, address to, address contract_, uint256 amount, uint256 tokenId, bytes32 rights, uint256 decreaseAmount)
        public
    {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC1155(to, contract_, tokenId, amount, rights, true);
        vm.stopPrank();
        uint256 expectedDecreasedAmount;
        unchecked {
            expectedDecreasedAmount = amount - decreaseAmount;
        }
        assertEq(expectedDecreasedAmount, Helpers.calculateDecreasedAmount(address(registry), hash, decreaseAmount));
        vm.startPrank(from);
        assertEq(registry.delegateERC1155(to, contract_, tokenId, amount, rights, false), hash);
        vm.stopPrank();
        unchecked {
            expectedDecreasedAmount = 0 - decreaseAmount;
        }
        assertEq(expectedDecreasedAmount, Helpers.calculateDecreasedAmount(address(registry), hash, decreaseAmount));
    }

    function testCalculateIncreasedAmountAll(address from, address to, bytes32 rights, uint256 increaseAmount) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateAll(to, rights, true);
        vm.stopPrank();
        uint256 expectedIncreasedAmount;
        unchecked {
            expectedIncreasedAmount = 0 + increaseAmount;
        }
        assertEq(expectedIncreasedAmount, Helpers.calculateIncreasedAmount(address(registry), hash, increaseAmount));
        vm.startPrank(from);
        assertEq(registry.delegateAll(to, rights, false), hash);
        vm.stopPrank();
        unchecked {
            expectedIncreasedAmount = 0 + increaseAmount;
        }
        assertEq(expectedIncreasedAmount, Helpers.calculateIncreasedAmount(address(registry), hash, increaseAmount));
    }

    function testCalculateIncreasedAmountContract(address from, address to, address contract_, bytes32 rights, uint256 increaseAmount) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateContract(to, contract_, rights, true);
        vm.stopPrank();
        uint256 expectedIncreasedAmount;
        unchecked {
            expectedIncreasedAmount = 0 + increaseAmount;
        }
        assertEq(expectedIncreasedAmount, Helpers.calculateIncreasedAmount(address(registry), hash, increaseAmount));
        vm.startPrank(from);
        assertEq(registry.delegateContract(to, contract_, rights, false), hash);
        vm.stopPrank();
        unchecked {
            expectedIncreasedAmount = 0 + increaseAmount;
        }
        assertEq(expectedIncreasedAmount, Helpers.calculateIncreasedAmount(address(registry), hash, increaseAmount));
    }

    function testCalculateIncreasedAmountERC721(address from, address to, address contract_, uint256 tokenId, bytes32 rights, uint256 increaseAmount) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC721(to, contract_, tokenId, rights, true);
        vm.stopPrank();
        uint256 expectedIncreasedAmount;
        unchecked {
            expectedIncreasedAmount = 0 + increaseAmount;
        }
        assertEq(expectedIncreasedAmount, Helpers.calculateIncreasedAmount(address(registry), hash, increaseAmount));
        vm.startPrank(from);
        assertEq(registry.delegateERC721(to, contract_, tokenId, rights, false), hash);
        vm.stopPrank();
        unchecked {
            expectedIncreasedAmount = 0 + increaseAmount;
        }
        assertEq(expectedIncreasedAmount, Helpers.calculateIncreasedAmount(address(registry), hash, increaseAmount));
    }

    function testCalculateIncreasedAmountERC20(address from, address to, address contract_, uint256 amount, bytes32 rights, uint256 increaseAmount) public {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC20(to, contract_, amount, rights, true);
        vm.stopPrank();
        uint256 expectedIncreasedAmount;
        unchecked {
            expectedIncreasedAmount = amount + increaseAmount;
        }
        assertEq(expectedIncreasedAmount, Helpers.calculateIncreasedAmount(address(registry), hash, increaseAmount));
        vm.startPrank(from);
        assertEq(registry.delegateERC20(to, contract_, amount, rights, false), hash);
        vm.stopPrank();
        unchecked {
            expectedIncreasedAmount = 0 + increaseAmount;
        }
        assertEq(expectedIncreasedAmount, Helpers.calculateIncreasedAmount(address(registry), hash, increaseAmount));
    }

    function testCalculateIncreasedAmountERC1155(address from, address to, address contract_, uint256 amount, uint256 tokenId, bytes32 rights, uint256 increaseAmount)
        public
    {
        vm.startPrank(from);
        bytes32 hash = registry.delegateERC1155(to, contract_, tokenId, amount, rights, true);
        vm.stopPrank();
        uint256 expectedIncreasedAmount;
        unchecked {
            expectedIncreasedAmount = amount + increaseAmount;
        }
        assertEq(expectedIncreasedAmount, Helpers.calculateIncreasedAmount(address(registry), hash, increaseAmount));
        vm.startPrank(from);
        assertEq(registry.delegateERC1155(to, contract_, tokenId, amount, rights, false), hash);
        vm.stopPrank();
        unchecked {
            expectedIncreasedAmount = 0 + increaseAmount;
        }
        assertEq(expectedIncreasedAmount, Helpers.calculateIncreasedAmount(address(registry), hash, increaseAmount));
    }

    function testNoRevertERC721FlashUnavailableAllRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 amount,
        bytes calldata data
    ) public {
        vm.startPrank(address(harness));
        registry.delegateERC721(delegateHolder, contract_, tokenId, "", true);
        vm.stopPrank();
        harness.revertERC721FlashUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: amount,
                data: data
            })
        );
    }

    function testNoRevertERC721FlashUnavailableFlashloanRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 amount,
        bytes calldata data
    ) public {
        vm.startPrank(address(harness));
        registry.delegateERC721(delegateHolder, contract_, tokenId, "flashloan", true);
        vm.stopPrank();
        harness.revertERC721FlashUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: amount,
                data: data
            })
        );
    }

    function testNoRevertERC721FlashUnavailableFlashloanRightsAndAllRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 amount,
        bytes calldata data
    ) public {
        vm.startPrank(address(harness));
        registry.delegateERC721(delegateHolder, contract_, tokenId, "", true);
        registry.delegateERC721(delegateHolder, contract_, tokenId, "flashloan", true);
        vm.stopPrank();
        harness.revertERC721FlashUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: amount,
                data: data
            })
        );
    }

    function testRevertERC721FlashUnavailableBadRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 amount,
        bytes32 rights,
        bytes calldata data
    ) public {
        vm.assume(rights != "" && rights != "flashloan");
        vm.startPrank(address(harness));
        registry.delegateERC721(delegateHolder, contract_, tokenId, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC721FlashUnavailable.selector);
        harness.revertERC721FlashUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: amount,
                data: data
            })
        );
    }

    function testRevertERC721FlashUnavailableBadDelegateHolder(
        address delegateHolder,
        address notDelegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 amount,
        bytes calldata data
    ) public {
        bytes32 rights;
        if (amount % 2 == 0) rights = "";
        else rights = "flashloan";
        vm.assume(delegateHolder != notDelegateHolder);
        vm.startPrank(address(harness));
        registry.delegateERC721(delegateHolder, contract_, tokenId, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC721FlashUnavailable.selector);
        harness.revertERC721FlashUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: notDelegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: amount,
                data: data
            })
        );
    }

    function testRevertERC721FlashUnavailableBadTokenId(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        uint256 badTokenId,
        address receiver,
        uint256 amount,
        bytes calldata data
    ) public {
        bytes32 rights;
        if (amount % 2 == 0) rights = "";
        else rights = "flashloan";
        vm.assume(tokenId != badTokenId);
        vm.startPrank(address(harness));
        registry.delegateERC721(delegateHolder, contract_, tokenId, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC721FlashUnavailable.selector);
        harness.revertERC721FlashUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: badTokenId,
                amount: amount,
                data: data
            })
        );
    }

    function testRevertERC721FlashUnavailableBadContract(
        address delegateHolder,
        address contract_,
        address badContract,
        uint256 tokenId,
        address receiver,
        uint256 amount,
        bytes calldata data
    ) public {
        bytes32 rights;
        if (amount % 2 == 0) rights = "";
        else rights = "flashloan";
        vm.assume(contract_ != badContract);
        vm.startPrank(address(harness));
        registry.delegateERC721(delegateHolder, contract_, tokenId, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC721FlashUnavailable.selector);
        harness.revertERC721FlashUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: badContract,
                tokenId: tokenId,
                amount: amount,
                data: data
            })
        );
    }

    function testRevertERC721FlashUnavailableBadType(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 amount,
        bytes32 rights,
        bytes calldata data
    ) public {
        vm.startPrank(address(harness));
        registry.delegateAll(delegateHolder, rights, true);
        registry.delegateContract(delegateHolder, contract_, rights, true);
        registry.delegateERC20(delegateHolder, contract_, amount, rights, true);
        registry.delegateERC1155(delegateHolder, contract_, tokenId, amount, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC721FlashUnavailable.selector);
        harness.revertERC721FlashUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: amount,
                data: data
            })
        );
    }

    function testRevertERC721FlashUnavailableNotFrom(
        address notFrom,
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 amount,
        bytes32 rights,
        bytes calldata data
    ) public {
        vm.assume(address(harness) != notFrom);
        vm.startPrank(address(notFrom));
        registry.delegateAll(delegateHolder, rights, true);
        registry.delegateERC721(delegateHolder, contract_, tokenId, rights, true);
        registry.delegateContract(delegateHolder, contract_, rights, true);
        registry.delegateERC20(delegateHolder, contract_, amount, rights, true);
        registry.delegateERC1155(delegateHolder, contract_, tokenId, amount, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC721FlashUnavailable.selector);
        harness.revertERC721FlashUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: amount,
                data: data
            })
        );
    }

    function testNoRevertERC20FlashAmountUnavailableAllRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes calldata data
    ) public {
        vm.assume(flashAmount <= delegateAmount);
        vm.startPrank(address(harness));
        registry.delegateERC20(delegateHolder, contract_, delegateAmount, "", true);
        vm.stopPrank();
        harness.revertERC20FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testNoRevertERC20FlashAmountUnavailableFlashloanRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes calldata data
    ) public {
        vm.assume(flashAmount <= delegateAmount);
        vm.startPrank(address(harness));
        registry.delegateERC20(delegateHolder, contract_, delegateAmount, "flashloan", true);
        vm.stopPrank();
        harness.revertERC20FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testNoRevertERC20FlashAmountUnavailableBothRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount1,
        uint256 delegateAmount2,
        uint256 flashAmount,
        bytes calldata data
    ) public {
        vm.assume(delegateAmount1 < type(uint128).max && delegateAmount2 < type(uint128).max);
        vm.assume(flashAmount <= delegateAmount1 + delegateAmount2);
        vm.startPrank(address(harness));
        registry.delegateERC20(delegateHolder, contract_, delegateAmount1, "", true);
        registry.delegateERC20(delegateHolder, contract_, delegateAmount2, "flashloan", true);
        vm.stopPrank();
        harness.revertERC20FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC20FlashAmountUnavailableAllRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes calldata data
    ) public {
        vm.assume(flashAmount > delegateAmount);
        vm.startPrank(address(harness));
        registry.delegateERC20(delegateHolder, contract_, delegateAmount, "", true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC20FlashAmountUnavailable.selector);
        harness.revertERC20FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC20FlashAmountUnavailableFlashloanRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes calldata data
    ) public {
        vm.assume(flashAmount > delegateAmount);
        vm.startPrank(address(harness));
        registry.delegateERC20(delegateHolder, contract_, delegateAmount, "flashloan", true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC20FlashAmountUnavailable.selector);
        harness.revertERC20FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC20FlashAmountUnavailableBothRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount1,
        uint256 delegateAmount2,
        uint256 flashAmount,
        bytes calldata data
    ) public {
        vm.assume(delegateAmount1 < type(uint128).max && delegateAmount2 < type(uint128).max);
        vm.assume(flashAmount > delegateAmount1 + delegateAmount2);
        vm.startPrank(address(harness));
        registry.delegateERC20(delegateHolder, contract_, delegateAmount1, "", true);
        registry.delegateERC20(delegateHolder, contract_, delegateAmount2, "flashloan", true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC20FlashAmountUnavailable.selector);
        harness.revertERC20FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC20FlashAmountUnavailableBadDelegateHolder(
        address delegateHolder,
        address badDelegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes32 rights,
        bytes calldata data
    ) public {
        vm.assume(flashAmount <= delegateAmount && flashAmount != 0);
        vm.assume(delegateHolder != badDelegateHolder);
        vm.startPrank(address(harness));
        registry.delegateERC20(delegateHolder, contract_, delegateAmount, "", true);
        registry.delegateERC20(delegateHolder, contract_, delegateAmount, "flashloan", true);
        registry.delegateERC20(delegateHolder, contract_, delegateAmount, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC20FlashAmountUnavailable.selector);
        harness.revertERC20FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: badDelegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC20FlashAmountUnavailableBadContract(
        address delegateHolder,
        address contract_,
        address badContract,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes32 rights,
        bytes calldata data
    ) public {
        vm.assume(flashAmount <= delegateAmount && flashAmount != 0);
        vm.assume(contract_ != badContract);
        vm.startPrank(address(harness));
        registry.delegateERC20(delegateHolder, contract_, delegateAmount, "", true);
        registry.delegateERC20(delegateHolder, contract_, delegateAmount, "flashloan", true);
        registry.delegateERC20(delegateHolder, contract_, delegateAmount, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC20FlashAmountUnavailable.selector);
        harness.revertERC20FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: badContract,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC20FlashAmountUnavailableBadType(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes32 rights,
        bytes calldata data
    ) public {
        vm.assume(flashAmount <= delegateAmount && flashAmount != 0);
        vm.startPrank(address(harness));
        registry.delegateAll(delegateHolder, rights, true);
        registry.delegateContract(delegateHolder, contract_, rights, true);
        registry.delegateERC721(delegateHolder, contract_, tokenId, rights, true);
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC20FlashAmountUnavailable.selector);
        harness.revertERC20FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC20FlashAmountUnavailableBadFrom(
        address badFrom,
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes32 rights,
        bytes calldata data
    ) public {
        vm.assume(flashAmount <= delegateAmount && flashAmount != 0);
        vm.assume(address(harness) != badFrom);
        vm.startPrank(address(badFrom));
        registry.delegateAll(delegateHolder, rights, true);
        registry.delegateContract(delegateHolder, contract_, rights, true);
        registry.delegateERC721(delegateHolder, contract_, tokenId, rights, true);
        registry.delegateERC20(delegateHolder, contract_, delegateAmount, rights, true);
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC20FlashAmountUnavailable.selector);
        harness.revertERC20FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testNoRevertERC1155FlashAmountUnavailableAllRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes calldata data
    ) public {
        vm.assume(flashAmount <= delegateAmount);
        vm.startPrank(address(harness));
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, "", true);
        vm.stopPrank();
        harness.revertERC1155FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testNoRevertERC1155FlashAmountUnavailableFlashloanRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes calldata data
    ) public {
        vm.assume(flashAmount <= delegateAmount);
        vm.startPrank(address(harness));
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, "flashloan", true);
        vm.stopPrank();
        harness.revertERC1155FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testNoRevertERC1155FlashAmountUnavailableBothRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount1,
        uint256 delegateAmount2,
        uint256 flashAmount,
        bytes calldata data
    ) public {
        vm.assume(delegateAmount1 < type(uint128).max && delegateAmount2 < type(uint128).max);
        vm.assume(flashAmount <= delegateAmount1 + delegateAmount2);
        vm.startPrank(address(harness));
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount1, "", true);
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount2, "flashloan", true);
        vm.stopPrank();
        harness.revertERC1155FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC1155FlashAmountUnavailableAllRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes calldata data
    ) public {
        vm.assume(flashAmount > delegateAmount);
        vm.startPrank(address(harness));
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, "", true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC1155FlashAmountUnavailable.selector);
        harness.revertERC1155FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC1155FlashAmountUnavailableFlashloanRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes calldata data
    ) public {
        vm.assume(flashAmount > delegateAmount);
        vm.startPrank(address(harness));
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, "flashloan", true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC1155FlashAmountUnavailable.selector);
        harness.revertERC1155FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC1155FlashAmountUnavailableBothRights(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount1,
        uint256 delegateAmount2,
        uint256 flashAmount,
        bytes calldata data
    ) public {
        vm.assume(delegateAmount1 < type(uint128).max && delegateAmount2 < type(uint128).max);
        vm.assume(flashAmount > delegateAmount1 + delegateAmount2);
        vm.startPrank(address(harness));
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount1, "", true);
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount2, "flashloan", true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC1155FlashAmountUnavailable.selector);
        harness.revertERC1155FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC1155FlashAmountUnavailableBadDelegateHolder(
        address delegateHolder,
        address badDelegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes32 rights,
        bytes calldata data
    ) public {
        vm.assume(flashAmount <= delegateAmount && flashAmount != 0);
        vm.assume(delegateHolder != badDelegateHolder);
        vm.startPrank(address(harness));
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, "", true);
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, "flashloan", true);
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC1155FlashAmountUnavailable.selector);
        harness.revertERC1155FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: badDelegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC1155FlashAmountUnavailableBadContract(
        address delegateHolder,
        address contract_,
        address badContract,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes32 rights,
        bytes calldata data
    ) public {
        vm.assume(flashAmount <= delegateAmount && flashAmount != 0);
        vm.assume(contract_ != badContract);
        vm.startPrank(address(harness));
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, "", true);
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, "flashloan", true);
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC1155FlashAmountUnavailable.selector);
        harness.revertERC1155FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: badContract,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC1155FlashAmountUnavailableBadTokenId(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        uint256 badTokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes32 rights,
        bytes calldata data
    ) public {
        vm.assume(flashAmount <= delegateAmount && flashAmount != 0);
        vm.assume(tokenId != badTokenId);
        vm.startPrank(address(harness));
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, "", true);
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, "flashloan", true);
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC1155FlashAmountUnavailable.selector);
        harness.revertERC1155FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: badTokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC1155FlashAmountUnavailableBadType(
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes32 rights,
        bytes calldata data
    ) public {
        vm.assume(flashAmount <= delegateAmount && flashAmount != 0);
        vm.startPrank(address(harness));
        registry.delegateAll(delegateHolder, rights, true);
        registry.delegateContract(delegateHolder, contract_, rights, true);
        registry.delegateERC721(delegateHolder, contract_, tokenId, rights, true);
        registry.delegateERC20(delegateHolder, contract_, delegateAmount, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC1155FlashAmountUnavailable.selector);
        harness.revertERC1155FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testRevertERC1155FlashAmountUnavailableBadFrom(
        address badFrom,
        address delegateHolder,
        address contract_,
        uint256 tokenId,
        address receiver,
        uint256 delegateAmount,
        uint256 flashAmount,
        bytes32 rights,
        bytes calldata data
    ) public {
        vm.assume(flashAmount <= delegateAmount && flashAmount != 0);
        vm.assume(address(harness) != badFrom);
        vm.startPrank(address(badFrom));
        registry.delegateAll(delegateHolder, rights, true);
        registry.delegateContract(delegateHolder, contract_, rights, true);
        registry.delegateERC721(delegateHolder, contract_, tokenId, rights, true);
        registry.delegateERC20(delegateHolder, contract_, delegateAmount, rights, true);
        registry.delegateERC1155(delegateHolder, contract_, tokenId, delegateAmount, rights, true);
        vm.stopPrank();
        vm.expectRevert(DelegateTokenErrors.ERC1155FlashAmountUnavailable.selector);
        harness.revertERC1155FlashAmountUnavailable(
            address(registry),
            DelegateTokenStructs.FlashInfo({
                receiver: receiver,
                delegateHolder: delegateHolder,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                tokenContract: contract_,
                tokenId: tokenId,
                amount: flashAmount,
                data: data
            })
        );
    }

    function testTransferERC721Delegation(address from, address to, bytes32 underlyingRights, address underlyingContract, uint256 underlyingTokenId) public {
        vm.assume(from != to);
        bytes32 registryHash = registry.delegateERC721(from, underlyingContract, underlyingTokenId, underlyingRights, true);
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC721,
            to: from,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: 0
        });
        _assertDelegationsCount(from, 1, address(this), 1);
        bytes32 newRegistryHash = registry.delegateERC721(to, underlyingContract, underlyingTokenId, underlyingRights, false);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.NONE,
            to: address(0),
            from: address(0),
            rights: "",
            contract_: address(0),
            tokenId: 0,
            amount: 0
        });
        _assertDelegationsCount(to, 0, address(this), 1);
        _assertDelegationsCount(from, 1, address(this), 1);
        Helpers.transferERC721({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: newRegistryHash,
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingTokenId: underlyingTokenId
        });
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.NONE,
            to: address(0),
            from: address(0),
            rights: 0,
            contract_: address(0),
            tokenId: 0,
            amount: 0
        });
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC721,
            to: to,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: 0
        });
        _assertDelegationsCount(to, 1, address(this), 1);
        _assertDelegationsCount(from, 0, address(this), 1);
    }

    function testRevertTransferERC721Delegation(address from, address to, bytes32 underlyingRights, address underlyingContract, uint256 underlyingTokenId) public {
        vm.assume(from != to);
        vm.startPrank(address(harness));
        bytes32 registryHash = registry.delegateERC721(from, underlyingContract, underlyingTokenId, underlyingRights, true);
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC721,
            to: from,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: 0
        });
        _assertDelegationsCount(from, 1, address(harness), 1);
        bytes32 newRegistryHash = registry.delegateERC721(to, underlyingContract, underlyingTokenId, underlyingRights, false);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.NONE,
            to: address(0),
            from: address(0),
            rights: "",
            contract_: address(0),
            tokenId: 0,
            amount: 0
        });
        _assertDelegationsCount(to, 0, address(harness), 1);
        _assertDelegationsCount(from, 1, address(harness), 1);
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC721({
            delegateRegistry: address(registry),
            registryHash: keccak256(abi.encode(registryHash)),
            from: from,
            newRegistryHash: newRegistryHash,
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingTokenId: underlyingTokenId
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC721({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: keccak256(abi.encode(newRegistryHash)),
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingTokenId: underlyingTokenId
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC721({
            delegateRegistry: address(registry),
            registryHash: keccak256(abi.encode(registryHash)),
            from: from,
            newRegistryHash: keccak256(abi.encode(newRegistryHash)),
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingTokenId: underlyingTokenId
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC721({
            delegateRegistry: address(registry),
            registryHash: newRegistryHash,
            from: from,
            newRegistryHash: registryHash,
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingTokenId: underlyingTokenId
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC721({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: to,
            newRegistryHash: newRegistryHash,
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingTokenId: underlyingTokenId
        });
        vm.stopPrank();
    }

    function testTransferERC721DelegationSymmetric(address from, bytes32 underlyingRights, address underlyingContract, uint256 underlyingTokenId) public {
        bytes32 registryHash = registry.delegateERC721(from, underlyingContract, underlyingTokenId, underlyingRights, true);
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC721,
            to: from,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: 0
        });
        _assertDelegationsCount(from, 1, address(this), 1);
        bytes32 newRegistryHash = registry.delegateERC721(from, underlyingContract, underlyingTokenId, underlyingRights, false);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.NONE,
            to: address(0),
            from: address(0),
            rights: "",
            contract_: address(0),
            tokenId: 0,
            amount: 0
        });
        _assertDelegationsCount(from, 0, address(this), 0);
        Helpers.transferERC721({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: newRegistryHash,
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingTokenId: underlyingTokenId
        });
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC721,
            to: from,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: 0
        });
        _assertDelegationsCount(from, 1, address(this), 1);
    }

    function testRevertTransferERC721DelegationSymmetric(address from, bytes32 underlyingRights, address underlyingContract, uint256 underlyingTokenId) public {
        vm.startPrank(address(harness));
        bytes32 registryHash = registry.delegateERC721(from, underlyingContract, underlyingTokenId, underlyingRights, true);
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC721,
            to: from,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: 0
        });
        _assertDelegationsCount(from, 1, address(harness), 1);
        bytes32 newRegistryHash = registry.delegateERC721(from, underlyingContract, underlyingTokenId, underlyingRights, false);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.NONE,
            to: address(0),
            from: address(0),
            rights: "",
            contract_: address(0),
            tokenId: 0,
            amount: 0
        });
        _assertDelegationsCount(from, 0, address(harness), 0);
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC721({
            delegateRegistry: address(registry),
            registryHash: keccak256(abi.encode(registryHash)),
            from: from,
            newRegistryHash: newRegistryHash,
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingTokenId: underlyingTokenId
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC721({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: keccak256(abi.encode(newRegistryHash)),
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingTokenId: underlyingTokenId
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC721({
            delegateRegistry: address(registry),
            registryHash: keccak256(abi.encode(registryHash)),
            from: from,
            newRegistryHash: keccak256(abi.encode(newRegistryHash)),
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingTokenId: underlyingTokenId
        });
        vm.stopPrank();
    }

    function testTransferERC20Delegation(
        address from,
        address to,
        bytes32 underlyingRights,
        address underlyingContract,
        uint256 fromStartingAmount,
        uint256 toStartingAmount,
        uint256 transferAmount
    ) public {
        vm.assume(from != to);
        bytes32 registryHash = registry.delegateERC20(from, underlyingContract, fromStartingAmount, underlyingRights, true);
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: from,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: fromStartingAmount
        });
        _assertDelegationsCount(from, 1, address(this), 1);
        bytes32 newRegistryHash = registry.delegateERC20(to, underlyingContract, toStartingAmount, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: to,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: toStartingAmount
        });
        _assertDelegationsCount(to, 1, address(this), 2);
        _assertDelegationsCount(from, 1, address(this), 2);
        Helpers.transferERC20({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: newRegistryHash,
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount
        });
        uint256 expectedFromAmount;
        uint256 expectedToAmount;
        unchecked {
            expectedFromAmount = fromStartingAmount - transferAmount;
            expectedToAmount = toStartingAmount + transferAmount;
        }
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: from,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: expectedFromAmount
        });
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: to,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: expectedToAmount
        });
        _assertDelegationsCount(to, 1, address(this), 2);
        _assertDelegationsCount(from, 1, address(this), 2);
    }

    function testRevertTransferERC20Delegation(
        address from,
        address to,
        bytes32 underlyingRights,
        address underlyingContract,
        uint256 fromStartingAmount,
        uint256 toStartingAmount,
        uint256 transferAmount
    ) public {
        vm.assume(from != to);
        vm.startPrank(address(harness));
        bytes32 registryHash = registry.delegateERC20(from, underlyingContract, fromStartingAmount, underlyingRights, true);
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: from,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: fromStartingAmount
        });
        _assertDelegationsCount(from, 1, address(harness), 1);
        bytes32 newRegistryHash = registry.delegateERC20(to, underlyingContract, toStartingAmount, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: to,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: toStartingAmount
        });
        _assertDelegationsCount(to, 1, address(harness), 2);
        _assertDelegationsCount(from, 1, address(harness), 2);
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC20({
            delegateRegistry: address(registry),
            registryHash: keccak256(abi.encode(registryHash)),
            from: from,
            newRegistryHash: newRegistryHash,
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC20({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: keccak256(abi.encode(newRegistryHash)),
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC20({
            delegateRegistry: address(registry),
            registryHash: keccak256(abi.encode(registryHash)),
            from: from,
            newRegistryHash: keccak256(abi.encode(newRegistryHash)),
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC20({
            delegateRegistry: address(registry),
            registryHash: newRegistryHash,
            from: from,
            newRegistryHash: registryHash,
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC20({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: to,
            newRegistryHash: newRegistryHash,
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount
        });
        vm.stopPrank();
    }

    function testTransferERC20DelegationSymmetric(address from, bytes32 underlyingRights, address underlyingContract, uint256 startingAmount, uint256 transferAmount)
        public
    {
        bytes32 registryHash = registry.delegateERC20(from, underlyingContract, startingAmount, underlyingRights, true);
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: from,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: startingAmount
        });
        _assertDelegationsCount(from, 1, address(this), 1);
        Helpers.transferERC20({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: registryHash,
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount
        });
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: from,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: startingAmount
        });
        _assertDelegationsCount(from, 1, address(this), 1);
    }

    function testRevertTransferERC20DelegationSymmetric(
        address from,
        bytes32 underlyingRights,
        address underlyingContract,
        uint256 startingAmount,
        uint256 transferAmount
    ) public {
        vm.startPrank(address(harness));
        bytes32 registryHash = registry.delegateERC20(from, underlyingContract, startingAmount, underlyingRights, true);
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: from,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: startingAmount
        });
        _assertDelegationsCount(from, 1, address(harness), 1);
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC20({
            delegateRegistry: address(registry),
            registryHash: keccak256(abi.encode(registryHash)),
            from: from,
            newRegistryHash: registryHash,
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC20({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: keccak256(abi.encode(registryHash)),
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC20({
            delegateRegistry: address(registry),
            registryHash: keccak256(abi.encode(registryHash)),
            from: from,
            newRegistryHash: keccak256(abi.encode(registryHash)),
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount
        });
        vm.stopPrank();
    }

    function testTransferERC1155Delegation(
        address from,
        address to,
        bytes32 underlyingRights,
        address underlyingContract,
        uint256 underlyingTokenId,
        uint256 fromStartingAmount,
        uint256 toStartingAmount,
        uint256 transferAmount
    ) public {
        vm.assume(from != to);
        bytes32 registryHash = registry.delegateERC1155(from, underlyingContract, underlyingTokenId, fromStartingAmount, underlyingRights, true);
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: from,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: fromStartingAmount
        });
        _assertDelegationsCount(from, 1, address(this), 1);
        bytes32 newRegistryHash = registry.delegateERC1155(to, underlyingContract, underlyingTokenId, toStartingAmount, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: to,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: toStartingAmount
        });
        _assertDelegationsCount(to, 1, address(this), 2);
        _assertDelegationsCount(from, 1, address(this), 2);
        Helpers.transferERC1155({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: newRegistryHash,
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount,
            underlyingTokenId: underlyingTokenId
        });
        uint256 expectedFromAmount;
        uint256 expectedToAmount;
        unchecked {
            expectedFromAmount = fromStartingAmount - transferAmount;
            expectedToAmount = toStartingAmount + transferAmount;
        }
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: from,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: expectedFromAmount
        });
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: to,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: expectedToAmount
        });
        _assertDelegationsCount(to, 1, address(this), 2);
        _assertDelegationsCount(from, 1, address(this), 2);
    }

    function testRevertTransferERC1155Delegation(
        address from,
        address to,
        bytes32 underlyingRights,
        address underlyingContract,
        uint256 underlyingTokenId,
        uint256 fromStartingAmount,
        uint256 toStartingAmount,
        uint256 transferAmount
    ) public {
        vm.assume(from != to);
        vm.startPrank(address(harness));
        bytes32 registryHash = registry.delegateERC1155(from, underlyingContract, underlyingTokenId, fromStartingAmount, underlyingRights, true);
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: from,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: fromStartingAmount
        });
        _assertDelegationsCount(from, 1, address(harness), 1);
        bytes32 newRegistryHash = registry.delegateERC1155(to, underlyingContract, underlyingTokenId, toStartingAmount, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: to,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: toStartingAmount
        });
        _assertDelegationsCount(to, 1, address(harness), 2);
        _assertDelegationsCount(from, 1, address(harness), 2);
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC1155({
            delegateRegistry: address(registry),
            registryHash: keccak256(abi.encode(registryHash)),
            from: from,
            newRegistryHash: newRegistryHash,
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount,
            underlyingTokenId: underlyingTokenId
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC1155({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: keccak256(abi.encode(newRegistryHash)),
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount,
            underlyingTokenId: underlyingTokenId
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC1155({
            delegateRegistry: address(registry),
            registryHash: keccak256(abi.encode(registryHash)),
            from: from,
            newRegistryHash: keccak256(abi.encode(newRegistryHash)),
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount,
            underlyingTokenId: underlyingTokenId
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC1155({
            delegateRegistry: address(registry),
            registryHash: newRegistryHash,
            from: from,
            newRegistryHash: registryHash,
            to: to,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount,
            underlyingTokenId: underlyingTokenId
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC1155({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: to,
            newRegistryHash: newRegistryHash,
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount,
            underlyingTokenId: underlyingTokenId
        });
        vm.stopPrank();
    }

    function testTransferERC1155DelegationSymmetric(
        address from,
        bytes32 underlyingRights,
        address underlyingContract,
        uint256 underlyingTokenId,
        uint256 startingAmount,
        uint256 transferAmount
    ) public {
        bytes32 registryHash = registry.delegateERC1155(from, underlyingContract, underlyingTokenId, startingAmount, underlyingRights, true);
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: from,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: startingAmount
        });
        _assertDelegationsCount(from, 1, address(this), 1);
        Helpers.transferERC1155({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: registryHash,
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount,
            underlyingTokenId: underlyingTokenId
        });
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: from,
            from: address(this),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: startingAmount
        });
        _assertDelegationsCount(from, 1, address(this), 1);
    }

    function testRevertTransferERC1155DelegationSymmetric(
        address from,
        bytes32 underlyingRights,
        address underlyingContract,
        uint256 startingAmount,
        uint256 transferAmount,
        uint256 underlyingTokenId
    ) public {
        vm.startPrank(address(harness));
        bytes32 registryHash = registry.delegateERC1155(from, underlyingContract, underlyingTokenId, startingAmount, underlyingRights, true);
        _assertDelegation({
            hash: registryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: from,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: startingAmount
        });
        _assertDelegationsCount(from, 1, address(harness), 1);
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC1155({
            delegateRegistry: address(registry),
            registryHash: keccak256(abi.encode(registryHash)),
            from: from,
            newRegistryHash: registryHash,
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount,
            underlyingTokenId: underlyingTokenId
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC1155({
            delegateRegistry: address(registry),
            registryHash: registryHash,
            from: from,
            newRegistryHash: keccak256(abi.encode(registryHash)),
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount,
            underlyingTokenId: underlyingTokenId
        });
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.transferERC1155({
            delegateRegistry: address(registry),
            registryHash: keccak256(abi.encode(registryHash)),
            from: from,
            newRegistryHash: keccak256(abi.encode(registryHash)),
            to: from,
            underlyingRights: underlyingRights,
            underlyingContract: underlyingContract,
            underlyingAmount: transferAmount,
            underlyingTokenId: underlyingTokenId
        });
        vm.stopPrank();
    }

    function testDelegateERC721(address delegateTokenHolder, bytes32 underlyingRights, address underlyingContract, uint256 underlyingTokenId) public {
        vm.startPrank(address(harness));
        bytes32 newRegistryHash = registry.delegateERC721(delegateTokenHolder, underlyingContract, underlyingTokenId, underlyingRights, false);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.NONE,
            to: address(0),
            from: address(0),
            rights: "",
            contract_: address(0),
            tokenId: 0,
            amount: 0
        });
        _assertDelegationsCount(delegateTokenHolder, 0, address(harness), 0);
        harness.delegateERC721(
            address(registry),
            newRegistryHash,
            DelegateTokenStructs.DelegateInfo({
                principalHolder: address(0),
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                delegateHolder: delegateTokenHolder,
                amount: 0,
                tokenContract: underlyingContract,
                tokenId: underlyingTokenId,
                rights: underlyingRights,
                expiry: 0
            })
        );
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC721,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: 0
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        vm.stopPrank();
    }

    function testRevertDelegateERC721(address delegateTokenHolder, bytes32 underlyingRights, address underlyingContract, uint256 underlyingTokenId) public {
        vm.startPrank(address(harness));
        bytes32 newRegistryHash = registry.delegateERC721(delegateTokenHolder, underlyingContract, underlyingTokenId, underlyingRights, false);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.NONE,
            to: address(0),
            from: address(0),
            rights: "",
            contract_: address(0),
            tokenId: 0,
            amount: 0
        });
        _assertDelegationsCount(delegateTokenHolder, 0, address(harness), 0);
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.delegateERC721(
            address(registry),
            keccak256(abi.encode(newRegistryHash)),
            DelegateTokenStructs.DelegateInfo({
                principalHolder: address(0),
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                delegateHolder: delegateTokenHolder,
                amount: 0,
                tokenContract: underlyingContract,
                tokenId: underlyingTokenId,
                rights: underlyingRights,
                expiry: 0
            })
        );
        vm.stopPrank();
    }

    function testDelegateERC20(address delegateTokenHolder, bytes32 underlyingRights, address underlyingContract, uint256 startingAmount, uint256 addAmount) public {
        vm.startPrank(address(harness));
        bytes32 newRegistryHash = registry.delegateERC20(delegateTokenHolder, underlyingContract, startingAmount, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: startingAmount
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        harness.delegateERC20(
            address(registry),
            newRegistryHash,
            DelegateTokenStructs.DelegateInfo({
                principalHolder: address(0),
                tokenType: IDelegateRegistry.DelegationType.ERC20,
                delegateHolder: delegateTokenHolder,
                amount: addAmount,
                tokenContract: underlyingContract,
                tokenId: 0,
                rights: underlyingRights,
                expiry: 0
            })
        );
        uint256 expectedAmount;
        unchecked {
            expectedAmount = startingAmount + addAmount;
        }
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: expectedAmount
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        vm.stopPrank();
    }

    function testRevertDelegateERC20(address delegateTokenHolder, bytes32 underlyingRights, address underlyingContract, uint256 startingAmount, uint256 addAmount)
        public
    {
        vm.startPrank(address(harness));
        bytes32 newRegistryHash = registry.delegateERC20(delegateTokenHolder, underlyingContract, startingAmount, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: startingAmount
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.delegateERC20(
            address(registry),
            keccak256(abi.encode(newRegistryHash)),
            DelegateTokenStructs.DelegateInfo({
                principalHolder: address(0),
                tokenType: IDelegateRegistry.DelegationType.ERC20,
                delegateHolder: delegateTokenHolder,
                amount: addAmount,
                tokenContract: underlyingContract,
                tokenId: 0,
                rights: underlyingRights,
                expiry: 0
            })
        );
        vm.stopPrank();
    }

    function testDelegateERC1155(
        address delegateTokenHolder,
        bytes32 underlyingRights,
        address underlyingContract,
        uint256 underlyingTokenId,
        uint256 startingAmount,
        uint256 addAmount
    ) public {
        vm.startPrank(address(harness));
        bytes32 newRegistryHash = registry.delegateERC1155(delegateTokenHolder, underlyingContract, underlyingTokenId, startingAmount, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: startingAmount
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        harness.delegateERC1155(
            address(registry),
            newRegistryHash,
            DelegateTokenStructs.DelegateInfo({
                principalHolder: address(0),
                tokenType: IDelegateRegistry.DelegationType.ERC1155,
                delegateHolder: delegateTokenHolder,
                amount: addAmount,
                tokenContract: underlyingContract,
                tokenId: underlyingTokenId,
                rights: underlyingRights,
                expiry: 0
            })
        );
        uint256 expectedAmount;
        unchecked {
            expectedAmount = startingAmount + addAmount;
        }
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: expectedAmount
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        vm.stopPrank();
    }

    function testRevertDelegateERC1155(
        address delegateTokenHolder,
        bytes32 underlyingRights,
        address underlyingContract,
        uint256 underlyingTokenId,
        uint256 startingAmount,
        uint256 addAmount
    ) public {
        vm.startPrank(address(harness));
        bytes32 newRegistryHash = registry.delegateERC1155(delegateTokenHolder, underlyingContract, underlyingTokenId, startingAmount, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: startingAmount
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.delegateERC1155(
            address(registry),
            keccak256(abi.encode(newRegistryHash)),
            DelegateTokenStructs.DelegateInfo({
                principalHolder: address(0),
                tokenType: IDelegateRegistry.DelegationType.ERC1155,
                delegateHolder: delegateTokenHolder,
                amount: addAmount,
                tokenContract: underlyingContract,
                tokenId: underlyingTokenId,
                rights: underlyingRights,
                expiry: 0
            })
        );
        vm.stopPrank();
    }

    function testRevokeERC721(address delegateTokenHolder, bytes32 underlyingRights, address underlyingContract, uint256 underlyingTokenId) public {
        vm.startPrank(address(harness));
        bytes32 newRegistryHash = registry.delegateERC721(delegateTokenHolder, underlyingContract, underlyingTokenId, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC721,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: 0
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        harness.revokeERC721(address(registry), newRegistryHash, delegateTokenHolder, underlyingContract, underlyingTokenId, underlyingRights);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.NONE,
            to: address(0),
            from: address(0),
            rights: 0,
            contract_: address(0),
            tokenId: 0,
            amount: 0
        });
        _assertDelegationsCount(delegateTokenHolder, 0, address(harness), 0);
        vm.stopPrank();
    }

    function testRevokeRevertERC721(address delegateTokenHolder, bytes32 underlyingRights, address underlyingContract, uint256 underlyingTokenId) public {
        vm.startPrank(address(harness));
        bytes32 newRegistryHash = registry.delegateERC721(delegateTokenHolder, underlyingContract, underlyingTokenId, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC721,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: 0
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.revokeERC721(address(registry), keccak256(abi.encode(newRegistryHash)), delegateTokenHolder, underlyingContract, underlyingTokenId, underlyingRights);
        vm.stopPrank();
    }

    function testRevokeERC20(address delegateTokenHolder, bytes32 underlyingRights, address underlyingContract, uint256 startingAmount, uint256 removeAmount) public {
        vm.startPrank(address(harness));
        bytes32 newRegistryHash = registry.delegateERC20(delegateTokenHolder, underlyingContract, startingAmount, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: startingAmount
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        harness.revokeERC20(address(registry), newRegistryHash, delegateTokenHolder, underlyingContract, removeAmount, underlyingRights);
        uint256 expectedAmount;
        unchecked {
            expectedAmount = startingAmount - removeAmount;
        }
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: expectedAmount
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        vm.stopPrank();
    }

    function testRevokeRevertERC20(address delegateTokenHolder, bytes32 underlyingRights, address underlyingContract, uint256 startingAmount, uint256 removeAmount)
        public
    {
        vm.startPrank(address(harness));
        bytes32 newRegistryHash = registry.delegateERC20(delegateTokenHolder, underlyingContract, startingAmount, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC20,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: 0,
            amount: startingAmount
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.revokeERC20(address(registry), keccak256(abi.encode(newRegistryHash)), delegateTokenHolder, underlyingContract, removeAmount, underlyingRights);
        vm.stopPrank();
    }

    function testRevokeERC1155(
        address delegateTokenHolder,
        bytes32 underlyingRights,
        address underlyingContract,
        uint256 underlyingTokenId,
        uint256 startingAmount,
        uint256 removeAmount
    ) public {
        vm.startPrank(address(harness));
        bytes32 newRegistryHash = registry.delegateERC1155(delegateTokenHolder, underlyingContract, underlyingTokenId, startingAmount, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: startingAmount
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        harness.revokeERC1155(address(registry), newRegistryHash, delegateTokenHolder, underlyingContract, underlyingTokenId, removeAmount, underlyingRights);
        uint256 expectedAmount;
        unchecked {
            expectedAmount = startingAmount - removeAmount;
        }
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: expectedAmount
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        vm.stopPrank();
    }

    function testRevokeRevertERC1155(
        address delegateTokenHolder,
        bytes32 underlyingRights,
        address underlyingContract,
        uint256 underlyingTokenId,
        uint256 startingAmount,
        uint256 removeAmount
    ) public {
        vm.startPrank(address(harness));
        bytes32 newRegistryHash = registry.delegateERC1155(delegateTokenHolder, underlyingContract, underlyingTokenId, startingAmount, underlyingRights, true);
        _assertDelegation({
            hash: newRegistryHash,
            tokenType: IDelegateRegistry.DelegationType.ERC1155,
            to: delegateTokenHolder,
            from: address(harness),
            rights: underlyingRights,
            contract_: underlyingContract,
            tokenId: underlyingTokenId,
            amount: startingAmount
        });
        _assertDelegationsCount(delegateTokenHolder, 1, address(harness), 1);
        vm.expectRevert(DelegateTokenErrors.HashMismatch.selector);
        harness.revokeERC1155(
            address(registry), keccak256(abi.encode(newRegistryHash)), delegateTokenHolder, underlyingContract, underlyingTokenId, removeAmount, underlyingRights
        );
        vm.stopPrank();
    }

    function _assertDelegation(
        bytes32 hash,
        IDelegateRegistry.DelegationType tokenType,
        address to,
        address from,
        bytes32 rights,
        address contract_,
        uint256 tokenId,
        uint256 amount
    ) internal {
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = hash;
        IDelegateRegistry.Delegation memory delegation = registry.getDelegationsFromHashes(hashes)[0];
        assertEq(uint256(tokenType), uint256(delegation.type_));
        assertEq(to, delegation.to);
        assertEq(from, delegation.from);
        assertEq(rights, delegation.rights);
        assertEq(contract_, delegation.contract_);
        assertEq(tokenId, delegation.tokenId);
        assertEq(amount, delegation.amount);
    }

    function _assertDelegationsCount(address incoming, uint256 incomingAmount, address outgoing, uint256 outgoingAmount) internal {
        assertEq(incomingAmount, registry.getIncomingDelegations(incoming).length);
        assertEq(outgoingAmount, registry.getOutgoingDelegations(outgoing).length);
    }
}
