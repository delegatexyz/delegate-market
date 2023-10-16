// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {DelegateTokenStructs, DelegateTokenErrors} from "./libraries/DelegateTokenLib.sol";
import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";

import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {ERC2981} from "openzeppelin/token/common/ERC2981.sol";

import {Base64} from "openzeppelin/utils/Base64.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";

contract MarketMetadata is Ownable2Step, ERC2981 {
    using Strings for address;
    using Strings for uint256;

    string public baseURI;

    string internal constant DT_NAME = "Delegate Token";
    string internal constant PT_NAME = "Principal Token";
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

    /// @dev Attributes are "collection address", "token id", "expires at", "principal owner address", "delegate status"
    function delegateTokenURI(uint256 delegateTokenId, DelegateTokenStructs.DelegateInfo calldata info) external view returns (string memory) {
        string memory imageUrl = string.concat(baseURI, "delegate/", delegateTokenId.toString());

        // Split attributes construction into two parts to avoid stack-too-deep
        string memory attributes1 = string.concat(
            '[{"trait_type":"Token Type","value":"',
            _tokenTypeToString(info.tokenType),
            '"},{"trait_type":"Principal Holder","value":"',
            info.principalHolder.toHexString(),
            '"},{"trait_type":"Delegate Holder","value":"',
            info.delegateHolder.toHexString(),
            '"},{"trait_type":"Token Contract","value":"',
            info.tokenContract.toHexString()
        );
        string memory attributes2 = string.concat(
            '"},{"trait_type":"Token Id","value":"',
            info.tokenId.toString(),
            '"},{"trait_type":"Token Amount","value":"',
            info.amount.toString(),
            '"},{"trait_type":"Rights","value":"',
            _bytes32ToString(info.rights),
            '"},{"trait_type":"Expiry","display_type":"date","value":',
            info.expiry.toString(),
            "}]"
        );
        string memory attributes = string.concat(attributes1, attributes2);

        string memory metadataString = string.concat('{"name": "', DT_NAME, '","description":"', DT_DESCRIPTION, '","image":"', imageUrl, '","attributes":', attributes, "}");

        return string.concat("data:application/json;base64,", Base64.encode(bytes(metadataString)));
    }

    function principalTokenURI(uint256 delegateTokenId, DelegateTokenStructs.DelegateInfo calldata info) external view returns (string memory) {
        string memory imageUrl = string.concat(baseURI, "principal/", delegateTokenId.toString());

        // Split attributes construction into two parts to avoid stack-too-deep
        string memory attributes1 = string.concat(
            '[{"trait_type":"Token Type","value":"',
            _tokenTypeToString(info.tokenType),
            '"},{"trait_type":"Principal Holder","value":"',
            info.principalHolder.toHexString(),
            '"},{"trait_type":"Delegate Holder","value":"',
            info.delegateHolder.toHexString(),
            '"},{"trait_type":"Token Contract","value":"',
            info.tokenContract.toHexString()
        );
        string memory attributes2 = string.concat(
            '"},{"trait_type":"Token Id","value":"',
            info.tokenId.toString(),
            '"},{"trait_type":"Token Amount","value":"',
            info.amount.toString(),
            '"},{"trait_type":"Rights","value":"',
            _bytes32ToString(info.rights),
            '"},{"trait_type":"Expiry","display_type":"date","value":',
            info.expiry.toString(),
            "}]"
        );
        string memory attributes = string.concat(attributes1, attributes2);

        string memory metadataString = string.concat('{"name": "', PT_NAME, '","description":"', PT_DESCRIPTION, '","image":"', imageUrl, '","attributes":', attributes, "}");

        return string.concat("data:application/json;base64,", Base64.encode(bytes(metadataString)));
    }

    function _tokenTypeToString(IDelegateRegistry.DelegationType tokenType) internal pure returns (string memory) {
        if (tokenType == IDelegateRegistry.DelegationType.ALL) {
            return "ALL";
        } else if (tokenType == IDelegateRegistry.DelegationType.CONTRACT) {
            return "CONTRACT";
        } else if (tokenType == IDelegateRegistry.DelegationType.ERC721) {
            return "ERC721";
        } else if (tokenType == IDelegateRegistry.DelegationType.ERC20) {
            return "ERC20";
        } else if (tokenType == IDelegateRegistry.DelegationType.ERC1155) {
            return "ERC1155";
        } else {
            revert DelegateTokenErrors.InvalidTokenType(tokenType);
        }
    }

    function _bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        bytes memory bytesArray = new bytes(64);
        for (i = 0; i < bytesArray.length; i++) {
            uint8 _f = uint8(_bytes32[i / 2] & 0x0f);
            uint8 _l = uint8(_bytes32[i / 2] >> 4);

            bytesArray[i] = _toByte(_f);
            i = i + 1;
            bytesArray[i] = _toByte(_l);
        }
        return string(bytesArray);
    }

    function _toByte(uint8 _uint8) internal pure returns (bytes1) {
        if (_uint8 < 10) {
            return bytes1(_uint8 + 48);
        } else {
            return bytes1(_uint8 + 87);
        }
    }
}
