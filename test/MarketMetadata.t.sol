// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IDelegateRegistry, DelegateTokenErrors as Errors, DelegateTokenStructs as Structs, DelegateTokenHelpers as Helpers} from "../src/libraries/DelegateTokenLib.sol";

import {Test} from "forge-std/Test.sol";
import {BaseLiquidDelegateTest} from "./base/BaseLiquidDelegateTest.t.sol";

import {MockERC721} from "./mock/MockTokens.t.sol";

import {console2} from "forge-std/console2.sol";

contract MarketMetadataTest is Test, BaseLiquidDelegateTest {
    function setUp() public {}

    function testMetadataResult() public {
        // TODO: Test metadata call reverts if DT does not exist
        // vm.expectRevert()

        uint256 tokenId = 72;
        uint256 timestamp = 1702737013;
        uint256 salt = 1000;
        address principalHolder = address(1);

        mockERC721.mint(address(this), tokenId);
        mockERC721.setApprovalForAll(address(dt), true);
        Structs.DelegateInfo memory info = Structs.DelegateInfo({
            principalHolder: principalHolder,
            tokenType: IDelegateRegistry.DelegationType.ERC721,
            delegateHolder: address(this),
            amount: 0,
            tokenContract: address(mockERC721),
            tokenId: tokenId,
            rights: "",
            expiry: timestamp
        });
        uint256 delegateId = dt.create(info, salt);

        string memory dtResult = marketMetadata.delegateTokenURI(delegateId, info);
        console2.log("delegatetoken metadata", dtResult);

        string memory ptResult = marketMetadata.principalTokenURI(delegateId, info);
        console2.log("principaltoken metadata", ptResult);
    }
}
