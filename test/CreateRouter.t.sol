// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {BaseSeaportTest} from "./base/BaseSeaportTest.t.sol";
import {BaseLiquidDelegateTest} from "./base/BaseLiquidDelegateTest.t.sol";
import {SeaportHelpers, User} from "./utils/SeaportHelpers.t.sol";
import {IDelegateToken} from "../src/interfaces/IDelegateToken.sol";

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {
    AdvancedOrder,
    OrderParameters,
    Fulfillment,
    CriteriaResolver,
    OfferItem,
    ConsiderationItem,
    FulfillmentComponent
} from "seaport/contracts/lib/ConsiderationStructs.sol";
import {ItemType, OrderType} from "seaport/contracts/lib/ConsiderationEnums.sol";
import {SpentItem} from "seaport/contracts/interfaces/ContractOffererInterface.sol";

import {CreateRouter, ExpiryType, OrderInfo} from "src/CreateRouter.sol";
import {MockERC721} from "./mock/MockTokens.t.sol";
import {WETH} from "./mock/WETH.t.sol";

import {console2} from "forge-std/console2.sol";

contract CreateRouterTest is Test, BaseSeaportTest, BaseLiquidDelegateTest, SeaportHelpers {
    CreateRouter createRouter;
    MockERC721 token;
    WETH weth;

    User user1 = makeUser("user1");
    User user2 = makeUser("user2");
    User user3 = makeUser("user3");

    uint96 internal constant SALT = 7;
    uint256 tokenId;

    function setUp() public {
        createRouter = new CreateRouter(address(seaport), address(dt));
        token = new MockERC721(0);
        weth = new WETH();
    }

    function testCreateRouterOrder() public {
        // Test setup
        User memory seller = user1;
        vm.label(seller.addr, "seller");
        User memory buyer = user2;
        vm.label(buyer.addr, "buyer");

        vm.prank(seller.addr);
        token.setApprovalForAll(address(conduit), true);

        AdvancedOrder[] memory orders = new AdvancedOrder[](2);

        // ========= Create Sell Delegate Order ==========
        // 1. Define parameters
        ExpiryType expiryType = ExpiryType.relative;
        uint256 expiryValue = 30 days;
        uint256 expectedETH = 0.3 ether;
        vm.deal(buyer.addr, expectedETH);
        tokenId = 69;
        token.mint(seller.addr, tokenId);

        // Store order info in memory
        OrderInfo memory createOrderInfo = OrderInfo(seller.addr, IDelegateRegistry.DelegationType.ERC721, expiryType, address(token), 1, tokenId, "", expiryValue, SALT);

        // 2. createRouter orders
        (orders[0], orders[1]) = _createRouterOrderERC721(seller, createOrderInfo);

        // 3. createFulfillments
        Fulfillment[] memory fulfillments = new Fulfillment[](2);
        {
            FulfillmentComponent[] memory underlyingOfferComponents = new FulfillmentComponent[](1);
            FulfillmentComponent[] memory underlyingConsiderationComponents = new FulfillmentComponent[](1);
            underlyingOfferComponents[0] = FulfillmentComponent(0, 0);
            underlyingConsiderationComponents[0] = FulfillmentComponent(1, 0);
            fulfillments[0] = Fulfillment(underlyingOfferComponents, underlyingConsiderationComponents);
            FulfillmentComponent[] memory tempOfferComponents = new FulfillmentComponent[](1);
            FulfillmentComponent[] memory tempConsiderationComponents = new FulfillmentComponent[](1);
            tempOfferComponents[0] = FulfillmentComponent(1, 0);
            tempConsiderationComponents[0] = FulfillmentComponent(0, 0);
            fulfillments[1] = Fulfillment(tempOfferComponents, tempConsiderationComponents);
        }

        // 4. Match the orders
        vm.startPrank(buyer.addr);
        uint256 gasTracker = gasleft();
        /// @dev this could be put into a new function in CreateRouter that loads the transient storage for you
        createRouter.storeOrderInfo(createOrderInfo);
        /// @dev fulfill rather than match seaport order could be used by adding a function that calls fulfillAdvancedOrders directly in CreateRouter, direct approvals
        /// for CreateRouter would be needed to do this since it would be the seaport "fulfiller"
        seaport.matchAdvancedOrders(orders, new CriteriaResolver[](0), fulfillments, buyer.addr);
        console2.log("matchAdvancedOrderGas", gasTracker - gasleft());
    }

    function _createRouterOrderERC721(User memory signer, OrderInfo memory createOrderInfo)
        internal
        view
        returns (AdvancedOrder memory depositorOrder, AdvancedOrder memory routerOrder)
    {
        uint256 createOrderHash = uint256(keccak256(abi.encode(createOrderInfo)));
        // Depositor order
        OfferItem[] memory depositorOffer = new OfferItem[](1);
        depositorOffer[0] = OfferItem({
            itemType: ItemType.ERC721,
            token: createOrderInfo.underlyingTokenContract,
            identifierOrCriteria: createOrderInfo.underlyingTokenId,
            startAmount: 1,
            endAmount: 1
        });
        ConsiderationItem[] memory depositorConsideration = new ConsiderationItem[](1);
        depositorConsideration[0] = ConsiderationItem({
            itemType: ItemType.ERC20,
            token: address(createRouter),
            identifierOrCriteria: 0,
            startAmount: createOrderHash,
            endAmount: createOrderHash,
            recipient: payable(signer.addr)
        });
        OrderParameters memory depositorOrderParams = OrderParameters({
            offerer: signer.addr,
            zone: address(0),
            offer: depositorOffer,
            consideration: depositorConsideration,
            orderType: OrderType.FULL_OPEN,
            startTime: 0,
            endTime: block.timestamp + 3 days,
            zoneHash: bytes32(0),
            salt: 1,
            conduitKey: conduitKey,
            totalOriginalConsiderationItems: 1
        });
        depositorOrder =
            AdvancedOrder({parameters: depositorOrderParams, numerator: 1, denominator: 1, signature: signOrder(seaport, signer, depositorOrderParams), extraData: ""});
        // CreateRouter order
        ConsiderationItem[] memory routerConsideration = new ConsiderationItem[](1);
        routerConsideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: createOrderInfo.underlyingTokenContract,
            identifierOrCriteria: createOrderInfo.underlyingTokenId,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(address(createRouter))
        });
        OfferItem[] memory routerOffer = new OfferItem[](1);
        routerOffer[0] =
            OfferItem({itemType: ItemType.ERC20, token: address(createRouter), identifierOrCriteria: 0, startAmount: createOrderHash, endAmount: createOrderHash});
        OrderParameters memory routerOrderParams = OrderParameters({
            offerer: address(createRouter),
            zone: address(0),
            offer: routerOffer,
            consideration: routerConsideration,
            orderType: OrderType.FULL_OPEN,
            startTime: 0,
            endTime: block.timestamp + 3 days,
            zoneHash: bytes32(0),
            salt: 1,
            conduitKey: conduitKey,
            totalOriginalConsiderationItems: 1
        });
        routerOrder = AdvancedOrder({parameters: routerOrderParams, numerator: 1, denominator: 1, signature: abi.encode(createOrderInfo), extraData: ""});
    }

    function testCreateRouterOrderWithDTSaleFilledByBuyer() public {
        // Test setup
        User memory seller = user1;
        vm.label(seller.addr, "seller");
        User memory buyer = user2;
        vm.label(buyer.addr, "buyer");

        vm.startPrank(seller.addr);
        token.setApprovalForAll(address(conduit), true);
        dt.setApprovalForAll(address(conduit), true);
        vm.stopPrank();

        AdvancedOrder[] memory orders = new AdvancedOrder[](2);

        // ========= Create Sell Delegate Order ==========
        // 1. Define parameters
        ExpiryType expiryType = ExpiryType.relative;
        uint256 expiryValue = 30 days;
        uint256 expectedETH = 0.3 ether;
        vm.deal(buyer.addr, expectedETH);
        tokenId = 69;
        token.mint(seller.addr, tokenId);

        // Store order info in memory
        OrderInfo memory createOrderInfo = OrderInfo(seller.addr, IDelegateRegistry.DelegationType.ERC721, expiryType, address(token), 1, tokenId, "", expiryValue, SALT);

        // 2. createRouter orders
        (orders[0], orders[1]) = _createRouterOrderERC721(seller, createOrderInfo);

        // 3. createFulfillments
        Fulfillment[] memory fulfillments = new Fulfillment[](2);
        {
            FulfillmentComponent[] memory underlyingOfferComponents = new FulfillmentComponent[](1);
            FulfillmentComponent[] memory underlyingConsiderationComponents = new FulfillmentComponent[](1);
            underlyingOfferComponents[0] = FulfillmentComponent(0, 0);
            underlyingConsiderationComponents[0] = FulfillmentComponent(1, 0);
            fulfillments[0] = Fulfillment(underlyingOfferComponents, underlyingConsiderationComponents);
            FulfillmentComponent[] memory tempOfferComponents = new FulfillmentComponent[](1);
            FulfillmentComponent[] memory tempConsiderationComponents = new FulfillmentComponent[](1);
            tempOfferComponents[0] = FulfillmentComponent(1, 0);
            tempConsiderationComponents[0] = FulfillmentComponent(0, 0);
            fulfillments[1] = Fulfillment(tempOfferComponents, tempConsiderationComponents);
        }

        // 4. Match the orders
        vm.startPrank(buyer.addr);
        uint256 gasTracker = gasleft();
        createRouter.storeOrderInfo(createOrderInfo);
        seaport.matchAdvancedOrders(orders, new CriteriaResolver[](0), fulfillments, buyer.addr);
        seaport.fulfillAdvancedOrder{value: expectedETH}(
            _createDelegateTokenSellOrderForETH(seller, createOrderInfo, expectedETH), new CriteriaResolver[](0), conduitKey, buyer.addr
        );
        console2.log("matchAdvancedOrderGas", gasTracker - gasleft());
    }

    function _createDelegateTokenSellOrderForETH(User memory signer, OrderInfo memory createOrderInfo, uint256 ethAmount)
        internal
        view
        returns (AdvancedOrder memory delegateTokenOrder)
    {
        uint256 delegateTokenId = uint256(keccak256(abi.encode(createRouter, keccak256(abi.encode(createOrderInfo)))));
        OfferItem[] memory delegateTokenOffer = new OfferItem[](1);
        delegateTokenOffer[0] = OfferItem({itemType: ItemType.ERC721, token: address(dt), identifierOrCriteria: delegateTokenId, startAmount: 1, endAmount: 1});
        ConsiderationItem[] memory delegateTokenConsideration = new ConsiderationItem[](1);
        delegateTokenConsideration[0] = ConsiderationItem({
            itemType: ItemType.NATIVE,
            token: address(0),
            identifierOrCriteria: 0,
            startAmount: ethAmount,
            endAmount: ethAmount,
            recipient: payable(signer.addr)
        });
        OrderParameters memory delegateTokenOrderParams = OrderParameters({
            offerer: signer.addr,
            zone: address(0),
            offer: delegateTokenOffer,
            consideration: delegateTokenConsideration,
            orderType: OrderType.FULL_OPEN,
            startTime: 0,
            endTime: block.timestamp + 3 days,
            zoneHash: bytes32(0),
            salt: 1,
            conduitKey: conduitKey,
            totalOriginalConsiderationItems: 1
        });
        delegateTokenOrder = AdvancedOrder({
            parameters: delegateTokenOrderParams,
            numerator: 1,
            denominator: 1,
            signature: signOrder(seaport, signer, delegateTokenOrderParams),
            extraData: ""
        });
    }
}
