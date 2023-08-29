// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {DelegateTokenStorageHelpers as Helpers} from "src/libraries/DelegateTokenStorageHelpers.sol";
import {IDelegateRegistry, BaseLiquidDelegateTest, DelegateTokenStructs} from "test/base/BaseLiquidDelegateTest.t.sol";
import {DelegateTokenErrors} from "src/libraries/DelegateTokenLib.sol";

contract DummyPrincipal {
    function burn(address caller, uint256 id) public pure {}

    function mint(address recipient, uint256 id) public pure {}
}

contract DelegateTokenStorageHelpersTest is Test, BaseLiquidDelegateTest {
    mapping(uint256 => uint256[3]) info;
    mapping(address => uint256) balances;
    mapping(address => mapping(address => bool)) accountOperator;
    uint256 constant deleteUpper160Bits = type(uint96).max;
    uint256 constant deleteLower96Bits = type(uint256).max << 96;
    uint256 constant registryHashPosition = 0;
    uint256 constant packedPosition = 1;
    uint256 constant amountPosition = 2;
    DelegateTokenStructs.Uint256 burnAuth;
    DelegateTokenStructs.Uint256 mintAuth;
    DummyPrincipal dummyPrincipal;

    function setUp() public {
        dummyPrincipal = new DummyPrincipal();
    }

    function testWriteApproved(uint256 data, uint256 delegateTokenId, address approved) public {
        info[delegateTokenId][packedPosition] = data;
        assertEq(info[delegateTokenId][packedPosition], data);
        Helpers.writeApproved(info, delegateTokenId, approved);
        uint256 storedData = info[delegateTokenId][packedPosition];
        assertEq(data & deleteUpper160Bits, storedData & deleteUpper160Bits);
        assertEq(uint256(uint160(approved)), storedData >> 96);
    }

    function testRecordWriteApproved(uint256 delegateTokenId, address approved) public {
        vm.record();
        Helpers.writeApproved(info, delegateTokenId, approved);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 2); // Every write counts as an additional read
        assertEq(writes.length, 1);
        assertEq(vm.load(address(this), reads[0]), bytes32(uint256(uint160(approved)) << 96));
        assertEq(reads[0], reads[1]);
        assertEq(reads[0], writes[0]);
    }

    function testWriteExpiry(uint256 data, uint256 delegateTokenId, uint256 expiry) public {
        vm.assume(expiry <= type(uint96).max); // Ensures no revert
        info[delegateTokenId][packedPosition] = data;
        assertEq(info[delegateTokenId][packedPosition], data);
        Helpers.writeExpiry(info, delegateTokenId, expiry);
        uint256 storedData = info[delegateTokenId][packedPosition];
        assertEq(data & deleteLower96Bits, storedData & deleteLower96Bits);
        assertEq(expiry, storedData & deleteUpper160Bits);
        assertEq(expiry, Helpers.readExpiry(info, delegateTokenId));
    }

    function testRecordWriteExpiry(uint256 delegateTokenId, uint256 expiry) public {
        vm.assume(expiry <= type(uint96).max);
        vm.record();
        Helpers.writeExpiry(info, delegateTokenId, expiry);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 2); // Every write counts as an additional read
        assertEq(writes.length, 1);
        assertEq(vm.load(address(this), reads[0]), bytes32(expiry));
        assertEq(reads[0], reads[1]);
        assertEq(reads[0], writes[0]);
    }

    function testRevertWriteExpiry(uint256 delegateTokenId, uint256 expiry) public {
        vm.assume(expiry > type(uint96).max);
        vm.expectRevert(DelegateTokenErrors.ExpiryTooLarge.selector);
        Helpers.writeExpiry(info, delegateTokenId, expiry);
    }

    function testRecordRevertWriteExpiry(uint256 delegateTokenId, uint256 expiry) public {
        vm.assume(expiry > type(uint96).max);
        vm.record();
        vm.expectRevert(DelegateTokenErrors.ExpiryTooLarge.selector);
        Helpers.writeExpiry(info, delegateTokenId, expiry);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
    }

    function testWriteRegistryHash(uint256 data, uint256 delegateTokenId, bytes32 registryHash) public {
        info[delegateTokenId][registryHashPosition] = data; // Put garbage data in slot
        Helpers.writeRegistryHash(info, delegateTokenId, registryHash);
        assertEq(registryHash, bytes32(info[delegateTokenId][registryHashPosition]));
        assertEq(registryHash, Helpers.readRegistryHash(info, delegateTokenId));
    }

    function testRecordWriteRegistryHash(uint256 delegateTokenId, bytes32 registryHash) public {
        vm.record();
        Helpers.writeRegistryHash(info, delegateTokenId, registryHash);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1); // Every write counts as an additional read
        assertEq(writes.length, 1);
        assertEq(vm.load(address(this), reads[0]), registryHash);
        assertEq(reads[0], writes[0]);
    }

    function testWriteUnderlyingAmount(uint256 data, uint256 delegateTokenId, uint256 amount) public {
        info[delegateTokenId][amountPosition] = data; // Put garbage data in slot
        Helpers.writeUnderlyingAmount(info, delegateTokenId, amount);
        assertEq(amount, info[delegateTokenId][amountPosition]);
        assertEq(amount, Helpers.readUnderlyingAmount(info, delegateTokenId));
    }

    function testRecordWriteUnderlyingAmount(uint256 delegateTokenId, uint256 amount) public {
        vm.record();
        Helpers.writeUnderlyingAmount(info, delegateTokenId, amount);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1); // Every write counts as an additional read
        assertEq(writes.length, 1);
        assertEq(vm.load(address(this), reads[0]), bytes32(amount));
        assertEq(reads[0], writes[0]);
    }

    function testIncrementBalance(uint256 balance, address owner) public {
        balances[owner] = balance;
        Helpers.incrementBalance(balances, owner);
        unchecked {
            balance++;
        }
        assertEq(balances[owner], balance);
    }

    function testRecordIncrementBalance(uint256 balance, address owner) public {
        balances[owner] = balance;
        vm.record();
        Helpers.incrementBalance(balances, owner);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 2); // Every write counts as an additional read
        assertEq(writes.length, 1);
        unchecked {
            balance++;
        }
        assertEq(vm.load(address(this), reads[0]), bytes32(balance));
        assertEq(reads[0], writes[0]);
        assertEq(reads[0], reads[1]);
    }

    function testDecrementBalance(uint256 balance, address owner) public {
        balances[owner] = balance;
        Helpers.decrementBalance(balances, owner);
        unchecked {
            balance--;
        }
        assertEq(balances[owner], balance);
    }

    function testRecordDecrementBalance(uint256 balance, address owner) public {
        balances[owner] = balance;
        vm.record();
        Helpers.decrementBalance(balances, owner);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 2); // Every write counts as an additional read
        assertEq(writes.length, 1);
        unchecked {
            balance--;
        }
        assertEq(vm.load(address(this), reads[0]), bytes32(balance));
        assertEq(reads[0], writes[0]);
        assertEq(reads[0], reads[1]);
    }

    function testRevertAlreadyExisted(uint256 delegateTokenId, uint256 flag) public {
        vm.assume(flag != 0); // Causes revert
        info[delegateTokenId][registryHashPosition] = flag;
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.AlreadyExisted.selector, delegateTokenId));
        Helpers.revertAlreadyExisted(info, delegateTokenId);
    }

    function testNoRevertAlreadyExisted(uint256 delegateTokenId) public {
        info[delegateTokenId][registryHashPosition] = 0; // Ensures no revert
        Helpers.revertAlreadyExisted(info, delegateTokenId);
    }

    function testRecordAlreadyExisted(uint256 delegateTokenId, uint256 flag) public {
        info[delegateTokenId][registryHashPosition] = flag;
        vm.record();
        if (flag != 0) vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.AlreadyExisted.selector, delegateTokenId));
        Helpers.revertAlreadyExisted(info, delegateTokenId);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1); // Every write counts as an additional read
        assertEq(writes.length, 0);
        assertEq(vm.load(address(this), reads[0]), bytes32(flag));
    }

    function testRevertNotOperatorOwner(address account) public {
        vm.assume(msg.sender != account);
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotOperator.selector, msg.sender, account));
        Helpers.revertNotOperator(accountOperator, account);
    }

    function testRevertNotOperatorOperator(address account, address operator) public {
        accountOperator[account][operator] = true;
        vm.assume(msg.sender != account && msg.sender != operator);
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotOperator.selector, msg.sender, account));
        Helpers.revertNotOperator(accountOperator, account);
    }

    function testNoRevertNotOperatorOwner() public view {
        Helpers.revertNotOperator(accountOperator, msg.sender);
    }

    function testNoRevertNotOperatorOperator(address account) public {
        accountOperator[account][msg.sender] = true;
        vm.assume(msg.sender != account);
        Helpers.revertNotOperator(accountOperator, account);
    }

    function testRecordRevertNotOperator(address account, address operator) public {
        accountOperator[account][operator] = true;
        vm.record();
        if (msg.sender != account && msg.sender != operator) vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotOperator.selector, msg.sender, account));
        Helpers.revertNotOperator(accountOperator, account);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(writes.length, 0);
        if (msg.sender != account) {
            assertEq(reads.length, 1);
            if (msg.sender == operator) assertEq(vm.load(address(this), reads[0]), bytes32(uint256(1)));
            else assertEq(vm.load(address(this), reads[0]), bytes32(uint256(0)));
        } else {
            assertEq(reads.length, 0);
        }
    }

    function testReadApproved(uint256 delegateTokenId, address approved) public {
        info[delegateTokenId][packedPosition] = uint256(uint160(approved)) << 96;
        assertEq(Helpers.readApproved(info, delegateTokenId), approved);
    }

    function testRecordReadApproved(uint256 delegateTokenId, address approved) public {
        info[delegateTokenId][packedPosition] = uint256(uint160(approved)) << 96;
        vm.record();
        address readApproved = Helpers.readApproved(info, delegateTokenId);
        assertEq(readApproved, approved);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1); // Every write counts as an additional read
        assertEq(writes.length, 0);
        assertEq(uint256(vm.load(address(this), reads[0])) >> 96, uint256(uint160(approved)));
    }

    function testReadExpiry(uint256 delegateTokenId, uint256 data) public {
        info[delegateTokenId][packedPosition] = data;
        assertEq(Helpers.readExpiry(info, delegateTokenId), uint96(data));
    }

    function testRecordReadExpiry(uint256 delegateTokenId, uint256 data) public {
        info[delegateTokenId][packedPosition] = data;
        vm.record();
        uint256 readExpiry = Helpers.readExpiry(info, delegateTokenId);
        assertEq(readExpiry, uint96(data));
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1); // Every write counts as an additional read
        assertEq(writes.length, 0);
        assertEq(uint256(vm.load(address(this), reads[0])), data);
    }

    function testReadRegistryHash(uint256 delegateTokenId, bytes32 registryHash) public {
        info[delegateTokenId][registryHashPosition] = uint256(registryHash);
        assertEq(Helpers.readRegistryHash(info, delegateTokenId), registryHash);
    }

    function testRecordReadRegistryHash(uint256 delegateTokenId, bytes32 registryHash) public {
        info[delegateTokenId][registryHashPosition] = uint256(registryHash);
        vm.record();
        bytes32 readRegistryHash = Helpers.readRegistryHash(info, delegateTokenId);
        assertEq(readRegistryHash, registryHash);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1); // Every write counts as an additional read
        assertEq(writes.length, 0);
        assertEq(vm.load(address(this), reads[0]), registryHash);
    }

    function testReadUnderlyingAmount(uint256 delegateTokenId, uint256 underlyingAmount) public {
        info[delegateTokenId][amountPosition] = underlyingAmount;
        assertEq(Helpers.readUnderlyingAmount(info, delegateTokenId), underlyingAmount);
    }

    function testRecordReadUnderlyingAmount(uint256 delegateTokenId, uint256 underlyingAmount) public {
        info[delegateTokenId][amountPosition] = underlyingAmount;
        vm.record();
        uint256 readUnderlyingAmount = Helpers.readUnderlyingAmount(info, delegateTokenId);
        assertEq(readUnderlyingAmount, underlyingAmount);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1); // Every write counts as an additional read
        assertEq(writes.length, 0);
        assertEq(vm.load(address(this), reads[0]), bytes32(underlyingAmount));
    }

    function testRevertNotApprovedOrOperatorOwner(address account, uint256 delegateTokenId) public {
        vm.assume(msg.sender != account);
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotApproved.selector, msg.sender, delegateTokenId));
        Helpers.revertNotApprovedOrOperator(accountOperator, info, account, delegateTokenId);
    }

    function testRevertNotApprovedOrOperatorOperator(address account, address operator, uint256 delegateTokenId) public {
        accountOperator[account][operator] = true;
        vm.assume(msg.sender != account && msg.sender != operator);
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotApproved.selector, msg.sender, delegateTokenId));
        Helpers.revertNotApprovedOrOperator(accountOperator, info, account, delegateTokenId);
    }

    function testRevertNotApprovedOrOperatorApproved(address account, address operator, address approved, uint256 delegateTokenId) public {
        accountOperator[account][operator] = true;
        info[delegateTokenId][packedPosition] = uint256(uint160(approved)) << 96;
        vm.assume(msg.sender != account && msg.sender != operator && msg.sender != approved);
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotApproved.selector, msg.sender, delegateTokenId));
        Helpers.revertNotApprovedOrOperator(accountOperator, info, account, delegateTokenId);
    }

    function testNoRevertNotApprovedOrOperatorOwner(uint256 delegateTokenId) public view {
        Helpers.revertNotApprovedOrOperator(accountOperator, info, msg.sender, delegateTokenId);
    }

    function testNoRevertNotApprovedOrOperatorOperator(address account, uint256 delegateTokenId) public {
        accountOperator[account][msg.sender] = true;
        vm.assume(msg.sender != account);
        Helpers.revertNotApprovedOrOperator(accountOperator, info, account, delegateTokenId);
    }

    function testNoRevertNotApprovedOrOperatorApproved(address account, address operator, uint256 delegateTokenId) public {
        accountOperator[account][operator] = true;
        info[delegateTokenId][packedPosition] = uint256(uint160(msg.sender)) << 96;
        vm.assume(msg.sender != account && msg.sender != operator);
        Helpers.revertNotApprovedOrOperator(accountOperator, info, account, delegateTokenId);
    }

    function testRecordNotApprovedOrOperator(address account, address operator, address approved, uint256 delegateTokenId) public {
        accountOperator[account][operator] = true;
        info[delegateTokenId][packedPosition] = uint256(uint160(approved)) << 96;
        vm.record();
        if (msg.sender != account && msg.sender != operator && msg.sender != approved) {
            vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotApproved.selector, msg.sender, delegateTokenId));
        }
        Helpers.revertNotApprovedOrOperator(accountOperator, info, account, delegateTokenId);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(writes.length, 0);
        if (msg.sender != account && msg.sender == operator) {
            assertEq(reads.length, 1);
            assertEq(vm.load(address(this), reads[0]), bytes32(uint256(1)));
        } else if (msg.sender != account && msg.sender != operator) {
            assertEq(reads.length, 2);
            assertEq(vm.load(address(this), reads[0]), bytes32(uint256(0)));
            assertEq(uint256(vm.load(address(this), reads[1])) >> 96, uint160(approved));
            assertNotEq(reads[0], reads[1]);
        } else {
            assertEq(reads.length, 0);
        }
    }

    function testRevertInvalidWithdrawalConditions(uint256 delegateTokenId, address delegateTokenHolder, uint256 expiry, address approved, address operator) public {
        vm.assume(expiry <= type(uint96).max && expiry > block.timestamp);
        vm.assume(delegateTokenHolder != msg.sender && msg.sender != approved && msg.sender != operator);
        Helpers.writeApproved(info, delegateTokenId, approved);
        Helpers.writeExpiry(info, delegateTokenId, expiry);
        accountOperator[delegateTokenHolder][operator] = true;
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.WithdrawNotAvailable.selector, delegateTokenId, expiry, block.timestamp));
        Helpers.revertInvalidWithdrawalConditions(info, accountOperator, delegateTokenId, delegateTokenHolder);
    }

    function testNoRevertInvalidWithdrawalConditionsExpiry(uint256 delegateTokenId, address delegateTokenHolder, uint256 expiry) public view {
        vm.assume(expiry <= type(uint96).max && expiry <= block.timestamp);
        Helpers.revertInvalidWithdrawalConditions(info, accountOperator, delegateTokenId, delegateTokenHolder);
    }

    function testNoRevertInvalidWithdrawalConditionsOwner(uint256 delegateTokenId, uint256 expiry, address approved, address operator) public {
        vm.assume(expiry <= type(uint96).max && expiry > block.timestamp);
        vm.assume(msg.sender != approved && msg.sender != operator);
        Helpers.writeApproved(info, delegateTokenId, approved);
        Helpers.writeExpiry(info, delegateTokenId, expiry);
        accountOperator[msg.sender][operator] = true;
        Helpers.revertInvalidWithdrawalConditions(info, accountOperator, delegateTokenId, msg.sender);
    }

    function testNoRevertInvalidWithdrawalConditionsApproved(uint256 delegateTokenId, address delegateTokenHolder, uint256 expiry, address operator) public {
        vm.assume(expiry <= type(uint96).max && expiry > block.timestamp);
        vm.assume(delegateTokenHolder != msg.sender && msg.sender != operator);
        Helpers.writeApproved(info, delegateTokenId, msg.sender);
        Helpers.writeExpiry(info, delegateTokenId, expiry);
        accountOperator[delegateTokenHolder][operator] = true;
        Helpers.revertInvalidWithdrawalConditions(info, accountOperator, delegateTokenId, delegateTokenHolder);
    }

    function testNoRevertInvalidWithdrawalConditionsOperator(uint256 delegateTokenId, address delegateTokenHolder, uint256 expiry, address approved) public {
        vm.assume(expiry <= type(uint96).max && expiry > block.timestamp);
        vm.assume(delegateTokenHolder != msg.sender && msg.sender != approved);
        Helpers.writeApproved(info, delegateTokenId, approved);
        Helpers.writeExpiry(info, delegateTokenId, expiry);
        accountOperator[delegateTokenHolder][msg.sender] = true;
        Helpers.revertInvalidWithdrawalConditions(info, accountOperator, delegateTokenId, delegateTokenHolder);
    }

    function testAvailableRevertNotMinted(uint256 id) public {
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, id));
        Helpers.revertNotMinted(0, id);
    }

    function testRecordAvailableRevertNotMinted(uint256 id) public {
        vm.record();
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, id));
        vm.record();
        Helpers.revertNotMinted(0, id);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
    }

    function testUsedRevertNotMinted(uint256 id) public {
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, id));
        Helpers.revertNotMinted(bytes32(uint256(1)), id);
    }

    function testRecordUsedRevertNotMinted(uint256 id) public {
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, id));
        vm.record();
        Helpers.revertNotMinted(bytes32(uint256(1)), id);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
    }

    function testNoRevertNotMinted(bytes32 random, uint256 id) public pure {
        vm.assume(uint256(random) != 0 && uint256(random) != 1);
        Helpers.revertNotMinted(random, id);
    }

    function testRecordNoRevertNotMinted(bytes32 random, uint256 id) public {
        vm.assume(uint256(random) != 0 && uint256(random) != 1);
        vm.record();
        Helpers.revertNotMinted(random, id);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
    }

    function testReadAvailableRevertNotMinted(uint256 id) public {
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, id));
        Helpers.revertNotMinted(info, id);
    }

    function testRecordReadAvailableRevertNotMinted(uint256 id) public {
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, id));
        vm.record();
        Helpers.revertNotMinted(info, id);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1);
        assertEq(writes.length, 0);
        assertEq(vm.load(address(this), reads[0]), bytes32(0));
    }

    function testReadUsedRevertNotMinted(uint256 id) public {
        info[id][0] = 1;
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, id));
        Helpers.revertNotMinted(info, id);
    }

    function testRecordReadUsedRevertNotMinted(uint256 id) public {
        info[id][0] = 1;
        vm.record();
        vm.expectRevert(abi.encodeWithSelector(DelegateTokenErrors.NotMinted.selector, id));
        Helpers.revertNotMinted(info, id);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1);
        assertEq(writes.length, 0);
        assertEq(vm.load(address(this), reads[0]), bytes32(uint256(1)));
    }

    function testReadNoRevertNotMinted(uint256 random, uint256 id) public {
        vm.assume(random != 0 && random != 1);
        info[id][0] = random;
        Helpers.revertNotMinted(info, id);
    }

    function testRecordReadNoRevertNotMinted(uint256 random, uint256 id) public {
        vm.assume(random != 0 && random != 1);
        info[id][0] = random;
        vm.record();
        Helpers.revertNotMinted(info, id);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1);
        assertEq(writes.length, 0);
        assertEq(vm.load(address(this), reads[0]), bytes32(random));
    }

    function testPrincipalAuthFlagsNonZeroAndUnique() public {
        uint256[4] memory authFlags;
        authFlags[0] = Helpers.MINT_NOT_AUTHORIZED;
        authFlags[1] = Helpers.MINT_AUTHORIZED;
        authFlags[2] = Helpers.BURN_NOT_AUTHORIZED;
        authFlags[3] = Helpers.BURN_AUTHORIZED;
        for (uint256 i = 0; i < 4; i++) {
            assertNotEq(authFlags[i], 0);
        }
        for (uint256 i = 0; i < 4; i++) {
            for (uint256 j = 0; j < 4; j++) {
                if (i == j) {
                    assertEq(authFlags[i], authFlags[j]);
                } else {
                    assertNotEq(authFlags[i], authFlags[j]);
                }
            }
        }
    }

    function testPrincipalBurnRevertAlreadyAuthorized(uint256 authFlag, uint256 delegateTokenId) public {
        vm.assume(authFlag != Helpers.BURN_NOT_AUTHORIZED);
        burnAuth.flag = authFlag;
        vm.expectRevert(DelegateTokenErrors.BurnAuthorized.selector);
        Helpers.burnPrincipal(address(principal), burnAuth, delegateTokenId);
    }

    function testPrincipalRecordBurnRevertAlreadyAuthorized(uint256 authFlag, uint256 delegateTokenId) public {
        vm.assume(authFlag != Helpers.BURN_NOT_AUTHORIZED);
        burnAuth.flag = authFlag;
        vm.record();
        vm.expectRevert(DelegateTokenErrors.BurnAuthorized.selector);
        Helpers.burnPrincipal(address(principal), burnAuth, delegateTokenId);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1);
        assertEq(writes.length, 0);
        assertEq(vm.load(address(this), reads[0]), bytes32(authFlag));
    }

    function testPrincipalBurnNoRevert(uint256 delegateTokenId) public {
        burnAuth.flag = Helpers.BURN_NOT_AUTHORIZED;
        Helpers.burnPrincipal(address(dummyPrincipal), burnAuth, delegateTokenId);
    }

    function testPrincipalRecordBurnNoRevert(uint256 delegateTokenId) public {
        burnAuth.flag = Helpers.BURN_NOT_AUTHORIZED;
        address cachedDummyPrincipal = address(dummyPrincipal);
        vm.record();
        Helpers.burnPrincipal(cachedDummyPrincipal, burnAuth, delegateTokenId);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 3); // Write counts as additional read
        assertEq(writes.length, 2);
        assertEq(reads[0], reads[1]);
        assertEq(reads[0], reads[2]);
        assertEq(writes[0], reads[0]);
        assertEq(writes[1], reads[0]);
        assertEq(vm.load(address(this), reads[0]), bytes32(Helpers.BURN_NOT_AUTHORIZED));
    }

    function testPrincipalMintRevertAlreadyAuthorized(uint256 authFlag, address recipient, uint256 delegateTokenId) public {
        vm.assume(authFlag != Helpers.MINT_NOT_AUTHORIZED);
        mintAuth.flag = authFlag;
        vm.expectRevert(DelegateTokenErrors.MintAuthorized.selector);
        Helpers.mintPrincipal(address(principal), mintAuth, recipient, delegateTokenId);
    }

    function testPrincipalRecordMintRevertAlreadyAuthorized(uint256 authFlag, address recipient, uint256 delegateTokenId) public {
        vm.assume(authFlag != Helpers.MINT_NOT_AUTHORIZED);
        mintAuth.flag = authFlag;
        vm.record();
        vm.expectRevert(DelegateTokenErrors.MintAuthorized.selector);
        Helpers.mintPrincipal(address(principal), mintAuth, recipient, delegateTokenId);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1);
        assertEq(writes.length, 0);
        assertEq(vm.load(address(this), reads[0]), bytes32(authFlag));
    }

    function testPrincipalMintNoRevert(address recipient, uint256 delegateTokenId) public {
        mintAuth.flag = Helpers.MINT_NOT_AUTHORIZED;
        Helpers.mintPrincipal(address(dummyPrincipal), mintAuth, recipient, delegateTokenId);
    }

    function testPrincipalRecordMintNoRevert(address recipient, uint256 delegateTokenId) public {
        mintAuth.flag = Helpers.MINT_NOT_AUTHORIZED;
        address cachedDummyPrincipal = address(dummyPrincipal);
        vm.record();
        Helpers.mintPrincipal(cachedDummyPrincipal, mintAuth, recipient, delegateTokenId);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 3); // Write counts as additional read
        assertEq(writes.length, 2);
        assertEq(reads[0], reads[1]);
        assertEq(reads[0], reads[2]);
        assertEq(writes[0], reads[0]);
        assertEq(writes[1], reads[0]);
        assertEq(vm.load(address(this), reads[0]), bytes32(Helpers.MINT_NOT_AUTHORIZED));
    }

    function testCheckBurnAuthorizedRevertCaller() public {
        vm.expectRevert(DelegateTokenErrors.CallerNotPrincipalToken.selector);
        Helpers.checkBurnAuthorized(address(principal), burnAuth);
    }

    function testRecordCheckBurnAuthorizedRevertCaller() public {
        vm.record();
        vm.expectRevert(DelegateTokenErrors.CallerNotPrincipalToken.selector);
        Helpers.checkBurnAuthorized(address(principal), burnAuth);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
    }

    function testCheckBurnAuthorizedRevertFlag(uint256 authFlag) public {
        vm.assume(authFlag != Helpers.BURN_AUTHORIZED);
        burnAuth.flag = authFlag;
        vm.expectRevert(DelegateTokenErrors.BurnNotAuthorized.selector);
        Helpers.checkBurnAuthorized(msg.sender, burnAuth);
    }

    function testRecordCheckBurnAuthorizedRevertFlag(uint256 authFlag) public {
        vm.assume(authFlag != Helpers.BURN_AUTHORIZED);
        burnAuth.flag = authFlag;
        vm.record();
        vm.expectRevert(DelegateTokenErrors.BurnNotAuthorized.selector);
        Helpers.checkBurnAuthorized(msg.sender, burnAuth);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1);
        assertEq(writes.length, 0);
        assertEq(vm.load(address(this), reads[0]), bytes32(authFlag));
    }

    function testCheckBurnAuthorizedNoRevert() public {
        burnAuth.flag = Helpers.BURN_AUTHORIZED;
        Helpers.checkBurnAuthorized(msg.sender, burnAuth);
    }

    function testRecordCheckBurnAuthorizedNoRevert() public {
        burnAuth.flag = Helpers.BURN_AUTHORIZED;
        vm.record();
        Helpers.checkBurnAuthorized(msg.sender, burnAuth);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1);
        assertEq(writes.length, 0);
        assertEq(vm.load(address(this), reads[0]), bytes32(Helpers.BURN_AUTHORIZED));
    }

    function testCheckMintAuthorizedRevertCaller() public {
        vm.expectRevert(DelegateTokenErrors.CallerNotPrincipalToken.selector);
        Helpers.checkMintAuthorized(address(principal), mintAuth);
    }

    function testRecordCheckMintAuthorizedRevertCaller() public {
        vm.record();
        vm.expectRevert(DelegateTokenErrors.CallerNotPrincipalToken.selector);
        Helpers.checkMintAuthorized(address(principal), mintAuth);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
    }

    function testCheckMintAuthorizedRevertFlag(uint256 authFlag) public {
        vm.assume(authFlag != Helpers.MINT_AUTHORIZED);
        mintAuth.flag = authFlag;
        vm.expectRevert(DelegateTokenErrors.MintNotAuthorized.selector);
        Helpers.checkMintAuthorized(msg.sender, mintAuth);
    }

    function testRecordCheckMintAuthorizedRevertFlag(uint256 authFlag) public {
        vm.assume(authFlag != Helpers.MINT_AUTHORIZED);
        mintAuth.flag = authFlag;
        vm.record();
        vm.expectRevert(DelegateTokenErrors.MintNotAuthorized.selector);
        Helpers.checkMintAuthorized(msg.sender, mintAuth);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1);
        assertEq(writes.length, 0);
        assertEq(vm.load(address(this), reads[0]), bytes32(authFlag));
    }

    function testCheckMintAuthorizedNoRevert() public {
        mintAuth.flag = Helpers.MINT_AUTHORIZED;
        Helpers.checkMintAuthorized(msg.sender, mintAuth);
    }

    function testRecordCheckMintAuthorizedNoRevert() public {
        mintAuth.flag = Helpers.MINT_AUTHORIZED;
        vm.record();
        Helpers.checkMintAuthorized(msg.sender, mintAuth);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 1);
        assertEq(writes.length, 0);
        assertEq(vm.load(address(this), reads[0]), bytes32(Helpers.MINT_AUTHORIZED));
    }

    function testPrincipalIsCallerRevert() public {
        vm.expectRevert(DelegateTokenErrors.CallerNotPrincipalToken.selector);
        Helpers.principalIsCaller(address(principal));
    }

    function testRecordPrincipalIsCallerRevert() public {
        vm.record();
        vm.expectRevert(DelegateTokenErrors.CallerNotPrincipalToken.selector);
        Helpers.principalIsCaller(address(principal));
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
    }

    function testPrincipalIsCallerNoRevert() public view {
        Helpers.principalIsCaller(msg.sender);
    }

    function testRecordPrincipalIsCallerNoRevert() public {
        vm.record();
        Helpers.principalIsCaller(msg.sender);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(this));
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
    }
}
