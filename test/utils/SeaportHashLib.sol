// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {OrderParameters, ConsiderationItem, OfferItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

library SeaportHashLib {
    bytes32 internal constant OFFER_ITEM_TYPEHASH =
        keccak256("OfferItem(uint8 itemType,address token,uint256 identifierOrCriteria,uint256 startAmount,uint256 endAmount)");
    bytes32 internal constant CONSIDERATION_ITEM_TYPEHASH =
        keccak256("ConsiderationItem(uint8 itemType,address token,uint256 identifierOrCriteria,uint256 startAmount,uint256 endAmount,address recipient)");
    bytes32 internal constant ORDER_TYPEHASH = keccak256(
        "OrderComponents(address offerer,address zone,OfferItem[] offer,ConsiderationItem[] consideration,uint8 orderType,uint256 startTime,uint256 endTime,bytes32 zoneHash,uint256 salt,bytes32 conduitKey,uint256 counter)ConsiderationItem(uint8 itemType,address token,uint256 identifierOrCriteria,uint256 startAmount,uint256 endAmount,address recipient)OfferItem(uint8 itemType,address token,uint256 identifierOrCriteria,uint256 startAmount,uint256 endAmount)"
    );

    function erc712DigestOf(bytes32 _domainSeparator, bytes32 _structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(uint16(0x1901), _domainSeparator, _structHash));
    }

    function hash(OfferItem memory offerItem) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(OFFER_ITEM_TYPEHASH, offerItem.itemType, offerItem.token, offerItem.identifierOrCriteria, offerItem.startAmount, offerItem.endAmount)
        );
    }

    function hash(ConsiderationItem memory considerationItem) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CONSIDERATION_ITEM_TYPEHASH,
                considerationItem.itemType,
                considerationItem.token,
                considerationItem.identifierOrCriteria,
                considerationItem.startAmount,
                considerationItem.endAmount,
                considerationItem.recipient
            )
        );
    }

    /// @dev Taken from Seaport
    function hash(OrderParameters memory orderParams, uint256 counter) internal pure returns (bytes32) {
        // Designate new memory regions for offer and consideration item hashes.
        bytes32[] memory offerHashes = new bytes32[](
            orderParams.offer.length
        );
        bytes32[] memory considerationHashes = new bytes32[](
            orderParams.totalOriginalConsiderationItems
        );

        // Iterate over each offer on the order.
        for (uint256 i = 0; i < orderParams.offer.length; ++i) {
            // Hash the offer and place the result into memory.
            offerHashes[i] = hash(orderParams.offer[i]);
        }

        // Iterate over each consideration on the order.
        for (uint256 i = 0; i < orderParams.totalOriginalConsiderationItems; ++i) {
            // Hash the consideration and place the result into memory.
            considerationHashes[i] = hash(orderParams.consideration[i]);
        }

        // Derive and return the order hash as specified by EIP-712.

        return keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                orderParams.offerer,
                orderParams.zone,
                keccak256(abi.encodePacked(offerHashes)),
                keccak256(abi.encodePacked(considerationHashes)),
                orderParams.orderType,
                orderParams.startTime,
                orderParams.endTime,
                orderParams.zoneHash,
                orderParams.salt,
                orderParams.conduitKey,
                counter
            )
        );
    }
}
