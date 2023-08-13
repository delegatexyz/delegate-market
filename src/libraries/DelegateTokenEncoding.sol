// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {Base64} from "openzeppelin/utils/Base64.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";

library DelegateTokenEncoding {
    function tokenURI(string storage baseURI, address tokenContract, uint256 delegateTokenId, uint256 expiry, address principalOwner)
        internal
        view
        returns (string memory)
    {
        string memory idstr = Strings.toString(delegateTokenId);

        string memory pownerstr = principalOwner == address(0) ? "N/A" : Strings.toHexString(principalOwner);
        //slither-disable-next-line timestamp
        string memory status = principalOwner == address(0) || expiry <= block.timestamp ? "Expired" : "Active";

        string memory firstPartOfMetadataString = string.concat(
            '{"name":"Delegate Token #"',
            idstr,
            '","description":"LiquidDelegate lets you escrow your token for a chosen timeperiod and receive a liquid NFT representing the associated delegation rights. This collection represents the tokenized delegation rights.","attributes":[{"trait_type":"Collection Address","value":"',
            Strings.toHexString(tokenContract),
            '"},{"trait_type":"Token ID","value":"',
            idstr,
            '"},{"trait_type":"Expires At","display_type":"date","value":',
            Strings.toString(expiry)
        );
        string memory secondPartOfMetadataString = string.concat(
            '},{"trait_type":"Principal Owner Address","value":"',
            pownerstr,
            '"},{"trait_type":"Delegate Status","value":"',
            status,
            '"}]',
            ',"image":"',
            baseURI,
            "rights/",
            idstr,
            '"}'
        );
        // Build via two substrings to avoid stack-too-deep
        string memory metadataString = string.concat(firstPartOfMetadataString, secondPartOfMetadataString);

        return string.concat("data:application/json;base64,", Base64.encode(bytes(metadataString)));
    }

    function delegateId(address caller, uint256 salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(caller, salt)));
    }
}
