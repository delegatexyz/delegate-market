// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

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
        "The Delegate Marketplace lets you escrow your token for a chosen time period and receive a token representing its delegate rights. These tokens represent tokenized delegate rights.";
    string internal constant PT_DESCRIPTION =
        "The Delegate Marketplace lets you escrow your token for a chosen time period and receive a token representing its delegate rights. These tokens represents the right to claim the escrowed spot asset once the delegate token expires.";

    constructor(address initialOwner, string memory initialBaseURI) {
        baseURI = initialBaseURI;
        _transferOwnership(initialOwner);
    }

    function setBaseURI(string calldata uri) external onlyOwner {
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

    function delegateTokenURI(uint256 delegateTokenId, DelegateTokenStructs.DelegateInfo calldata info) external view returns (string memory) {
        //slither-disable-next-line timestamp
        string memory status = info.principalHolder == address(0) || info.expiry <= block.timestamp ? "Expired" : "Active";

        string memory imageUrl = string.concat(baseURI, "delegate/", delegateTokenId.toString());

        string memory firstPartOfMetadataString = string.concat(
            '{"name": "',
            "DelegateToken",
            '","description":"',
            DT_DESCRIPTION,
            '","attributes":[{"trait_type":"Collection Address","value":"',
            info.tokenContract.toHexString(),
            '"},{"trait_type":"Token ID","value":"',
            info.tokenId.toString(),
            '"},{"trait_type":"Expires At","display_type":"date","value":',
            info.expiry.toString()
        );
        string memory secondPartOfMetadataString = string.concat(
            '},{"trait_type":"Principal Owner Address","value":"',
            info.principalHolder.toHexString(),
            '"},{"trait_type":"Delegate Status","value":"',
            status,
            '"}]',
            ',"image":"',
            imageUrl,
            '"}'
        );
        // Build via two substrings to avoid stack-too-deep
        string memory metadataString = string.concat(firstPartOfMetadataString, secondPartOfMetadataString);

        return string.concat("data:application/json;base64,", Base64.encode(bytes(metadataString)));
    }

    function principalTokenURI(uint256 delegateTokenId, DelegateTokenStructs.DelegateInfo calldata info) external view returns (string memory) {
        string memory imageUrl = string.concat(baseURI, "principal/", delegateTokenId.toString());

        //slither-disable-next-line timestamp
        string memory status = info.delegateHolder == address(0) || info.expiry <= block.timestamp ? "Unlocked" : "Locked";

        string memory firstPartOfMetadataString = string.concat(
            '{"name":"',
            "PrincipalToken",
            '","description":"',
            PT_DESCRIPTION,
            '","attributes":[{"trait_type":"Collection Address","value":"',
            info.tokenContract.toHexString(),
            '"},{"trait_type":"Token ID","value":"',
            info.tokenId.toString(),
            '"},{"trait_type":"Unlocks At","display_type":"date","value":',
            info.expiry.toString()
        );
        string memory secondPartOfMetadataString = string.concat(
            '},{"trait_type":"Delegate Owner Address","value":"',
            info.delegateHolder.toHexString(),
            '"},{"trait_type":"Principal Status","value":"',
            status,
            '"}],"image":"',
            imageUrl,
            '"}'
        );
        // Build in two parts to avoid stack-too-deep
        string memory metadataString = string.concat(firstPartOfMetadataString, secondPartOfMetadataString);

        return string.concat("data:application/json;base64,", Base64.encode(bytes(metadataString)));
    }
}
