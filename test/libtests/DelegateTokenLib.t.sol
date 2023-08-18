// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IDelegateFlashloan} from "src/interfaces/IDelegateFlashloan.sol";
import {ERC721Holder} from "openzeppelin/token/ERC721/utils/ERC721Holder.sol";
import {IDelegateRegistry, BaseLiquidDelegateTest, DelegateTokenStructs} from "test/base/BaseLiquidDelegateTest.t.sol";
import {DelegateTokenHelpers as Helpers, DelegateTokenErrors} from "src/libraries/DelegateTokenLib.sol";

contract CalldataHarness {
    function revertOnCallingInvalidFlashloan(DelegateTokenStructs.FlashInfo calldata info) external {
        Helpers.revertOnCallingInvalidFlashloan(info);
    }

    function revertOnInvalidERC721ReceiverCallback(address from, address to, uint256 delegateTokenId, bytes calldata data) external {
        Helpers.revertOnInvalidERC721ReceiverCallback(from, to, delegateTokenId, data);
    }

    function revertOnInvalidERC721ReceiverCallback(address from, address to, uint256 delegateTokenId) external {
        Helpers.revertOnInvalidERC721ReceiverCallback(from, to, delegateTokenId);
    }
}

contract ValidFlashloanContract is IDelegateFlashloan {
    function onFlashloan(address, DelegateTokenStructs.FlashInfo calldata) external payable returns (bytes32) {
        return IDelegateFlashloan.onFlashloan.selector;
    }
}

contract InValidFlashloanContract is IDelegateFlashloan {
    function onFlashloan(address, DelegateTokenStructs.FlashInfo calldata) external payable returns (bytes32) {
        return 0;
    }
}

contract InvalidERC721Holder is ERC721Holder {
    function onERC721Received(address, address, uint256, bytes memory) public pure override returns (bytes4) {
        return 0;
    }
}

