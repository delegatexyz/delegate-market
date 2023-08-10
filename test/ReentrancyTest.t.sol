// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {FlashReentrancyTester} from "./utils/FlashReentrancy.t.sol";
import {DelegateToken} from "src/DelegateToken.sol";
import {DelegateRegistry} from "delegate-registry/src/DelegateRegistry.sol";
import {ComputeAddress} from "script/ComputeAddress.s.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";
import {MockERC721} from "./mock/MockTokens.t.sol";
import {DelegateTokenStructs} from "src/libraries/DelegateTokenStructs.sol";

contract ReentrancyTest is Test {
    DelegateToken dt;
    MockERC721 erc721;
    FlashReentrancyTester flash;

    function setUp() public {
        DelegateRegistry registry = new DelegateRegistry();
        address deployer = address(100);

        vm.startPrank(deployer);
        DelegateTokenStructs.DelegateTokenParameters memory delegateTokenParameters = DelegateTokenStructs.DelegateTokenParameters({
            delegateRegistry: address(registry),
            principalToken: ComputeAddress.addressFrom(deployer, vm.getNonce(deployer) + 1),
            baseURI: "",
            initialMetadataOwner: deployer
        });
        dt = new DelegateToken(delegateTokenParameters);
        new PrincipalToken(
            address(dt)
        );
        vm.stopPrank();
        erc721 = new MockERC721(0);
        flash = new FlashReentrancyTester(address(dt));
    }

    function testFlashReentrancy() public {
        vm.assume(address(flash) != address(this));
        uint256 erc721TokenId = erc721.mintNext(address(flash));
        vm.expectRevert("ReentrancyGuard: reentrant call");
        flash.flashReentrancyTester(address(erc721), erc721TokenId);
        assertFalse(erc721.ownerOf(erc721TokenId) == address(this));
    }
}
