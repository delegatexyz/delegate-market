// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {BaseSeaportTest} from "./base/BaseSeaportTest.t.sol";
import {BaseLiquidDelegateTest} from "./base/BaseLiquidDelegateTest.t.sol";
import {SeaportHelpers, User} from "./utils/SeaportHelpers.t.sol";
import {IDelegateToken, Structs as IDelegateTokenStructs} from "src/interfaces/IDelegateToken.sol";
import {AdvancedOrder, OrderParameters, Fulfillment, CriteriaResolver, OfferItem, ConsiderationItem, FulfillmentComponent} from "seaport/contracts/lib/ConsiderationStructs.sol";
import {ItemType, OrderType} from "seaport/contracts/lib/ConsiderationEnums.sol";
import {SpentItem} from "seaport/contracts/interfaces/ContractOffererInterface.sol";

import {CreateOfferer, Enums as OffererEnums, Structs as OffererStructs} from "src/CreateOfferer.sol";
import {MockERC721} from "./mock/MockTokens.t.sol";
import {WETH} from "./mock/WETH.t.sol";

import {console2} from "forge-std/console2.sol";

contract CreateOffererTest is Test, BaseSeaportTest, BaseLiquidDelegateTest, SeaportHelpers {
    CreateOfferer createOfferer;
    WETH weth;
    uint256 startGas;
    User buyer;
    User seller;

    function setUp() public {
        createOfferer = new CreateOfferer(address(seaport), address(dt));
        weth = new WETH();
        // Setup buyer and seller
        seller = makeUser("seller");
        vm.label(seller.addr, "seller");
        buyer = makeUser("buyer");
        vm.label(buyer.addr, "buyer");
    }

    function test721OrderFilledByBuyer() public {
        // Approve conduit for token for seller
        vm.prank(seller.addr);
        mockERC721.setApprovalForAll(address(conduit), true);

        // Define 721 order info and mint to seller, and deal expected eth to buyer
        OffererStructs.ERC721Order memory erc721Order = OffererStructs.ERC721Order({
            tokenId: 42,
            info: OffererStructs.Order({
                rights: "",
                tokenContract: address(mockERC721),
                expiryLength: 30 days,
                expiryType: OffererEnums.ExpiryType.relative,
                signerSalt: 9,
                targetToken: OffererEnums.TargetToken.principal
            })
        });
        OfferItem memory offerItem =
            OfferItem({itemType: ItemType.ERC721, token: erc721Order.info.tokenContract, identifierOrCriteria: erc721Order.tokenId, startAmount: 1, endAmount: 1});
        ConsiderationItem memory considerationItem = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: erc721Order.info.tokenContract,
            identifierOrCriteria: erc721Order.tokenId,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(address(createOfferer))
        });
        bytes memory extraData = abi.encode(
            OffererStructs.Context({
                rights: erc721Order.info.rights,
                signerSalt: erc721Order.info.signerSalt,
                expiryLength: erc721Order.info.expiryLength,
                expiryType: erc721Order.info.expiryType,
                targetToken: erc721Order.info.targetToken
            })
        );
        uint256 expectedETH = 0.3 ether;
        vm.deal(buyer.addr, expectedETH);
        mockERC721.mint(seller.addr, erc721Order.tokenId);

        // Create order hash and id
        (uint256 createOrderHash, uint256 delegateId) = createOfferer.calculateERC721OrderHashAndId(seller.addr, address(conduit), erc721Order);

        // Build Order
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        orders[0] = _createSellerSignedOrder(seller, offerItem, createOrderHash, erc721Order.info.signerSalt, expectedETH);
        orders[1] = _createContractOrder(considerationItem, createOrderHash, extraData);
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
        assertTrue(mockERC721.ownerOf(erc721Order.tokenId) == address(dt));
        assertEq(seller.addr.balance, expectedETH);
        assertEq(buyer.addr.balance, 0);
        IDelegateTokenStructs.DelegateInfo memory delegateInfo = dt.getDelegateTokenInfo(delegateId);
        assertEq(dt.ownerOf(delegateId), buyer.addr);
        assertEq(principal.ownerOf(delegateId), seller.addr);
        assertEq(delegateInfo.expiry, block.timestamp + erc721Order.info.expiryLength);
    }

    function test721OfferFilledBySeller() public {
        // Approve conduit for token for seller
        vm.prank(seller.addr);
        mockERC721.setApprovalForAll(address(conduit), true);
        vm.prank(buyer.addr);
        weth.approve(address(conduit), type(uint256).max);

        // Define 721 order info and mint token seller, and mint expected weth to buyer
        OffererStructs.ERC721Order memory erc721Order = OffererStructs.ERC721Order({
            tokenId: 34,
            info: OffererStructs.Order({
                rights: "",
                tokenContract: address(mockERC721),
                expiryLength: block.timestamp + 40 days,
                expiryType: OffererEnums.ExpiryType.relative,
                signerSalt: 9,
                targetToken: OffererEnums.TargetToken.delegate
            })
        });
        OfferItem memory offerItem = OfferItem({itemType: ItemType.ERC721, token: address(mockERC721), identifierOrCriteria: erc721Order.tokenId, startAmount: 1, endAmount: 1});
        ConsiderationItem memory considerationItem = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: erc721Order.info.tokenContract,
            identifierOrCriteria: erc721Order.tokenId,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(address(createOfferer))
        });
        bytes memory extraData = abi.encode(
            OffererStructs.Context({
                rights: erc721Order.info.rights,
                signerSalt: erc721Order.info.signerSalt,
                expiryLength: erc721Order.info.expiryLength,
                expiryType: erc721Order.info.expiryType,
                targetToken: erc721Order.info.targetToken
            })
        );
        uint256 expectedETH = 0.22 ether;
        weth.mint(buyer.addr, expectedETH);
        mockERC721.mint(seller.addr, erc721Order.tokenId);

        // Create order hash
        (uint256 createOrderHash, uint256 delegateId) = createOfferer.calculateERC721OrderHashAndId(buyer.addr, address(conduit), erc721Order);

        // Build Order
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        orders[0] = _createBuyerSignedOrder(buyer, createOrderHash, expectedETH);
        orders[1] = _createContractOrder(considerationItem, createOrderHash, extraData);
        orders[2] = _createSellerFillOrder(seller, offerItem, erc721Order.info.signerSalt, expectedETH);

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
        assertTrue(mockERC721.ownerOf(erc721Order.tokenId) == address(dt));
        assertEq(weth.balanceOf(seller.addr), expectedETH);
        assertEq(buyer.addr.balance, 0);
        IDelegateTokenStructs.DelegateInfo memory delegateInfo = dt.getDelegateTokenInfo(delegateId);
        assertEq(dt.ownerOf(delegateId), buyer.addr);
        assertEq(principal.ownerOf(delegateId), seller.addr);
        assertEq(delegateInfo.expiry, block.timestamp + erc721Order.info.expiryLength);
    }

    function test20OrderFilledByBuyer() public {
        // Approve conduit for token for seller
        vm.prank(seller.addr);
        mockERC20.approve(address(conduit), type(uint256).max);

        // Define 20 order info and mint to seller, and deal expected eth to buyer
        OffererStructs.ERC20Order memory erc20Order = OffererStructs.ERC20Order({
            amount: 10 ** 18,
            info: OffererStructs.Order({
                rights: "",
                tokenContract: address(mockERC20),
                expiryLength: 30 days,
                expiryType: OffererEnums.ExpiryType.relative,
                signerSalt: 9,
                targetToken: OffererEnums.TargetToken.principal
            })
        });
        OfferItem memory offerItem =
            OfferItem({itemType: ItemType.ERC20, token: erc20Order.info.tokenContract, identifierOrCriteria: 0, startAmount: erc20Order.amount, endAmount: erc20Order.amount});
        ConsiderationItem memory considerationItem = ConsiderationItem({
            itemType: ItemType.ERC20,
            token: erc20Order.info.tokenContract,
            identifierOrCriteria: 0,
            startAmount: erc20Order.amount,
            endAmount: erc20Order.amount,
            recipient: payable(address(createOfferer))
        });
        bytes memory extraData = abi.encode(
            OffererStructs.Context({
                rights: erc20Order.info.rights,
                signerSalt: erc20Order.info.signerSalt,
                expiryLength: erc20Order.info.expiryLength,
                expiryType: erc20Order.info.expiryType,
                targetToken: erc20Order.info.targetToken
            })
        );
        uint256 expectedETH = 0.3 ether;
        vm.deal(buyer.addr, expectedETH);
        mockERC20.mint(seller.addr, erc20Order.amount);

        // Create order hash and id
        (uint256 createOrderHash, uint256 delegateId) = createOfferer.calculateERC20OrderHashAndId(seller.addr, address(conduit), erc20Order);

        // Build Order
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        orders[0] = _createSellerSignedOrder(seller, offerItem, createOrderHash, erc20Order.info.signerSalt, expectedETH);
        orders[1] = _createContractOrder(considerationItem, createOrderHash, extraData);
        orders[2] = _createBuyerFillOrder(buyer, expectedETH);

        // ============== Set Fulfillments ===============
        // Fulfillments tells Seaport how to match the different order components to ensure
        // everyone's conditions are satisfied.
        Fulfillment[] memory fulfillments = new Fulfillment[](3);
        // Seller ERC20s => WrapReceipt, black line, order 0 offer item 0 matches with order 1 consideration item 0
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
        assertEq(mockERC20.balanceOf(address(dt)), erc20Order.amount);
        assertEq(seller.addr.balance, expectedETH);
        assertEq(buyer.addr.balance, 0);
        assertEq(mockERC20.balanceOf(seller.addr), 0);
        IDelegateTokenStructs.DelegateInfo memory delegateInfo = dt.getDelegateTokenInfo(delegateId);
        assertEq(dt.ownerOf(delegateId), buyer.addr);
        assertEq(principal.ownerOf(delegateId), seller.addr);
        assertEq(delegateInfo.expiry, block.timestamp + erc20Order.info.expiryLength);
    }

    function test20OfferFilledBySeller() public {
        // Approve conduit for token for seller
        vm.prank(seller.addr);
        mockERC20.approve(address(conduit), type(uint256).max);
        vm.prank(buyer.addr);
        weth.approve(address(conduit), type(uint256).max);

        // Define 20 order info and mint tokens seller, and mint expected weth to buyer
        OffererStructs.ERC20Order memory erc20Order = OffererStructs.ERC20Order({
            amount: 10 ** 18,
            info: OffererStructs.Order({
                rights: "",
                tokenContract: address(mockERC20),
                expiryLength: block.timestamp + 40 days,
                expiryType: OffererEnums.ExpiryType.relative,
                signerSalt: 9,
                targetToken: OffererEnums.TargetToken.delegate
            })
        });
        OfferItem memory offerItem =
            OfferItem({itemType: ItemType.ERC20, token: address(mockERC20), identifierOrCriteria: 0, startAmount: erc20Order.amount, endAmount: erc20Order.amount});
        ConsiderationItem memory considerationItem = ConsiderationItem({
            itemType: ItemType.ERC20,
            token: erc20Order.info.tokenContract,
            identifierOrCriteria: 0,
            startAmount: erc20Order.amount,
            endAmount: erc20Order.amount,
            recipient: payable(address(createOfferer))
        });
        bytes memory extraData = abi.encode(
            OffererStructs.Context({
                rights: erc20Order.info.rights,
                signerSalt: erc20Order.info.signerSalt,
                expiryLength: erc20Order.info.expiryLength,
                expiryType: erc20Order.info.expiryType,
                targetToken: erc20Order.info.targetToken
            })
        );
        uint256 expectedETH = 0.22 ether;
        weth.mint(buyer.addr, expectedETH);
        mockERC20.mint(seller.addr, erc20Order.amount);

        // Create order hash
        (uint256 createOrderHash, uint256 delegateId) = createOfferer.calculateERC20OrderHashAndId(buyer.addr, address(conduit), erc20Order);

        // Build Order
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        orders[0] = _createBuyerSignedOrder(buyer, createOrderHash, expectedETH);
        orders[1] = _createContractOrder(considerationItem, createOrderHash, extraData);
        orders[2] = _createSellerFillOrder(seller, offerItem, erc20Order.info.signerSalt, expectedETH);

        // ============== Set Fulfillments ===============
        // Fulfillments tells Seaport how to match the different order components to ensure
        // everyone's conditions are satisfied.
        Fulfillment[] memory fulfillments = new Fulfillment[](3);
        // Seller ERC20s => Liquid Delegate V2
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
        assertEq(mockERC20.balanceOf(address(dt)), erc20Order.amount);
        assertEq(weth.balanceOf(seller.addr), expectedETH);
        assertEq(buyer.addr.balance, 0);
        assertEq(mockERC20.balanceOf(seller.addr), 0);
        IDelegateTokenStructs.DelegateInfo memory delegateInfo = dt.getDelegateTokenInfo(delegateId);
        assertEq(dt.ownerOf(delegateId), buyer.addr);
        assertEq(principal.ownerOf(delegateId), seller.addr);
        assertEq(delegateInfo.expiry, block.timestamp + erc20Order.info.expiryLength);
    }

    function test1155OrderFilledByBuyer() public {
        // Approve conduit for token for seller
        vm.prank(seller.addr);
        mockERC1155.setApprovalForAll(address(conduit), true);

        // Define 1155 order info and mint to seller, and deal expected eth to buyer
        OffererStructs.ERC1155Order memory erc1155Order = OffererStructs.ERC1155Order({
            amount: 10 ** 18,
            tokenId: 42,
            info: OffererStructs.Order({
                rights: "",
                tokenContract: address(mockERC1155),
                expiryLength: 30 days,
                expiryType: OffererEnums.ExpiryType.relative,
                signerSalt: 9,
                targetToken: OffererEnums.TargetToken.principal
            })
        });
        OfferItem memory offerItem = OfferItem({
            itemType: ItemType.ERC1155,
            token: erc1155Order.info.tokenContract,
            identifierOrCriteria: erc1155Order.tokenId,
            startAmount: erc1155Order.amount,
            endAmount: erc1155Order.amount
        });
        ConsiderationItem memory considerationItem = ConsiderationItem({
            itemType: ItemType.ERC1155,
            token: erc1155Order.info.tokenContract,
            identifierOrCriteria: erc1155Order.tokenId,
            startAmount: erc1155Order.amount,
            endAmount: erc1155Order.amount,
            recipient: payable(address(createOfferer))
        });
        bytes memory extraData = abi.encode(
            OffererStructs.Context({
                rights: erc1155Order.info.rights,
                signerSalt: erc1155Order.info.signerSalt,
                expiryLength: erc1155Order.info.expiryLength,
                expiryType: erc1155Order.info.expiryType,
                targetToken: erc1155Order.info.targetToken
            })
        );
        uint256 expectedETH = 0.3 ether;
        vm.deal(buyer.addr, expectedETH);
        mockERC1155.mint(seller.addr, erc1155Order.tokenId, erc1155Order.amount, "");

        // Create order hash and id
        (uint256 createOrderHash, uint256 delegateId) = createOfferer.calculateERC1155OrderHashAndId(seller.addr, address(conduit), erc1155Order);

        // Build Order
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        orders[0] = _createSellerSignedOrder(seller, offerItem, createOrderHash, erc1155Order.info.signerSalt, expectedETH);
        orders[1] = _createContractOrder(considerationItem, createOrderHash, extraData);
        orders[2] = _createBuyerFillOrder(buyer, expectedETH);

        // ============== Set Fulfillments ===============
        // Fulfillments tells Seaport how to match the different order components to ensure
        // everyone's conditions are satisfied.
        Fulfillment[] memory fulfillments = new Fulfillment[](3);
        // Seller ERC1155s => WrapReceipt, black line, order 0 offer item 0 matches with order 1 consideration item 0
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
        assertEq(mockERC1155.balanceOf(address(dt), erc1155Order.tokenId), erc1155Order.amount);
        assertEq(seller.addr.balance, expectedETH);
        assertEq(buyer.addr.balance, 0);
        assertEq(mockERC1155.balanceOf(seller.addr, erc1155Order.tokenId), 0);
        IDelegateTokenStructs.DelegateInfo memory delegateInfo = dt.getDelegateTokenInfo(delegateId);
        assertEq(dt.ownerOf(delegateId), buyer.addr);
        assertEq(principal.ownerOf(delegateId), seller.addr);
        assertEq(delegateInfo.expiry, block.timestamp + erc1155Order.info.expiryLength);
    }

    function test1155OfferFilledBySeller() public {
        // Approve conduit for token for seller
        vm.prank(seller.addr);
        mockERC1155.setApprovalForAll(address(conduit), true);
        vm.prank(buyer.addr);
        weth.approve(address(conduit), type(uint256).max);

        // Define 1155 order info and mint tokens seller, and mint expected weth to buyer
        OffererStructs.ERC1155Order memory erc1155Order = OffererStructs.ERC1155Order({
            amount: 10 ** 18,
            tokenId: 42,
            info: OffererStructs.Order({
                rights: "",
                tokenContract: address(mockERC1155),
                expiryLength: block.timestamp + 40 days,
                expiryType: OffererEnums.ExpiryType.relative,
                signerSalt: 9,
                targetToken: OffererEnums.TargetToken.delegate
            })
        });
        OfferItem memory offerItem = OfferItem({
            itemType: ItemType.ERC1155,
            token: erc1155Order.info.tokenContract,
            identifierOrCriteria: erc1155Order.tokenId,
            startAmount: erc1155Order.amount,
            endAmount: erc1155Order.amount
        });
        ConsiderationItem memory considerationItem = ConsiderationItem({
            itemType: ItemType.ERC1155,
            token: erc1155Order.info.tokenContract,
            identifierOrCriteria: erc1155Order.tokenId,
            startAmount: erc1155Order.amount,
            endAmount: erc1155Order.amount,
            recipient: payable(address(createOfferer))
        });
        bytes memory extraData = abi.encode(
            OffererStructs.Context({
                rights: erc1155Order.info.rights,
                signerSalt: erc1155Order.info.signerSalt,
                expiryLength: erc1155Order.info.expiryLength,
                expiryType: erc1155Order.info.expiryType,
                targetToken: erc1155Order.info.targetToken
            })
        );
        uint256 expectedETH = 0.22 ether;
        weth.mint(buyer.addr, expectedETH);
        mockERC1155.mint(seller.addr, erc1155Order.tokenId, erc1155Order.amount, "");

        // Create order hash
        (uint256 createOrderHash, uint256 delegateId) = createOfferer.calculateERC1155OrderHashAndId(buyer.addr, address(conduit), erc1155Order);

        // Build Order
        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        orders[0] = _createBuyerSignedOrder(buyer, createOrderHash, expectedETH);
        orders[1] = _createContractOrder(considerationItem, createOrderHash, extraData);
        orders[2] = _createSellerFillOrder(seller, offerItem, erc1155Order.info.signerSalt, expectedETH);

        // ============== Set Fulfillments ===============
        // Fulfillments tells Seaport how to match the different order components to ensure
        // everyone's conditions are satisfied.
        Fulfillment[] memory fulfillments = new Fulfillment[](3);
        // Seller ERC1155s => Liquid Delegate V2
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
        assertEq(mockERC1155.balanceOf(address(dt), erc1155Order.tokenId), erc1155Order.amount);
        assertEq(weth.balanceOf(seller.addr), expectedETH);
        assertEq(buyer.addr.balance, 0);
        assertEq(mockERC1155.balanceOf(seller.addr, erc1155Order.tokenId), 0);
        IDelegateTokenStructs.DelegateInfo memory delegateInfo = dt.getDelegateTokenInfo(delegateId);
        assertEq(dt.ownerOf(delegateId), buyer.addr);
        assertEq(principal.ownerOf(delegateId), seller.addr);
        assertEq(delegateInfo.expiry, block.timestamp + erc1155Order.info.expiryLength);
    }

    function _trackMatchOrderGasBefore() internal {
        startGas = gasleft();
    }

    function _trackMatchOrderGasAfter() internal view {
        uint256 gasUsed = startGas - gasleft();
        console2.log("gas use by matchAdvancedOrder", gasUsed);
    }

    function _createSellerFillOrder(User memory user, OfferItem memory offerItem, uint256 signerSalt, uint256 expectedETH) internal view returns (AdvancedOrder memory) {
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = offerItem;
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
            salt: signerSalt,
            conduitKey: conduitKey,
            totalOriginalConsiderationItems: 1
        });
        return AdvancedOrder({parameters: orderParams, numerator: 1, denominator: 1, signature: "", extraData: ""});
    }

    function _createSellerSignedOrder(User memory user, OfferItem memory offerItem, uint256 createOrderHash, uint256 signerSalt, uint256 expectedETH)
        internal
        view
        returns (AdvancedOrder memory)
    {
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = offerItem;
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
            salt: signerSalt,
            conduitKey: conduitKey,
            totalOriginalConsiderationItems: 2
        });
        return AdvancedOrder({parameters: orderParams, numerator: 1, denominator: 1, signature: signOrder(seaport, user, orderParams), extraData: ""});
    }

    function _createContractOrder(ConsiderationItem memory considerationItem, uint256 createOrderHash, bytes memory extraData) internal view returns (AdvancedOrder memory) {
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({itemType: ItemType.ERC721, token: address(createOfferer), identifierOrCriteria: createOrderHash, startAmount: 1, endAmount: 1});
        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = considerationItem;
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
        SpentItem[] memory minimumReceived = new SpentItem[](1);
        minimumReceived[0] = SpentItem({itemType: offer[0].itemType, token: offer[0].token, identifier: offer[0].identifierOrCriteria, amount: offer[0].endAmount});
        SpentItem[] memory maximumSpent = new SpentItem[](1);
        maximumSpent[0] =
            SpentItem({itemType: consideration[0].itemType, token: consideration[0].token, identifier: consideration[0].identifierOrCriteria, amount: consideration[0].endAmount});
        createOfferer.previewOrder(address(seaport), address(0), minimumReceived, maximumSpent, extraData);
        return AdvancedOrder({parameters: orderParams, numerator: 1, denominator: 1, signature: "", extraData: extraData});
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
