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
            '"},{"trait_type":"Token Amount","display_type":"number","value":',
            info.amount.toString(),
            '},{"trait_type":"Rights","value":"',
            fromSmallString(info.rights),
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
            '"},{"trait_type":"Token Amount","display_type":"number","value":',
            info.amount.toString(),
            '},{"trait_type":"Rights","value":"',
            fromSmallString(info.rights),
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

    /// @dev Returns a string from a small bytes32 string.
    function fromSmallString(bytes32 smallString) internal pure returns (string memory result) {
        if (smallString == bytes32(0)) return result;
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40)
            let n
            for {} 1 {} {
                n := add(n, 1)
                if iszero(byte(n, smallString)) { break } // Scan for '\0'.
            }
            mstore(result, n)
            let o := add(result, 0x20)
            mstore(o, smallString)
            mstore(add(o, n), 0)
            mstore(0x40, add(result, 0x40))
        }
    }
}
