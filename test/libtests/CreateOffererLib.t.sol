// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {SpentItem, ReceivedItem} from "seaport/contracts/interfaces/ContractOffererInterface.sol";
import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {ItemType} from "seaport/contracts/lib/ConsiderationEnums.sol";
import {BaseLiquidDelegateTest, DelegateTokenStructs} from "test/base/BaseLiquidDelegateTest.t.sol";
import {DelegateTokenErrors} from "src/libraries/DelegateTokenErrors.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";
import {
    CreateOffererModifiers as Modifiers,
    CreateOffererEnums as Enums,
    CreateOffererErrors as Errors,
    CreateOffererStructs as Structs,
    CreateOffererHelpers as Helpers
} from "src/libraries/CreateOffererLib.sol";

import {console2} from "forge-std/console2.sol";

contract CreateOffererTestHelpers {
    function _createRandomValidDelegationType(uint256 seed) internal pure returns (IDelegateRegistry.DelegationType) {
        if (seed % 3 == 0) return IDelegateRegistry.DelegationType.ERC721;
        if (seed % 3 == 1) return IDelegateRegistry.DelegationType.ERC20;
        return IDelegateRegistry.DelegationType.ERC1155;
    }

    function _createRandomValidDelegationTypeAndItemType(uint256 seed) internal pure returns (IDelegateRegistry.DelegationType delegationType, ItemType itemType) {
        delegationType = _createRandomValidDelegationType(seed);
        if (delegationType == IDelegateRegistry.DelegationType.ERC721) itemType = ItemType.ERC721;
        else if (delegationType == IDelegateRegistry.DelegationType.ERC20) itemType = ItemType.ERC20;
        else itemType = ItemType.ERC1155;
    }

    function _createRandomTargetToken(uint256 seed) internal pure returns (Enums.TargetToken) {
        if (seed % 3 == 0) return Enums.TargetToken.none;
        else if (seed % 3 == 1) return Enums.TargetToken.principal;
        else return Enums.TargetToken.delegate;
    }

    function _createRandomExpiryType(uint256 seed) internal pure returns (Enums.ExpiryType) {
        if (seed % 3 == 0) return Enums.ExpiryType.none;
        if (seed % 3 == 1) return Enums.ExpiryType.relative;
        else return Enums.ExpiryType.absolute;
    }
}

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

