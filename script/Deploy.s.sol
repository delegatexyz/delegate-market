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
    address deployer = 0xe5ee2B9d5320f2D1492e16567F36b578372B3d9F;

    string baseURI = string.concat("https://metadata.delegate.xyz/", block.chainid.toString(), "/marketplace/v2/");

    CreateOfferer createOfferer;

    function deploy() external {
        console2.log("msg.sender:", msg.sender);
        require(msg.sender == deployer, "wrong deployer addy");

        uint256 nonce = vm.getNonce(msg.sender);
        console2.log("nonce:", nonce);
        address _origin = msg.sender;
        address ptPrediction = ComputeAddress.addressFrom(_origin, nonce);
        address dtPrediction = ComputeAddress.addressFrom(_origin, nonce + 1);

        console2.log("ptPrediction:", ptPrediction);
        console2.log("dtPrediction:", dtPrediction);

        vm.startBroadcast();

        MarketMetadata marketMetadata = new MarketMetadata(deployer, baseURI);
        PrincipalToken principalToken = new PrincipalToken(dtPrediction);
        DelegateToken delegateToken = new DelegateToken(address(registry), ptPrediction, address(marketMetadata));
        createOfferer = new CreateOfferer(seaport15, address(delegateToken));

        console2.log("Delegate Registry", address(registry));
        console2.log("Principal Token:", address(principalToken));
        console2.log("Delegate Token:", address(delegateToken));
        console2.log("Create Offerer:", address(createOfferer));
        console2.log("Market Metadata:", address(marketMetadata));

        require(address(principalToken) == ptPrediction, "wrong sim");
        require(address(delegateToken) == dtPrediction, "wrong sim");

        vm.stopBroadcast();
    }

    function postDeployConfig() external {
        require(msg.sender == deployer, "wrong owner addy");

        vm.startBroadcast();

        vm.stopBroadcast();
    }
}
