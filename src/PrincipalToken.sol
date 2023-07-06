// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IDelegateToken, IDelegateRegistry} from "./interfaces/IDelegateToken.sol";

import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";

import {ERC721} from "solady/tokens/ERC721.sol";

/// @notice A simple NFT that doesn't store any user data itself, being tightly linked to the more stateful Delegate Token.
/// @notice The holder of the PT is eligible to reclaim the escrowed NFT when the DT expires or is burned.
contract PrincipalToken is ERC721 {
    address public immutable delegateToken;

    error CallerNotDelegateToken();
    error NotAuthorized();
    error NotMinted();
    error NotDelegateToken();

    constructor(address delegateToken_) {
        if (delegateToken_ == address(0)) revert NotDelegateToken();
        delegateToken = delegateToken_;
    }

    function name() public pure override returns (string memory) {
        return "Principal Token";
    }

    function symbol() public pure override returns (string memory) {
        return "PT";
    }

    function mint(address to, uint256 id) external {
        if (msg.sender != delegateToken) revert CallerNotDelegateToken();
        _mint(to, id);
    }

    function burnIfAuthorized(address burner, uint256 id) external {
        if (msg.sender != delegateToken) revert CallerNotDelegateToken();
        if (!_isApprovedOrOwner(burner, id)) revert NotAuthorized();
        _burn(id);
    }

    /// @dev expose _isApprovedOrOwner method
    function isApprovedOrOwner(address account, uint256 id) external view returns (bool) {
        return _isApprovedOrOwner(account, id);
    }

    /*//////////////////////////////////////////////////////////////
                        METADATA METHODS
    //////////////////////////////////////////////////////////////*/

    /// TODO: implement support for ERC20 and ERC1155 metadata
    function tokenURI(uint256 id) public view override returns (string memory) {
        if (_ownerOf(id) == address(0)) revert NotMinted();

        IDelegateToken dt = IDelegateToken(delegateToken);

        (
            /* delegation type */
            ,
            address tokenContract,
            uint256 tokenId,
            /* tokenAmount */
            ,
            /* right */
            ,
            uint256 expiry
        ) = dt.getDelegateInfo(id);

        string memory idstr = LibString.toString(tokenId);
        string memory imageUrl = string.concat(dt.baseURI(), "principal/", idstr);

        address rightsOwner = address(0);
        try dt.ownerOf(id) returns (address retrievedOwner) {
            rightsOwner = retrievedOwner;
        } catch {}

        string memory rightsOwnerStr = rightsOwner == address(0) ? "N/A" : LibString.toHexStringChecksummed(rightsOwner);
        string memory status = rightsOwner == address(0) || expiry <= block.timestamp ? "Unlocked" : "Locked";

        string memory firstPartOfMetadataString = string.concat(
            '{"name":"',
            string.concat(name(), " #", idstr),
            '","description":"LiquidDelegate lets you escrow your token for a chosen timeperiod and receive a liquid NFT representing the associated delegation rights. This collection represents the principal i.e. the future right to claim the underlying token once the associated delegate token expires.","attributes":[{"trait_type":"Collection Address","value":"',
            LibString.toHexStringChecksummed(tokenContract),
            '"},{"trait_type":"Token ID","value":"',
            idstr,
            '"},{"trait_type":"Unlocks At","display_type":"date","value":',
            LibString.toString(expiry)
        );
        string memory secondPartOfMetadataString = string.concat(
            '},{"trait_type":"Delegate Owner Address","value":"', rightsOwnerStr, '"},{"trait_type":"Principal Status","value":"', status, '"}],"image":"', imageUrl, '"}'
        );
        // Build in two parts to avoid stack-too-deep
        string memory metadataString = string.concat(firstPartOfMetadataString, secondPartOfMetadataString);

        return string.concat("data:application/json;base64,", Base64.encode(bytes(metadataString)));
    }
}
