// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {BaseLiquidDelegateTest} from "./base/BaseLiquidDelegateTest.t.sol";

import {DelegateTokenHandler} from "./handlers/DelegateTokenHandler.t.sol";

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

contract DelegateTokenInvariants is StdInvariant, BaseLiquidDelegateTest {
    DelegateTokenHandler internal handler;

    bytes4[] internal selectors;

    function setUp() public {
        handler = new DelegateTokenHandler(address(dt));

        // Add target selectors.
        selectors.push(handler.createDTToken.selector);
        selectors.push(handler.transferDTToken.selector);
        selectors.push(handler.burnDTToken.selector);
        selectors.push(handler.withdrawExpired.selector);
        selectors.push(handler.withdrawBurned.selector);
        selectors.push(handler.extend.selector);

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));

        targetContract(address(handler));
    }

    // function invariant_depositedTokensInDT() public {
    //     handler.forEachDepositedToken(this.tokenInDT);
    // }

    // function tokenInDT(address tokenContract, uint256 tokenId) external {
    //     assertEq(IERC721(tokenContract).ownerOf(tokenId), address(dt));
    // }

    // function invariant_oneTokenDelegatePerToken() public {
    //     handler.forEachDepositedToken(this.singleDelegate);
    // }

    // function singleDelegate(address tokenContract, uint256 tokenId) external {
    //     assertEq(registry.getDelegatesForAll(address(dt)).length, 0);
    //     assertEq(registry.getDelegatesForContract(address(dt), tokenContract).length, 0);
    //     assertEq(registry.getDelegatesForToken(address(dt), tokenContract, tokenId).length, 1);
    // }

    // function invariant_delegateOwnerDelegated() public {
    //     handler.forEachDepositedToken(this.delegateOwnerDelegated);
    // }

    // function delegateOwnerDelegated(address tokenContract, uint256 tokenId) external {
    //     (, uint256 delegateId,) = dt.getRights(dt.getBaseDelegateId(tokenContract, tokenId));
    //     address owner;
    //     try dt.ownerOf(delegateId) returns (address retrievedOwner) {
    //         owner = retrievedOwner;
    //     } catch {}
    //     assertTrue(owner != address(0));
    //     assertTrue(registry.checkDelegateForToken(owner, address(dt), tokenContract, tokenId));
    // }

    // function invariant_callSummary() public view {
    //     handler.callSummary();
    // }

    // function invariant_noncesNotAboveActive() public {
    //     handler.forAllDelegateTokens(this.rightsNonceLteActive);
    //     handler.forAllPrincipalTokens(this.rightsNonceLteActive);
    // }

    // function rightsNonceLteActive(uint256 delegateId) external {
    //     uint56 nonce = uint56(delegateId);
    //     (,, Rights memory rights) = dt.getRights(delegateId);
    //     assertLe(nonce, rights.nonce);
    // }

    // /// @dev Two existing principal tokens shoudt never have the same base rights Id
    // function invariant_onlySinglePrincipal() public {
    //     handler.forEachExistingPrincipalToken(this.uniquePrincipalBaseDelegateId);
    // }

    // uint256 internal currentPrId;

    // function uniquePrincipalBaseDelegateId(uint256 prId) external {
    //     currentPrId = prId;
    //     handler.forEachExistingPrincipalToken(this.noDuplicatePrBaseDelegateId);
    //     currentPrId = 0;
    // }

    // function noDuplicatePrBaseDelegateId(uint256 prId) external {
    //     // `forEach` iterates over whole set so need to skip the item itself.
    //     if (prId != currentPrId) {
    //         (uint256 baseDelegateId1,,) = dt.getRights(prId);
    //         (uint256 baseDelegateId2,,) = dt.getRights(currentPrId);
    //         assertTrue(baseDelegateId1 != baseDelegateId2);
    //     }
    // }
}
