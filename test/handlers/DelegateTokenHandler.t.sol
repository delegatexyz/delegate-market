// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";

import {AddressSet, TokenSet, UintSet, SetsLib} from "../utils/SetsLib.t.sol";
import {MockERC721} from "../mock/MockTokens.t.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {IDelegateToken, Structs as IDelegateTokenStructs} from "src/interfaces/IDelegateToken.sol";
import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";

import {CreateOffererEnums} from "src/libraries/CreateOffererLib.sol";

contract DelegateTokenHandler is CommonBase, StdCheats, StdUtils {
    using Strings for address;
    using Strings for uint256;

    using SetsLib for AddressSet;
    using SetsLib for TokenSet;
    using SetsLib for UintSet;

    using SafeCast for uint256;

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
            IDelegateTokenStructs.DelegateInfo(
                currentActor, IDelegateRegistry.DelegationType.ERC721, currentActor, amount, address(token), id, "", block.timestamp + 1 seconds
            ),
            salt
        );
        allDelegateTokens.add(delegateId);
        allPrincipalTokens.add(delegateId);
        existingDelegateTokens.add(delegateId);
        existingPrincipalTokens.add(delegateId);
        ownedDTTokens[currentActor].add(delegateId);
        ownedPrTokens[currentActor].add(delegateId);

        vm.stopPrank();
    }

    function transferDTToken(uint256 fromSeed, uint256 toSeed, uint256 rightsSeed, uint256 backupTokenSeed) public useActor(fromSeed) countCall("dt_transfer") {
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
                IDelegateTokenStructs.DelegateInfo(to, IDelegateRegistry.DelegationType.ERC721, currentActor, amount, address(token), id, "", block.timestamp + 1 seconds),
                salt
            );

            allDelegateTokens.add(delegateId);
            allPrincipalTokens.add(delegateId);
            existingDelegateTokens.add(delegateId);
            existingPrincipalTokens.add(delegateId);
            ownedPrTokens[currentActor].add(delegateId);
        } else {
            ownedDTTokens[currentActor].remove(delegateId);
            IERC721(address(delegateToken)).transferFrom(currentActor, to, delegateId);
        }

        vm.stopPrank();
        ownedDTTokens[to].add(delegateId);
    }

    function burnDTToken(uint256 actorSeed, uint256 rightsSeed) public useActor(actorSeed) countCall("dt_burn") {
        uint256 delegateId = ownedDTTokens[currentActor].get(rightsSeed);

        if (delegateId != 0) {
            vm.startPrank(currentActor);

            delegateToken.rescind(delegateId);
            ownedDTTokens[currentActor].remove(delegateId);
            existingDelegateTokens.remove(delegateId);

            vm.stopPrank();
        }
    }

    function withdrawExpired(uint256 actorSeed, uint256 prSeed) public useActor(actorSeed) countCall("withdraw_expired") {
        uint256 prId = ownedPrTokens[currentActor].get(prSeed);

        if (prId == 0) return;

        address dtOwner = _getDTOwner(prId);

        IDelegateTokenStructs.DelegateInfo memory delegateInfo = delegateToken.getDelegateInfo(prId);
        vm.warp(delegateInfo.expiry);
        vm.startPrank(currentActor);
        delegateToken.withdraw(prId);
        vm.stopPrank();

        existingPrincipalTokens.remove(prId);
        ownedPrTokens[currentActor].remove(prId);
        depositedTokens.remove(delegateInfo.tokenContract, delegateInfo.tokenId);

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
            delegateToken.rescind(prId);

            existingDelegateTokens.remove(prId);
            ownedDTTokens[dtOwner].remove(prId);
        }

        IDelegateTokenStructs.DelegateInfo memory delegateInfo = delegateToken.getDelegateInfo(prId);
        vm.prank(currentActor);
        delegateToken.withdraw(prId);

        existingPrincipalTokens.remove(prId);
        ownedPrTokens[currentActor].remove(prId);
        depositedTokens.remove(delegateInfo.tokenContract, delegateInfo.tokenId);
    }

    function extend(uint256 prSeed, uint8 rawExpiryType, uint40 expiryValue) public countCall("extend") {
        uint256 prId = existingPrincipalTokens.get(prSeed);
        if (prId == 0) return;

        IDelegateTokenStructs.DelegateInfo memory delegateInfo = delegateToken.getDelegateInfo(prId);

        CreateOffererEnums.ExpiryType expiryType = CreateOffererEnums.ExpiryType(
            bound(rawExpiryType, uint256(type(CreateOffererEnums.ExpiryType).min), uint256(type(CreateOffererEnums.ExpiryType).max)).toUint8()
        );

        uint256 minTime = (delegateInfo.expiry > block.timestamp ? delegateInfo.expiry : block.timestamp) + 1;
        uint256 maxTime = expiryType == CreateOffererEnums.ExpiryType.relative ? type(uint40).max - block.timestamp : type(uint40).max;
        // No possible extension
        if (maxTime < minTime) return;

        expiryValue = bound(expiryValue, minTime, maxTime).toUint40();

        address owner = principal.ownerOf(prId);
        vm.prank(owner);
        delegateToken.extend(prId, delegateInfo.expiry);
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
        try IERC721(address(delegateToken)).ownerOf(dtId) returns (address retrievedOwner) {
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
