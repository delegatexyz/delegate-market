// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";

import {ComputeAddress} from "../../script/ComputeAddress.s.sol";

import {DelegateToken, Structs as DelegateTokenStructs} from "src/DelegateToken.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";
import {DelegateRegistry} from "delegate-registry/src/DelegateRegistry.sol";
import {MockERC721, MockERC20, MockERC1155} from "test/mock/MockTokens.t.sol";
import {ERC1155Holder} from "openzeppelin/token/ERC1155/utils/ERC1155Holder.sol";

contract BaseLiquidDelegateTest is Test, ERC1155Holder {
    DelegateRegistry internal registry;
    PrincipalToken internal principal;
    DelegateToken internal dt;
    MockERC721 internal mockERC721;
    MockERC20 internal mockERC20;
    MockERC1155 internal mockERC1155;

    address internal dtDeployer = makeAddr("DT_CORE_DEPLOYER");
    address internal dtOwner = makeAddr("DT_OWNER");

    constructor() {
        registry = new DelegateRegistry();

        vm.startPrank(dtDeployer);
        DelegateTokenStructs.DelegateTokenParameters memory delegateTokenParameters = DelegateTokenStructs.DelegateTokenParameters({
            delegateRegistry: address(registry),
            principalToken: ComputeAddress.addressFrom(dtDeployer, vm.getNonce(dtDeployer) + 1),
            baseURI: "",
            initialMetadataOwner: dtOwner
        });
        dt = new DelegateToken(delegateTokenParameters);
        principal = new PrincipalToken(address(dt));
        vm.stopPrank();
        mockERC721 = new MockERC721(0);
        mockERC20 = new MockERC20();
        mockERC1155 = new MockERC1155();
    }
}
