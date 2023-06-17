// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LibRLP} from "solady/utils/LibRLP.sol";
import {LibString} from "solady/utils/LibString.sol";
import {DelegateToken, ExpiryType, TokenType} from "src/DelegateToken.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";
import {DelegateRegistry} from "delegate-registry/src/DelegateRegistry.sol";
import {MockERC721} from "./mock/MockERC721.sol";

contract DelegateTokenTest is Test {
    using LibString for uint256;

    // Environment contracts.
    DelegateRegistry registry;
    DelegateToken dt;
    PrincipalToken principal;
    MockERC721 token;

    // Test actors.
    address coreDeployer = makeAddr("coreDeployer");
    address dtOwner = makeAddr("dtOwner");

    uint256 internal constant TOTAL_USERS = 100;
    address[TOTAL_USERS] internal users;

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

        token = new MockERC721(0);

        for (uint256 i; i < TOTAL_USERS; i++) {
            users[i] = makeAddr(string.concat("user", (i + 1).toString()));
        }
    }

    function test_fuzzingCreateRights(
        address tokenOwner,
        address dtTo,
        address notLdTo,
        address principalTo,
        uint256 tokenId,
        bool expiryTypeRelative,
        uint256 time
    ) public {
        vm.assume(tokenOwner != address(0));
        vm.assume(dtTo != address(0));
        vm.assume(principalTo != address(0));
        vm.assume(notLdTo != dtTo);

        (ExpiryType expiryType, uint256 expiry, uint256 expiryValue) = prepareValidExpiry(expiryTypeRelative, time);

        token.mint(tokenOwner, tokenId);
        vm.startPrank(tokenOwner);
        token.setApprovalForAll(address(dt), true);

        uint256 delegateId = dt.create(dtTo, principalTo, address(token), TokenType.ERC721, tokenId, expiryType, expiryValue);

        vm.stopPrank();

        assertEq(dt.ownerOf(delegateId), dtTo);
        assertEq(principal.ownerOf(delegateId), principalTo);

        (uint256 baseDelegateId, uint256 activeDelegateId, ViewRights memory rights) = dt.getRights(delegateId);
        assertEq(activeDelegateId, delegateId);
        assertEq(baseDelegateId, dt.getBaseDelegateId(address(token), tokenId));
        assertEq(uint256(bytes32(bytes25(bytes32(delegateId)))), baseDelegateId);
        assertEq(rights.nonce, 0);
        assertEq(rights.tokenContract, address(token));
        assertEq(rights.tokenId, tokenId);
        assertEq(rights.expiry, expiry);

        assertTrue(registry.checkDelegateForERC721(dtTo, address(dt), address(token), tokenId, ""));
        assertFalse(registry.checkDelegateForERC721(notLdTo, address(dt), address(token), tokenId, ""));
    }

    function test_fuzzingTransferDelegation(address from, address to, uint256 underlyingTokenId, bool expiryTypeRelative, uint256 time) public {
        vm.assume(from != address(0));
        vm.assume(to != address(0));

        (ExpiryType expiryType,, uint256 expiryValue) = prepareValidExpiry(expiryTypeRelative, time);
        token.mint(address(dt), underlyingTokenId);

        vm.prank(from);
        uint256 delegateId = dt.createUnprotected(from, from, address(token), TokenType.ERC721, underlyingTokenId, expiryType, expiryValue);

        vm.prank(from);
        dt.transferFrom(from, to, delegateId);

        assertTrue(registry.checkDelegateForERC721(to, address(dt), address(token), underlyingTokenId, ""));

        if (from != to) {
            assertFalse(registry.checkDelegateForERC721(from, address(dt), address(token), underlyingTokenId, ""));
        }
    }

    function test_fuzzingCannotCreateWithoutToken(address minter, uint256 tokenId, bool expiryTypeRelative, uint256 time) public {
        vm.assume(minter != address(0));
        (ExpiryType expiryType,, uint256 expiryValue) = prepareValidExpiry(expiryTypeRelative, time);

        vm.startPrank(minter);
        vm.expectRevert();
        dt.create(minter, minter, address(token), TokenType.ERC721, tokenId, expiryType, expiryValue);
        vm.stopPrank();
    }

    function test_fuzzingMintRights(
        address tokenOwner,
        address dtTo,
        address notLdTo,
        address principalTo,
        uint256 tokenId,
        bool expiryTypeRelative,
        uint256 time
    ) public {
        vm.assume(tokenOwner != address(0));
        vm.assume(dtTo != address(0));
        vm.assume(principalTo != address(0));
        vm.assume(notLdTo != dtTo);

        (ExpiryType expiryType, uint256 expiry, uint256 expiryValue) = prepareValidExpiry(expiryTypeRelative, time);

        token.mint(tokenOwner, tokenId);
        vm.startPrank(tokenOwner);
        token.transferFrom(tokenOwner, address(dt), tokenId);

        uint256 delegateId = dt.createUnprotected(dtTo, principalTo, address(token), TokenType.ERC721, tokenId, expiryType, expiryValue);

        vm.stopPrank();

        assertEq(dt.ownerOf(delegateId), dtTo);
        assertEq(principal.ownerOf(delegateId), principalTo);

        (uint256 baseDelegateId, uint256 activeDelegateId, ViewRights memory rights) = dt.getRights(delegateId);
        assertEq(activeDelegateId, delegateId);
        assertEq(baseDelegateId, dt.getBaseDelegateId(address(token), tokenId));
        assertEq(uint256(bytes32(bytes25(bytes32(delegateId)))), baseDelegateId);
        assertEq(rights.nonce, 0);
        assertEq(rights.tokenContract, address(token));
        assertEq(rights.tokenId, tokenId);
        assertEq(rights.expiry, expiry);

        assertTrue(registry.checkDelegateForERC721(dtTo, address(dt), address(token), tokenId, ""));
        assertFalse(registry.checkDelegateForERC721(notLdTo, address(dt), address(token), tokenId, ""));
    }

    function testCannotMintWithExisting() public {
        address tokenOwner = makeAddr("tokenOwner");
        uint256 tokenId = token.mintNext(tokenOwner);
        vm.startPrank(tokenOwner);
        token.setApprovalForAll(address(dt), true);
        dt.create(tokenOwner, tokenOwner, address(token), TokenType.ERC721, tokenId, ExpiryType.RELATIVE, 10 days);
        vm.stopPrank();

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        dt.createUnprotected(attacker, attacker, address(token), TokenType.ERC721, tokenId, ExpiryType.RELATIVE, 5 days);
    }

    function test_fuzzingCannotCreateWithNonexistentContract(address minter, address tokenContract, uint256 tokenId, bool expiryTypeRelative, uint256 time)
        public
    {
        vm.assume(minter != address(0));
        vm.assume(tokenContract.code.length == 0);

        (ExpiryType expiryType,, uint256 expiryValue) = prepareValidExpiry(expiryTypeRelative, time);

        vm.startPrank(minter);
        vm.expectRevert();
        dt.create(minter, minter, tokenContract, TokenType.ERC721, tokenId, expiryType, expiryValue);
        vm.stopPrank();
    }

    function testStaticMetadata() public {
        assertEq(dt.name(), "Delegate Token");
        assertEq(dt.symbol(), "DT");
        assertEq(dt.version(), "1");
        assertEq(
            dt.DOMAIN_SEPARATOR(),
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes(dt.name())),
                    keccak256(bytes(dt.version())),
                    block.chainid,
                    address(dt)
                )
            )
        );
    }

    function testTokenURI() public {
        uint256 id = 9827;
        address user = makeAddr("user");
        token.mint(address(dt), id);
        vm.prank(user);
        uint256 delegateId = dt.createUnprotected(user, user, address(token), TokenType.ERC721, id, ExpiryType.RELATIVE, 10 seconds);

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
