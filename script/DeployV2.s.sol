// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DelegationRegistry} from "../src/DelegationRegistry.sol";
import {LiquidDelegateV2} from "../src/LiquidDelegateV2.sol";
import {PrincipalToken} from "../src/PrincipalToken.sol";
import {WrapOfferer} from "../src/WrapOfferer.sol";
import {Strings} from "openzeppelin-contracts/utils/Strings.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";

contract DeployV2 is Script {
    using Strings for uint256;
    using Strings for address;

    address payable constant ZERO = payable(address(0x0));
    DelegationRegistry registry = DelegationRegistry(0x00000000000076A84feF008CDAbe6409d2FE638B);
    address seaport14 = 0x00000000000001ad428e4906aE43D8F9852d0dD6;
    address deployer = 0xe5ee2B9d5320f2D1492e16567F36b578372B3d9F;

    address ptAddress = address(0xE98b24636746704f53625ed4300d84181819E512); // populate via simulation
    address ldAddress = address(0x70Ee311907291129a959b5Bf6AE1d4a3Ed869CDE); // populate via simulation

    string baseURI = "https://metadata.delegate.cash/liquid/";

    function deploy() external {
        console2.log(msg.sender);
        require(msg.sender == deployer, "wrong deployer addy");

        vm.startBroadcast();

        PrincipalToken pt = new PrincipalToken(ldAddress);
        LiquidDelegateV2 ld = new LiquidDelegateV2(address(registry), ptAddress, baseURI, deployer);
        WrapOfferer market = new WrapOfferer(seaport14, ldAddress);

        require(address(pt) == ptAddress, "wrong sim");
        require(address(ld) == ldAddress, "wrong sim");

        vm.stopBroadcast();
    }

    function postDeployConfig() external {
        // require(msg.sender == owner, "wrong owner addy");
        PrincipalToken pt = PrincipalToken(0xE98b24636746704f53625ed4300d84181819E512);
        LiquidDelegateV2 ld = LiquidDelegateV2(0x70Ee311907291129a959b5Bf6AE1d4a3Ed869CDE);
        WrapOfferer wo = WrapOfferer(0x74A2Dc882b41DD2dB3DB88857dDc0f28F257473f);

        vm.startBroadcast();


        // string memory baseURI = string.concat("https://metadata.delegate.cash/liquid/", block.chainid.toString(), "/", address(rights).toHexString(), "/");
        // rights.setBaseURI(baseURI);
        // uint256 creationFee = 0.01 ether;
        // uint256 creationFee = 0 ether;
        // rights.setCreationFee(creationFee);

        vm.stopBroadcast();
    }
}