contract CreateOffererModifiersTest is Test, CreateOffererTestHelpers {
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

contract HelpersCalldataHarness {
    Structs.TransientState internal transientState_;

    function transientState() external view returns (Structs.TransientState memory) {
        return transientState_;
    }

    function updateTransientState(SpentItem calldata minimumReceived, SpentItem calldata maximumSpent, Structs.Context memory decodedContext) external {
        Structs.TransientState storage ptr = transientState_;
        Helpers.updateTransientState(ptr, minimumReceived, maximumSpent, decodedContext);
    }

    function verifyCreate(address delegateToken, SpentItem calldata offer, ReceivedItem calldata consideration, bytes calldata context) external {
        Helpers.verifyCreate(delegateToken, offer, consideration, context);
    }
}

contract CreateOffererHelpersTest is Test, CreateOffererTestHelpers {
    Structs.Receivers receivers;
    Structs.Nonce nonce;
    HelpersCalldataHarness harness;

    function setUp() public {
        harness = new HelpersCalldataHarness();
    }

    function testUpdateReceivers(address initialPT, address initialDT, address targetTokenReceiver, uint256 seed) public {
        receivers = Structs.Receivers({principal: initialPT, delegate: initialDT});
        Enums.TargetToken targetToken = _createRandomTargetToken(seed);
        if (targetToken == Enums.TargetToken.none) {
            vm.expectRevert(abi.encodeWithSelector(Errors.TargetTokenInvalid.selector, targetToken));
            Helpers.updateReceivers(receivers, targetTokenReceiver, targetToken);
        } else if (targetToken == Enums.TargetToken.principal) {
            Structs.Receivers memory updatedReceivers = Helpers.updateReceivers(receivers, targetTokenReceiver, targetToken);
            assertEq(updatedReceivers.principal, targetTokenReceiver);
            assertEq(updatedReceivers.delegate, initialDT);
            assertEq(receivers.principal, targetTokenReceiver);
            assertEq(receivers.delegate, initialDT);
        } else if (targetToken == Enums.TargetToken.delegate) {
            Structs.Receivers memory updatedReceivers = Helpers.updateReceivers(receivers, targetTokenReceiver, targetToken);
            assertEq(updatedReceivers.principal, initialPT);
            assertEq(updatedReceivers.delegate, targetTokenReceiver);
            assertEq(receivers.principal, initialPT);
            assertEq(receivers.delegate, targetTokenReceiver);
        }
    }

    function testProcessNonce(uint256 initialNonce) public {
        nonce.value = initialNonce;
        Helpers.processNonce(nonce, initialNonce);
        uint256 expectedNonce = initialNonce;
        unchecked {
            expectedNonce++;
        }
        assertEq(nonce.value, expectedNonce);
    }

    function testProcessNonceRevert(uint256 initialNonce, uint256 contractNonce) public {
        nonce.value = initialNonce;
        vm.assume(initialNonce != contractNonce);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidContractNonce.selector, initialNonce, contractNonce));
        Helpers.processNonce(nonce, contractNonce);
    }

    function testUpdateTransientStateERC721(uint256 seed, address token, uint256 tokenId, bytes32 rights, uint256 expiryLength, address ptReceiver, address dtReceiver)
        public
    {
        Structs.TransientState memory transientStateBefore = harness.transientState();
        SpentItem memory minimumReceived =
            SpentItem({itemType: ItemType.ERC721, token: address(this), identifier: seed << 8 | uint256(IDelegateRegistry.DelegationType.ERC721), amount: 1});
        SpentItem memory maximumSpent = SpentItem({itemType: ItemType.ERC721, token: token, identifier: tokenId, amount: 1});
        Structs.Context memory decodedContext = Structs.Context({
            rights: rights,
            signerSalt: uint256(keccak256(abi.encode("salt", seed))),
            expiryLength: expiryLength,
            expiryType: _createRandomExpiryType(uint256(keccak256(abi.encode("expiry", seed)))),
            targetToken: _createRandomTargetToken(uint256(keccak256(abi.encode("targetToken", seed)))),
            receivers: Structs.Receivers({delegate: dtReceiver, principal: ptReceiver})
        });
        harness.updateTransientState(minimumReceived, maximumSpent, decodedContext);
        assertEq(keccak256(abi.encode(transientStateBefore.erc20Order)), keccak256(abi.encode(harness.transientState().erc20Order)));
        assertEq(keccak256(abi.encode(transientStateBefore.erc1155Order)), keccak256(abi.encode(harness.transientState().erc1155Order)));
        assertEq(keccak256(abi.encode(harness.transientState().receivers)), keccak256(abi.encode(Structs.Receivers({delegate: dtReceiver, principal: ptReceiver}))));
        assertEq(
            keccak256(abi.encode(harness.transientState().erc721Order)),
            keccak256(
                abi.encode(
                    Structs.ERC721Order({
                        tokenId: tokenId,
                        info: Structs.Order({
                            rights: rights,
                            expiryLength: expiryLength,
                            signerSalt: decodedContext.signerSalt,
                            tokenContract: token,
                            expiryType: decodedContext.expiryType,
                            targetToken: decodedContext.targetToken
                        })
                    })
                )
            )
        );
    }

    function testUpdateTransientStateERC20(uint256 seed, address token, uint256 amount, bytes32 rights, uint256 expiryLength, address ptReceiver, address dtReceiver)
        public
    {
        Structs.TransientState memory transientStateBefore = harness.transientState();
        SpentItem memory minimumReceived =
            SpentItem({itemType: ItemType.ERC721, token: address(this), identifier: seed << 8 | uint256(IDelegateRegistry.DelegationType.ERC20), amount: 1});
        SpentItem memory maximumSpent = SpentItem({itemType: ItemType.ERC20, token: token, identifier: 1, amount: amount});
        Structs.Context memory decodedContext = Structs.Context({
            rights: rights,
            signerSalt: uint256(keccak256(abi.encode("salt", seed))),
            expiryLength: expiryLength,
            expiryType: _createRandomExpiryType(uint256(keccak256(abi.encode("expiry", seed)))),
            targetToken: _createRandomTargetToken(uint256(keccak256(abi.encode("targetToken", seed)))),
            receivers: Structs.Receivers({delegate: dtReceiver, principal: ptReceiver})
        });
        harness.updateTransientState(minimumReceived, maximumSpent, decodedContext);
        assertEq(keccak256(abi.encode(transientStateBefore.erc721Order)), keccak256(abi.encode(harness.transientState().erc721Order)));
        assertEq(keccak256(abi.encode(transientStateBefore.erc1155Order)), keccak256(abi.encode(harness.transientState().erc1155Order)));
        assertEq(keccak256(abi.encode(harness.transientState().receivers)), keccak256(abi.encode(Structs.Receivers({delegate: dtReceiver, principal: ptReceiver}))));
        assertEq(
            keccak256(abi.encode(harness.transientState().erc20Order)),
            keccak256(
                abi.encode(
                    Structs.ERC20Order({
                        amount: amount,
                        info: Structs.Order({
                            rights: rights,
                            expiryLength: expiryLength,
                            signerSalt: decodedContext.signerSalt,
                            tokenContract: token,
                            expiryType: decodedContext.expiryType,
                            targetToken: decodedContext.targetToken
                        })
                    })
                )
            )
        );
    }

    function testUpdateTransientStateERC1155(uint256 seed, address token, uint256 amount, bytes32 rights, uint256 expiryLength, address ptReceiver, address dtReceiver)
        public
    {
        Structs.TransientState memory transientStateBefore = harness.transientState();
        SpentItem memory minimumReceived =
            SpentItem({itemType: ItemType.ERC721, token: address(this), identifier: seed << 8 | uint256(IDelegateRegistry.DelegationType.ERC1155), amount: 1});
        SpentItem memory maximumSpent =
            SpentItem({itemType: ItemType.ERC1155, token: token, identifier: uint256(keccak256(abi.encode("identifier", seed))), amount: amount});
        Structs.Context memory decodedContext = Structs.Context({
            rights: rights,
            signerSalt: uint256(keccak256(abi.encode("salt", seed))),
            expiryLength: expiryLength,
            expiryType: _createRandomExpiryType(uint256(keccak256(abi.encode("expiry", seed)))),
            targetToken: _createRandomTargetToken(uint256(keccak256(abi.encode("targetToken", seed)))),
            receivers: Structs.Receivers({delegate: dtReceiver, principal: ptReceiver})
        });
        harness.updateTransientState(minimumReceived, maximumSpent, decodedContext);
        assertEq(keccak256(abi.encode(transientStateBefore.erc721Order)), keccak256(abi.encode(harness.transientState().erc721Order)));
        assertEq(keccak256(abi.encode(transientStateBefore.erc20Order)), keccak256(abi.encode(harness.transientState().erc20Order)));
        assertEq(keccak256(abi.encode(harness.transientState().receivers)), keccak256(abi.encode(Structs.Receivers({delegate: dtReceiver, principal: ptReceiver}))));
        assertEq(
            keccak256(abi.encode(harness.transientState().erc1155Order)),
            keccak256(
                abi.encode(
                    Structs.ERC1155Order({
                        tokenId: maximumSpent.identifier,
                        amount: amount,
                        info: Structs.Order({
                            rights: rights,
                            expiryLength: expiryLength,
                            signerSalt: decodedContext.signerSalt,
                            tokenContract: token,
                            expiryType: decodedContext.expiryType,
                            targetToken: decodedContext.targetToken
                        })
                    })
                )
            )
        );
    }

    function testUpdateTransientStateRevert(uint256 seed, address token, uint256 amount, bytes32 rights, uint256 expiryLength, address ptReceiver, address dtReceiver)
        public
    {
        Structs.TransientState memory transientStateBefore = harness.transientState();
        SpentItem memory minimumReceived =
            SpentItem({itemType: ItemType.ERC721, token: address(this), identifier: uint256(IDelegateRegistry.DelegationType.NONE), amount: 1});
        SpentItem memory maximumSpent =
            SpentItem({itemType: ItemType.ERC1155, token: token, identifier: uint256(keccak256(abi.encode("identifier", seed))), amount: amount});
        Structs.Context memory decodedContext = Structs.Context({
            rights: rights,
            signerSalt: uint256(keccak256(abi.encode("salt", seed))),
            expiryLength: expiryLength,
            expiryType: _createRandomExpiryType(uint256(keccak256(abi.encode("expiry", seed)))),
            targetToken: _createRandomTargetToken(uint256(keccak256(abi.encode("targetToken", seed)))),
            receivers: Structs.Receivers({delegate: dtReceiver, principal: ptReceiver})
        });
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTokenType.selector, IDelegateRegistry.DelegationType.NONE));
        harness.updateTransientState(minimumReceived, maximumSpent, decodedContext);
        minimumReceived.identifier = uint256(IDelegateRegistry.DelegationType.ALL);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTokenType.selector, IDelegateRegistry.DelegationType.ALL));
        harness.updateTransientState(minimumReceived, maximumSpent, decodedContext);
        minimumReceived.identifier = uint256(IDelegateRegistry.DelegationType.CONTRACT);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTokenType.selector, IDelegateRegistry.DelegationType.CONTRACT));
        harness.updateTransientState(minimumReceived, maximumSpent, decodedContext);
        assertEq(keccak256(abi.encode(transientStateBefore)), keccak256(abi.encode(harness.transientState())));
    }
}

