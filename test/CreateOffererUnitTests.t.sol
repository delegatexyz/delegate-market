// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {BaseSeaportTest} from "./base/BaseSeaportTest.t.sol";
import {MockERC20, BaseLiquidDelegateTest} from "./base/BaseLiquidDelegateTest.t.sol";
import {IDelegateToken, Structs as IDelegateTokenStructs} from "src/interfaces/IDelegateToken.sol";
import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {AdvancedOrder, OrderParameters, Fulfillment, CriteriaResolver, OfferItem, ConsiderationItem, FulfillmentComponent} from "seaport/contracts/lib/ConsiderationStructs.sol";
import {ItemType, OrderType} from "seaport/contracts/lib/ConsiderationEnums.sol";
import {SpentItem, Schema} from "seaport/contracts/interfaces/ContractOffererInterface.sol";

import {CreateOfferer, Enums as OffererEnums, Structs as OffererStructs, Errors as OffererErrors} from "src/CreateOfferer.sol";

contract ERC20ApproveFalseReturn {
    function approve(address, uint256) external pure returns (bool) {
        return false;
    }
}

contract ERC20AllowanceInvariant is MockERC20 {
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        _approve(from, spender, 42);
        return true;
    }
}

contract CreateOffererUnitTests is Test, BaseSeaportTest, BaseLiquidDelegateTest {
    CreateOfferer createOfferer;
    ERC20ApproveFalseReturn erc20ApproveFalseReturn;
    ERC20AllowanceInvariant erc20AllowanceInvariant;

    function setUp() public {
        OffererStructs.Parameters memory createOffererParameters =
            OffererStructs.Parameters({seaport: address(seaport), delegateToken: address(dt), principalToken: address(principal)});
        createOfferer = new CreateOfferer(createOffererParameters);
        erc20ApproveFalseReturn = new ERC20ApproveFalseReturn();
        erc20AllowanceInvariant = new ERC20AllowanceInvariant();
    }

    function testTransferFromRevertFrom(address from, address targetTokenReceiver, uint256 createOrderHash) public {
        uint256 stageSlotContent = uint256(uint8(OffererEnums.Stage.transfer));
        stageSlotContent = uint256(uint8(OffererEnums.Lock.unlocked)) << 8 | stageSlotContent;
        vm.store(address(createOfferer), 0, bytes32(stageSlotContent));
        vm.assume(from != address(createOfferer));
        vm.expectRevert(abi.encodeWithSelector(OffererErrors.FromNotCreateOfferer.selector, from));
        createOfferer.transferFrom(from, targetTokenReceiver, createOrderHash);
    }

    function testTransferFromRevertFailedERC20ApproveCall(address targetTokenReceiver, address conduit) public {
        uint256 stageSlotContent = uint256(uint8(OffererEnums.Stage.transfer));
        stageSlotContent = uint256(uint8(OffererEnums.Lock.unlocked)) << 8 | stageSlotContent;
        vm.store(address(createOfferer), 0, bytes32(stageSlotContent));
        (uint256 createOrderHash,) = createOfferer.calculateERC20OrderHashAndId(
            targetTokenReceiver,
            conduit,
            OffererStructs.ERC20Order({
                amount: 1,
                info: OffererStructs.Order({
                    rights: 0,
                    expiryLength: 1,
                    signerSalt: 1,
                    tokenContract: address(42),
                    expiryType: OffererEnums.ExpiryType.absolute,
                    targetToken: OffererEnums.TargetToken.principal
                })
            })
        );
        vm.etch(address(42), address(erc20ApproveFalseReturn).code);
        vm.startPrank(conduit);
        vm.expectRevert(abi.encodeWithSelector(OffererErrors.ERC20ApproveFailed.selector, address(42)));
        createOfferer.transferFrom(address(createOfferer), targetTokenReceiver, createOrderHash);
        vm.stopPrank();
    }

    function testTransferFromRevertERC20AllowanceInvariant(address targetTokenReceiver, address conduit) public {
        vm.assume(conduit != address(0) && targetTokenReceiver != address(0));
        uint256 stageSlotContent = uint256(uint8(OffererEnums.Stage.transfer));
        stageSlotContent = uint256(uint8(OffererEnums.Lock.unlocked)) << 8 | stageSlotContent;
        vm.store(address(createOfferer), 0, bytes32(stageSlotContent));
        (uint256 createOrderHash,) = createOfferer.calculateERC20OrderHashAndId(
            targetTokenReceiver,
            conduit,
            OffererStructs.ERC20Order({
                amount: 1,
                info: OffererStructs.Order({
                    rights: 0,
                    expiryLength: 1,
                    signerSalt: 1,
                    tokenContract: address(42),
                    expiryType: OffererEnums.ExpiryType.absolute,
                    targetToken: OffererEnums.TargetToken.principal
                })
            })
        );
        vm.etch(address(42), address(erc20AllowanceInvariant).code);
        MockERC20(address(42)).mint(address(createOfferer), 1);
        vm.warp(0);
        vm.startPrank(conduit);
        vm.expectRevert(abi.encodeWithSelector(OffererErrors.ERC20AllowanceInvariant.selector, address(42)));
        createOfferer.transferFrom(address(createOfferer), targetTokenReceiver, createOrderHash);
        vm.stopPrank();
    }

    function testGetSeaportMetadata() public {
        (string memory metadataString, Schema[] memory schema) = createOfferer.getSeaportMetadata();
        assertEq("Delegate Market Contract Offerer", metadataString);
        assertEq(schema.length, 0);
    }

    function testGenerateOrderRevertIncorrectContextLength(address fulfiller, uint256 minimumReceivedLength, uint256 maximumSpentLength, uint256 contextSize) public {
        vm.assume(minimumReceivedLength > 0 && minimumReceivedLength < 100 && maximumSpentLength > 0 && maximumSpentLength < 100);
        vm.assume(contextSize != 160 && contextSize < 1000);
        bytes memory context = new bytes(contextSize);
        vm.startPrank(address(seaport));
        SpentItem[] memory minimumReceived = new SpentItem[](minimumReceivedLength);
        SpentItem[] memory maximumSpent = new SpentItem[](maximumSpentLength);
        vm.expectRevert(OffererErrors.InvalidContextLength.selector);
        createOfferer.generateOrder(fulfiller, minimumReceived, maximumSpent, context);
        vm.stopPrank();
    }

    function testPreviewOrderRevertIncorrectContextLength(address fulfiller, uint256 minimumReceivedLength, uint256 maximumSpentLength, uint256 contextSize) public {
        vm.assume(minimumReceivedLength > 0 && minimumReceivedLength < 100 && maximumSpentLength > 0 && maximumSpentLength < 100);
        vm.assume(contextSize != 160 && contextSize < 1000);
        bytes memory context = new bytes(contextSize);
        SpentItem[] memory minimumReceived = new SpentItem[](minimumReceivedLength);
        SpentItem[] memory maximumSpent = new SpentItem[](maximumSpentLength);
        vm.expectRevert(OffererErrors.InvalidContextLength.selector);
        createOfferer.previewOrder(address(seaport), fulfiller, minimumReceived, maximumSpent, context);
    }
}
