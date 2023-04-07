// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

import {LibRLP} from "solady/utils/LibRLP.sol";

import {LiquidDelegateV2} from "src/LiquidDelegateV2.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";
import {DelegationRegistry} from "src/DelegationRegistry.sol";

/// @author philogy <https://github.com/philogy>
contract BaseLiquidDelegateTest is Test {
    DelegationRegistry internal registry;
    PrincipalToken internal principal;
    LiquidDelegateV2 internal ld;

    address internal ldDeployer = makeAddr("LD_CORE_DEPLOYER");
    address internal ldOwner = makeAddr("LD_OWNER");

    constructor() {
        registry = new DelegationRegistry();

        vm.startPrank(ldDeployer);
        ld = new LiquidDelegateV2(
            address(registry),
            LibRLP.computeAddress(ldDeployer, vm.getNonce(ldDeployer) + 1),
            "",
            ldOwner
        );
        principal = new PrincipalToken(address(ld));
        vm.stopPrank();
    }
}
