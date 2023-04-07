// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {BaseERC721} from "./lib/BaseERC721.sol";

import {ILiquidDelegateV2, Rights} from "./interfaces/ILiquidDelegateV2.sol";

import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";

contract PrincipalToken is BaseERC721("Principal (LiquidDelegate V2)", "LDP") {
    using LibString for uint256;
    using LibString for address;

    address public immutable LIQUID_DELEGATE;

    error NotLD();

    modifier onlyLD() {
        if (msg.sender != LIQUID_DELEGATE) revert NotLD();
        _;
    }

    constructor(address _LIQUID_DELEGATE) {
        LIQUID_DELEGATE = _LIQUID_DELEGATE;
    }

    function mint(address to, uint256 id) external onlyLD {
        _mint(to, id);
    }

    function burnIfAuthorized(address burner, uint256 id) external onlyLD {
        // Owner != 0 check done by `_burn`.
        (bool approvedOrOwner,) = _isApprovedOrOwner(burner, id);
        if (!approvedOrOwner) revert NotAuthorized();
        _burn(id);
    }

    /*//////////////////////////////////////////////////////////////
                        METADATA METHODS
    //////////////////////////////////////////////////////////////*/

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (_ownerOf[id] == address(0)) revert NotMinted();

        ILiquidDelegateV2 ld = ILiquidDelegateV2(LIQUID_DELEGATE);

        (,, Rights memory rights) = ld.getRights(id);

        string memory idstr = rights.tokenId.toString();
        string memory imageUrl = string.concat(ld.baseURI(), "principal/", idstr);

        address rightsOwner;
        try ld.ownerOf(id) returns (address retrievedOwner) {
            rightsOwner = retrievedOwner;
        } catch {}

        string memory rightsOwnerStr = rightsOwner == address(0) ? "N/A" : rightsOwner.toHexStringChecksumed();
        string memory status = rightsOwner == address(0) || rights.expiry <= block.timestamp ? "Unlocked" : "Locked";

        string memory metadataString = string.concat(
            '{"name":"',
            string.concat(name, " #", idstr),
            '","description":"LiquidDelegate lets you escrow your token for a chosen timeperiod and receive a liquid NFT representing the associated delegation rights. This collection represents the principal i.e. the future right to claim the underlying token once the associated delegate token expires.","attributes":[{"trait_type":"Collection Address","value":"',
            rights.tokenContract.toHexStringChecksumed(),
            '"},{"trait_type":"Token ID","value":"',
            idstr,
            '"},{"trait_type":"Unlocks At","display_type":"date","value":',
            uint256(rights.expiry).toString(),
            '},{"trait_type":"Delegate Owner Address","value":"',
            rightsOwnerStr,
            '"},{"trait_type":"Principal Status","value":"',
            status,
            '"}],"image":"',
            imageUrl,
            '"}'
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(metadataString)));
    }
}
