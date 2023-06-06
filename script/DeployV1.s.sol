// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DelegateRegistry} from "delegate-registry/src/DelegateRegistry.sol";
import {LiquidDelegate} from "../src/LiquidDelegate.sol";
import {LiquidDelegateMarket} from "../src/LiquidDelegateMarket.sol";
import {MockERC721Metadata} from "../src/MockERC721Metadata.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

contract DeployV1 is Script {
    using Strings for uint256;
    using Strings for address;

    address payable constant ZERO = payable(address(0x0));
    DelegateRegistry registry = DelegateRegistry(0x00000000000076A84feF008CDAbe6409d2FE638B);
    address constant deployer = 0x65e5e55A221886B22cf2e3dE4c2b9126a16514F5;
    address constant owner = 0xB69319B9B3Eb6cD99f5379b9b3909570F099652a;

    LiquidDelegate rights;
    LiquidDelegateMarket market;

    function deploy() external {
        require(msg.sender == deployer, "wrong deployer addy");

        vm.startBroadcast();

        rights = new LiquidDelegate(address(registry), owner, "");
        market = new LiquidDelegateMarket(address(rights));

        vm.stopBroadcast();
    }

    function postDeployConfig() external {
        require(msg.sender == owner, "wrong owner addy");
        rights = LiquidDelegate(address(0x2E7AfEE4d068Cdcc427Dba6AE2A7de94D15cf356));
        market = LiquidDelegateMarket(address(0xA54E8f1eA1cD5D208b0449f984E783da75a6887d));

        vm.startBroadcast();

        // string memory baseURI = string.concat("https://metadata.delegate.cash/liquid/", block.chainid.toString(), "/", address(rights).toHexString(), "/");
        // rights.setBaseURI(baseURI);
        // uint256 creationFee = 0.01 ether;
        // uint256 creationFee = 0 ether;
        // rights.setCreationFee(creationFee);

        vm.stopBroadcast();
    }
}
