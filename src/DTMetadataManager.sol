// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC2981} from "openzeppelin-contracts/contracts/token/common/ERC2981.sol";
import {Owned} from "solmate/auth/Owned.sol";

import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";

abstract contract DTMetadataManager is ERC2981, Owned {
    using LibString for address;
    using LibString for uint256;

    string internal _baseURI;

    constructor(string memory baseURI_, address initialOwner) Owned(initialOwner) {
        _baseURI = baseURI_;
    }

    function _name() internal pure virtual returns (string memory) {
        return "Delegate Token";
    }

    function _symbol() internal pure virtual returns (string memory) {
        return "DT";
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function baseURI() public view virtual returns (string memory) {
        return _baseURI;
    }

    function setBaseURI(string memory baseURI_) external onlyOwner {
        _baseURI = baseURI_;
    }

    /// @dev Returns contract-level metadata URI for OpenSea (reference)[https://docs.opensea.io/docs/contract-level-metadata]
    function contractURI() public view returns (string memory) {
        return string.concat(_baseURI, "contract");
    }

    function _buildTokenURI(address tokenContract, uint256 id, uint256 expiry, address principalOwner) internal view returns (string memory) {
        string memory idstr = id.toString();

        string memory pownerstr = principalOwner == address(0) ? "N/A" : principalOwner.toHexStringChecksummed();
        string memory status = principalOwner == address(0) || expiry <= block.timestamp ? "Expired" : "Active";

        string memory metadataStringPart1 = string.concat(
            '{"name":"',
            _name(),
            " #",
            idstr,
            '","description":"LiquidDelegate lets you escrow your token for a chosen timeperiod and receive a liquid NFT representing the associated delegation rights. This collection represents the tokenized delegation rights.","attributes":[{"trait_type":"Collection Address","value":"',
            tokenContract.toHexStringChecksummed(),
            '"},{"trait_type":"Token ID","value":"',
            idstr,
            '"},{"trait_type":"Expires At","display_type":"date","value":',
            expiry.toString()
        );
        string memory metadataStringPart2 = string.concat(
            '},{"trait_type":"Principal Owner Address","value":"',
            pownerstr,
            '"},{"trait_type":"Delegate Status","value":"',
            status,
            '"}]',
            ',"image":"',
            _baseURI,
            "rights/",
            idstr,
            '"}'
        );
        // Build via two substrings to avoid stack-too-deep
        string memory metadataString = string.concat(metadataStringPart1, metadataStringPart2);

        return string.concat("data:application/json;base64,", Base64.encode(bytes(metadataString)));
    }

    /// @dev See {ERC2981-_setDefaultRoyalty}.
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @dev See {ERC2981-_deleteDefaultRoyalty}.
    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }
}
