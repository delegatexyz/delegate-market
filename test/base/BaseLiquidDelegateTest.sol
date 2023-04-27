// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {LibRLP} from "solady/utils/LibRLP.sol";

import {DelegateToken} from "src/DelegateToken.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";
import {DelegationRegistry} from "src/DelegationRegistry.sol";

contract BaseLiquidDelegateTest is Test {
    DelegationRegistry internal registry;
    PrincipalToken internal principal;
    DelegateToken internal ld;

    address internal ldDeployer = makeAddr("LD_CORE_DEPLOYER");
    address internal ldOwner = makeAddr("LD_OWNER");

    constructor() {
        registry = new DelegationRegistry();

        vm.startPrank(ldDeployer);
        ld = new DelegateToken(
            address(registry),
            LibRLP.computeAddress(ldDeployer, vm.getNonce(ldDeployer) + 1),
            "",
            ldOwner
        );
        principal = new PrincipalToken(address(ld));
        vm.stopPrank();
    }
}
