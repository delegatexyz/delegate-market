// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {DelegateTokenErrors} from "src/libraries/DelegateTokenLib.sol";
import {DTHarness} from "./utils/DTHarness.t.sol";
import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";
import {ERC721Holder} from "openzeppelin/token/ERC721/utils/ERC721Holder.sol";
import {IERC721Metadata} from "openzeppelin/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC2981} from "openzeppelin/interfaces/IERC2981.sol";
import {IERC165} from "openzeppelin/utils/introspection/IERC165.sol";
import {IERC1155Receiver} from "openzeppelin/token/ERC1155/IERC1155Receiver.sol";

import {
    PrincipalToken, DelegateToken, MarketMetadata, DelegateTokenStructs, BaseLiquidDelegateTest, ComputeAddress, IDelegateRegistry
} from "test/base/BaseLiquidDelegateTest.t.sol";

contract FalseIsApprovedOrOwner {
    function isApprovedOrOwner(address, uint256) external pure returns (bool) {
        return false;
    }
}

contract TrueIsApprovedOrOwner {
    function isApprovedOrOwner(address, uint256) external pure returns (bool) {
        return true;
    }
}

contract DelegateTokenTest is Test, BaseLiquidDelegateTest {
    DTHarness dtHarness;
    PrincipalToken ptShadow;
    FalseIsApprovedOrOwner falseIsApprovedOrOwner;
    TrueIsApprovedOrOwner trueIsApprovedOrOwner;

    function setUp() public {
        DelegateTokenStructs.DelegateTokenParameters memory delegateTokenParameters = DelegateTokenStructs.DelegateTokenParameters({
            delegateRegistry: address(registry),
            principalToken: ComputeAddress.addressFrom(address(this), vm.getNonce(address(this)) + 1),
            marketMetadata: address(marketMetadata)
        });
        delegateTokenParameters.principalToken = ComputeAddress.addressFrom(address(this), vm.getNonce(address(this)) + 1);
        dtHarness = new DTHarness(delegateTokenParameters);
        ptShadow = new PrincipalToken(address(dtHarness));
        falseIsApprovedOrOwner = new FalseIsApprovedOrOwner();
        trueIsApprovedOrOwner = new TrueIsApprovedOrOwner();
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

    function testDTConstructor(address delegateRegistry, address principalToken, address marketMetadata_) public {
        vm.assume(delegateRegistry != address(0) && principalToken != address(0) && marketMetadata_ != address(0));
        // Check zero reverts
        vm.expectRevert(DelegateTokenErrors.DelegateRegistryZero.selector);
        new DelegateToken(DelegateTokenStructs.DelegateTokenParameters({
            delegateRegistry: address(0), 
            principalToken: principalToken, 
            marketMetadata: marketMetadata_
            }));
        vm.expectRevert(DelegateTokenErrors.PrincipalTokenZero.selector);
        new DelegateToken(DelegateTokenStructs.DelegateTokenParameters({
            delegateRegistry: delegateRegistry, 
            principalToken: address(0), 
            marketMetadata: marketMetadata_
            }));
        vm.expectRevert(DelegateTokenErrors.MarketMetadataZero.selector);
        new DelegateToken(DelegateTokenStructs.DelegateTokenParameters({
            delegateRegistry: delegateRegistry, 
            principalToken: principalToken, 
            marketMetadata: address(0)
            }));
        // Check successful constructor
        dt = new DelegateToken(DelegateTokenStructs.DelegateTokenParameters({delegateRegistry: delegateRegistry, principalToken: principalToken, marketMetadata: marketMetadata_}));
        assertEq(delegateRegistry, dt.delegateRegistry());
        assertEq(principalToken, dt.principalToken());
        assertEq(marketMetadata_, dt.marketMetadata());
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

    function testBalanceOfRevert() public {
        vm.expectRevert(DelegateTokenErrors.DelegateTokenHolderZero.selector);
        dt.balanceOf(address(0));
    }

    function testBalanceOfNoRevert(address delegateTokenHolder, uint256 balance) public {
        vm.assume(delegateTokenHolder != address(0));
        // Check balance is stored correctly, mapping is at slot 2
        vm.store(address(dt), keccak256(abi.encode(delegateTokenHolder, 2)), bytes32(balance));
        assertEq(dt.balanceOf(delegateTokenHolder), balance);
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

    function testCreateRevertToIsZero(address from, bytes32 rights, uint256 tokenId, uint256 expiry) public {
        vm.assume(expiry > block.timestamp && expiry <= type(uint96).max);
        vm.assume(address(dt) != from);
        vm.assume(from != address(0));
        vm.startPrank(from);
        mockERC721.mint(from, tokenId);
        mockERC721.approve(address(dt), tokenId);
        vm.expectRevert(DelegateTokenErrors.ToIsZero.selector);
        dt.create(
            DelegateTokenStructs.DelegateInfo({
                principalHolder: from,
                tokenType: IDelegateRegistry.DelegationType.ERC721,
                delegateHolder: address(0),
                amount: 0,
                tokenContract: address(mockERC721),
                tokenId: tokenId,
                rights: rights,
                expiry: expiry
            }),
            1
        );
        vm.stopPrank();
    }

    function testSafeTransferFromReverts(address from, address to, bytes32 rights, uint256 expiry) public {
        vm.assume(expiry > block.timestamp && expiry <= type(uint96).max);
        vm.assume(from != address(0));
        vm.assume(to != address(0));
        vm.assume(address(dt) != from);
        vm.startPrank(from);
        mockERC721.mintNext(from);
        mockERC721.approve(address(dt), 0);
        uint256 delegateTokenId = dt.create(DelegateTokenStructs.DelegateInfo(from, IDelegateRegistry.DelegationType.ERC721, from, 0, address(mockERC721), 0, rights, expiry), 1);
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
        uint256 delegateTokenId = dt.create(DelegateTokenStructs.DelegateInfo(from, IDelegateRegistry.DelegationType.ERC721, from, 0, address(mockERC721), 0, rights, expiry), 1);
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

    function testApprove(address searchDelegateTokenHolder, address delegateTokenHolder, address spender, bytes32 rights, uint256 delegateTokenId, uint256 randomData) public {
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
        uint256 delegateTokenId = dt.create(DelegateTokenStructs.DelegateInfo(from, IDelegateRegistry.DelegationType.ERC721, from, 0, address(mockERC721), 0, rights, expiry), 1);
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

    function testRevertBatchERC1155TransferUnsupported(address data1, address data2, uint256[] calldata data3, uint256[] calldata data4, bytes calldata data5) public {
        vm.expectRevert(DelegateTokenErrors.BatchERC1155TransferUnsupported.selector);
        dt.onERC1155BatchReceived(data1, data2, data3, data4, data5);
    }

    function testRevertInvalidERC721TransferOperator(address operator, address data1, uint256 data2, bytes calldata data3) public {
        vm.assume(address(dt) != operator);
        vm.expectRevert(DelegateTokenErrors.InvalidERC721TransferOperator.selector);
        dt.onERC721Received(operator, data1, data2, data3);
    }

    function testNoRevertInvalidERC721TransferOperator(address data1, uint256 data2, bytes calldata data3) public view {
        dt.onERC721Received(address(dt), data1, data2, data3);
    }

    function testIsApprovedOrOwnerRevertNotMinted(address spender, uint256 delegateTokenId) public {
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, delegateTokenId));
        dt.isApprovedOrOwner(spender, delegateTokenId);
    }

    function testIsApprovedOrOwnerSpenderIsDelegateTokenHolder(address spender, bytes32 rights, uint256 delegateTokenId) public {
        vm.startPrank(address(dt));
        bytes32 hash = registry.delegateAll(spender, rights, true);
        vm.stopPrank();
        vm.store(address(dt), keccak256(abi.encode(bytes32(delegateTokenId), 1)), hash);
        assertTrue(dt.isApprovedOrOwner(spender, delegateTokenId));
    }

    function testIsApprovedOrOwnerSpenderIsAccountOperator(address spender, address tokenHolder, bytes32 rights, uint256 delegateTokenId) public {
        vm.assume(spender != tokenHolder);
        vm.startPrank(address(dt));
        bytes32 hash = registry.delegateAll(tokenHolder, rights, true);
        vm.stopPrank();
        vm.store(address(dt), keccak256(abi.encode(delegateTokenId, 1)), hash);
        vm.store(address(dt), keccak256(abi.encode(spender, keccak256(abi.encode(tokenHolder, 3)))), bytes32(uint256(1)));
        assertTrue(dt.isApprovedOrOwner(spender, delegateTokenId));
    }

    function testIsApprovedOrOwnerSpenderIsApproved(address spender, address tokenHolder, bytes32 rights, uint256 delegateTokenId) public {
        vm.assume(spender != tokenHolder);
        vm.startPrank(address(dt));
        bytes32 hash = registry.delegateAll(tokenHolder, rights, true);
        vm.stopPrank();
        vm.store(address(dt), keccak256(abi.encode(delegateTokenId, 1)), hash);
        vm.store(address(dt), bytes32(uint256(keccak256(abi.encode(delegateTokenId, 1))) + 1), bytes32(uint256(uint160(spender)) << 96));
        assertTrue(dt.isApprovedOrOwner(spender, delegateTokenId));
    }

    function testIsNotApprovedOrOwner(address spender, address notSpender, address tokenHolder, bytes32 rights, uint256 delegateTokenId) public {
        vm.assume(spender != notSpender && spender != tokenHolder);
        vm.startPrank(address(dt));
        bytes32 hash = registry.delegateAll(tokenHolder, rights, true);
        vm.stopPrank();
        vm.store(address(dt), keccak256(abi.encode(delegateTokenId, 1)), hash);
        vm.store(address(dt), keccak256(abi.encode(notSpender, keccak256(abi.encode(tokenHolder, 3)))), bytes32(uint256(1)));
        vm.store(address(dt), bytes32(uint256(keccak256(abi.encode(delegateTokenId, 1))) + 1), bytes32(uint256(uint160(notSpender)) << 96));
        assertFalse(dt.isApprovedOrOwner(spender, delegateTokenId));
    }

    function testExtendRevertNotMinted(uint256 delegateTokenId, uint256 newExpiry) public {
        vm.record();
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, delegateTokenId));
        dt.extend(delegateTokenId, newExpiry);
        (, bytes32[] memory writes) = vm.accesses(address(dt));
        assertEq(writes.length, 0);
    }

    function testExtendRevertOldExpiry(address holder, uint256 delegateTokenId, uint256 newExpiry, uint256 time, bytes32 rights) public {
        vm.startPrank(address(dt));
        bytes32 hash = registry.delegateAll(holder, rights, true);
        vm.stopPrank();
        vm.store(address(dt), keccak256(abi.encode(bytes32(delegateTokenId), 1)), hash);
        vm.warp(time);
        vm.assume(newExpiry <= block.timestamp);
        vm.record();
        vm.expectRevert(DelegateTokenErrors.ExpiryInPast.selector);
        dt.extend(delegateTokenId, newExpiry);
        (, bytes32[] memory writes) = vm.accesses(address(dt));
        assertEq(writes.length, 0);
    }

    function testExtendRevertInvalidUpdate(address holder, uint256 delegateTokenId, uint256 newExpiry, uint256 currentExpiry, bytes32 rights) public {
        vm.startPrank(address(dt));
        bytes32 hash = registry.delegateAll(holder, rights, true);
        vm.stopPrank();
        vm.store(address(dt), keccak256(abi.encode(bytes32(delegateTokenId), 1)), hash);
        vm.assume(newExpiry > block.timestamp && newExpiry <= currentExpiry && currentExpiry <= type(uint96).max);
        vm.store(address(dt), bytes32(uint256(keccak256(abi.encode(bytes32(delegateTokenId), 1))) + 1), bytes32(currentExpiry));
        vm.record();
        vm.expectRevert(DelegateTokenErrors.ExpiryTooSmall.selector);
        dt.extend(delegateTokenId, newExpiry);
        (, bytes32[] memory writes) = vm.accesses(address(dt));
        assertEq(writes.length, 0);
    }

    function testExtendRevertPrincipalApprovedOwnerFalse(address holder, uint256 delegateTokenId, uint256 newExpiry, uint256 currentExpiry, bytes32 rights) public {
        vm.startPrank(address(dt));
        bytes32 hash = registry.delegateAll(holder, rights, true);
        vm.stopPrank();
        vm.store(address(dt), keccak256(abi.encode(bytes32(delegateTokenId), 1)), hash);
        vm.assume(newExpiry > block.timestamp && newExpiry > currentExpiry && currentExpiry <= type(uint96).max);
        vm.store(address(dt), bytes32(uint256(keccak256(abi.encode(bytes32(delegateTokenId), 1))) + 1), bytes32(currentExpiry));
        vm.etch(address(principal), address(falseIsApprovedOrOwner).code);
        vm.record();
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotApproved.selector, address(this), delegateTokenId));
        dt.extend(delegateTokenId, newExpiry);
        (, bytes32[] memory writes) = vm.accesses(address(dt));
        assertEq(writes.length, 0);
    }

    function testExtendRevertExpiryTooLarge(address holder, uint256 delegateTokenId, uint256 newExpiry, uint256 currentExpiry, bytes32 rights) public {
        vm.startPrank(address(dt));
        bytes32 hash = registry.delegateAll(holder, rights, true);
        vm.stopPrank();
        vm.store(address(dt), keccak256(abi.encode(bytes32(delegateTokenId), 1)), hash);
        vm.assume(newExpiry > block.timestamp && newExpiry > type(uint96).max && currentExpiry <= type(uint96).max);
        vm.store(address(dt), bytes32(uint256(keccak256(abi.encode(bytes32(delegateTokenId), 1))) + 1), bytes32(currentExpiry));
        vm.etch(address(principal), address(trueIsApprovedOrOwner).code);
        vm.record();
        vm.expectRevert(DelegateTokenErrors.ExpiryTooLarge.selector);
        dt.extend(delegateTokenId, newExpiry);
        (, bytes32[] memory writes) = vm.accesses(address(dt));
        assertEq(writes.length, 0);
    }

    event ExpiryExtended(uint256 indexed delegateTokenId, uint256 previousExpiry, uint256 newExpiry);

    function testExtendNoRevert(address holder, uint256 delegateTokenId, uint256 newExpiry, uint256 currentExpiry, bytes32 rights) public {
        vm.startPrank(address(dt));
        bytes32 hash = registry.delegateAll(holder, rights, true);
        vm.stopPrank();
        vm.store(address(dt), keccak256(abi.encode(bytes32(delegateTokenId), 1)), hash);
        vm.assume(newExpiry > block.timestamp && newExpiry > currentExpiry && newExpiry <= type(uint96).max && currentExpiry <= type(uint96).max);
        vm.store(address(dt), bytes32(uint256(keccak256(abi.encode(bytes32(delegateTokenId), 1))) + 1), bytes32(currentExpiry));
        vm.etch(address(principal), address(trueIsApprovedOrOwner).code);
        vm.record();
        vm.expectEmit(true, true, true, true, address(dt));
        emit ExpiryExtended(delegateTokenId, currentExpiry, newExpiry);
        dt.extend(delegateTokenId, newExpiry);
        (, bytes32[] memory writes) = vm.accesses(address(dt));
        assertEq(writes.length, 1);
        assertEq(vm.load(address(dt), writes[0]), bytes32(newExpiry));
    }

    function testSymbol() public {
        assertEq("DT", dt.symbol());
    }
}
