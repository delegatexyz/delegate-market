// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {EIP712} from "solady/utils/EIP712.sol";
import {IWrapOfferer, ReceiptFillerType} from "./interfaces/IWrapOfferer.sol";

import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";
import {ReceivedItem, SpentItem, Schema} from "seaport/interfaces/ContractOffererInterface.sol";
import {ItemType} from "seaport/lib/ConsiderationEnums.sol";

import {ILiquidDelegateV2, ExpiryType} from "./interfaces/ILiquidDelegateV2.sol";

contract WrapOfferer is IWrapOfferer, EIP712 {
    using LibBitmap for LibBitmap.Bitmap;

    bytes32 internal constant RELATIVE_EXPIRY_TYPE_HASH = keccak256("Relative");
    bytes32 internal constant ABSOLUTE_EXPIRY_TYPE_HASH = keccak256("Absolute");

    error NotSeaport();
    error EmptyReceived();
    error IncorrectReceived();
    error InvalidExpiryType();
    error InvalidSignature();
    error InvalidReceiptTransfer();
    error InvalidReceiptId();
    error InvalidContext();
    error NonceAlreadyUsed();

    uint256 internal constant EMPTY_RECEIPT_PLACEHOLDER = 1;

    /// @dev 20 * 2 (addresses) + 1 * 2 (enums) + 5 * 2 (uin40) = 52
    uint256 internal constant CONTEXT_MIN_SIZE = 52;

    bytes32 internal constant RECEIPT_TYPE_HASH = keccak256(
        "WrapReceipt(address token,uint256 id,string expiryType,uint256 expiryTime,address delegateRecipient,address principalRecipient,uint256 nonce)"
    );

    address public immutable SEAPORT;
    address public immutable LIQUID_DELEGATE;

    uint256 internal validatedReceiptId = EMPTY_RECEIPT_PLACEHOLDER;

    mapping(address => LibBitmap.Bitmap) internal usedNonces;

    constructor(address _SEAPORT, address _LIQUID_DELEGATE) {
        SEAPORT = _SEAPORT;
        LIQUID_DELEGATE = _LIQUID_DELEGATE;
    }

    modifier onlySeaport(address caller) {
        if (caller != SEAPORT) revert NotSeaport();
        _;
    }

    function generateOrder(
        address,
        // What LiquidDelegate is giving up
        SpentItem[] calldata minimumReceived,
        // What LiquidDelegate is receiving
        SpentItem[] calldata maximumSpent,
        bytes calldata context // encoded based on the schemaID
    ) external onlySeaport(msg.sender) returns (SpentItem[] memory, ReceivedItem[] memory) {
        (address tokenContract, uint256 tokenId) = _getTokenFromSpends(maximumSpent);
        (address signer, bytes32 receiptHash, uint40 nonce, bytes memory sig) =
            _receiptFromContext(tokenContract, tokenId, context);
        if (!usedNonces[signer].toggle(nonce)) revert NonceAlreadyUsed();
        if (!SignatureCheckerLib.isValidSignatureNow(signer, _hashTypedData(receiptHash), sig)) {
            revert InvalidSignature();
        }
        validatedReceiptId = uint(receiptHash);
        return _createReturnItems(minimumReceived.length, receiptHash, tokenContract, tokenId);
    }

    function getNonceUsed(address owner, uint256 nonce) external view returns (bool) {
        return usedNonces[owner].get(nonce);
    }

    function ratifyOrder(
        SpentItem[] calldata,
        ReceivedItem[] calldata consideration,
        bytes calldata context, // encoded based on the schemaID
        bytes32[] calldata,
        uint256
    ) external onlySeaport(msg.sender) returns (bytes4) {
        (, ExpiryType expiryType, uint40 expiryValue, address delegateRecipient, address principalRecipient,,) =
            decodeContext(context);

        // Remove validated receipt
        validatedReceiptId = EMPTY_RECEIPT_PLACEHOLDER;

        // `LiquidDelegateV2.mint` checks whether the appropriate NFT has been deposited.
        ILiquidDelegateV2(LIQUID_DELEGATE).mint(
            delegateRecipient,
            principalRecipient,
            consideration[0].token,
            consideration[0].identifier,
            expiryType,
            expiryValue
        );

        return this.ratifyOrder.selector;
    }

    function previewOrder(
        address caller,
        address,
        // What LiquidDelegate is giving up
        SpentItem[] calldata minimumReceived,
        // What LiquidDelegate is receiving
        SpentItem[] calldata maximumSpent,
        bytes calldata context // encoded based on the schemaID
    ) public view onlySeaport(caller) returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        (address tokenContract, uint256 tokenId) = _getTokenFromSpends(maximumSpent);
        if (caller != SEAPORT) revert NotSeaport();
        (address signer, bytes32 receiptHash, uint40 nonce, bytes memory sig) =
            _receiptFromContext(tokenContract, tokenId, context);
        if (usedNonces[signer].get(nonce)) revert NonceAlreadyUsed();
        if (!SignatureCheckerLib.isValidSignatureNow(signer, _hashTypedData(receiptHash), sig)) {
            revert InvalidSignature();
        }
        return _createReturnItems(minimumReceived.length, receiptHash, tokenContract, tokenId);
    }

    function getSeaportMetadata() external pure returns (string memory, Schema[] memory) {
        return (name(), new Schema[](0));
    }

    // /// @dev Builds unique ERC-712 struct hash
    function getReceiptHash(
        address delegateRecipient,
        address principalRecipient,
        address token,
        uint256 id,
        ExpiryType expiryType,
        uint256 expiryValue,
        uint40 nonce
    ) public pure returns (bytes32 receiptHash) {
        bytes32 expiryTypeHash;
        if (expiryType == ExpiryType.Relative) {
            expiryTypeHash = RELATIVE_EXPIRY_TYPE_HASH;
        } else if (expiryType == ExpiryType.Absolute) {
            expiryTypeHash = ABSOLUTE_EXPIRY_TYPE_HASH;
        } else {
            // Incase another enum type accidentally added
            revert InvalidExpiryType();
        }

        receiptHash = keccak256(
            abi.encode(
                RECEIPT_TYPE_HASH, token, id, expiryTypeHash, expiryValue, delegateRecipient, principalRecipient, nonce
            )
        );
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    function name() public pure returns (string memory) {
        return "Liquid Delegate V2 Seaport Offerer";
    }

    function transferFrom(address from, address, uint256 id) public view {
        if (from != address(this) || id == EMPTY_RECEIPT_PLACEHOLDER) revert InvalidReceiptTransfer();
        if (id != validatedReceiptId) revert InvalidReceiptId();
    }

    function encodeContext(
        ReceiptFillerType fillerType,
        ExpiryType expiryType,
        uint40 expiryValue,
        address delegateRecipient,
        address principalRecipient,
        uint40 nonce,
        bytes memory signature
    ) public pure returns (bytes memory) {
        return abi.encodePacked(
            fillerType, expiryType, expiryValue, delegateRecipient, principalRecipient, nonce, signature
        );
    }

    function decodeContext(bytes calldata context)
        public
        pure
        returns (
            ReceiptFillerType fillerType,
            ExpiryType expiryType,
            uint40 expiryValue,
            address delegateRecipient,
            address principalRecipient,
            uint40 nonce,
            bytes memory signature
        )
    {
        if (context.length < CONTEXT_MIN_SIZE) revert InvalidContext();
        fillerType = ReceiptFillerType(uint8(context[0]));
        expiryType = ExpiryType(uint8(context[1]));
        expiryValue = uint40(bytes5(context[2:7]));
        delegateRecipient = address(bytes20(context[7:27]));
        principalRecipient = address(bytes20(context[27:47]));
        nonce = uint40(bytes5(context[47:52]));
        signature = context[52:];
    }

    function _domainNameAndVersion() internal pure override returns (string memory, string memory) {
        return (name(), "1");
    }

    function _getTokenFromSpends(SpentItem[] calldata inSpends) internal pure returns (address, uint256) {
        if (inSpends.length == 0) revert EmptyReceived();
        SpentItem calldata inItem = inSpends[0];
        if (inItem.amount != 1 || inItem.itemType != ItemType.ERC721) revert IncorrectReceived();
        return (inItem.token, inItem.identifier);
    }

    function _createReturnItems(uint256 receiptCount, bytes32 receiptHash, address tokenContract, uint256 tokenId)
        internal
        view
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        offer = new SpentItem[](receiptCount);
        for (uint256 i; i < receiptCount;) {
            offer[i] = SpentItem({
                itemType: ItemType.ERC721,
                token: address(this),
                identifier: uint256(receiptHash),
                amount: 1
            });
            unchecked {
                ++i;
            }
        }

        consideration = new ReceivedItem[](1);
        consideration[0] = ReceivedItem({
            itemType: ItemType.ERC721,
            token: tokenContract,
            identifier: tokenId,
            amount: 1,
            recipient: payable(LIQUID_DELEGATE)
        });
    }

    function _receiptFromContext(address token, uint256 id, bytes calldata context)
        internal
        pure
        returns (address, bytes32, uint40, bytes memory)
    {
        (
            ReceiptFillerType fillerType,
            ExpiryType expiryType,
            uint40 expiryValue,
            address delegateRecipient,
            address principalRecipient,
            uint40 nonce,
            bytes memory signature
        ) = decodeContext(context);

        bool delegateSigning =
            fillerType == ReceiptFillerType.PrincipalOpen || fillerType == ReceiptFillerType.PrincipalClosed;
        bool matchClosed =
            fillerType == ReceiptFillerType.PrincipalClosed || fillerType == ReceiptFillerType.DelegateClosed;

        address signer = delegateSigning ? delegateRecipient : principalRecipient;

        // Check signature
        bytes32 receiptHash = getReceiptHash(
            matchClosed || delegateSigning ? delegateRecipient : address(0),
            matchClosed || !delegateSigning ? principalRecipient : address(0),
            token,
            id,
            expiryType,
            expiryValue,
            nonce
        );

        return (signer, receiptHash, nonce, signature);
    }
}
