// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DelegateRegistry} from "delegate-registry/src/DelegateRegistry.sol";
import {DelegateToken, Structs as DelegateTokenStructs} from "src/DelegateToken.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";
import {MarketMetadata} from "src/MarketMetadata.sol";
import {CreateOfferer, Structs as OffererStructs} from "src/CreateOfferer.sol";
import {ComputeAddress} from "script/ComputeAddress.s.sol";

contract SimpleDeploy is Script {
    address seaport15 = 0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC;

    string baseURI = "https://metadata.delegate.cash/liquid/";

    function run() external {
        vm.startBroadcast();

        address delegateRegistry = address(new DelegateRegistry());
        address marketMetadata = address(new MarketMetadata(msg.sender, baseURI));

        uint256 nonce = vm.getNonce(msg.sender);

        address ptPrediction = ComputeAddress.addressFrom(msg.sender, nonce);
        address dtPrediction = ComputeAddress.addressFrom(msg.sender, nonce + 1);

        address principalToken = address(new PrincipalToken(dtPrediction));
        DelegateTokenStructs.DelegateTokenParameters memory delegateTokenParameters =
            DelegateTokenStructs.DelegateTokenParameters({delegateRegistry: delegateRegistry, principalToken: ptPrediction, marketMetadata: marketMetadata});
        address delegateToken = address(new DelegateToken(delegateTokenParameters));
        OffererStructs.Parameters memory createOffererParameters = OffererStructs.Parameters({seaport: seaport15, delegateToken: delegateToken, principalToken: principalToken});
        address createOfferer = address(new CreateOfferer(createOffererParameters));

        console2.log("Delegate Registry", delegateRegistry);
        console2.log("Principal Token:", principalToken);
        console2.log("Delegate Token:", delegateToken);
        console2.log("Create Offerer:", createOfferer);

        require(principalToken == ptPrediction, "wrong sim");
        require(delegateToken == dtPrediction, "wrong sim");

        vm.stopBroadcast();
    }
}
