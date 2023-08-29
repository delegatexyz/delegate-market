// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";

import {DelegateTokenErrors} from "src/libraries/DelegateTokenLib.sol";

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
    function testMintRevertNotDelegateToken(address to, uint256 id, address caller) public {
        vm.assume(caller != address(dt));
        vm.expectRevert(PrincipalToken.CallerNotDelegateToken.selector);
        principal.mint(to, id);
    }

    function testMintRevertAuthorizedCallback(address to, uint256 id) public {
        vm.assume(to != address(0));
        vm.startPrank(address(dt));
        vm.expectRevert(DelegateTokenErrors.MintNotAuthorized.selector);
        principal.mint(to, id);
        vm.stopPrank();
    }

    function testBurnRevertNotDelegateToken(address spender, uint256 id, address caller) public {
        vm.assume(caller != address(dt));
        vm.expectRevert(PrincipalToken.CallerNotDelegateToken.selector);
        principal.burn(spender, id);
    }

    function testBurnRevertSpenderNotOwner(address owner, address spender, uint256 id) public {
        vm.assume(owner != spender && owner != address(0) && spender != address(0));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 2)), bytes32(uint256(uint160(owner))));
        vm.startPrank(address(dt));
        vm.expectRevert(abi.encodeWithSelector(PrincipalToken.NotApproved.selector, spender, id));
        principal.burn(spender, id);
        vm.stopPrank();
    }

    function testBurnRevertSpenderNotApproved(address owner, address approved, address spender, uint256 id) public {
        vm.assume(owner != spender && owner != address(0) && spender != address(0) && spender != approved);
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 2)), bytes32(uint256(uint160(owner))));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 4)), bytes32(uint256(uint160(approved))));
        vm.startPrank(address(dt));
        vm.expectRevert(abi.encodeWithSelector(PrincipalToken.NotApproved.selector, spender, id));
        principal.burn(spender, id);
        vm.stopPrank();
    }

    function testBurnRevertSpenderNotOperator(address owner, address approved, address operator, address spender, uint256 id) public {
        vm.assume(owner != spender && owner != address(0) && spender != address(0) && spender != approved && operator != spender && operator != owner);
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 2)), bytes32(uint256(uint160(owner))));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 4)), bytes32(uint256(uint160(approved))));
        vm.startPrank(owner);
        principal.setApprovalForAll(operator, true);
        vm.stopPrank();
        vm.startPrank(address(dt));
        vm.expectRevert(abi.encodeWithSelector(PrincipalToken.NotApproved.selector, spender, id));
        principal.burn(spender, id);
        vm.stopPrank();
    }

    function testBurnRevertOwner(address spender, uint256 id) public {
        vm.assume(spender != address(0));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 2)), bytes32(uint256(uint160(spender))));
        vm.startPrank(address(dt));
        vm.expectRevert(DelegateTokenErrors.BurnNotAuthorized.selector);
        principal.burn(spender, id);
        vm.stopPrank();
    }

    function testBurnRevertApproved(address owner, address spender, uint256 id) public {
        vm.assume(owner != spender && owner != address(0) && spender != address(0));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 2)), bytes32(uint256(uint160(owner))));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 4)), bytes32(uint256(uint160(spender))));
        vm.startPrank(address(dt));
        vm.expectRevert(DelegateTokenErrors.BurnNotAuthorized.selector);
        principal.burn(spender, id);
        vm.stopPrank();
    }

    function testBurnRevertOperator(address owner, address approved, address spender, uint256 id) public {
        vm.assume(owner != spender && owner != address(0) && spender != address(0) && spender != approved);
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 2)), bytes32(uint256(uint160(owner))));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 4)), bytes32(uint256(uint160(approved))));
        vm.startPrank(owner);
        principal.setApprovalForAll(spender, true);
        vm.stopPrank();
        vm.startPrank(address(dt));
        vm.expectRevert(DelegateTokenErrors.BurnNotAuthorized.selector);
        principal.burn(spender, id);
        vm.stopPrank();
    }

    function testIsApprovedOrOwnerNotOwner(address owner, address account, uint256 id) public {
        vm.assume(owner != account && owner != address(0) && account != address(0));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 2)), bytes32(uint256(uint160(owner))));
        assertFalse(principal.isApprovedOrOwner(account, id));
    }

    function testIsApprovedOrOwnerNotApproved(address owner, address approved, address account, uint256 id) public {
        vm.assume(owner != account && owner != address(0) && account != address(0) && account != approved);
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 2)), bytes32(uint256(uint160(owner))));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 4)), bytes32(uint256(uint160(approved))));
        assertFalse(principal.isApprovedOrOwner(account, id));
    }

    function testIsApprovedOrOwnerNotOperator(address owner, address approved, address operator, address account, uint256 id) public {
        vm.assume(owner != account && owner != address(0) && account != address(0) && account != approved && operator != account && operator != owner);
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 2)), bytes32(uint256(uint160(owner))));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 4)), bytes32(uint256(uint160(approved))));
        vm.startPrank(owner);
        principal.setApprovalForAll(operator, true);
        vm.stopPrank();
        assertFalse(principal.isApprovedOrOwner(account, id));
    }

    function testIsApprovedOrOwnerOwner(address account, uint256 id) public {
        vm.assume(account != address(0));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 2)), bytes32(uint256(uint160(account))));
        assertTrue(principal.isApprovedOrOwner(account, id));
    }

    function testIsApprovedOrOwnerApproved(address owner, address account, uint256 id) public {
        vm.assume(owner != account && owner != address(0) && account != address(0));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 2)), bytes32(uint256(uint160(owner))));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 4)), bytes32(uint256(uint160(account))));
        assertTrue(principal.isApprovedOrOwner(account, id));
    }

    function testIsApprovedOrOwnerOperator(address owner, address approved, address account, uint256 id) public {
        vm.assume(owner != account && owner != address(0) && account != address(0) && account != approved);
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 2)), bytes32(uint256(uint160(owner))));
        vm.store(address(principal), keccak256(abi.encode(bytes32(id), 4)), bytes32(uint256(uint160(approved))));
        vm.startPrank(owner);
        principal.setApprovalForAll(account, true);
        vm.stopPrank();
        assertTrue(principal.isApprovedOrOwner(account, id));
    }
}
