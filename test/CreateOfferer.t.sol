// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {BaseSeaportTest} from "./base/BaseSeaportTest.t.sol";
import {BaseLiquidDelegateTest} from "./base/BaseLiquidDelegateTest.t.sol";
import {SeaportHelpers, User} from "./utils/SeaportHelpers.t.sol";
import {IDelegateToken, Structs as IDelegateTokenStructs} from "src/interfaces/IDelegateToken.sol";
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

import {CreateOfferer, Enums as OffererEnums, Structs as OffererStructs} from "src/CreateOfferer.sol";
import {MockERC721} from "./mock/MockTokens.t.sol";
import {WETH} from "./mock/WETH.t.sol";

import {console2} from "forge-std/console2.sol";

contract CreateOffererTest is Test, BaseSeaportTest, BaseLiquidDelegateTest, SeaportHelpers {
    CreateOfferer createOfferer;
    MockERC721 token;
    WETH weth;
    uint256 startGas;

    function setUp() public {
        OffererStructs.Parameters memory createOffererParameters =
            OffererStructs.Parameters({seaport: address(seaport), delegateToken: address(dt), principalToken: address(principal)});
        createOfferer = new CreateOfferer(createOffererParameters);
        token = new MockERC721(0);
        weth = new WETH();
    }

    function testWrapOrderV2FilledByBuyer() public {
        // Setup buyer and sell, and approve conduit for token for seller
        User memory seller = makeUser("seller");
        vm.label(seller.addr, "seller");
        User memory buyer = makeUser("buyer");
        vm.label(buyer.addr, "buyer");
        vm.prank(seller.addr);
        token.setApprovalForAll(address(conduit), true);

        // Define 721 order info and mint to seller, and deal expected eth to buyer
        OffererStructs.ERC721Order memory erc721Order = OffererStructs.ERC721Order({
            tokenId: 42,
            info: OffererStructs.Order({
                rights: "",
                tokenContract: address(token),
                expiryLength: 30 days,
                expiryType: OffererEnums.ExpiryType.relative,
                signerSalt: 9,
                targetToken: OffererEnums.TargetToken.principal
            })
        });
        OffererStructs.Receivers memory receivers = OffererStructs.Receivers({principal: seller.addr, delegate: buyer.addr});
        uint256 expectedETH = 0.3 ether;
        vm.deal(buyer.addr, expectedETH);
        token.mint(seller.addr, erc721Order.tokenId);

        // Create order hash and id
        (uint256 createOrderHash, uint256 delegateId) = createOfferer.calculateERC721OrderHashAndId(seller.addr, address(conduit), erc721Order);

        // Build Order
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        orders[0] = _createSellerSignedOrder(seller, createOrderHash, erc721Order, expectedETH);
        orders[1] = _createContractOrder(receivers, createOrderHash, erc721Order);
        orders[2] = _createBuyerFillOrder(buyer, expectedETH);

        // ============== Set Fulfillments ===============
        // Fulfillments tells Seaport how to match the different order components to ensure
        // everyone's conditions are satisfied.
        Fulfillment[] memory fulfillments = new Fulfillment[](3);
        // Seller NFT => WrapReceipt, black line, order 0 offer item 0 matches with order 1 consideration item 0
        fulfillments[0] = _constructFulfillment(0, 0, 1, 0);
        // Wrap Receipt => Seller, red line, order 1 offer item 0 matches with order 0 consideration item 1
        fulfillments[1] = _constructFulfillment(1, 0, 0, 1);
        // Buyer ETH => Seller, blue line, order 2 offer item 0 matches with order 0 consideration item 0
        // offer: (2, 0); consideration: (0, 0); (orderIndex, itemIndex)
        fulfillments[2] = _constructFulfillment(2, 0, 0, 0);

        // Match orders
        vm.startPrank(buyer.addr);
        _trackMatchOrderGasBefore();
        seaport.matchAdvancedOrders{value: expectedETH}(orders, new CriteriaResolver[](0), fulfillments, buyer.addr);
        _trackMatchOrderGasAfter();
        vm.stopPrank();

        // Check
        assertEq(seller.addr.balance, expectedETH);
        IDelegateTokenStructs.DelegateInfo memory delegateInfo = dt.getDelegateInfo(delegateId);
        assertEq(dt.ownerOf(delegateId), buyer.addr);
        assertEq(principal.ownerOf(delegateId), seller.addr);
        assertEq(delegateInfo.expiry, block.timestamp + erc721Order.info.expiryLength);
    }

    function testWrapOrderV2FilledBySeller() public {
        // Setup buyer and sell, and approve conduit for token for seller
        User memory seller = makeUser("seller");
        vm.label(seller.addr, "seller");
        User memory buyer = makeUser("buyer");
        vm.label(buyer.addr, "buyer");

        vm.prank(seller.addr);
        token.setApprovalForAll(address(conduit), true);
        vm.prank(buyer.addr);
        weth.approve(address(conduit), type(uint256).max);

        // Define 721 order info and mint token seller, and mint expected weth to buyer
        OffererStructs.ERC721Order memory erc721Order = OffererStructs.ERC721Order({
            tokenId: 34,
            info: OffererStructs.Order({
                rights: "",
                tokenContract: address(token),
                expiryLength: block.timestamp + 40 days,
                expiryType: OffererEnums.ExpiryType.relative,
                signerSalt: 9,
                targetToken: OffererEnums.TargetToken.delegate
            })
        });
        OffererStructs.Receivers memory receivers = OffererStructs.Receivers({principal: seller.addr, delegate: buyer.addr});
        uint256 expectedETH = 0.22 ether;
        weth.mint(buyer.addr, expectedETH);
        token.mint(seller.addr, erc721Order.tokenId);

        // Create order hash
        (uint256 createOrderHash, uint256 delegateId) = createOfferer.calculateERC721OrderHashAndId(buyer.addr, address(conduit), erc721Order);

        // Build Order
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        orders[0] = _createBuyerSignedOrder(buyer, createOrderHash, expectedETH);
        orders[1] = _createContractOrder(receivers, createOrderHash, erc721Order);
        orders[2] = _createSellerFillOrder(seller, erc721Order, expectedETH);

        // ============== Set Fulfillments ===============
        // Fulfillments tells Seaport how to match the different order components to ensure
        // everyone's conditions are satisfied.
        Fulfillment[] memory fulfillments = new Fulfillment[](3);
        // Seller NFT => Liquid Delegate V2
        fulfillments[0] = _constructFulfillment(2, 0, 1, 0);
        // Wrap Receipt => Buyer
        fulfillments[1] = _constructFulfillment(1, 0, 0, 0);
        // Buyer ETH => Seller
        fulfillments[2] = _constructFulfillment(0, 0, 2, 0);

        // Match orders
        vm.startPrank(seller.addr);
        _trackMatchOrderGasBefore();
        seaport.matchAdvancedOrders(orders, new CriteriaResolver[](0), fulfillments, seller.addr);
        _trackMatchOrderGasAfter();

        // Check
        assertEq(weth.balanceOf(seller.addr), expectedETH);
        IDelegateTokenStructs.DelegateInfo memory delegateInfo = dt.getDelegateInfo(delegateId);
        assertEq(dt.ownerOf(delegateId), buyer.addr);
        assertEq(principal.ownerOf(delegateId), seller.addr);
        assertEq(delegateInfo.expiry, block.timestamp + erc721Order.info.expiryLength);
    }

    function _trackMatchOrderGasBefore() internal {
        startGas = gasleft();
    }

    function _trackMatchOrderGasAfter() internal view {
        uint256 gasUsed = startGas - gasleft();
        console2.log("gas use by matchAdvancedOrder", gasUsed);
    }

    function _createSellerFillOrder(User memory user, OffererStructs.ERC721Order memory erc721Order, uint256 expectedETH) internal view returns (AdvancedOrder memory) {
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({itemType: ItemType.ERC721, token: address(token), identifierOrCriteria: erc721Order.tokenId, startAmount: 1, endAmount: 1});
        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC20,
            token: address(weth),
            identifierOrCriteria: 0,
            startAmount: expectedETH,
            endAmount: expectedETH,
            recipient: payable(user.addr)
        });
        OrderParameters memory orderParams = OrderParameters({
            offerer: user.addr,
            zone: address(0),
            offer: offer,
            consideration: consideration,
            orderType: OrderType.FULL_OPEN,
            startTime: 0,
            endTime: block.timestamp + 3 days,
            zoneHash: bytes32(0),
            salt: erc721Order.info.signerSalt,
            conduitKey: conduitKey,
            totalOriginalConsiderationItems: 1
        });
        return AdvancedOrder({parameters: orderParams, numerator: 1, denominator: 1, signature: "", extraData: ""});
    }

    function _createSellerSignedOrder(User memory user, uint256 createOrderHash, OffererStructs.ERC721Order memory erc721Order, uint256 expectedETH)
        internal
        view
        returns (AdvancedOrder memory)
    {
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({itemType: ItemType.ERC721, token: erc721Order.info.tokenContract, identifierOrCriteria: erc721Order.tokenId, startAmount: 1, endAmount: 1});
        ConsiderationItem[] memory consideration = new ConsiderationItem[](2);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.NATIVE,
            token: address(0),
            identifierOrCriteria: 0,
            startAmount: expectedETH,
            endAmount: expectedETH,
            recipient: payable(user.addr)
        });
        consideration[1] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: address(createOfferer),
            identifierOrCriteria: createOrderHash,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(user.addr)
        });
        OrderParameters memory orderParams = OrderParameters({
            offerer: user.addr,
            zone: address(0),
            offer: offer,
            consideration: consideration,
            orderType: OrderType.FULL_OPEN,
            startTime: 0,
            endTime: block.timestamp + 3 days,
            zoneHash: bytes32(0),
            salt: erc721Order.info.signerSalt,
            conduitKey: conduitKey,
            totalOriginalConsiderationItems: 2
        });
        return AdvancedOrder({parameters: orderParams, numerator: 1, denominator: 1, signature: signOrder(seaport, user, orderParams), extraData: ""});
    }

    function _createContractOrder(OffererStructs.Receivers memory receivers, uint256 createOrderHash, OffererStructs.ERC721Order memory erc721Order)
        internal
        view
        returns (AdvancedOrder memory)
    {
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({itemType: ItemType.ERC721, token: address(createOfferer), identifierOrCriteria: createOrderHash, startAmount: 1, endAmount: 1});
        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: erc721Order.info.tokenContract,
            identifierOrCriteria: erc721Order.tokenId,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(address(createOfferer))
        });
        OrderParameters memory orderParams = OrderParameters({
            offerer: address(createOfferer),
            zone: address(0),
            offer: offer,
            consideration: consideration,
            orderType: OrderType.CONTRACT,
            startTime: 0,
            endTime: block.timestamp + 3 days,
            zoneHash: bytes32(0),
            salt: 1,
            conduitKey: conduitKey,
            totalOriginalConsiderationItems: 1
        });
        return AdvancedOrder({
            parameters: orderParams,
            numerator: 1,
            denominator: 1,
            signature: "",
            extraData: abi.encode(
                OffererStructs.Context({
                    rights: erc721Order.info.rights,
                    signerSalt: erc721Order.info.signerSalt,
                    expiryLength: erc721Order.info.expiryLength,
                    expiryType: erc721Order.info.expiryType,
                    targetToken: erc721Order.info.targetToken,
                    receivers: receivers
                })
                )
        });
    }

    function _createBuyerFillOrder(User memory user, uint256 expectedETH) internal view returns (AdvancedOrder memory) {
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({itemType: ItemType.NATIVE, token: address(0), identifierOrCriteria: 0, startAmount: expectedETH, endAmount: expectedETH});
        ConsiderationItem[] memory consideration = new ConsiderationItem[](0);
        OrderParameters memory orderParams = OrderParameters({
            offerer: user.addr,
            zone: address(0),
            offer: offer,
            consideration: consideration,
            orderType: OrderType.FULL_OPEN,
            startTime: 0,
            endTime: block.timestamp + 3 days,
            zoneHash: bytes32(0),
            salt: 1,
            conduitKey: conduitKey,
            totalOriginalConsiderationItems: 0
        });
        return AdvancedOrder({parameters: orderParams, numerator: 1, denominator: 1, signature: bytes(""), extraData: ""});
    }

    function _createBuyerSignedOrder(User memory user, uint256 createOrderHash, uint256 expectedETH) internal view returns (AdvancedOrder memory) {
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({itemType: ItemType.ERC20, token: address(weth), identifierOrCriteria: 0, startAmount: expectedETH, endAmount: expectedETH});
        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: address(createOfferer),
            identifierOrCriteria: createOrderHash,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(user.addr)
        });
        OrderParameters memory orderParams = OrderParameters({
            offerer: user.addr,
            zone: address(0),
            offer: offer,
            consideration: consideration,
            orderType: OrderType.FULL_OPEN,
            startTime: 0,
            endTime: block.timestamp + 3 days,
            zoneHash: bytes32(0),
            salt: 1,
            conduitKey: conduitKey,
            totalOriginalConsiderationItems: 1
        });
        return AdvancedOrder({parameters: orderParams, numerator: 1, denominator: 1, signature: signOrder(seaport, user, orderParams), extraData: ""});
    }

    function _constructFulfillment(uint256 _offerOrderIndex, uint256 _offerItemIndex, uint256 _considerationOrderIndex, uint256 _considerationItemIndex)
        internal
        pure
        returns (Fulfillment memory)
    {
        FulfillmentComponent[] memory offerComponents = new FulfillmentComponent[](1);
        offerComponents[0] = FulfillmentComponent({orderIndex: _offerOrderIndex, itemIndex: _offerItemIndex});
        FulfillmentComponent[] memory considerationComponents = new FulfillmentComponent[](1);
        considerationComponents[0] = FulfillmentComponent({orderIndex: _considerationOrderIndex, itemIndex: _considerationItemIndex});
        return Fulfillment({offerComponents: offerComponents, considerationComponents: considerationComponents});
    }
}
