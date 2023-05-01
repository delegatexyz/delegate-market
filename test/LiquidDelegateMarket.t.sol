// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import {NFTFlashBorrower} from "../src/NFTFlashBorrower.sol";
import {DelegationRegistry} from "../src/DelegationRegistry.sol";
import {LiquidDelegate} from "../src/LiquidDelegate.sol";
import {LiquidDelegateMarket} from "../src/LiquidDelegateMarket.sol";

contract LiquidDelegateMarketTest is Test {
    string public constant baseURI = "test";
    uint96 public constant interval = 60;
    address payable public constant ZERO = payable(address(0x0));
    address payable public constant liquidDelegateOwner = payable(address(0x9));
    MockERC721 public nft;
    DelegationRegistry public registry;
    LiquidDelegate public rights;
    LiquidDelegateMarket public market;

    function setUp() public {
        registry = new DelegationRegistry();
        nft = new MockERC721("Test", "TEST");
        rights = new LiquidDelegate(address(registry), liquidDelegateOwner, baseURI);
        market = new LiquidDelegateMarket(address(rights));
        rights.setApprovalForAll(address(market), true);
        vm.label(address(market), "market");
        vm.label(address(registry), "registry");
        vm.label(address(nft), "nft");
        vm.label(address(rights), "rights");
        vm.label(address(this), "test");
    }

    receive() external payable {}

    function _create(address creator, uint256 tokenId, uint96 expiration, address payable referrer) internal returns (uint256 delegateId) {
        vm.startPrank(creator);
        nft.mint(creator, tokenId);
        nft.approve(address(rights), tokenId);
        // rights.create{value: rights.creationFee()}(address(nft), tokenId, expiration, referrer);
        rights.create(address(nft), tokenId, expiration, referrer);
        vm.stopPrank();
        return rights.nextLiquidDelegateId() - 1;
    }

    function testBidAndSell(address creator, address buyer, uint256 tokenId) public {
        vm.assume(creator != ZERO);
        vm.assume(buyer != ZERO);
        uint256 delegateId = _create(creator, tokenId, uint96(block.timestamp) + interval, ZERO);
        uint256 bidPrice = 0.25 ether;
        uint256 bidId = market.nextBidId();
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        market.bid{value: bidPrice}(delegateId);
        vm.startPrank(creator);
        rights.setApprovalForAll(address(market), true);
        market.sell(bidId);
    }

    function testBidAndCancel(address creator, uint256 tokenId) public {
        vm.assume(creator != ZERO);
        uint256 delegateId = _create(creator, tokenId, uint96(block.timestamp) + interval, ZERO);
        uint256 bidPrice = 0.25 ether;
        uint256 bidId = market.nextBidId();
        market.bid{value: bidPrice}(delegateId);
        market.cancelBid(bidId);
    }

    function testListAndBuy(address creator, address buyer, uint256 tokenId) public {
        vm.assume(creator != ZERO);
        vm.assume(buyer != ZERO);
        uint256 delegateId = _create(creator, tokenId, uint96(block.timestamp) + interval, ZERO);
        uint256 listPrice = 0.25 ether;
        uint256 listingId = market.nextListingId();
        vm.startPrank(creator);
        rights.setApprovalForAll(address(market), true);
        market.list(delegateId, listPrice);
        vm.stopPrank();
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        market.buy{value: listPrice}(listingId);
    }
}
