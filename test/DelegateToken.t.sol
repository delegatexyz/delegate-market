// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LibRLP} from "solady/utils/LibRLP.sol";
import {LibString} from "solady/utils/LibString.sol";
import {DelegateToken} from "src/DelegateToken.sol";
import {ExpiryType} from "src/interfaces/IWrapOfferer.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";
import {DelegateRegistry, IDelegateRegistry} from "delegate-registry/src/DelegateRegistry.sol";
import {MockERC721, MockERC20, MockERC1155} from "./mock/MockTokens.sol";

contract DelegateTokenTest is Test {
    using LibString for uint256;

    // Environment contracts.
    DelegateRegistry registry;
    DelegateToken dt;
    PrincipalToken principal;
    MockERC721 mock721;
    MockERC20 mock20;
    MockERC1155 mock1155;

    // Test actors.
    address coreDeployer = makeAddr("coreDeployer");
    address dtOwner = makeAddr("dtOwner");

    uint256 internal constant TOTAL_USERS = 100;
    address[TOTAL_USERS] internal users;

    uint96 internal constant SALT = 7;

    function setUp() public {
        registry = new DelegateRegistry();

        vm.startPrank(coreDeployer);
        dt = new DelegateToken(
            address(registry),
            LibRLP.computeAddress(coreDeployer, vm.getNonce(coreDeployer) + 1),
            "",
            dtOwner
        );
        principal = new PrincipalToken(
            address(dt)
        );
        vm.stopPrank();

        mock721 = new MockERC721(0);
        mock20 = new MockERC20();
        mock1155 = new MockERC1155();

        for (uint256 i; i < TOTAL_USERS; i++) {
            users[i] = makeAddr(string.concat("user", (i + 1).toString()));
        }
    }

    function testFuzzingCreate721(address tokenOwner, address dtTo, address notLdTo, address principalTo, uint256 tokenId, bool expiryTypeRelative, uint256 time)
        public
    {
        vm.assume(tokenOwner != address(0));
        vm.assume(dtTo != address(0));
        vm.assume(principalTo != address(0));
        vm.assume(notLdTo != dtTo);

        ( /* ExpiryType */ , uint256 expiry, /* expiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        mock721.mint(tokenOwner, tokenId);
        vm.startPrank(tokenOwner);
        mock721.setApprovalForAll(address(dt), true);

        uint256 delegateId = dt.create(dtTo, principalTo, IDelegateRegistry.DelegationType.ERC721, address(mock721), tokenId, 0, "", expiry, SALT);

        vm.stopPrank();

        assertEq(dt.ownerOf(delegateId), dtTo);
        assertEq(principal.ownerOf(delegateId), principalTo);

        assertTrue(registry.checkDelegateForERC721(dtTo, address(dt), address(mock721), tokenId, ""));
        assertFalse(registry.checkDelegateForERC721(notLdTo, address(dt), address(mock721), tokenId, ""));
    }

    function testFuzzingCreate20(address tokenOwner, address dtTo, address notLdTo, address principalTo, uint256 amount, bool expiryTypeRelative, uint256 time) public {
        vm.assume(tokenOwner != address(0));
        vm.assume(dtTo != address(0));
        vm.assume(principalTo != address(0));
        vm.assume(notLdTo != dtTo);
        vm.assume(amount != 0);

        ( /* ExpiryType */ , uint256 expiry, /* expiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        mock20.mint(tokenOwner, amount);
        vm.startPrank(tokenOwner);
        mock20.approve(address(dt), amount);

        uint256 delegateId = dt.create(dtTo, principalTo, IDelegateRegistry.DelegationType.ERC20, address(mock20), 0, amount, "", expiry, SALT);

        vm.stopPrank();

        assertEq(dt.ownerOf(delegateId), dtTo);
        assertEq(principal.ownerOf(delegateId), principalTo);

        assertEq(amount, registry.checkDelegateForERC20(dtTo, address(dt), address(mock20), ""));
        assertEq(0, registry.checkDelegateForERC20(notLdTo, address(dt), address(mock20), ""));
    }

    function testFuzzingCreate1155(
        address tokenOwner,
        address dtTo,
        address notLdTo,
        address principalTo,
        uint256 tokenId,
        uint256 amount,
        bool expiryTypeRelative,
        uint256 time
    ) public {
        vm.assume(tokenOwner != address(0));
        vm.assume(dtTo != address(0));
        vm.assume(principalTo != address(0));
        vm.assume(notLdTo != dtTo);
        vm.assume(amount != 0);

        ( /* ExpiryType */ , uint256 expiry, /* expiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        mock1155.mint(tokenOwner, tokenId, amount, "");
        vm.startPrank(tokenOwner);
        mock1155.setApprovalForAll(address(dt), true);

        uint256 delegateId = dt.create(dtTo, principalTo, IDelegateRegistry.DelegationType.ERC1155, address(mock1155), tokenId, amount, "", expiry, SALT);

        vm.stopPrank();

        assertEq(dt.ownerOf(delegateId), dtTo);
        assertEq(principal.ownerOf(delegateId), principalTo);

        assertEq(amount, registry.checkDelegateForERC1155(dtTo, address(dt), address(mock1155), tokenId, ""));
        assertEq(0, registry.checkDelegateForERC1155(notLdTo, address(dt), address(mock1155), tokenId, ""));
    }

    function test_fuzzingTransferDelegation(address from, address to, uint256 underlyingTokenId, bool expiryTypeRelative, uint256 time) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));

        ( /* ExpiryType */ , uint256 expiry, /* ExpiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);
        mock721.mint(address(from), underlyingTokenId);

        vm.startPrank(from);
        mock721.setApprovalForAll(address(dt), true);
        uint256 delegateId = dt.create(from, from, IDelegateRegistry.DelegationType.ERC721, address(mock721), underlyingTokenId, 0, "", expiry, SALT);

        vm.prank(from);
        dt.transferFrom(from, to, delegateId);

        assertTrue(registry.checkDelegateForERC721(to, address(dt), address(mock721), underlyingTokenId, ""));

        if (from != to) {
            assertFalse(registry.checkDelegateForERC721(from, address(dt), address(mock721), underlyingTokenId, ""));
        }
    }

    function test_fuzzingCannotCreateWithoutToken(address minter, uint256 tokenId, bool expiryTypeRelative, uint256 time) public {
        vm.assume(minter != address(0));
        ( /* ExpiryType */ , uint256 expiry, /* expiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        vm.startPrank(minter);
        vm.expectRevert();
        dt.create(minter, minter, IDelegateRegistry.DelegationType.ERC721, address(mock721), tokenId, 0, "", expiry, SALT);
        vm.stopPrank();
    }

    function test_fuzzingMintRights(address tokenOwner, address dtTo, address notLdTo, address principalTo, uint256 tokenId, bool expiryTypeRelative, uint256 time)
        public
    {
        vm.assume(tokenOwner != address(0));
        vm.assume(dtTo != address(0));
        vm.assume(principalTo != address(0));
        vm.assume(notLdTo != dtTo);

        ( /* ExpiryType */ , uint256 expiry, /* expiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        mock721.mint(tokenOwner, tokenId);
        vm.startPrank(tokenOwner);
        mock721.setApprovalForAll(address(dt), true);
        uint256 delegateId = dt.create(dtTo, principalTo, IDelegateRegistry.DelegationType.ERC721, address(mock721), tokenId, 0, "", expiry, SALT);

        vm.stopPrank();

        assertEq(dt.ownerOf(delegateId), dtTo);
        assertEq(principal.ownerOf(delegateId), principalTo);

        assertTrue(registry.checkDelegateForERC721(dtTo, address(dt), address(mock721), tokenId, ""));
        assertFalse(registry.checkDelegateForERC721(notLdTo, address(dt), address(mock721), tokenId, ""));
    }

    function testCannotMintWithExisting() public {
        address tokenOwner = makeAddr("tokenOwner");
        uint256 tokenId = mock721.mintNext(tokenOwner);
        vm.startPrank(tokenOwner);
        mock721.setApprovalForAll(address(dt), true);
        dt.create(tokenOwner, tokenOwner, IDelegateRegistry.DelegationType.ERC721, address(mock721), tokenId, 0, "", block.timestamp + 10 days, SALT);
        vm.stopPrank();

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        dt.create(attacker, attacker, IDelegateRegistry.DelegationType.ERC721, address(mock721), tokenId, 0, "", block.timestamp + 10 days, SALT);
    }

    function test_fuzzingCannotCreateWithNonexistentContract(address minter, address tokenContract, uint256 tokenId, bool expiryTypeRelative, uint256 time) public {
        vm.assume(minter != address(0));
        vm.assume(tokenContract.code.length == 0);

        ( /* ExpiryType */ , uint256 expiry, /* expiryValue */ ) = prepareValidExpiry(expiryTypeRelative, time);

        vm.startPrank(minter);
        vm.expectRevert();
        dt.create(minter, minter, IDelegateRegistry.DelegationType.ERC721, tokenContract, tokenId, 0, "", expiry, SALT);
        vm.stopPrank();
    }

    function testTokenURI() public {
        uint256 id = 9827;
        address user = makeAddr("user");
        mock721.mint(address(user), id);
        vm.startPrank(user);
        mock721.setApprovalForAll(address(dt), true);
        uint256 delegateId = dt.create(user, user, IDelegateRegistry.DelegationType.ERC721, address(mock721), id, 0, "", block.timestamp + 10 seconds, SALT);

        vm.prank(dtOwner);
        dt.setBaseURI("https://test-uri.com/");

        emit log_named_string("delegate tokenURI:", dt.tokenURI(delegateId));
        emit log_named_string("principal tokenURI:", principal.tokenURI(delegateId));
    }

    function randUser(uint256 i) internal view returns (address) {
        return users[bound(i, 0, TOTAL_USERS - 1)];
    }

    function prepareValidExpiry(bool expiryTypeRelative, uint256 time) internal view returns (ExpiryType, uint256, uint256) {
        ExpiryType expiryType = expiryTypeRelative ? ExpiryType.RELATIVE : ExpiryType.ABSOLUTE;
        time = bound(time, block.timestamp + 1, type(uint40).max);
        uint256 expiryValue = expiryType == ExpiryType.RELATIVE ? time - block.timestamp : time;
        return (expiryType, time, expiryValue);
    }
}
