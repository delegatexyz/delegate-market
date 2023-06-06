// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DelegateRegistry} from "delegate-registry/src/DelegateRegistry.sol";
import {DelegateToken} from "../src/DelegateToken.sol";
import {PrincipalToken} from "../src/PrincipalToken.sol";
import {WrapOfferer} from "../src/WrapOfferer.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

contract DeployV2 is Script {
    using Strings for uint256;
    using Strings for address;

    address payable constant ZERO = payable(address(0x0));
    DelegateRegistry registry = DelegateRegistry(0x00000000000076A84feF008CDAbe6409d2FE638B);
    address seaport15 = 0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC;
    address deployer = 0xe5ee2B9d5320f2D1492e16567F36b578372B3d9F;

    string baseURI = "https://metadata.delegate.cash/liquid/";

    WrapOfferer market;

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
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce)))))); // more than 2^32 nonces not realistic
    }

    function deploy() external {
        console2.log("msg.sender:", msg.sender);
        require(msg.sender == deployer, "wrong deployer addy");

        uint256 nonce = vm.getNonce(msg.sender);
        console2.log("nonce:", nonce);
        address _origin = msg.sender;
        address ptPrediction = addressFrom(_origin, nonce);
        address dtPrediction = addressFrom(_origin, nonce + 1);

        console2.log("ptPrediction:", ptPrediction);
        console2.log("dtPrediction:", dtPrediction);

        vm.startBroadcast();

        PrincipalToken pt = new PrincipalToken(dtPrediction);
        DelegateToken dt = new DelegateToken(address(registry), ptPrediction, baseURI, deployer);
        market = new WrapOfferer(seaport15, dtPrediction);

        console2.log("ptAddress:", address(pt));
        console2.log("dtAddress:", address(dt));

        require(address(pt) == ptPrediction, "wrong sim");
        require(address(dt) == dtPrediction, "wrong sim");

        vm.stopBroadcast();
    }

    function postDeployConfig() external {
        // require(msg.sender == owner, "wrong owner addy");

        vm.startBroadcast();

        // string memory baseURI = string.concat("https://metadata.delegate.cash/liquid/", block.chainid.toString(), "/", address(rights).toHexString(), "/");
        // rights.setBaseURI(baseURI);
        // uint256 creationFee = 0.01 ether;
        // uint256 creationFee = 0 ether;
        // rights.setCreationFee(creationFee);

        vm.stopBroadcast();
    }
}
