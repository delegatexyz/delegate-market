// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ComputeAddress} from "../script/ComputeAddress.s.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {DelegateToken, IDelegateToken} from "src/DelegateToken.sol";
import {DTHarness} from "./utils/DTHarness.t.sol";
import {ExpiryType} from "src/interfaces/IWrapOfferer.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";
import {DelegateRegistry, IDelegateRegistry} from "delegate-registry/src/DelegateRegistry.sol";
import {MockERC721, MockERC20, MockERC1155} from "./mock/MockTokens.t.sol";

contract DelegateTokenTest is Test {
    DelegateRegistry reg;
    DelegateToken dt;
    PrincipalToken pt;
    DTHarness dtHarness;
    PrincipalToken ptShadow;
    MockERC721 mock721;
    MockERC20 mock20;
    MockERC1155 mock1155;

    address dtOwner = address(42);

    string baseURI = "https://metadata.delegate.cash/liquid/";

    function setUp() public {
        reg = new DelegateRegistry();
        dt = new DelegateToken(
            address(reg),
            ComputeAddress.addressFrom(address(this), vm.getNonce(address(this)) + 1),
            baseURI,
            dtOwner
        );
        pt = new PrincipalToken(
            address(dt)
        );

        dtHarness = new DTHarness(
            address(reg),
            ComputeAddress.addressFrom(address(this), vm.getNonce(address(this)) + 1),
            baseURI,
            dtOwner
        );
        ptShadow = new PrincipalToken(
            address(dtHarness)
        );

        mock721 = new MockERC721(0);
        mock20 = new MockERC20();
        mock1155 = new MockERC1155();
    }

    function testDTConstantsAndInitialStateVars() public {
        assertEq(dt.flashLoanCallBackSuccess(), bytes32(uint256(keccak256("INFTFlashBorrower.onFlashLoan")) - 1));
        assertEq(dt.delegateRegistry(), address(reg));
        assertEq(dt.principalToken(), address(pt));
        assertEq(dt.baseURI(), baseURI);
        assertEq(dtHarness.exposedDelegateTokenInfo(0, 0), 1);
        assertEq(dtHarness.exposedDelegateTokenInfo(0, 1), 2);
        assertEq(dtHarness.exposedDelegateTokenInfo(0, 2), 3);
        vm.expectRevert();
        dtHarness.exposedDelegateTokenInfo(0, 3);
        assertEq(dtHarness.exposedStoragePositionsMin(), 0);
        assertEq(dtHarness.exposedStoragePositionsMax(), 2);
        assertEq(dtHarness.exposedMaxExpiry(), type(uint256).max >> 160);
        assertEq(dtHarness.exposedDelegateTokenIdAvailable(), 0);
        assertEq(dtHarness.exposedDelegateTokenIdUsed(), 1);
        assertEq(dtHarness.exposedApproveAllDisabled(), 0);
        assertEq(dtHarness.exposedApproveAllEnabled(), 1);
        assertEq(dtHarness.exposedRescindAddress(), address(1));
        // Check slots
        assertEq(dtHarness.exposedSlotUint256(0), 1); // OpenZep reentrancy guard (not entered)
        assertEq(dtHarness.exposedSlotUint256(1), uint256(uint160(dtOwner))); // OpenZep ownable2step owner
        assertEq(dtHarness.exposedSlotUint256(2), 0); // OpenZep ownable2Step pending owner
        assertEq(dtHarness.exposedSlotUint256(3), 0); // OpenZep 4626 defaultRoyaltyInfo
        assertEq(dtHarness.exposedSlotUint256(4), 0); // OpenZep 4626 royaltyInfo mapping
        // Skip slot 5 as this is baseURI
        assertEq(dtHarness.exposedSlotUint256(6), 0); // delegateTokenInfo mapping
        assertEq(dtHarness.exposedSlotUint256(7), 0); // balances mapping
        assertEq(dtHarness.exposedSlotUint256(8), 0); // approvals mappings
    }

    function testDTConstructor(address delegateRegistry, address principalToken, string calldata baseURI_, address initialMetadataOwner) public {
        vm.assume(delegateRegistry != address(0) && principalToken != address(0) && initialMetadataOwner != address(0));
        // Check zero reverts
        vm.expectRevert(IDelegateToken.DelegateRegistryZero.selector);
        new DelegateToken(address(0), principalToken, baseURI_, initialMetadataOwner);
        vm.expectRevert(IDelegateToken.PrincipalTokenZero.selector);
        new DelegateToken(delegateRegistry, address(0), baseURI_, initialMetadataOwner);
        vm.expectRevert(IDelegateToken.InitialMetadataOwnerZero.selector);
        new DelegateToken(delegateRegistry, principalToken, baseURI_, address(0));
        // Check successful constructor
        dt = new DelegateToken(delegateRegistry, principalToken, baseURI_, initialMetadataOwner);
        assertEq(delegateRegistry, dt.delegateRegistry());
        assertEq(principalToken, dt.principalToken());
        assertEq(baseURI_, dt.baseURI());
        assertEq(initialMetadataOwner, dt.owner());
    }

    function testTokenReceiverMethods(address operator, address from, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data) public {
        if (ids.length > 0 && amounts.length > 0) {
            assertEq(dt.onERC1155Received(operator, from, ids[0], amounts[0], data), bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)")));
        }
        if (ids.length == 1 && amounts.length == 1) {
            assertEq(
                dt.onERC1155BatchReceived(operator, from, ids, amounts, data), bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))
            );
        } else {
            assertEq(dt.onERC1155BatchReceived(operator, from, ids, amounts, data), 0);
        }
    }

    function testBalanceOf(address delegateTokenHolder, uint256 balance) public {
        // Check zero address revert
        if (delegateTokenHolder == address(0)) {
            vm.expectRevert(IDelegateToken.DelegateTokenHolderZero.selector);
            dt.balanceOf(delegateTokenHolder);
        } else {
            // Check balance is stored correctly, mapping is at slot 7
            vm.store(address(dt), keccak256(abi.encode(delegateTokenHolder, 7)), bytes32(balance));
            assertEq(dt.balanceOf(delegateTokenHolder), balance);
        }
    }
}
