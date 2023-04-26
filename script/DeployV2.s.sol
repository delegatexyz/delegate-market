// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DelegationRegistry} from "../src/DelegationRegistry.sol";
import {DelegateToken} from "../src/DelegateToken.sol";
import {PrincipalToken} from "../src/PrincipalToken.sol";
import {WrapOfferer} from "../src/WrapOfferer.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

contract DeployV2 is Script {
    using Strings for uint256;
    using Strings for address;

    address payable constant ZERO = payable(address(0x0));
    DelegationRegistry registry = DelegationRegistry(0x00000000000076A84feF008CDAbe6409d2FE638B);
    address seaport15 = 0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC;
    address deployer = 0xe5ee2B9d5320f2D1492e16567F36b578372B3d9F;

    address ptAddress = address(0xcA2430C1Ac3f9bfd558481Fcf5cce5dC1d3454bC); // populate via simulation
    address dtAddress = address(0x8525572bCC80c7c558Bbd7f387948fCb1144e2df); // populate via simulation

    string baseURI = "https://metadata.delegate.cash/liquid/";

    function deploy() external {
        console2.log(msg.sender);
        require(msg.sender == deployer, "wrong deployer addy");

        vm.startBroadcast();

        PrincipalToken pt = new PrincipalToken(dtAddress);
        DelegateToken dt = new DelegateToken(address(registry), ptAddress, baseURI, deployer);
        WrapOfferer market = new WrapOfferer(seaport15, dtAddress);

        require(address(pt) == ptAddress, "wrong sim");
        require(address(dt) == dtAddress, "wrong sim");

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
