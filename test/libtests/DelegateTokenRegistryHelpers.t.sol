// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IDelegateRegistry, BaseLiquidDelegateTest} from "test/base/BaseLiquidDelegateTest.t.sol";
import {DelegateTokenRegistryHelpers as Helpers} from "src/libraries/DelegateTokenRegistryHelpers.sol";

contract DelegateTokenRegistryHelpersTest is BaseLiquidDelegateTest {
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
}
