// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BaseSeaportTest} from "./base/BaseSeaportTest.sol";
import {BaseLiquidDelegateTest} from "./base/BaseLiquidDelegateTest.sol";
import {SeaportHelpers, User} from "./utils/SeaportHelpers.sol";

import {ExpiryType} from "src/interfaces/IDelegateToken.sol";
import {
    AdvancedOrder,
    OrderParameters,
    Fulfillment,
    CriteriaResolver,
    OfferItem,
    ConsiderationItem,
    FulfillmentComponent
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ItemType, OrderType} from "seaport-types/src/lib/ConsiderationEnums.sol";
import {Rights} from "src/interfaces/IDelegateToken.sol";

import {WrapOfferer, ReceiptFillerType} from "src/WrapOfferer.sol";
import {MockERC721} from "./mock/MockERC721.sol";
import {WETH} from "./mock/WETH.sol";

contract WrapOffererTest is Test, BaseSeaportTest, BaseLiquidDelegateTest, SeaportHelpers {
    WrapOfferer wofferer;
    MockERC721 token;
    WETH weth;

    User user1 = makeUser("user1");
    User user2 = makeUser("user2");
    User user3 = makeUser("user3");

    function setUp() public {
        wofferer = new WrapOfferer(address(seaport), address(ld));
        token = new MockERC721(0);
        weth = new WETH();
    }

    function testWrapOrderFilledByBuyer() public {
        // Test setup
        User memory seller = user1;
        vm.label(seller.addr, "seller");
        User memory buyer = user2;
        vm.label(buyer.addr, "buyer");

        vm.prank(seller.addr);
        token.setApprovalForAll(address(conduit), true);

        AdvancedOrder[] memory orders = new AdvancedOrder[](3);

        // ========= Create Sell Delegate Order ==========
        // 1. Define parameters
        ExpiryType expiryType = ExpiryType.RELATIVE;
        uint256 expiryValue = 30 days;
        uint256 expectedETH = 0.3 ether;
        vm.deal(buyer.addr, expectedETH);
        uint256 tokenId = 69;
        token.mint(seller.addr, tokenId);
        // 2. Create and sign wrap receipt
        bytes32 receiptHash = wofferer.getReceiptHash(address(0), seller.addr, address(token), tokenId, expiryType, expiryValue);
        // 3. Build Order
        orders[0] = _createSellerOrder(seller, tokenId, uint256(receiptHash), expectedETH, false);

        // ============== Create Wrap Order ==============
        address buyerAddr = buyer.addr;
        address sellerAddr = seller.addr;
        orders[1] = _createWrapContractOrder(
            tokenId, uint256(receiptHash), wofferer.encodeContext(ReceiptFillerType.DelegateOpen, expiryType, uint40(expiryValue), buyerAddr, sellerAddr)
        );

        // ========== Create Buy Delegate Order ==========
        orders[2] = _createBuyerOrder(buyer, 0, expectedETH, true);

        // ============== Set Fulfillments ===============
        // Fulfillments tells Seaport how to match the different order components to ensure
        // everyone's conditions are satisfied.
        Fulfillment[] memory fulfillments = new Fulfillment[](3);
        // Seller NFT => Liquid Delegate V2
        fulfillments[0] = _constructFulfillment(0, 0, 1, 0);
        // Wrap Receipt => Seller
        fulfillments[1] = _constructFulfillment(1, 0, 0, 1);
        // Buyer ETH => Seller
        // offer: (2, 0); consideration: (0, 0); (orderIndex, itemIndex)
        fulfillments[2] = _constructFulfillment(2, 0, 0, 0);

        // =============== Execute Orders ================
        vm.prank(buyerAddr);
        seaport.matchAdvancedOrders{value: expectedETH}(orders, new CriteriaResolver[](0), fulfillments, buyerAddr);

        // =========== Verify Correct Receipt ===========
        assertEq(seller.addr.balance, expectedETH);
        (, uint256 activeDelegateId, Rights memory rights) = ld.getRights(address(token), tokenId);
        assertEq(ld.ownerOf(activeDelegateId), buyerAddr);
        assertEq(principal.ownerOf(activeDelegateId), sellerAddr);
        assertEq(rights.expiry, block.timestamp + expiryValue);
    }

    function test_fuzzingContextEncodingReversible(
        uint8 rawFillerType,
        uint8 rawExpiryType,
        uint40 inExpiryValue,
        address inDelegateRecipient,
        address inPrincipalRecipient
    ) public {
        ReceiptFillerType inFillerType = ReceiptFillerType(bound(rawFillerType, uint8(type(ReceiptFillerType).min), uint8(type(ReceiptFillerType).max)));
        ExpiryType inExpiryType = ExpiryType(bound(rawExpiryType, uint8(type(ExpiryType).min), uint8(type(ExpiryType).max)));

        bytes memory encodedContext = wofferer.encodeContext(inFillerType, inExpiryType, inExpiryValue, inDelegateRecipient, inPrincipalRecipient);
        (ReceiptFillerType outFillerType, ExpiryType outExpiryType, uint40 outExpiryValue, address outDelegateRecipient, address outPrincipalRecipient) =
            wofferer.decodeContext(encodedContext);
        assertEq(uint8(inFillerType), uint8(outFillerType));
        assertEq(uint8(inExpiryType), uint8(outExpiryType));
        assertEq(inExpiryValue, outExpiryValue);
        assertEq(inDelegateRecipient, outDelegateRecipient);
        assertEq(inPrincipalRecipient, outPrincipalRecipient);
    }

    function testWrapOrderFilledBySeller() public {
        // Test setup
        User memory seller = user3;
        vm.label(seller.addr, "seller");
        User memory buyer = user1;
        vm.label(buyer.addr, "buyer");

        vm.prank(seller.addr);
        token.setApprovalForAll(address(conduit), true);

        AdvancedOrder[] memory orders = new AdvancedOrder[](3);

        // ============== Create Buy Order ===============
        // 1. Define parameters
        ExpiryType expiryType = ExpiryType.ABSOLUTE;
        uint256 expiryValue = block.timestamp + 40 days;
        uint256 expectedETH = 0.22 ether;
        weth.mint(buyer.addr, expectedETH);
        vm.prank(buyer.addr);
        weth.approve(address(conduit), type(uint256).max);
        uint256 tokenId = 34;
        token.mint(seller.addr, tokenId);

        // 2. Create and sign wrap receipt
        bytes32 receiptHash = wofferer.getReceiptHash(buyer.addr, address(0), address(token), tokenId, expiryType, expiryValue);

        // 3. Build Order
        orders[0] = _createBuyerOrder(buyer, uint256(receiptHash), expectedETH, false);

        // ============== Create Wrap Order ==============
        // stack2deep cache
        address buyerAddr = buyer.addr;
        address sellerAddr = seller.addr;
        orders[1] = _createWrapContractOrder(
            tokenId, uint256(receiptHash), wofferer.encodeContext(ReceiptFillerType.PrincipalOpen, expiryType, uint40(expiryValue), buyerAddr, sellerAddr)
        );

        // ========= Create Sell Delegate Order ==========
        orders[2] = _createSellerOrder(seller, tokenId, 0, expectedETH, true);

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

        // =============== Execute Orders ================
        vm.prank(seller.addr);
        seaport.matchAdvancedOrders(orders, new CriteriaResolver[](0), fulfillments, seller.addr);

        // =========== Verify Correct Receival ===========
        assertEq(weth.balanceOf(seller.addr), expectedETH);
        (, uint256 activeDelegateId, Rights memory rights) = ld.getRights(address(token), tokenId);
        assertEq(ld.ownerOf(activeDelegateId), buyer.addr);
        assertEq(principal.ownerOf(activeDelegateId), seller.addr);
        assertEq(rights.expiry, expiryValue);
    }

    function _createSellerOrder(User memory user, uint256 tokenId, uint256 receiptId, uint256 expectedETH, bool submittingAsCaller)
        internal
        view
        returns (AdvancedOrder memory)
    {
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({itemType: ItemType.ERC721, token: address(token), identifierOrCriteria: tokenId, startAmount: 1, endAmount: 1});
        uint256 totalConsiders = receiptId == 0 ? 1 : 2;
        ConsiderationItem[] memory consideration = new ConsiderationItem[](totalConsiders);
        consideration[0] = ConsiderationItem({
            itemType: submittingAsCaller ? ItemType.ERC20 : ItemType.NATIVE,
            token: submittingAsCaller ? address(weth) : address(0),
            identifierOrCriteria: 0,
            startAmount: expectedETH,
            endAmount: expectedETH,
            recipient: payable(user.addr)
        });
        if (receiptId != 0) {
            consideration[1] = ConsiderationItem({
                itemType: ItemType.ERC721,
                token: address(wofferer),
                identifierOrCriteria: receiptId,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(user.addr)
            });
        }
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
            totalOriginalConsiderationItems: totalConsiders
        });
        return AdvancedOrder({
            parameters: orderParams,
            numerator: 1,
            denominator: 1,
            // Can omit signature if submitting the order as the caller
            signature: submittingAsCaller ? bytes("") : _signOrder(user, orderParams),
            extraData: ""
        });
    }

    function _createWrapContractOrder(uint256 tokenId, uint256 receiptId, bytes memory context) internal view returns (AdvancedOrder memory) {
        // Wrap Offerer, offers gives a certain receipt as a commitment that certain parties
        // received principal / delegate tokens with certain terms
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({itemType: ItemType.ERC721, token: address(wofferer), identifierOrCriteria: receiptId, startAmount: 1, endAmount: 1});
        // Wrap Offerer expects the Liquid Delegate contract to receive the underlying NFT so that it
        // can execute the `createUnprotected` in ratify.
        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: address(token),
            identifierOrCriteria: tokenId,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(address(ld))
        });
        OrderParameters memory orderParams = OrderParameters({
            offerer: address(wofferer),
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
        return AdvancedOrder({parameters: orderParams, numerator: 1, denominator: 1, signature: "", extraData: context});
    }

    function _createBuyerOrder(User memory user, uint256 receiptId, uint256 expectedETH, bool submittingAsCaller)
        internal
        view
        returns (AdvancedOrder memory)
    {
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({
            itemType: submittingAsCaller ? ItemType.NATIVE : ItemType.ERC20,
            token: submittingAsCaller ? address(0) : address(weth),
            identifierOrCriteria: 0,
            startAmount: expectedETH,
            endAmount: expectedETH
        });
        uint256 totalConsiders = receiptId != 0 ? 1 : 0;
        ConsiderationItem[] memory consideration = new ConsiderationItem[](totalConsiders);
        if (receiptId != 0) {
            consideration[0] = ConsiderationItem({
                itemType: ItemType.ERC721,
                token: address(wofferer),
                identifierOrCriteria: receiptId,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(user.addr)
            });
        }
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
            totalOriginalConsiderationItems: totalConsiders
        });
        return AdvancedOrder({
            parameters: orderParams,
            numerator: 1,
            denominator: 1,
            signature: submittingAsCaller ? bytes("") : _signOrder(user, orderParams),
            extraData: ""
        });
    }

    function _signOrder(User memory _user, OrderParameters memory _params) internal view returns (bytes memory) {
        (, bytes32 seaportDomainSeparator,) = seaport.information();
        return signOrder(_user, seaportDomainSeparator, _params, seaport.getCounter(_user.addr));
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
