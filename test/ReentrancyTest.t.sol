// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {FlashReentrancyTester} from "./utils/FlashReentrancy.t.sol";
import {DelegateTokenStructs, BaseLiquidDelegateTest, ComputeAddress} from "test/base/BaseLiquidDelegateTest.t.sol";

contract ReentrancyTest is Test, BaseLiquidDelegateTest {
    FlashReentrancyTester flash;

    function setUp() public {
        flash = new FlashReentrancyTester(address(dt));
    }

    function testFlashReentrancy() public {
        vm.assume(address(flash) != address(this));
        uint256 erc721TokenId = mockERC721.mintNext(address(flash));
        vm.expectRevert("ReentrancyGuard: reentrant call");
        flash.flashReentrancyTester(address(mockERC721), erc721TokenId);
        assertFalse(mockERC721.ownerOf(erc721TokenId) == address(this));
    }
}
