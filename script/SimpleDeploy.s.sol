// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {DelegateRegistry} from "delegate-registry/src/DelegateRegistry.sol";
import {DelegateToken, Structs as DelegateTokenStructs} from "src/DelegateToken.sol";
import {PrincipalToken} from "src/PrincipalToken.sol";
import {CreateOfferer, Structs as OffererStructs} from "src/CreateOfferer.sol";
import {ComputeAddress} from "script/ComputeAddress.s.sol";

contract SimpleDeploy is Script {
    address seaport15 = 0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC;
    address seaportConduit = 0x1E0049783F008A0085193E00003D00cd54003c71;

    string baseURI = "https://metadata.delegate.cash/liquid/";

    function run() external {
        vm.startBroadcast();

        address delegateRegistry = address(new DelegateRegistry());

        uint256 nonce = vm.getNonce(msg.sender);

        address ptPrediction = ComputeAddress.addressFrom(msg.sender, nonce);
        address dtPrediction = ComputeAddress.addressFrom(msg.sender, nonce + 1);

        address principalToken = address(new PrincipalToken(dtPrediction));
        DelegateTokenStructs.DelegateTokenParameters memory delegateTokenParameters = DelegateTokenStructs.DelegateTokenParameters({
            delegateRegistry: delegateRegistry,
            principalToken: ptPrediction,
            baseURI: baseURI,
            initialMetadataOwner: msg.sender
        });
        address delegateToken = address(new DelegateToken(delegateTokenParameters));
        OffererStructs.Parameters memory createOffererParameters =
            OffererStructs.Parameters({seaport: seaport15, seaportConduit: seaportConduit, delegateToken: delegateToken, principalToken: principalToken});
        address createOfferer = address(new CreateOfferer(createOffererParameters));

        console2.log("Delegate Registry", delegateRegistry);
        console2.log("Principal Token:", principalToken);
        console2.log("Delegate Token:", delegateToken);
        console2.log("Wrap Offerer:", createOfferer);

        require(principalToken == ptPrediction, "wrong sim");
        require(delegateToken == dtPrediction, "wrong sim");

        vm.stopBroadcast();
    }
}
