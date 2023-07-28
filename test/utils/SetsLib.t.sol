// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

struct UintSet {
    uint256[] nums;
    mapping(uint256 => uint256) index;
}

struct AddressSet {
    address[] addrs;
    mapping(address => uint256) index;
}

struct Token {
    address addr;
    uint256 id;
}

struct TokenSet {
    mapping(address => mapping(uint256 => uint256)) index;
    Token[] tokens;
}

/// @author Adapted from horsefact's [AddressSet](https://github.com/horsefacts/weth-invariant-testing/blob/main/test/helpers/AddressSet.sol)
library SetsLib {
    function add(TokenSet storage s, address addr, uint256 id) internal returns (bool) {
        if (s.index[addr][id] == 0) {
            s.tokens.push(Token(addr, id));
            s.index[addr][id] = s.tokens.length;
            return true;
        }
        return false;
    }

    function remove(TokenSet storage s, address addr, uint256 id) internal returns (bool) {
        uint256 i = s.index[addr][id];
        if (i != 0) {
            uint256 lastInd = s.tokens.length - 1;
            if (i - 1 != lastInd) {
                Token memory lastToken = s.tokens[lastInd];
                s.tokens[i - 1] = lastToken;
                s.index[lastToken.addr][lastToken.id] = i;
            }
            s.tokens.pop();
            s.index[addr][id] = 0;
            return true;
        }
        return false;
    }

    function contains(TokenSet storage s, address addr, uint256 id) internal view returns (bool) {
        return s.index[addr][id] != 0;
    }

    function count(TokenSet storage s) internal view returns (uint256) {
        return s.tokens.length;
    }

    function get(TokenSet storage s, uint256 seed) internal view returns (address, uint256) {
        if (s.tokens.length > 0) {
            Token memory t = s.tokens[seed % s.tokens.length];
            return (t.addr, t.id);
        } else {
            return (address(0), 0);
        }
    }

    function forEach(TokenSet storage s, function(address, uint) external func) internal {
        for (uint256 i; i < s.tokens.length; ++i) {
            Token memory t = s.tokens[i];
            func(t.addr, t.id);
        }
    }

    function reduce(TokenSet storage s, uint256 acc, function(uint256,address,uint256) external returns (uint256) func) internal returns (uint256) {
        for (uint256 i; i < s.tokens.length; ++i) {
            Token memory t = s.tokens[i];
            acc = func(acc, t.addr, t.id);
        }
        return acc;
    }

    function __toUintSet(AddressSet storage addrSet) internal pure returns (UintSet storage uintSet) {
        assembly {
            uintSet.slot := addrSet.slot
        }
    }

    function add(AddressSet storage s, address a) internal returns (bool) {
        return add(__toUintSet(s), uint256(uint160(a)));
    }

    function remove(AddressSet storage s, address a) internal returns (bool) {
        return remove(__toUintSet(s), uint256(uint160(a)));
    }

    function contains(AddressSet storage s, address a) internal view returns (bool) {
        return contains(__toUintSet(s), uint256(uint160(a)));
    }

    function count(AddressSet storage s) internal view returns (uint256) {
        return count(__toUintSet(s));
    }

    function get(AddressSet storage s, uint256 seed) internal view returns (address) {
        return address(uint160(get(__toUintSet(s), seed)));
    }

    function forEach(AddressSet storage s, function(address) external func) internal {
        for (uint256 i; i < s.addrs.length; ++i) {
            func(s.addrs[i]);
        }
    }

    function reduce(AddressSet storage s, uint256 acc, function(uint256,address) external returns (uint256) func) internal returns (uint256) {
        for (uint256 i; i < s.addrs.length; ++i) {
            acc = func(acc, s.addrs[i]);
        }
        return acc;
    }

    function add(UintSet storage s, uint256 x) internal returns (bool) {
        if (s.index[x] == 0) {
            s.nums.push(x);
            s.index[x] = s.nums.length;
            return true;
        }
        return false;
    }

    function remove(UintSet storage s, uint256 x) internal returns (bool) {
        uint256 i = s.index[x];
        if (i != 0) {
            uint256 lastInd = s.nums.length - 1;
            if (i - 1 != lastInd) {
                uint256 lastNum = s.nums[lastInd];
                s.nums[i - 1] = lastNum;
                s.index[lastNum] = i;
            }
            s.nums.pop();
            s.index[x] = 0;
            return true;
        }
        return false;
    }

    function contains(UintSet storage s, uint256 x) internal view returns (bool) {
        return s.index[x] != 0;
    }

    function count(UintSet storage s) internal view returns (uint256) {
        return s.nums.length;
    }

    function get(UintSet storage s, uint256 seed) internal view returns (uint256) {
        if (s.nums.length > 0) {
            return s.nums[seed % s.nums.length];
        } else {
            return 0;
        }
    }

    function forEach(UintSet storage s, function(uint) external func) internal {
        for (uint256 i; i < s.nums.length; ++i) {
            func(s.nums[i]);
        }
    }

    function reduce(UintSet storage s, uint256 acc, function(uint256,uint256) external returns (uint256) func) internal returns (uint256) {
        for (uint256 i; i < s.nums.length; ++i) {
            acc = func(acc, s.nums[i]);
        }
        return acc;
    }
}
