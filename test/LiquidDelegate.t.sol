// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import {NFTFlashBorrower} from "../src/NFTFlashBorrower.sol";
import {DelegationRegistry} from "../src/DelegationRegistry.sol";
import {LiquidDelegate} from "../src/LiquidDelegate.sol";

contract LiquidDelegateTest is Test {
    string constant public baseURI = "test";
    uint96 constant public interval = 60;
    address payable constant public ZERO = payable(address(0x0));
    address payable constant public liquidDelegateOwner = payable(address(0x9));
    MockERC721 public nft;
    DelegationRegistry public registry;
    LiquidDelegate public rights;

    function setUp() public {
        registry = new DelegationRegistry();
        nft = new MockERC721("Test", "TEST");
        rights = new LiquidDelegate(address(registry), liquidDelegateOwner, baseURI);
        vm.label(address(registry), "registry");
        vm.label(address(nft), "nft");
        vm.label(address(rights), "rights");
        vm.label(address(this), "test");
    }

    receive() external payable {}

    function _create(address creator, uint256 tokenId, uint96 expiration, address payable referrer) internal returns (uint256 rightsId) {
        vm.startPrank(creator);
        nft.mint(creator, tokenId);
        nft.approve(address(rights), tokenId);
        rights.create{value: rights.creationFee()}(address(nft), tokenId, expiration, referrer);
        vm.stopPrank();
        return rights.nextRightsId() - 1;
    }

    function testCreateOnly(address creator, uint256 tokenId) public {
        vm.assume(creator != ZERO);
        uint256 rightsId = _create(creator, tokenId, uint96(block.timestamp) + 60, ZERO);
        assertEq(rights.ownerOf(rightsId), creator);
        assertTrue(registry.checkDelegateForToken(creator, address(rights), address(nft), tokenId));
    }

    function testCreateAndPayReferrer(address creator, address payable referrer, uint256 tokenId) public {
        vm.assume(creator != ZERO);
        vm.assume(referrer != ZERO);
        vm.assume(creator != referrer);
        assumePayable(referrer);
        vm.prank(liquidDelegateOwner);
        rights.setCreationFee(0.1 ether);
        vm.deal(creator, 100 ether);
        uint256 startBalance = referrer.balance;
        uint256 rightsId = _create(creator, tokenId, uint96(block.timestamp) + 60, referrer);
        assertEq(referrer.balance - startBalance, rights.creationFee() / 2);
    }

    function testCreateAndTransfer(address creator, address rightsOwner, uint256 tokenId) public {
        vm.assume(creator != ZERO);
        vm.assume(rightsOwner != ZERO);
        vm.assume(creator != rightsOwner);
        uint256 rightsId = _create(creator, tokenId, uint96(block.timestamp) + 60, ZERO);
        vm.prank(creator);
        rights.transferFrom(creator, rightsOwner, rightsId);
        assertEq(rights.ownerOf(rightsId), rightsOwner);
        assertTrue(registry.checkDelegateForToken(rightsOwner, address(rights), address(nft), tokenId));
        assertFalse(registry.checkDelegateForToken(creator, address(rights), address(nft), tokenId));
    }

    function testCreateAndRedeem(address creator, address rightsOwner, uint256 tokenId) public {
        vm.assume(creator != ZERO);
        vm.assume(rightsOwner != ZERO);
        vm.assume(creator != rightsOwner);
        uint256 rightsId = _create(creator, tokenId, uint96(block.timestamp) + interval, ZERO);
        // Fail to redeem if you don't own it
        vm.expectRevert("INVALID_BURN");
        vm.prank(address(rightsOwner));
        rights.burn(rightsId);
        // Succeed at redeeming if you do
        vm.prank(creator);
        rights.burn(rightsId);
        // Check that token burned
        vm.expectRevert("NOT_MINTED");
        rights.ownerOf(rightsId);
        // Check that delegation reset
        assertFalse(registry.checkDelegateForToken(creator, address(rights), address(nft), tokenId));
    }

    function testCreateAndExpire(address creator, address rightsOwner, uint256 tokenId) public {
        vm.assume(creator != ZERO);
        vm.assume(rightsOwner != ZERO);
        vm.assume(creator != rightsOwner);
        uint256 rightsId = _create(creator, tokenId, uint96(block.timestamp) + interval, ZERO);
        // Fail to expire before expiration
        vm.startPrank(creator);
        rights.transferFrom(creator, rightsOwner, rightsId);
        vm.expectRevert("INVALID_BURN");
        rights.burn(rightsId);
        vm.stopPrank();
        // Succeed at expiring after expiration, let anyone expire
        vm.warp(uint96(block.timestamp) + interval);
        vm.prank(rightsOwner);
        rights.burn(rightsId);
        // Check that token burned
        vm.expectRevert("NOT_MINTED");
        rights.ownerOf(rightsId);
        // Check that delegation reset
        assertFalse(registry.checkDelegateForToken(creator, address(rights), address(nft), tokenId));
    }

    function testCreateAndFlashloan(address creator, uint256 tokenId) public {
        vm.assume(creator != ZERO);
        uint256 rightsId = _create(creator, tokenId, uint96(block.timestamp) + interval, ZERO);
        NFTFlashBorrower borrower = new NFTFlashBorrower(address(rights));
        vm.prank(creator);
        rights.flashLoan(rightsId, borrower, bytes(""));
    }

    function testCreateAndClaimFees(address creator, address fundsClaimer, uint256 tokenId) public {
        vm.assume(creator != ZERO);
        vm.assume(fundsClaimer != ZERO);
        vm.assume(creator != fundsClaimer);
        vm.assume(fundsClaimer != liquidDelegateOwner);
        assumePayable(fundsClaimer);
        uint256 startBalance = fundsClaimer.balance;
        vm.prank(liquidDelegateOwner);
        rights.setCreationFee(0.3 ether);
        vm.deal(creator, 100 ether);
        uint256 rightsId = _create(creator, tokenId, uint96(block.timestamp) + interval, ZERO);
        assertEq(address(rights).balance, rights.creationFee());
        vm.prank(liquidDelegateOwner);
        rights.claimFunds(payable(fundsClaimer));
        assertEq(address(rights).balance, 0);
        assertEq(fundsClaimer.balance - startBalance, rights.creationFee());
    }

    function testMetadata() public {
        uint tokenId = 5;
        uint256 rightsId = _create(address(0x1), tokenId, uint96(block.timestamp) + interval, ZERO);
        string memory metadata = rights.tokenURI(rightsId);
        console2.log(metadata);
    }
}
