// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";

import {AddressSet, TokenSet, UintSet, SetsLib} from "../utils/SetsLib.sol";
import {MockERC721} from "../mock/MockERC721.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

import {IDelegateToken, ExpiryType, Rights} from "src/interfaces/IDelegateToken.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";

contract DelegateTokenHandler is CommonBase, StdCheats, StdUtils {
    using LibString for address;
    using LibString for uint256;

    using SetsLib for AddressSet;
    using SetsLib for TokenSet;
    using SetsLib for UintSet;

    using SafeCastLib for uint256;

    IDelegateToken public immutable liquidDelegate;
    PrincipalToken public immutable principal;
    uint256 internal constant TOTAL_TOKENS = 10;

    mapping(bytes32 => uint256) public calls;

    string[] internal messages;

    address internal currentActor;
    AddressSet internal actors;
    AddressSet internal tokenContracts;

    TokenSet internal allTokens;
    TokenSet internal depositedTokens;
    mapping(address => UintSet) internal ownedLDTokens;
    mapping(address => UintSet) internal ownedPrTokens;

    UintSet internal allDelegateTokens;
    UintSet internal allPrincipalTokens;
    UintSet internal existingDelegateTokens;
    UintSet internal existingPrincipalTokens;

    modifier createActor() {
        currentActor = msg.sender;
        actors.add(msg.sender);
        _;
    }

    modifier useActor(uint256 seed) {
        currentActor = actors.get(seed);
        if (currentActor == address(0)) currentActor = msg.sender;
        _;
    }

    modifier countCall(bytes32 name) {
        calls[name]++;
        _;
    }

    constructor(address ld) {
        liquidDelegate = IDelegateToken(ld);
        principal = PrincipalToken(IDelegateToken(ld).PRINCIPAL_TOKEN());
        for (uint256 i; i < TOTAL_TOKENS; i++) {
            tokenContracts.add(address(new MockERC721(uint(keccak256(abi.encode("start_id", i))))));
        }
    }

    function createLDToken(uint256 tokenSeed) public createActor countCall("create_ld") {
        (address token, uint256 id) = _mintToken(tokenSeed, currentActor);

        vm.startPrank(currentActor);

        MockERC721(token).approve(address(liquidDelegate), id);

        uint256 delegateId = liquidDelegate.create(currentActor, currentActor, address(token), id, ExpiryType.Relative, 1 seconds);
        allDelegateTokens.add(delegateId);
        allPrincipalTokens.add(delegateId);
        existingDelegateTokens.add(delegateId);
        existingPrincipalTokens.add(delegateId);
        ownedLDTokens[currentActor].add(delegateId);
        ownedPrTokens[currentActor].add(delegateId);

        vm.stopPrank();
    }

    function transferLDToken(uint256 fromSeed, uint256 toSeed, uint256 rightsSeed, uint256 backupTokenSeed)
        public
        useActor(fromSeed)
        countCall("ld_transfer")
    {
        address to = actors.get(toSeed);
        if (to == address(0)) to = currentActor;

        // Select random token from actor owns.
        uint256 delegateId = ownedLDTokens[currentActor].get(rightsSeed);
        // If they don't have tokens create new one.
        vm.startPrank(currentActor);
        if (delegateId == 0) {
            (address token, uint256 id) = _mintToken(backupTokenSeed, currentActor);
            MockERC721(token).approve(address(liquidDelegate), id);

            delegateId = liquidDelegate.create(to, currentActor, address(token), id, ExpiryType.Relative, 1 seconds);

            allDelegateTokens.add(delegateId);
            allPrincipalTokens.add(delegateId);
            existingDelegateTokens.add(delegateId);
            existingPrincipalTokens.add(delegateId);
            ownedPrTokens[currentActor].add(delegateId);
        } else {
            ownedLDTokens[currentActor].remove(delegateId);
            liquidDelegate.transferFrom(currentActor, to, delegateId);
        }

        vm.stopPrank();
        ownedLDTokens[to].add(delegateId);
    }

    function burnLDToken(uint256 actorSeed, uint256 rightsSeed) public useActor(actorSeed) countCall("ld_burn") {
        uint256 delegateId = ownedLDTokens[currentActor].get(rightsSeed);

        if (delegateId != 0) {
            vm.startPrank(currentActor);

            liquidDelegate.burn(delegateId);
            ownedLDTokens[currentActor].remove(delegateId);
            existingDelegateTokens.remove(delegateId);

            vm.stopPrank();
        }
    }

    function withdrawExpired(uint256 actorSeed, uint256 prSeed) public useActor(actorSeed) countCall("withdraw_expired") {
        uint256 prId = ownedPrTokens[currentActor].get(prSeed);

        if (prId == 0) return;

        address ldOwner = _getLDOwner(prId);

        (,, Rights memory rights) = liquidDelegate.getRights(prId);
        vm.warp(rights.expiry);
        vm.startPrank(currentActor);
        liquidDelegate.withdrawTo(currentActor, rights.nonce, rights.tokenContract, rights.tokenId);
        vm.stopPrank();

        existingPrincipalTokens.remove(prId);
        ownedPrTokens[currentActor].remove(prId);
        depositedTokens.remove(rights.tokenContract, rights.tokenId);

        if (ldOwner != address(0)) {
            existingDelegateTokens.remove(prId);
            ownedLDTokens[ldOwner].remove(prId);
        }
    }

    function withdrawBurned(uint256 actorSeed, uint256 prSeed) public useActor(actorSeed) countCall("withdraw_burned") {
        uint256 prId = ownedPrTokens[currentActor].get(prSeed);
        if (prId == 0) return;

        address ldOwner = _getLDOwner(prId);
        if (ldOwner != address(0)) {
            vm.prank(ldOwner);
            liquidDelegate.burn(prId);

            existingDelegateTokens.remove(prId);
            ownedLDTokens[ldOwner].remove(prId);
        }

        (,, Rights memory rights) = liquidDelegate.getRights(prId);
        vm.prank(currentActor);
        liquidDelegate.withdrawTo(currentActor, rights.nonce, rights.tokenContract, rights.tokenId);

        existingPrincipalTokens.remove(prId);
        ownedPrTokens[currentActor].remove(prId);
        depositedTokens.remove(rights.tokenContract, rights.tokenId);
    }

    function extend(uint256 prSeed, uint8 rawExpiryType, uint40 expiryValue) public countCall("extend") {
        uint256 prId = existingPrincipalTokens.get(prSeed);
        if (prId == 0) return;

        (,, Rights memory rights) = liquidDelegate.getRights(prId);

        ExpiryType expiryType = ExpiryType(bound(rawExpiryType, uint256(type(ExpiryType).min), uint256(type(ExpiryType).max)).toUint8());

        uint256 minTime = (rights.expiry > block.timestamp ? rights.expiry : block.timestamp) + 1;
        uint256 maxTime = expiryType == ExpiryType.Relative ? type(uint40).max - block.timestamp : type(uint40).max;
        // No possible extension
        if (maxTime < minTime) return;

        expiryValue = bound(expiryValue, minTime, maxTime).toUint40();

        address owner = principal.ownerOf(prId);
        vm.prank(owner);
        liquidDelegate.extend(prId, expiryType, expiryValue);
    }

    function callSummary() external view {
        console.log("Call summary:");
        console.log("------------------");
        console.log("create_ld", calls["create_ld"]);
        console.log("ld_transfer", calls["ld_transfer"]);
        console.log("ld_burn", calls["ld_burn"]);
        console.log("withdraw_expired", calls["withdraw_expired"]);
        console.log("withdraw_burned", calls["withdraw_burned"]);
        console.log("extend", calls["extend"]);
        if (messages.length > 0) console.log("messages:");
        for (uint256 i; i < messages.length; i++) {
            console.log(messages[i]);
        }
    }

    function _mintToken(uint256 tokenSeed, address recipient) internal returns (address token, uint256 id) {
        token = tokenContracts.get(tokenSeed);
        id = MockERC721(token).mintNext(recipient);
    }

    function _getLDOwner(uint256 ldId) internal view returns (address owner) {
        try liquidDelegate.ownerOf(ldId) returns (address retrievedOwner) {
            owner = retrievedOwner;
        } catch {}
    }

    function _getPrOwner(uint256 prId) internal view returns (address owner) {
        try principal.ownerOf(prId) returns (address retrievedOwner) {
            owner = retrievedOwner;
        } catch {}
    }

    function forEachDepositedToken(function(address, uint) external func) public {
        depositedTokens.forEach(func);
    }

    function forAllDelegateTokens(function(uint) external func) public {
        allDelegateTokens.forEach(func);
    }

    function forAllPrincipalTokens(function(uint) external func) public {
        allPrincipalTokens.forEach(func);
    }

    function forEachExistingPrincipalToken(function (uint) external func) public {
        existingPrincipalTokens.forEach(func);
    }
}
