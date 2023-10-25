// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DelegateRegistry} from "delegate-registry/src/DelegateRegistry.sol";
import {DelegateToken} from "src/DelegateToken.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";
import {MarketMetadata} from "src/MarketMetadata.sol";
import {CreateOfferer} from "src/CreateOfferer.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {ComputeAddress} from "script/ComputeAddress.s.sol";

contract Deploy is Script {
    using Strings for uint256;
    using Strings for address;

    address payable constant ZERO = payable(address(0x0));
    DelegateRegistry registry = DelegateRegistry(0x00000000000000447e69651d841bD8D104Bed493);
    address seaport15 = 0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC;
    address deployer = 0xBc22c4FbD596885a8C5cd490ba25515dADF1a91A;

    // string baseURI = string.concat("https://metadata.delegate.xyz/", block.chainid.toString(), "/marketplace/v2/");
    string baseURI = string.concat("https://cdn.delegate.xyz/marketplace/v2/", block.chainid.toString(), "/");

    function deploy() external {
        console2.log("msg.sender:", msg.sender);
        require(msg.sender == deployer, "wrong deployer addy");

        vm.startBroadcast();

        MarketMetadata marketMetadata = new MarketMetadata(deployer, baseURI);

        uint256 nonce = vm.getNonce(msg.sender);
        console2.log("nonce:", nonce);
        address _origin = msg.sender;
        address ptPrediction = ComputeAddress.addressFrom(_origin, nonce);
        address dtPrediction = ComputeAddress.addressFrom(_origin, nonce + 1);

        console2.log("ptPrediction:", ptPrediction);
        console2.log("dtPrediction:", dtPrediction);

        PrincipalToken principalToken = new PrincipalToken(dtPrediction);
        DelegateToken delegateToken = new DelegateToken(address(registry), ptPrediction, address(marketMetadata));
        CreateOfferer createOfferer = new CreateOfferer(seaport15, address(delegateToken));

        console2.log("Market Metadata:", address(marketMetadata));
        // console2.log("Delegate Registry", address(registry));
        console2.log("Principal Token:", address(principalToken));
        console2.log("Delegate Token:", address(delegateToken));
        console2.log("Create Offerer:", address(createOfferer));

        require(address(principalToken) == ptPrediction, "wrong sim");
        require(address(delegateToken) == dtPrediction, "wrong sim");

        vm.stopBroadcast();
    }

    function postDeployConfig() external {
        require(msg.sender == deployer, "wrong owner addy");

        vm.startBroadcast();

        MarketMetadata marketMetadata = MarketMetadata(0xBa93c25cD7db01b5d8f4b74aE4e3F5e048144834);
        marketMetadata.setBaseURI(baseURI);

        vm.stopBroadcast();
    }
}
