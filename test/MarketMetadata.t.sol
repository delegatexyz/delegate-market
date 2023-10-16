// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {BaseLiquidDelegateTest} from "./base/BaseLiquidDelegateTest.t.sol";

import {MockERC721} from "./mock/MockTokens.t.sol";

import {console2} from "forge-std/console2.sol";

contract MarketMetadataTest is Test, BaseLiquidDelegateTest {
    function setUp() public {}

    function testMetadataResult() public {
        // TODO: Test metadata call reverts if DT does not exist
        // vm.expectRevert()
        // mockERC721.mint(address(this), tokenId);
        uint256 tokenId = 29004481359446502546631248805879161310821617999425410428854822506768421526883;
        uint256 timestamp = 1702737013;
        string memory dtResult = marketMetadata.delegateTokenURI(address(dt), tokenId, 1702737013, address(1));
        console2.log("delegatetoken metadata", dtResult);

        // string memory ptResult = marketMetadata.principalTokenURI(address(principal), address(dt), tokenId);
        // console2.log("principaltoken metadata", ptResult);
    }
}
