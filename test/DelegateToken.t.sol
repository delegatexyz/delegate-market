// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {DelegateTokenErrors} from "src/libraries/DelegateTokenLib.sol";
import {CreateOffererEnums} from "src/libraries/CreateOffererLib.sol";

import {
    PrincipalToken, DelegateToken, MarketMetadata, DelegateTokenStructs, BaseLiquidDelegateTest, ComputeAddress, IDelegateRegistry
} from "test/base/BaseLiquidDelegateTest.t.sol";

contract DelegateTokenTest is Test, BaseLiquidDelegateTest {
    using Strings for uint256;

    // Test actors.
    uint256 internal constant TOTAL_USERS = 100;
    address[TOTAL_USERS] internal users;

    uint96 internal constant SALT = 7;

    function setUp() public {
        for (uint256 i; i < TOTAL_USERS; i++) {
            users[i] = makeAddr(string.concat("user", (i + 1).toString()));
        }
    }

    function testFuzzingCreate721(address tokenOwner, address dtTo, address notLdTo, address principalTo, uint256 tokenId, bool expiryTypeRelative, uint256 time) public {
        vm.assume(tokenOwner != address(0));
        vm.assume(principalTo != address(0));
        vm.assume(notLdTo != dtTo);
        vm.assume(tokenOwner != address(dt));
        vm.assume(dtTo != address(0));

        ( /* ExpiryType */ , uint256 expiry, /* expiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        mockERC721.mint(tokenOwner, tokenId);
        vm.startPrank(tokenOwner);
        mockERC721.setApprovalForAll(address(dt), true);
        uint256 delegateId =
            dt.create(DelegateTokenStructs.DelegateInfo(principalTo, IDelegateRegistry.DelegationType.ERC721, dtTo, 0, address(mockERC721), tokenId, "", expiry), SALT);
        vm.stopPrank();

        assertEq(dt.ownerOf(delegateId), dtTo);
        assertEq(principal.ownerOf(delegateId), principalTo);
        assertEq(mockERC721.ownerOf(tokenId), address(dt));

        assertTrue(registry.checkDelegateForERC721(dtTo, address(dt), address(mockERC721), tokenId, ""));
        assertFalse(registry.checkDelegateForERC721(notLdTo, address(dt), address(mockERC721), tokenId, ""));
    }

    function testFuzzingCreate20(address tokenOwner, address dtTo, address notLdTo, address principalTo, uint256 amount, bool expiryTypeRelative, uint256 time) public {
        vm.assume(tokenOwner != address(0));
        vm.assume(principalTo != address(0));
        vm.assume(notLdTo != dtTo);
        vm.assume(tokenOwner != address(dt));
        vm.assume(dtTo != address(0));
        vm.assume(amount != 0);

        ( /* ExpiryType */ , uint256 expiry, /* expiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        mockERC20.mint(tokenOwner, amount);
        vm.startPrank(tokenOwner);
        mockERC20.approve(address(dt), amount);
        uint256 delegateId =
            dt.create(DelegateTokenStructs.DelegateInfo(principalTo, IDelegateRegistry.DelegationType.ERC20, dtTo, amount, address(mockERC20), 0, "", expiry), SALT);
        vm.stopPrank();

        assertEq(dt.ownerOf(delegateId), dtTo);
        assertEq(principal.ownerOf(delegateId), principalTo);
        assertEq(mockERC20.balanceOf(tokenOwner), 0);
        assertEq(mockERC20.balanceOf(address(dt)), amount);

        assertEq(amount, registry.checkDelegateForERC20(dtTo, address(dt), address(mockERC20), ""));
        assertEq(0, registry.checkDelegateForERC20(notLdTo, address(dt), address(mockERC20), ""));
    }

    function testFuzzingCreate1155(address tokenOwner, address dtTo, address notLdTo, address principalTo, uint256 tokenId, uint256 amount, bool expiryTypeRelative, uint256 time)
        public
    {
        vm.assume(tokenOwner != address(0));
        vm.assume(principalTo != address(0));
        vm.assume(notLdTo != dtTo);
        vm.assume(tokenOwner != address(dt));
        vm.assume(dtTo != address(0));
        vm.assume(amount != 0);

        ( /* ExpiryType */ , uint256 expiry, /* expiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        vm.assume(tokenOwner.code.length == 0); //  Prevents reverts if tokenOwner is a contract and not a 1155 receiver
        mockERC1155.mint(tokenOwner, tokenId, amount, "");
        vm.startPrank(tokenOwner);
        mockERC1155.setApprovalForAll(address(dt), true);
        uint256 delegateId =
            dt.create(DelegateTokenStructs.DelegateInfo(principalTo, IDelegateRegistry.DelegationType.ERC1155, dtTo, amount, address(mockERC1155), tokenId, "", expiry), SALT);

        vm.stopPrank();

        assertEq(dt.ownerOf(delegateId), dtTo);
        assertEq(principal.ownerOf(delegateId), principalTo);
        assertEq(mockERC1155.balanceOf(tokenOwner, tokenId), 0);
        assertEq(mockERC1155.balanceOf(address(dt), tokenId), amount);

        assertEq(amount, registry.checkDelegateForERC1155(dtTo, address(dt), address(mockERC1155), tokenId, ""));
        assertEq(0, registry.checkDelegateForERC1155(notLdTo, address(dt), address(mockERC1155), tokenId, ""));
    }

    function testFuzzingTransfer721(address from, address to, uint256 underlyingTokenId, bool expiryTypeRelative, uint256 time) public {
        vm.assume(from != address(0));
        vm.assume(from != address(dt));

        ( /* ExpiryType */ , uint256 expiry, /* ExpiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);
        mockERC721.mint(address(from), underlyingTokenId);

        vm.startPrank(from);
        mockERC721.setApprovalForAll(address(dt), true);
        uint256 delegateId =
            dt.create(DelegateTokenStructs.DelegateInfo(from, IDelegateRegistry.DelegationType.ERC721, from, 0, address(mockERC721), underlyingTokenId, "", expiry), SALT);
        if (to == address(0)) vm.expectRevert(DelegateTokenErrors.ToIsZero.selector);
        dt.transferFrom(from, to, delegateId);
        if (to == address(0)) return;

        assertTrue(registry.checkDelegateForERC721(to, address(dt), address(mockERC721), underlyingTokenId, ""));

        if (from != to) {
            assertFalse(registry.checkDelegateForERC721(from, address(dt), address(mockERC721), underlyingTokenId, ""));
        }
    }

    function testFuzzingTransfer20(address from, address to, uint256 underlyingAmount, bool expiryTypeRelative, uint256 time) public {
        vm.assume(from != address(0));
        vm.assume(underlyingAmount != 0);

        ( /* ExpiryType */ , uint256 expiry, /* ExpiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);
        mockERC20.mint(address(from), underlyingAmount);

        vm.startPrank(from);
        mockERC20.approve(address(dt), underlyingAmount);
        uint256 delegateId =
            dt.create(DelegateTokenStructs.DelegateInfo(from, IDelegateRegistry.DelegationType.ERC20, from, underlyingAmount, address(mockERC20), 0, "", expiry), SALT);
        if (to == address(0)) vm.expectRevert(DelegateTokenErrors.ToIsZero.selector);
        dt.transferFrom(from, to, delegateId);
        if (to == address(0)) return;

        assertEq(underlyingAmount, registry.checkDelegateForERC20(to, address(dt), address(mockERC20), ""));

        if (from != to) {
            assertEq(0, registry.checkDelegateForERC20(from, address(dt), address(mockERC20), ""));
        }
    }

    function testFuzzingTransfer1155(address from, address to, uint256 underlyingAmount, uint256 underlyingTokenId, bool expiryTypeRelative, uint256 time) public {
        vm.assume(from != address(0));
        vm.assume(underlyingAmount != 0);

        ( /* ExpiryType */ , uint256 expiry, /* ExpiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        vm.assume(from.code.length == 0); //  Prevents reverts if from is a contract and not a 1155 receiver
        mockERC1155.mint(address(from), underlyingTokenId, underlyingAmount, "");

        vm.startPrank(from);
        mockERC1155.setApprovalForAll(address(dt), true);
        uint256 delegateId = dt.create(
            DelegateTokenStructs.DelegateInfo(from, IDelegateRegistry.DelegationType.ERC1155, from, underlyingAmount, address(mockERC1155), underlyingTokenId, "", expiry), SALT
        );
        if (to == address(0)) vm.expectRevert(DelegateTokenErrors.ToIsZero.selector);
        dt.transferFrom(from, to, delegateId);
        if (to == address(0)) return;

        assertEq(underlyingAmount, registry.checkDelegateForERC1155(to, address(dt), address(mockERC1155), underlyingTokenId, ""));

        if (from != to) {
            assertEq(0, registry.checkDelegateForERC1155(from, address(dt), address(mockERC1155), underlyingTokenId, ""));
        }
    }

    function testFuzzingWithdraw721Immediately(address from, uint256 underlyingTokenId, bool expiryTypeRelative, uint256 time) public {
        vm.assume(from != address(0));
        vm.assume(from != address(dt));

        ( /* ExpiryType */ , uint256 expiry, /* ExpiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);
        mockERC721.mint(address(from), underlyingTokenId);

        vm.startPrank(from);
        mockERC721.setApprovalForAll(address(dt), true);
        uint256 delegateId =
            dt.create(DelegateTokenStructs.DelegateInfo(from, IDelegateRegistry.DelegationType.ERC721, from, 0, address(mockERC721), underlyingTokenId, "", expiry), SALT);
        dt.withdraw(delegateId);

        vm.expectRevert(DelegateTokenErrors.DelegateTokenHolderZero.selector);
        dt.ownerOf(delegateId);
        vm.expectRevert();
        principal.ownerOf(delegateId);
        assertEq(mockERC721.ownerOf(underlyingTokenId), from);

        assertFalse(registry.checkDelegateForERC721(from, address(dt), address(mockERC721), underlyingTokenId, ""));
    }

    function testFuzzingWithdraw20Immediately(address from, uint256 underlyingAmount, bool expiryTypeRelative, uint256 time) public {
        vm.assume(from != address(0));
        vm.assume(from != address(dt));
        vm.assume(underlyingAmount != 0);

        ( /* ExpiryType */ , uint256 expiry, /* ExpiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);
        mockERC20.mint(address(from), underlyingAmount);

        vm.startPrank(from);
        mockERC20.approve(address(dt), underlyingAmount);
        uint256 delegateId =
            dt.create(DelegateTokenStructs.DelegateInfo(from, IDelegateRegistry.DelegationType.ERC20, from, underlyingAmount, address(mockERC20), 0, "", expiry), SALT);
        dt.withdraw(delegateId);

        vm.expectRevert(DelegateTokenErrors.DelegateTokenHolderZero.selector);
        dt.ownerOf(delegateId);
        vm.expectRevert();
        principal.ownerOf(delegateId);
        assertEq(mockERC20.balanceOf(from), underlyingAmount);
        assertEq(mockERC20.balanceOf(address(dt)), 0);

        assertEq(0, registry.checkDelegateForERC20(from, address(dt), address(mockERC20), ""));
    }

    function testFuzzingWithdraw1155Immediately(address from, uint256 underlyingAmount, uint256 underlyingTokenId, bool expiryTypeRelative, uint256 time) public {
        vm.assume(from != address(0));
        vm.assume(from != address(dt));
        vm.assume(underlyingAmount != 0);

        ( /* ExpiryType */ , uint256 expiry, /* ExpiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        vm.assume(from.code.length == 0); //  Prevents reverts if from is a contract and not a 1155 receiver
        mockERC1155.mint(address(from), underlyingTokenId, underlyingAmount, "");

        vm.startPrank(from);
        mockERC1155.setApprovalForAll(address(dt), true);
        uint256 delegateId = dt.create(
            DelegateTokenStructs.DelegateInfo(from, IDelegateRegistry.DelegationType.ERC1155, from, underlyingAmount, address(mockERC1155), underlyingTokenId, "", expiry), SALT
        );
        dt.withdraw(delegateId);

        vm.expectRevert(DelegateTokenErrors.DelegateTokenHolderZero.selector);
        dt.ownerOf(delegateId);
        vm.expectRevert();
        principal.ownerOf(delegateId);
        assertEq(mockERC1155.balanceOf(from, underlyingTokenId), underlyingAmount);
        assertEq(mockERC1155.balanceOf(address(dt), underlyingTokenId), 0);

        assertEq(0, registry.checkDelegateForERC1155(from, address(dt), address(mockERC1155), underlyingTokenId, ""));
    }

    function testFuzzingCannotCreateWithoutToken(address minter, uint256 amount, uint256 tokenId, bool expiryTypeRelative, uint256 time) public {
        vm.assume(minter != address(0));
        ( /* ExpiryType */ , uint256 expiry, /* expiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        vm.startPrank(minter);
        vm.expectRevert();
        dt.create(DelegateTokenStructs.DelegateInfo(minter, IDelegateRegistry.DelegationType.ERC721, minter, 0, address(mockERC721), tokenId, "", expiry), SALT);
        vm.expectRevert();
        dt.create(DelegateTokenStructs.DelegateInfo(minter, IDelegateRegistry.DelegationType.ERC20, minter, amount, address(mockERC20), 0, "", expiry), SALT);
        vm.expectRevert();
        dt.create(DelegateTokenStructs.DelegateInfo(minter, IDelegateRegistry.DelegationType.ERC1155, minter, amount, address(mockERC1155), tokenId, "", expiry), SALT);
        vm.stopPrank();
    }

    function testFuzzingMintRights(address tokenOwner, address dtTo, address notLdTo, address principalTo, uint256 tokenId, bool expiryTypeRelative, uint256 time) public {
        vm.assume(tokenOwner != address(0));
        vm.assume(dtTo != address(0));
        vm.assume(principalTo != address(0));
        vm.assume(notLdTo != dtTo);
        vm.assume(tokenOwner != address(dt));

        ( /* ExpiryType */ , uint256 expiry, /* expiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        mockERC721.mint(tokenOwner, tokenId);
        vm.startPrank(tokenOwner);
        mockERC721.setApprovalForAll(address(dt), true);
        uint256 delegateId =
            dt.create(DelegateTokenStructs.DelegateInfo(principalTo, IDelegateRegistry.DelegationType.ERC721, dtTo, 0, address(mockERC721), tokenId, "", expiry), SALT);

        vm.stopPrank();

        assertEq(dt.ownerOf(delegateId), dtTo);
        assertEq(principal.ownerOf(delegateId), principalTo);

        assertTrue(registry.checkDelegateForERC721(dtTo, address(dt), address(mockERC721), tokenId, ""));
        assertFalse(registry.checkDelegateForERC721(notLdTo, address(dt), address(mockERC721), tokenId, ""));
    }

    function testCannotMintWithExisting() public {
        address tokenOwner = makeAddr("tokenOwner");
        uint256 tokenId = mockERC721.mintNext(tokenOwner);
        vm.startPrank(tokenOwner);
        mockERC721.setApprovalForAll(address(dt), true);
        dt.create(
            DelegateTokenStructs.DelegateInfo(tokenOwner, IDelegateRegistry.DelegationType.ERC721, tokenOwner, 0, address(mockERC721), tokenId, "", block.timestamp + 10 days), SALT
        );
        vm.stopPrank();

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        dt.create(
            DelegateTokenStructs.DelegateInfo(attacker, IDelegateRegistry.DelegationType.ERC721, attacker, 0, address(mockERC721), tokenId, "", block.timestamp + 10 days), SALT
        );
    }

    function testFuzzingCannotCreateWithNonexistentContract(
        address minter,
        uint256 underlyingAmount,
        address tokenContract,
        uint256 tokenId,
        bool expiryTypeRelative,
        bytes32 rights,
        uint256 time
    ) public {
        vm.assume(tokenContract.code.length == 0);

        ( /* ExpiryType */ , uint256 expiry, /* expiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        vm.startPrank(minter);
        vm.expectRevert();
        dt.create(DelegateTokenStructs.DelegateInfo(minter, IDelegateRegistry.DelegationType.ERC721, minter, 1, tokenContract, tokenId, rights, expiry), SALT);
        vm.expectRevert();
        dt.create(DelegateTokenStructs.DelegateInfo(minter, IDelegateRegistry.DelegationType.ERC20, minter, underlyingAmount, tokenContract, tokenId, rights, expiry), SALT);
        vm.expectRevert();
        dt.create(DelegateTokenStructs.DelegateInfo(minter, IDelegateRegistry.DelegationType.ERC1155, minter, underlyingAmount, tokenContract, tokenId, rights, expiry), SALT);
        vm.stopPrank();
    }

    function testTokenURI() public {
        uint256 id = 9827;
        address user = makeAddr("user");
        mockERC721.mint(address(user), id);
        vm.startPrank(user);
        mockERC721.setApprovalForAll(address(dt), true);
        uint256 delegateId =
            dt.create(DelegateTokenStructs.DelegateInfo(user, IDelegateRegistry.DelegationType.ERC721, user, 0, address(mockERC721), id, "", block.timestamp + 10 seconds), SALT);
        vm.stopPrank();
        vm.prank(dtOwner);
        marketMetadata.setBaseURI("https://test-uri.com/");

        emit log_named_string("delegate tokenURI:", dt.tokenURI(delegateId));
        emit log_named_string("principal tokenURI:", principal.tokenURI(delegateId));
    }

    function randUser(uint256 i) internal view returns (address) {
        return users[bound(i, 0, TOTAL_USERS - 1)];
    }

    function prepareValidExpiry(bool expiryTypeRelative, uint256 time) internal view returns (CreateOffererEnums.ExpiryType, uint256, uint256) {
        CreateOffererEnums.ExpiryType expiryType = expiryTypeRelative ? CreateOffererEnums.ExpiryType.relative : CreateOffererEnums.ExpiryType.absolute;
        time = bound(time, block.timestamp + 1, type(uint40).max);
        uint256 expiryValue = expiryType == CreateOffererEnums.ExpiryType.relative ? time - block.timestamp : time;
        return (expiryType, time, expiryValue);
    }
}
