// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IDelegateToken, TokenType} from "./interfaces/IDelegateToken.sol";

import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";

import {BaseERC721} from "./BaseERC721.sol";

/// @notice A simple NFT that doesn't store any user data itself, being tightly linked to the more stateful Delegate Token.
/// @notice The holder of the PT is eligible to reclaim the escrowed NFT when the DT expires or is burned.
contract PrincipalToken is BaseERC721("Principal Token", "PT") {
    using LibString for address;
    using LibString for uint256;

    address public immutable DELEGATE_TOKEN;

    error NotDT();

    constructor(address _DELEGATE_TOKEN) {
        DELEGATE_TOKEN = _DELEGATE_TOKEN;
    }

    function mint(address to, uint256 id) external onlyDT {
        _mint(to, id);
    }

    function burnIfAuthorized(address burner, uint256 id) external onlyDT {
        // Owner != 0 check done by `_burn`.
        (bool approvedOrOwner,) = _isApprovedOrOwner(burner, id);
        if (!approvedOrOwner) revert NotAuthorized();
        _burn(id);
    }

    modifier onlyDT() {
        if (msg.sender != DELEGATE_TOKEN) revert NotDT();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                        METADATA METHODS
    //////////////////////////////////////////////////////////////*/

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (_ownerOf[id] == address(0)) revert NotMinted();

        IDelegateToken dt = IDelegateToken(DELEGATE_TOKEN);

        (TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, uint256 expiry) = dt.getRightsInfo(id);

        string memory idstr = tokenId.toString();
        string memory imageUrl = string.concat(dt.baseURI(), "principal/", idstr);

        address rightsOwner;
        try dt.ownerOf(id) returns (address retrievedOwner) {
            rightsOwner = retrievedOwner;
        } catch {}

        string memory rightsOwnerStr = rightsOwner == address(0) ? "N/A" : rightsOwner.toHexStringChecksummed();
        string memory status = rightsOwner == address(0) || expiry <= block.timestamp ? "Unlocked" : "Locked";

        string memory metadataStringPart1 = string.concat(
            '{"name":"',
            string.concat(name, " #", idstr),
            '","description":"LiquidDelegate lets you escrow your token for a chosen timeperiod and receive a liquid NFT representing the associated delegation rights. This collection represents the principal i.e. the future right to claim the underlying token once the associated delegate token expires.","attributes":[{"trait_type":"Collection Address","value":"',
            tokenContract.toHexStringChecksummed(),
            '"},{"trait_type":"Token ID","value":"',
            idstr,
            '"},{"trait_type":"Unlocks At","display_type":"date","value":',
            expiry.toString()
        );
        string memory metadataStringPart2 = string.concat(
            '},{"trait_type":"Delegate Owner Address","value":"',
            rightsOwnerStr,
            '"},{"trait_type":"Principal Status","value":"',
            status,
            '"}],"image":"',
            imageUrl,
            '"}'
        );
        // Build in two parts to avoid stack-too-deep
        string memory metadataString = string.concat(metadataStringPart1, metadataStringPart2);

        return string.concat("data:application/json;base64,", Base64.encode(bytes(metadataString)));
    }
}