contract CreateOffererDelegateTokenHelpers is Test, BaseLiquidDelegateTest, CreateOffererTestHelpers {
    HelpersCalldataHarness harness;

    function setUp() public {
        harness = new HelpersCalldataHarness();
    }

    function testCreateAndValidateDelegateTokenId(uint256 seed, bytes32 rights, address principalHolder, address delegateHolder) public {
        vm.assume(principalHolder != address(0) && delegateHolder != address(0));
        IDelegateRegistry.DelegationType tokenType = _createRandomValidDelegationType(seed);
        uint256 amount;
        uint256 tokenId;
        address token;
        if (tokenType == IDelegateRegistry.DelegationType.ERC721) {
            amount = 0;
            tokenId = uint256(keccak256(abi.encode("721tokenId", seed)));
            token = address(mockERC721);
            mockERC721.mint(address(this), tokenId);
            mockERC721.approve(address(dt), tokenId);
        } else if (tokenType == IDelegateRegistry.DelegationType.ERC20) {
            amount = uint256(keccak256(abi.encode("20amount", seed)));
            tokenId = 0;
            token = address(mockERC20);
            mockERC20.mint(address(this), amount);
            mockERC20.approve(address(dt), amount);
        } else {
            amount = uint256(keccak256(abi.encode("1155amount", seed)));
            tokenId = uint256(keccak256(abi.encode("1155tokenId", seed)));
            token = address(mockERC1155);
            mockERC1155.mint(address(this), tokenId, amount, "");
            mockERC1155.setApprovalForAll(address(dt), true);
        }
        DelegateTokenStructs.DelegateInfo memory delegateInfo = DelegateTokenStructs.DelegateInfo({
            principalHolder: principalHolder,
            tokenType: tokenType,
            delegateHolder: delegateHolder,
            amount: amount,
            tokenContract: token,
            tokenId: tokenId,
            rights: rights,
            expiry: block.timestamp + 100
        });
        Helpers.createAndValidateDelegateTokenId(address(dt), seed, delegateInfo);
    }

    function testCalculateOrderHashAndId(address targetTokenReceiver, address conduit, bytes memory orderInfo, uint256 seed) public {
        IDelegateRegistry.DelegationType tokenType = _createRandomValidDelegationType(seed);
        (uint256 calculatedOrderHash, uint256 calculatedDelegateId) = Helpers.calculateOrderHashAndId(address(dt), targetTokenReceiver, conduit, orderInfo, tokenType);
        assertEq(calculatedOrderHash, uint256(keccak256(abi.encode(targetTokenReceiver, conduit, orderInfo))) << 8 | uint256(tokenType));
        assertEq(
            calculatedDelegateId,
            uint256(keccak256(abi.encode(address(this), uint256(keccak256(abi.encode(targetTokenReceiver, conduit, orderInfo))) << 8 | uint256(tokenType))))
        );
    }

    function testCalculateOrderHashAndIdReverts(address targetTokenReceiver, address conduit, bytes memory orderInfo, uint256 seed, uint256 slotData) public {
        vm.assume(slotData > 1);
        IDelegateRegistry.DelegationType tokenType = _createRandomValidDelegationType(seed);
        (uint256 calculatedOrderHash, uint256 calculatedDelegateId) = Helpers.calculateOrderHashAndId(address(dt), targetTokenReceiver, conduit, orderInfo, tokenType);
        // Write storage slot in DelegateToken to cause a revert
        vm.store(address(dt), keccak256(abi.encode(calculatedDelegateId, 6)), bytes32(slotData));
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.AlreadyExisted.selector, calculatedDelegateId));
        (calculatedOrderHash, calculatedDelegateId) = Helpers.calculateOrderHashAndId(address(dt), targetTokenReceiver, conduit, orderInfo, tokenType);
    }

    function testCalculateOrderHashAndIdTypeCollisions(address targetTokenReceiver, address conduit, bytes memory orderInfo) public {
        (uint256 calculated721OrderHash, uint256 calculated721DelegateId) =
            Helpers.calculateOrderHashAndId(address(dt), targetTokenReceiver, conduit, orderInfo, IDelegateRegistry.DelegationType.ERC721);
        (uint256 calculated20OrderHash, uint256 calculated20DelegateId) =
            Helpers.calculateOrderHashAndId(address(dt), targetTokenReceiver, conduit, orderInfo, IDelegateRegistry.DelegationType.ERC20);
        (uint256 calculated1155OrderHash, uint256 calculated1155DelegateId) =
            Helpers.calculateOrderHashAndId(address(dt), targetTokenReceiver, conduit, orderInfo, IDelegateRegistry.DelegationType.ERC1155);
        assertNotEq(calculated721OrderHash, calculated721DelegateId);
        assertNotEq(calculated721OrderHash, calculated20OrderHash);
        assertNotEq(calculated721OrderHash, calculated20DelegateId);
        assertNotEq(calculated721OrderHash, calculated1155OrderHash);
        assertNotEq(calculated721OrderHash, calculated1155DelegateId);
        assertNotEq(calculated721DelegateId, calculated20OrderHash);
        assertNotEq(calculated721DelegateId, calculated20DelegateId);
        assertNotEq(calculated721DelegateId, calculated1155OrderHash);
        assertNotEq(calculated721DelegateId, calculated1155DelegateId);
        assertNotEq(calculated20OrderHash, calculated20DelegateId);
        assertNotEq(calculated20OrderHash, calculated1155OrderHash);
        assertNotEq(calculated20OrderHash, calculated1155DelegateId);
        assertNotEq(calculated20DelegateId, calculated1155OrderHash);
        assertNotEq(calculated20DelegateId, calculated1155DelegateId);
        assertNotEq(calculated1155OrderHash, calculated1155DelegateId);
    }

    function testCalculateOrderHashAndIdCollisions(
        address targetTokenReceiver,
        address notTargetTokenReceiver,
        address conduit,
        address searchConduit,
        bytes memory orderInfo,
        bytes memory searchOrderInfo,
        uint256 seed,
        uint256 searchSeed
    ) public {
        vm.assume(targetTokenReceiver != notTargetTokenReceiver);
        IDelegateRegistry.DelegationType tokenType = _createRandomValidDelegationType(seed);
        IDelegateRegistry.DelegationType searchTokenType = _createRandomValidDelegationType(searchSeed);
        (uint256 calculatedOrderHash, uint256 calculatedDelegateId) = Helpers.calculateOrderHashAndId(address(dt), targetTokenReceiver, conduit, orderInfo, tokenType);
        (uint256 searchCalculatedOrderHash, uint256 searchCalculatedDelegateId) =
            Helpers.calculateOrderHashAndId(address(dt), notTargetTokenReceiver, searchConduit, searchOrderInfo, searchTokenType);
        assertNotEq(calculatedOrderHash, searchCalculatedOrderHash);
        assertNotEq(calculatedOrderHash, searchCalculatedDelegateId);
        assertNotEq(calculatedOrderHash, calculatedDelegateId);
        assertNotEq(calculatedDelegateId, searchCalculatedDelegateId);
        assertNotEq(calculatedDelegateId, searchCalculatedOrderHash);
    }

    function testVerifyCreate(uint256 seed, address token, uint256 tokenId, uint256 amount, bytes32 rights, address ptReceiver, address dtReceiver) public {
        vm.assume(amount > 0);
        vm.assume(dtReceiver != address(0) && ptReceiver != address(0));
        (IDelegateRegistry.DelegationType tokenType, ItemType itemType) = _createRandomValidDelegationTypeAndItemType(seed);
        uint256 createOrderHash = seed << 8 | uint256(tokenType);
        SpentItem memory offer = SpentItem({itemType: ItemType.ERC721, token: address(harness), identifier: createOrderHash, amount: 1});
        ReceivedItem memory consideration = ReceivedItem({
            itemType: itemType,
            token: token,
            identifier: itemType != ItemType.ERC20 ? tokenId : 0,
            amount: itemType != ItemType.ERC721 ? amount : 1,
            recipient: payable(address(harness))
        });
        Structs.Context memory contextStruct = Structs.Context({
            rights: rights,
            signerSalt: seed,
            expiryLength: 10 ** 4,
            expiryType: Enums.ExpiryType.absolute,
            targetToken: Enums.TargetToken.delegate,
            receivers: Structs.Receivers({principal: ptReceiver, delegate: dtReceiver})
        });
        // Create delegation as DelegateToken and save
        vm.startPrank(address(dt));
        bytes32 registryHash;
        if (itemType == ItemType.ERC721) {
            registryHash = registry.delegateERC721(dtReceiver, token, tokenId, rights, true);
        } else if (itemType == ItemType.ERC20) {
            registryHash = registry.delegateERC20(dtReceiver, token, amount, rights, true);
        } else if (itemType == ItemType.ERC1155) {
            registryHash = registry.delegateERC1155(dtReceiver, token, tokenId, amount, rights, true);
        }
        vm.stopPrank();
        uint256 delegateTokenSlot = uint256(keccak256(abi.encode(keccak256(abi.encode(address(harness), createOrderHash)), 6))); // Setting delegate id to zero
            // here
        vm.store(address(dt), bytes32(delegateTokenSlot), registryHash);
        vm.store(address(dt), bytes32(delegateTokenSlot + 1), bytes32(uint256(10 ** 4)));
        if (itemType != ItemType.ERC721) {
            vm.store(address(dt), bytes32(delegateTokenSlot + 2), bytes32(amount));
        }
        // Override principal token bytecode with mock 721 and mint delegateId
        vm.etch(address(principal), address(mockERC721).code);
        PrincipalToken(principal).mint(ptReceiver, uint256(keccak256(abi.encode(address(harness), createOrderHash))));
        // Test
        harness.verifyCreate(address(dt), offer, consideration, abi.encode(contextStruct));
    }
}
