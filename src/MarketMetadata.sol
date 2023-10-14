// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IDelegateToken} from "./interfaces/IDelegateToken.sol";
import {DelegateTokenStructs} from "./libraries/DelegateTokenLib.sol";

import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {ERC2981} from "openzeppelin/token/common/ERC2981.sol";

import {Base64} from "openzeppelin/utils/Base64.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";

contract MarketMetadata is Ownable2Step, ERC2981 {
    using Strings for address;
    using Strings for uint256;

    string public baseURI;

    string internal constant DT_DESCRIPTION =
        "DelegateMarket lets you escrow your token for a chosen timeperiod and receive a token representing its delegate rights. These tokens represent tokenized delegate rights.";
    string internal constant PT_DESCRIPTION =
        "DelegateMarket lets you escrow your token for a chosen timeperiod and receive a token representing its delegate rights. These tokens represents the right to claim the escrowed spot asset once the delegate token expires.";

    constructor(address initialOwner, string memory initialBaseURI) {
        baseURI = initialBaseURI;
        _transferOwnership(initialOwner);
    }

    function setDelegateTokenBaseURI(string calldata uri) external onlyOwner {
        baseURI = uri;
    }

    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }

    function delegateTokenContractURI() external view returns (string memory) {
        return string.concat(baseURI, "delegateContract");
    }

    function principalTokenContractURI() external view returns (string memory) {
        return string.concat(baseURI, "principalContract");
    }

    function delegateTokenURI(address tokenContract, uint256 delegateTokenId, uint256 expiry, address principalOwner) external view returns (string memory) {
        string memory idstr = delegateTokenId.toString();

        string memory pownerstr = principalOwner == address(0) ? "N/A" : principalOwner.toHexString();
        //slither-disable-next-line timestamp
        string memory status = principalOwner == address(0) || expiry <= block.timestamp ? "Expired" : "Active";

        string memory imageUrl = string.concat(baseURI, "delegate/", idstr);

        string memory firstPartOfMetadataString = string.concat(
            '{"name":"Delegate Token #"',
            idstr,
            '","description":"',
            DT_DESCRIPTION,
            '","attributes":[{"trait_type":"Collection Address","value":"',
            tokenContract.toHexString(),
            '"},{"trait_type":"Token ID","value":"',
            idstr,
            '"},{"trait_type":"Expires At","display_type":"date","value":',
            expiry.toString()
        );
        string memory secondPartOfMetadataString = string.concat(
            '},{"trait_type":"Principal Owner Address","value":"', pownerstr, '"},{"trait_type":"Delegate Status","value":"', status, '"}]', ',"image":"', imageUrl, '"}'
        );
        // Build via two substrings to avoid stack-too-deep
        string memory metadataString = string.concat(firstPartOfMetadataString, secondPartOfMetadataString);

        return string.concat("data:application/json;base64,", Base64.encode(bytes(metadataString)));
    }

    function principalTokenURI(address delegateToken, uint256 id) external view returns (string memory) {
        IDelegateToken dt = IDelegateToken(delegateToken);

        DelegateTokenStructs.DelegateInfo memory delegateInfo = dt.getDelegateTokenInfo(id);

        string memory idstr = delegateInfo.tokenId.toString();
        string memory imageUrl = string.concat(baseURI, "principal/", idstr);

        address rightsOwner = address(0);
        try dt.ownerOf(id) returns (address retrievedOwner) {
            rightsOwner = retrievedOwner;
        } catch {}

        string memory rightsOwnerStr = rightsOwner == address(0) ? "N/A" : rightsOwner.toHexString();
        //slither-disable-next-line timestamp
        string memory status = rightsOwner == address(0) || delegateInfo.expiry <= block.timestamp ? "Unlocked" : "Locked";

        string memory firstPartOfMetadataString = string.concat(
            '{"name":"',
            string.concat(dt.name(), " #", idstr),
            '","description":"',
            PT_DESCRIPTION,
            '","attributes":[{"trait_type":"Collection Address","value":"',
            delegateInfo.tokenContract.toHexString(),
            '"},{"trait_type":"Token ID","value":"',
            idstr,
            '"},{"trait_type":"Unlocks At","display_type":"date","value":',
            delegateInfo.expiry.toString()
        );
        string memory secondPartOfMetadataString = string.concat(
            '},{"trait_type":"Delegate Owner Address","value":"', rightsOwnerStr, '"},{"trait_type":"Principal Status","value":"', status, '"}],"image":"', imageUrl, '"}'
        );
        // Build in two parts to avoid stack-too-deep
        string memory metadataString = string.concat(firstPartOfMetadataString, secondPartOfMetadataString);

        return string.concat("data:application/json;base64,", Base64.encode(bytes(metadataString)));
    }
}
