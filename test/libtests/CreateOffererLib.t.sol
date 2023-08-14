// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {CreateOffererModifiers as Modifiers, CreateOffererEnums as Enums, CreateOffererErrors as Errors} from "src/libraries/CreateOffererLib.sol";

contract ModifierTester is Modifiers {
    constructor(address seaport, Enums.Stage firstStage) Modifiers(seaport, firstStage) {}

    function onlySeaportForParameter(address parameter) external onlySeaport(parameter) {}

    function onlySeaportForCaller() external onlySeaport(msg.sender) {}

    function parameterizedStage(Enums.Stage currentStage, Enums.Stage nextStage) public checkStage(currentStage, nextStage) {
        _checkLocked();
    }

    function reenterParametrizedStage(Enums.Stage currentStage, Enums.Stage nextStage, Enums.Stage randomStage1, Enums.Stage randomStage2)
        external
        checkStage(currentStage, nextStage)
    {
        _checkLocked();
        parameterizedStage(randomStage1, randomStage2);
    }

    function _checkLocked() internal view {
        uint256 lock;
        assembly {
            lock := shr(8, sload(0))
        }
        require(lock == uint256(Enums.Lock.locked), "lock invariant");
    }
}

contract CreateOffererModifiersTest is Test {
    ModifierTester modifierTester;

    function setUp() public {
        modifierTester = new ModifierTester(address(42), Enums.Stage.none);
    }

    function testModifiersConstructor(address seaport, uint256 seed) public {
        vm.assume(seaport != address(0));
        modifierTester = new ModifierTester(seaport, createRandomStage(seed));
        assertEq(modifierTester.seaport(), seaport);
        assertStageValues(address(modifierTester), createRandomStage(seed), Enums.Lock.unlocked);
    }

    function testModifiersConstructorReverts() public {
        vm.expectRevert(Errors.SeaportIsZero.selector);
        new ModifierTester(address(0), Enums.Stage.none);
    }

    function testOnlySeaportForParameter(address seaport, address parameter) public {
        vm.assume(seaport != address(0));
        modifierTester = new ModifierTester(seaport, Enums.Stage.none);
        if (parameter != seaport) {
            vm.expectRevert(abi.encodeWithSelector(Errors.CallerNotSeaport.selector, parameter));
        }
        modifierTester.onlySeaportForParameter(parameter);
    }

    function testOnlySeaportForCaller(address seaport, address caller) public {
        vm.assume(seaport != address(0));
        modifierTester = new ModifierTester(seaport, Enums.Stage.none);
        vm.startPrank(caller);
        if (caller != seaport) {
            vm.expectRevert(abi.encodeWithSelector(Errors.CallerNotSeaport.selector, caller));
        }
        modifierTester.onlySeaportForCaller();
        vm.stopPrank();
    }

    function testSuccessfulStageTransition(address seaport, uint256 seed1, uint256 seed2) public {
        vm.assume(seaport != address(0));
        Enums.Stage currentStage = createRandomStage(seed1);
        Enums.Stage nextStage = createRandomStage(seed2);
        modifierTester = new ModifierTester(seaport, currentStage);
        assertStageValues(address(modifierTester), currentStage, Enums.Lock.unlocked);
        modifierTester.parameterizedStage(currentStage, nextStage);
        assertStageValues(address(modifierTester), nextStage, Enums.Lock.unlocked);
    }

    function testStageReentrancyProtection(address seaport, uint256 seed1, uint256 seed2, uint256 seed3, uint256 seed4) public {
        vm.assume(seaport != address(0));
        Enums.Stage currentStage = createRandomStage(seed1);
        Enums.Stage nextStage = createRandomStage(seed2);
        Enums.Stage randomStage1 = createRandomStage(seed3);
        Enums.Stage randomStage2 = createRandomStage(seed4);
        modifierTester = new ModifierTester(seaport, currentStage);
        assertStageValues(address(modifierTester), currentStage, Enums.Lock.unlocked);
        vm.expectRevert(Errors.Locked.selector);
        modifierTester.reenterParametrizedStage(currentStage, nextStage, randomStage1, randomStage2);
    }

    function testWrongStageRevert(address seaport, uint256 seed1, uint256 seed2) public {
        vm.assume(seaport != address(0));
        Enums.Stage currentStage = createRandomStage(seed1);
        Enums.Stage wrongStage = createRandomStage(seed2);
        vm.assume(currentStage != wrongStage);
        modifierTester = new ModifierTester(seaport, currentStage);
        assertStageValues(address(modifierTester), currentStage, Enums.Lock.unlocked);
        vm.expectRevert(abi.encodeWithSelector(Errors.WrongStage.selector, wrongStage, currentStage));
        modifierTester.parameterizedStage(wrongStage, currentStage);
    }

    function testMultipleStageTransitions(address seaport, uint256 seed1, uint256 seed2, uint256 seed3, uint256 seed4) public {
        vm.assume(seaport != address(0));
        Enums.Stage stage1 = createRandomStage(seed1);
        Enums.Stage stage2 = createRandomStage(seed2);
        Enums.Stage stage3 = createRandomStage(seed3);
        Enums.Stage stage4 = createRandomStage(seed4);
        modifierTester = new ModifierTester(seaport, stage1);
        assertStageValues(address(modifierTester), stage1, Enums.Lock.unlocked);
        modifierTester.parameterizedStage(stage1, stage2);
        assertStageValues(address(modifierTester), stage2, Enums.Lock.unlocked);
        modifierTester.parameterizedStage(stage2, stage3);
        assertStageValues(address(modifierTester), stage3, Enums.Lock.unlocked);
        modifierTester.parameterizedStage(stage3, stage4);
        assertStageValues(address(modifierTester), stage4, Enums.Lock.unlocked);
        modifierTester.parameterizedStage(stage4, stage1);
        assertStageValues(address(modifierTester), stage1, Enums.Lock.unlocked);
        modifierTester.parameterizedStage(stage1, stage1);
        assertStageValues(address(modifierTester), stage1, Enums.Lock.unlocked);
    }

    function createRandomStage(uint256 seed) internal pure returns (Enums.Stage) {
        if (seed % 4 == 0) return Enums.Stage.none;
        if (seed % 4 == 1) return Enums.Stage.generate;
        if (seed % 4 == 2) return Enums.Stage.transfer;
        else return Enums.Stage.ratify;
    }

    function assertStageValues(address modifierTesterAddress, Enums.Stage stage, Enums.Lock lock) internal {
        bytes32 stageSlot = vm.load(modifierTesterAddress, 0);
        assertEq(uint8(uint256(stageSlot)), uint8(stage));
        assertEq(uint8(uint256(stageSlot >> 8)), uint8(lock));
        assertEq(uint256(stageSlot >> 16), 0);
    }
}
