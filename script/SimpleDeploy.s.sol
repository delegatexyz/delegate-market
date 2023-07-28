// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DelegateRegistry} from "delegate-registry/src/DelegateRegistry.sol";
import {DelegateToken} from "../src/DelegateToken.sol";
import {PrincipalToken} from "../src/PrincipalToken.sol";
import {WrapOfferer} from "../src/WrapOfferer.sol";

contract SimpleDeploy is Script {
    address seaport15 = 0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC;

    string baseURI = "https://metadata.delegate.cash/liquid/";

    // Modified from https://ethereum.stackexchange.com/questions/760/how-is-the-address-of-an-ethereum-contract-computed
    function addressFrom(address _origin, uint256 _nonce) public pure returns (address) {
        if (_nonce == 0x00) {
            return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80))))));
        }
        if (_nonce <= 0x7f) {
            return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(uint8(_nonce)))))));
        }
        if (_nonce <= 0xff) {
            return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce))))));
        }
        if (_nonce <= 0xffff) {
            return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce))))));
        }
        if (_nonce <= 0xffffff) {
            return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce))))));
        }
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce)))))); // more than 2^32 nonces not
            // realistic
    }

    function run() external {
        vm.startBroadcast();

        address delegateRegistry = address(new DelegateRegistry());

        uint256 nonce = vm.getNonce(msg.sender);

        address ptPrediction = addressFrom(msg.sender, nonce);
        address dtPrediction = addressFrom(msg.sender, nonce + 1);

        address principalToken = address(new PrincipalToken(dtPrediction));
        address delegateToken = address(new DelegateToken(delegateRegistry, ptPrediction, baseURI, msg.sender));
        address wrapOfferer = address(new WrapOfferer(seaport15, dtPrediction));

        console2.log("Delegate Registry", delegateRegistry);
        console2.log("Principal Token:", principalToken);
        console2.log("Delegate Token:", delegateToken);
        console2.log("Wrap Offerer:", wrapOfferer);

        require(principalToken == ptPrediction, "wrong sim");
        require(delegateToken == dtPrediction, "wrong sim");

        vm.stopBroadcast();
    }
}
