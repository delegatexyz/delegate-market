// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";

import {AddressSet, TokenSet, UintSet, SetsLib} from "../utils/SetsLib.sol";
import {MockERC721} from "../mock/MockERC721.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

import {IDelegateToken, IDelegateRegistry} from "src/interfaces/IDelegateToken.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";

import {ExpiryType} from "src/interfaces/IWrapOfferer.sol";

contract DelegateTokenHandler is CommonBase, StdCheats, StdUtils {
    using LibString for address;
    using LibString for uint256;

    using SetsLib for AddressSet;
    using SetsLib for TokenSet;
    using SetsLib for UintSet;

    using SafeCastLib for uint256;

    IDelegateToken public immutable delegateToken;
    PrincipalToken public immutable principal;
    uint256 internal constant TOTAL_TOKENS = 10;

    mapping(bytes32 => uint256) public calls;

    string[] internal messages;

    address internal currentActor;
    AddressSet internal actors;
    AddressSet internal tokenContracts;

    TokenSet internal allTokens;
    TokenSet internal depositedTokens;
    mapping(address => UintSet) internal ownedDTTokens;
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

    constructor(address dt) {
        delegateToken = IDelegateToken(dt);
        principal = PrincipalToken(IDelegateToken(dt).principalToken());
        for (uint256 i; i < TOTAL_TOKENS; i++) {
            tokenContracts.add(address(new MockERC721(uint(keccak256(abi.encode("start_id", i))))));
        }
    }

    function createDTToken(uint256 tokenSeed) public createActor countCall("create_dt") {
        (address token, uint256 id) = _mintToken(tokenSeed, currentActor);

        vm.startPrank(currentActor);

        MockERC721(token).approve(address(delegateToken), id);

        uint256 amount = 0;
        uint96 salt = 3;
        uint256 delegateId = delegateToken.create(
            currentActor, currentActor, IDelegateRegistry.DelegationType.ERC721, address(token), id, amount, "", block.timestamp + 1 seconds, salt
        );
        allDelegateTokens.add(delegateId);
        allPrincipalTokens.add(delegateId);
        existingDelegateTokens.add(delegateId);
        existingPrincipalTokens.add(delegateId);
        ownedDTTokens[currentActor].add(delegateId);
        ownedPrTokens[currentActor].add(delegateId);

        vm.stopPrank();
    }

    function transferDTToken(uint256 fromSeed, uint256 toSeed, uint256 rightsSeed, uint256 backupTokenSeed)
        public
        useActor(fromSeed)
        countCall("dt_transfer")
    {
        address to = actors.get(toSeed);
        if (to == address(0)) to = currentActor;

        // Select random token from actor owns.
        uint256 delegateId = ownedDTTokens[currentActor].get(rightsSeed);
        // If they don't have tokens create new one.
        vm.startPrank(currentActor);
        if (delegateId == 0) {
            (address token, uint256 id) = _mintToken(backupTokenSeed, currentActor);
            MockERC721(token).approve(address(delegateToken), id);

            uint256 amount = 0;
            uint96 salt = 3;
            delegateId = delegateToken.create(
                to, currentActor, IDelegateRegistry.DelegationType.ERC721, address(token), id, amount, "", block.timestamp + 1 seconds, salt
            );

            allDelegateTokens.add(delegateId);
            allPrincipalTokens.add(delegateId);
            existingDelegateTokens.add(delegateId);
            existingPrincipalTokens.add(delegateId);
            ownedPrTokens[currentActor].add(delegateId);
        } else {
            ownedDTTokens[currentActor].remove(delegateId);
            delegateToken.transferFrom(currentActor, to, delegateId);
        }

        vm.stopPrank();
        ownedDTTokens[to].add(delegateId);
    }

    function burnDTToken(uint256 actorSeed, uint256 rightsSeed) public useActor(actorSeed) countCall("dt_burn") {
        uint256 delegateId = ownedDTTokens[currentActor].get(rightsSeed);

        if (delegateId != 0) {
            vm.startPrank(currentActor);

            delegateToken.burn(delegateId);
            ownedDTTokens[currentActor].remove(delegateId);
            existingDelegateTokens.remove(delegateId);

            vm.stopPrank();
        }
    }

    function withdrawExpired(uint256 actorSeed, uint256 prSeed) public useActor(actorSeed) countCall("withdraw_expired") {
        uint256 prId = ownedPrTokens[currentActor].get(prSeed);

        if (prId == 0) return;

        address dtOwner = _getDTOwner(prId);

        ( /* DelegationType */ , address tokenContract, uint256 tokenId, /* tokenAmount */, /* rights */, uint256 expiry) = delegateToken.getDelegateInfo(prId);
        vm.warp(expiry);
        vm.startPrank(currentActor);
        delegateToken.withdrawTo(currentActor, prId);
        vm.stopPrank();

        existingPrincipalTokens.remove(prId);
        ownedPrTokens[currentActor].remove(prId);
        depositedTokens.remove(tokenContract, tokenId);

        if (dtOwner != address(0)) {
            existingDelegateTokens.remove(prId);
            ownedDTTokens[dtOwner].remove(prId);
        }
    }

    function withdrawBurned(uint256 actorSeed, uint256 prSeed) public useActor(actorSeed) countCall("withdraw_burned") {
        uint256 prId = ownedPrTokens[currentActor].get(prSeed);
        if (prId == 0) return;

        address dtOwner = _getDTOwner(prId);
        if (dtOwner != address(0)) {
            vm.prank(dtOwner);
            delegateToken.burn(prId);

            existingDelegateTokens.remove(prId);
            ownedDTTokens[dtOwner].remove(prId);
        }

        ( /* DelegationType */ , address tokenContract, uint256 tokenId, /* tokenAmount */, /* rights */, /* expiry */ ) = delegateToken.getDelegateInfo(prId);
        vm.prank(currentActor);
        delegateToken.withdrawTo(currentActor, prId);

        existingPrincipalTokens.remove(prId);
        ownedPrTokens[currentActor].remove(prId);
        depositedTokens.remove(tokenContract, tokenId);
    }

    function extend(uint256 prSeed, uint8 rawExpiryType, uint40 expiryValue) public countCall("extend") {
        uint256 prId = existingPrincipalTokens.get(prSeed);
        if (prId == 0) return;

        (,,,,, uint256 expiry) = delegateToken.getDelegateInfo(prId);

        ExpiryType expiryType = ExpiryType(bound(rawExpiryType, uint256(type(ExpiryType).min), uint256(type(ExpiryType).max)).toUint8());

        uint256 minTime = (expiry > block.timestamp ? expiry : block.timestamp) + 1;
        uint256 maxTime = expiryType == ExpiryType.RELATIVE ? type(uint40).max - block.timestamp : type(uint40).max;
        // No possible extension
        if (maxTime < minTime) return;

        expiryValue = bound(expiryValue, minTime, maxTime).toUint40();

        address owner = principal.ownerOf(prId);
        vm.prank(owner);
        delegateToken.extend(prId, expiry);
    }

    function callSummary() external view {
        console.log("Call summary:");
        console.log("------------------");
        console.log("create_dt", calls["create_dt"]);
        console.log("dt_transfer", calls["dt_transfer"]);
        console.log("dt_burn", calls["dt_burn"]);
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

    function _getDTOwner(uint256 dtId) internal view returns (address owner) {
        try delegateToken.ownerOf(dtId) returns (address retrievedOwner) {
            owner = retrievedOwner;
        } catch {}
    }

    function _getPTOwner(uint256 ptId) internal view returns (address owner) {
        try principal.ownerOf(ptId) returns (address retrievedOwner) {
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
