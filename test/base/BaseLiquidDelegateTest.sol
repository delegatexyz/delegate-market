// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {LibRLP} from "solady/utils/LibRLP.sol";

import {DelegateToken} from "src/DelegateToken.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";
import {DelegateRegistry} from "delegate-registry/src/DelegateRegistry.sol";

contract BaseLiquidDelegateTest is Test {
    DelegateRegistry internal registry;
    PrincipalToken internal principal;
    DelegateToken internal dt;

    address internal dtDeployer = makeAddr("LD_CORE_DEPLOYER");
    address internal dtOwner = makeAddr("LD_OWNER");

    constructor() {
        registry = new DelegateRegistry();

        vm.startPrank(dtDeployer);
        dt = new DelegateToken(
            address(registry),
            LibRLP.computeAddress(dtDeployer, vm.getNonce(dtDeployer) + 1),
            "",
            dtOwner
        );
        principal = new PrincipalToken(address(dt));
        vm.stopPrank();
    }
}