contract DelegateTokenLibTest is Test, BaseLiquidDelegateTest {
    CalldataHarness harness;
    InValidFlashloanContract invalidFlashloan;
    ValidFlashloanContract validFlashloan;
    ERC721Holder erc721Holder;
    InvalidERC721Holder invalidERC721Holder;

    function setUp() public {
        harness = new CalldataHarness();
        invalidFlashloan = new InValidFlashloanContract();
        validFlashloan = new ValidFlashloanContract();
        erc721Holder = new ERC721Holder();
        invalidERC721Holder = new InvalidERC721Holder();
    }

    function testRevertOnCallingInvalidFlashloan(address random) internal {
        vm.assume(random != address(validFlashloan));
        vm.expectRevert(IDelegateFlashloan.InvalidFlashloan.selector);
        harness.revertOnCallingInvalidFlashloan(
            DelegateTokenStructs.FlashInfo({
                receiver: address(invalidFlashloan),
                delegateHolder: address(0),
                tokenType: IDelegateRegistry.DelegationType.NONE,
                tokenContract: address(0),
                tokenId: 0,
                amount: 0,
                data: ""
            })
        );
        vm.expectRevert(IDelegateFlashloan.InvalidFlashloan.selector);
        harness.revertOnCallingInvalidFlashloan(
            DelegateTokenStructs.FlashInfo({
                receiver: random,
                delegateHolder: address(0),
                tokenType: IDelegateRegistry.DelegationType.NONE,
                tokenContract: address(0),
                tokenId: 0,
                amount: 0,
                data: ""
            })
        );
    }

    function testNoRevertOnCallingInvalidFlashloan() internal {
        harness.revertOnCallingInvalidFlashloan(
            DelegateTokenStructs.FlashInfo({
                receiver: address(validFlashloan),
                delegateHolder: address(0),
                tokenType: IDelegateRegistry.DelegationType.NONE,
                tokenContract: address(0),
                tokenId: 0,
                amount: 0,
                data: ""
            })
        );
    }

    function testRevertOnInvalidERC721ReceiverCallback() public {
        vm.expectRevert(DelegateTokenErrors.NotERC721Receiver.selector);
        harness.revertOnInvalidERC721ReceiverCallback(address(0), address(invalidERC721Holder), 0, "");
        vm.expectRevert(DelegateTokenErrors.NotERC721Receiver.selector);
        harness.revertOnInvalidERC721ReceiverCallback(address(0), address(invalidERC721Holder), 0);
    }

    function testNoRevertOnInvalidERC721ReceiverCallback() public {
        harness.revertOnInvalidERC721ReceiverCallback(address(0), address(erc721Holder), 0, "");
        harness.revertOnInvalidERC721ReceiverCallback(address(0), address(erc721Holder), 0);
    }

    function testNoEOARevertOnInvalidERC721ReceiverCallback(address random) public {
        vm.assume(random.code.length == 0);
        harness.revertOnInvalidERC721ReceiverCallback(address(0), address(erc721Holder), 0, "");
        harness.revertOnInvalidERC721ReceiverCallback(address(0), address(erc721Holder), 0);
    }

    function testPastRevertInvalidExpiry(uint256 randomTime, uint256 expiry) public {
        vm.warp(randomTime);
        vm.assume(expiry < randomTime);
        vm.expectRevert(DelegateTokenErrors.ExpiryInPast.selector);
        Helpers.revertInvalidExpiry(expiry);
    }

    function testNoRevertInvalidExpiry(uint256 randomTime, uint256 expiry) public {
        vm.assume(randomTime < type(uint96).max);
        vm.warp(randomTime);
        vm.assume(expiry <= type(uint96).max && expiry >= randomTime);
        Helpers.revertInvalidExpiry(expiry);
    }

    function testLargeRevertInvalidExpiry(uint256 expiry) public {
        vm.warp(0);
        vm.assume(expiry > type(uint96).max);
        vm.expectRevert(DelegateTokenErrors.ExpiryTooLarge.selector);
        Helpers.revertInvalidExpiry(expiry);
    }

    function testRevertInvalidERC721TransferOperator(address operator) public {
        vm.assume(address(this) != operator);
        vm.expectRevert(DelegateTokenErrors.InvalidERC721TransferOperator.selector);
        Helpers.revertInvalidERC721TransferOperator(operator);
    }

    function testNoRevertInvalidERC721TransferOperator() public view {
        Helpers.revertInvalidERC721TransferOperator(address(this));
    }

    function testAvailableRevertNotMinted(uint256 id) public {
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, id));
        Helpers.revertNotMinted(0, id);
    }

    function testUsedRevertNotMinted(uint256 id) public {
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, id));
        Helpers.revertNotMinted(bytes32(uint256(1)), id);
    }

    function testNoRevertNotMinted(bytes32 random, uint256 id) public pure {
        vm.assume(uint256(random) != 0 && uint256(random) != 1);
        Helpers.revertNotMinted(random, id);
    }

    function testRevertToIsZero(address to) public {
        if (to == address(0)) {
            vm.expectRevert(DelegateTokenErrors.ToIsZero.selector);
        }
        Helpers.revertToIsZero(to);
    }

    function testRevertDelegateTokenHolderZero(address delegateTokenHolder) public {
        if (delegateTokenHolder == address(0)) {
            vm.expectRevert(DelegateTokenErrors.DelegateTokenHolderZero.selector);
        }
        Helpers.revertDelegateTokenHolderZero(delegateTokenHolder);
    }

    function testRevertFromNotDelegateTokenHolder(address from, address delegateTokenHolder) public {
        if (delegateTokenHolder != from) {
            vm.expectRevert(DelegateTokenErrors.FromNotDelegateTokenHolder.selector);
        }
        Helpers.revertFromNotDelegateTokenHolder(from, delegateTokenHolder);
    }

    function revertBatchERC1155TransferUnsupported() public {
        vm.expectRevert(DelegateTokenErrors.BatchERC1155TransferUnsupported.selector);
        Helpers.revertBatchERC1155TransferUnsupported();
    }

    function testDelegateId(address caller, uint256 salt) public {
        assertEq(uint256(keccak256(abi.encode(caller, salt))), Helpers.delegateId(caller, salt));
    }

    function testDelegateIdCollisions(address caller, address notCaller, uint256 salt, uint256 searchSalt) public {
        vm.assume(caller != notCaller);
        assertNotEq(Helpers.delegateId(caller, salt), Helpers.delegateId(notCaller, searchSalt));
    }
}
