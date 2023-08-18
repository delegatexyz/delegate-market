// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {DelegateTokenErrors, DelegateTokenConstants} from "src/libraries/DelegateTokenLib.sol";
import {DTHarness} from "./utils/DTHarness.t.sol";
import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";
import {ERC721Holder} from "openzeppelin/token/ERC721/utils/ERC721Holder.sol";
import {IERC721Metadata} from "openzeppelin/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC2981} from "openzeppelin/interfaces/IERC2981.sol";
import {IERC165} from "openzeppelin/utils/introspection/IERC165.sol";
import {IERC1155Receiver} from "openzeppelin/token/ERC1155/IERC1155Receiver.sol";

import {
    PrincipalToken,
    DelegateToken,
    MarketMetadata,
    DelegateTokenStructs,
    BaseLiquidDelegateTest,
    ComputeAddress,
    IDelegateRegistry
} from "test/base/BaseLiquidDelegateTest.t.sol";

contract DelegateTokenTest is Test, BaseLiquidDelegateTest {
    DTHarness dtHarness;
    PrincipalToken ptShadow;

    function setUp() public {
        DelegateTokenStructs.DelegateTokenParameters memory delegateTokenParameters = DelegateTokenStructs.DelegateTokenParameters({
            delegateRegistry: address(registry),
            principalToken: ComputeAddress.addressFrom(address(this), vm.getNonce(address(this)) + 1),
            marketMetadata: address(marketMetadata)
        });
        delegateTokenParameters.principalToken = ComputeAddress.addressFrom(address(this), vm.getNonce(address(this)) + 1);
        dtHarness = new DTHarness(delegateTokenParameters);
        ptShadow = new PrincipalToken(
            address(dtHarness),
            address(marketMetadata)
        );
    }

    function testDTConstantsAndInitialStateVars() public {
        assertEq(dt.delegateRegistry(), address(registry));
        assertEq(dt.principalToken(), address(principal));
        assertEq(dt.baseURI(), baseURI);
        assertEq(dtHarness.exposedDelegateTokenInfo(0, 0), 1);
        assertEq(dtHarness.exposedDelegateTokenInfo(0, 1), 2);
        assertEq(dtHarness.exposedDelegateTokenInfo(0, 2), 3);
        vm.expectRevert();
        dtHarness.exposedDelegateTokenInfo(0, 3);
        // Check slots
        assertEq(dtHarness.exposedSlotUint256(0), 1); // OpenZep reentrancy guard (not entered)
        // Skip slot 1 as this is baseURI
        assertEq(dtHarness.exposedSlotUint256(1), 0); // delegateTokenInfo mapping
        assertEq(dtHarness.exposedSlotUint256(2), 0); // balances mapping
        assertEq(dtHarness.exposedSlotUint256(3), 0); // approvals mappings
    }

    function testDTConstructor(address delegateRegistry, address principalToken, string calldata baseURI_, address initialMetadataOwner) public {
        vm.assume(delegateRegistry != address(0) && principalToken != address(0) && initialMetadataOwner != address(0));
        marketMetadata = new MarketMetadata(initialMetadataOwner, baseURI_);
        // Check zero reverts
        vm.expectRevert(DelegateTokenErrors.DelegateRegistryZero.selector);
        new DelegateToken(DelegateTokenStructs.DelegateTokenParameters({
            delegateRegistry: address(0), 
            principalToken: principalToken, 
            marketMetadata: address(marketMetadata)
            }));
        vm.expectRevert(DelegateTokenErrors.PrincipalTokenZero.selector);
        new DelegateToken(DelegateTokenStructs.DelegateTokenParameters({
            delegateRegistry: delegateRegistry, 
            principalToken: address(0), 
            marketMetadata: address(marketMetadata)
            }));
        vm.expectRevert(DelegateTokenErrors.InitialMetadataOwnerZero.selector);
        new DelegateToken(DelegateTokenStructs.DelegateTokenParameters({
            delegateRegistry: delegateRegistry, 
            principalToken: principalToken, 
            marketMetadata: address(0)
            }));
        // Check successful constructor
        dt =
        new DelegateToken(DelegateTokenStructs.DelegateTokenParameters({delegateRegistry: delegateRegistry, principalToken: principalToken, marketMetadata: address(marketMetadata)}));
        assertEq(delegateRegistry, dt.delegateRegistry());
        assertEq(principalToken, dt.principalToken());
        assertEq(baseURI_, dt.baseURI());
        // assertEq(initialMetadataOwner, dt.owner());
    }

    function testSupportsInterface(bytes32 interfaceSeed) public {
        vm.assume(uint256(interfaceSeed) <= 0xFFFFFFFF);
        bytes4 randomInterface;
        if (
            randomInterface == type(IERC2981).interfaceId || randomInterface == type(IERC165).interfaceId || randomInterface == type(IERC721).interfaceId
                || randomInterface == type(IERC721Metadata).interfaceId || randomInterface == type(IERC1155Receiver).interfaceId
        ) {
            assertTrue(dt.supportsInterface(randomInterface));
        } else {
            assertFalse(dt.supportsInterface(randomInterface));
        }
    }

    function testSupportedInterfaces() public {
        assertTrue(dt.supportsInterface(type(IERC2981).interfaceId));
        assertTrue(dt.supportsInterface(type(IERC165).interfaceId));
        assertTrue(dt.supportsInterface(type(IERC721).interfaceId));
        assertTrue(dt.supportsInterface(type(IERC721Metadata).interfaceId));
        assertTrue(dt.supportsInterface(type(IERC1155Receiver).interfaceId));
    }

    function testOnERC1155BatchReceived(address addr1, address addr2, uint256[] memory data, uint256[] memory data2, bytes memory data3) public {
        vm.expectRevert(DelegateTokenErrors.BatchERC1155TransferUnsupported.selector);
        dt.onERC1155BatchReceived(addr1, addr2, data, data2, data3);
    }

    function testRevertOnERC721Received(address operator, address addr1, uint256 data, bytes calldata data2) public {
        vm.assume(address(dt) != operator);
        vm.expectRevert(DelegateTokenErrors.InvalidERC721TransferOperator.selector);
        dt.onERC721Received(operator, addr1, data, data2);
    }

    function testOnERC721Received(address addr1, uint256 data, bytes calldata data2) public {
        assertEq(bytes4(dt.onERC721Received(address(dt), addr1, data, data2)), bytes4(0x150b7a02));
    }

    function testBalanceOf(address delegateTokenHolder, uint256 balance) public {
        // Check zero address revert
        if (delegateTokenHolder == address(0)) {
            vm.expectRevert(DelegateTokenErrors.DelegateTokenHolderZero.selector);
            dt.balanceOf(delegateTokenHolder);
        } else {
            // Check balance is stored correctly, mapping is at slot 2
            vm.store(address(dt), keccak256(abi.encode(delegateTokenHolder, 2)), bytes32(balance));
            assertEq(dt.balanceOf(delegateTokenHolder), balance);
        }
    }

    function testOwnerOf(address delegateTokenHolder, uint256 delegateTokenId, bytes32 rights) public {
        // Check zero address revert
        vm.expectRevert(DelegateTokenErrors.DelegateTokenHolderZero.selector);
        dt.ownerOf(delegateTokenId);
        // Create registry delegation
        vm.prank(address(dt));
        bytes32 registryHash = registry.delegateAll(delegateTokenHolder, rights, true);
        // Store registryHash at expected location, mapping is a slot 1
        vm.store(address(dt), keccak256(abi.encode(delegateTokenId, 1)), registryHash);
        if (delegateTokenHolder == address(0)) {
            vm.expectRevert(DelegateTokenErrors.DelegateTokenHolderZero.selector);
            dt.ownerOf(delegateTokenId);
        } else {
            assertEq(delegateTokenHolder, dt.ownerOf(delegateTokenId));
        }
    }

    function testSafeTransferFromReverts(address from, address to, bytes32 rights, uint256 expiry) public {
        vm.assume(expiry > block.timestamp && expiry <= type(uint96).max);
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(address(dt) != from);
        vm.startPrank(from);
        mockERC721.mintNext(from);
        mockERC721.approve(address(dt), 0);
        uint256 delegateTokenId =
            dt.create(DelegateTokenStructs.DelegateInfo(from, IDelegateRegistry.DelegationType.ERC721, from, 0, address(mockERC721), 0, rights, expiry), 1);
        vm.stopPrank();
        if (to.code.length != 0) {
            vm.expectRevert();
            vm.prank(from);
            dt.safeTransferFrom(from, to, delegateTokenId);
            // Create mock 721 holder and should no longer revert
            ERC721Holder erc721Holder = new ERC721Holder();
            vm.prank(from);
            dt.safeTransferFrom(from, address(erc721Holder), delegateTokenId);
        } else {
            vm.prank(from);
            dt.safeTransferFrom(from, to, delegateTokenId);
        }
    }

    function testSafeTransferFromWithDataReverts(address from, address to, bytes32 rights, uint256 expiry, bytes calldata data) public {
        vm.assume(expiry > block.timestamp && expiry <= type(uint96).max);
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(address(dt) != from);
        vm.startPrank(from);
        mockERC721.mintNext(from);
        mockERC721.approve(address(dt), 0);
        uint256 delegateTokenId =
            dt.create(DelegateTokenStructs.DelegateInfo(from, IDelegateRegistry.DelegationType.ERC721, from, 0, address(mockERC721), 0, rights, expiry), 1);
        vm.stopPrank();
        if (to.code.length != 0) {
            vm.expectRevert();
            vm.prank(from);
            dt.safeTransferFrom(from, to, delegateTokenId, data);
            // Create mock 721 holder and should no longer revert
            ERC721Holder erc721Holder = new ERC721Holder();
            vm.prank(from);
            dt.safeTransferFrom(from, address(erc721Holder), delegateTokenId, data);
        } else {
            vm.prank(from);
            dt.safeTransferFrom(from, to, delegateTokenId, data);
        }
    }

    event Approval(address indexed owner_, address indexed approved_, uint256 indexed tokenId_);

    function testApprove(address searchDelegateTokenHolder, address delegateTokenHolder, address spender, bytes32 rights, uint256 delegateTokenId, uint256 randomData)
        public
    {
        vm.assume(searchDelegateTokenHolder != delegateTokenHolder);
        // Create delegation
        vm.prank(address(dt));
        bytes32 registryHash = registry.delegateAll(delegateTokenHolder, rights, true);
        // Store registryHash at expected location, mapping is at slot 1
        vm.store(address(dt), keccak256(abi.encode(delegateTokenId, 1)), registryHash);
        // Expect revert if caller is not delegateTokenHolder
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotOperator.selector, searchDelegateTokenHolder, delegateTokenHolder));
        vm.prank(searchDelegateTokenHolder);
        dt.approve(spender, delegateTokenId);
        // Store dirty bits at approve location
        vm.store(address(dt), bytes32(uint256(keccak256(abi.encode(delegateTokenId, 1))) + 1), bytes32(randomData));
        vm.startPrank(delegateTokenHolder);
        vm.expectEmit(true, true, true, true, address(dt));
        emit Approval(delegateTokenHolder, spender, delegateTokenId);
        dt.approve(spender, delegateTokenId);
        vm.stopPrank();
        // Check that dirty bits in expiry location are preserved and spender matches
        uint256 approveSlot = uint256(vm.load(address(dt), bytes32(uint256(keccak256(abi.encode(delegateTokenId, 1))) + 1)));
        assertEq(approveSlot << 160, randomData << 160);
        assertEq(approveSlot >> 96, uint160(spender));
        // Check that no revert happens if searchDelegateTokenHolder is authorized operator
        vm.prank(delegateTokenHolder);
        dt.setApprovalForAll(searchDelegateTokenHolder, true);
        vm.prank(searchDelegateTokenHolder);
        dt.approve(spender, delegateTokenId);
    }

    event ApprovalForAll(address indexed owner_, address indexed operator_, bool approved_);

    function testApprovalForAll(address from, address operator, bool approve) public {
        vm.startPrank(from);
        vm.expectEmit(true, true, true, true, address(dt));
        emit ApprovalForAll(from, operator, approve);
        dt.setApprovalForAll(operator, approve);
        vm.stopPrank();
        // Load approvals slot and check it has been set correctly, approvals mapping is at slot 3
        uint256 approvalSlot = uint256(vm.load(address(dt), keccak256(abi.encode(operator, keccak256(abi.encode(from, 3))))));
        assertEq(approvalSlot >> 1, 0);
        if (approve) {
            assertEq(approvalSlot, 1);
        } else {
            assertEq(approvalSlot, 0);
        }
    }

    function testGetApproved(address from, address approved, bytes32 rights, uint256 delegateTokenId, uint256 dirtyBits) public {
        // Test revert if not minted
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, delegateTokenId));
        dt.getApproved(delegateTokenId);
        // Store registryHash at expected location, mapping is at slot 1
        vm.prank(address(dt));
        bytes32 registryHash = registry.delegateAll(from, rights, true);
        vm.store(address(dt), keccak256(abi.encode(delegateTokenId, 1)), registryHash);
        // Expect zero address return now
        assertEq(dt.getApproved(delegateTokenId), address(0));
        // Assign slot with dirty bits for expiry space
        vm.store(address(dt), bytes32(uint256(keccak256(abi.encode(delegateTokenId, 1))) + 1), bytes32((uint256(uint160(approved)) << 96) | (dirtyBits >> 160)));
        assertEq(dt.getApproved(delegateTokenId), approved);
    }

    function testIsApprovedForAll(address from, address operator, uint256 approve) public {
        vm.assume(approve <= 1);
        // Store test approval, approvals mapping is at slot 3
        vm.store(address(dt), keccak256(abi.encode(operator, keccak256(abi.encode(from, 3)))), bytes32(approve));
        if (approve == 0) assertFalse(dt.isApprovedForAll(from, operator));
        else assertTrue(dt.isApprovedForAll(from, operator));
    }

    function testTransferFromReverts(address from, address searchFrom, uint256 searchTokenId, address to, bytes32 rights, uint256 expiry, bytes calldata data) public {
        vm.assume(expiry > block.timestamp && expiry <= type(uint96).max);
        vm.assume(from != searchFrom);
        vm.assume(searchFrom != address(0));
        vm.assume(from != address(0));
        vm.assume(address(dt) != from);
        vm.startPrank(from);
        mockERC721.mintNext(from);
        mockERC721.approve(address(dt), 0);
        uint256 delegateTokenId =
            dt.create(DelegateTokenStructs.DelegateInfo(from, IDelegateRegistry.DelegationType.ERC721, from, 0, address(mockERC721), 0, rights, expiry), 1);
        vm.stopPrank();
        // Should revert if to is zero
        if (to == address(0)) {
            vm.expectRevert(DelegateTokenErrors.ToIsZero.selector);
            vm.prank(from);
            dt.safeTransferFrom(from, to, delegateTokenId, data);
        }
        // Should revert if invalid tokenId
        if (delegateTokenId != searchTokenId && to != address(0)) {
            vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, searchTokenId));
            vm.prank(from);
            dt.safeTransferFrom(from, to, searchTokenId);
            vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, searchTokenId));
            vm.prank(searchFrom);
            dt.safeTransferFrom(from, to, searchTokenId);
        }
        if (to != address(0)) {
            // Should revert if from != delegateTokenHolder
            vm.expectRevert(DelegateTokenErrors.FromNotDelegateTokenHolder.selector);
            vm.prank(from);
            dt.safeTransferFrom(searchFrom, to, delegateTokenId);
            // Should revert if from != msg.sender
            vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotApproved.selector, searchFrom, delegateTokenId));
            vm.prank(searchFrom);
            dt.safeTransferFrom(from, to, delegateTokenId);
        }
    }
}
