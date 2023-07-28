// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";

import {ComputeAddress} from "../../script/ComputeAddress.s.sol";

import {DelegateToken} from "src/DelegateToken.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";
import {DelegateRegistry} from "delegate-registry/src/DelegateRegistry.sol";

contract BaseLiquidDelegateTest is Test {
    DelegateRegistry internal registry;
    PrincipalToken internal principal;
    DelegateToken internal dt;

    address internal dtDeployer = makeAddr("DT_CORE_DEPLOYER");
    address internal dtOwner = makeAddr("DT_OWNER");

    constructor() {
        registry = new DelegateRegistry();

        vm.startPrank(dtDeployer);
        dt = new DelegateToken(
            address(registry),
            ComputeAddress.addressFrom(dtDeployer, vm.getNonce(dtDeployer) + 1),
            "",
            dtOwner
        );
        principal = new PrincipalToken(address(dt));
        vm.stopPrank();
    }
}