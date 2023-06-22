// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ContractOffererInterface, IWrapOfferer, ReceiptFillerType, ExpiryType} from "./interfaces/IWrapOfferer.sol";

import {ReceivedItem, SpentItem, Schema} from "seaport-types/src/interfaces/ContractOffererInterface.sol";
import {ItemType} from "seaport-types/src/lib/ConsiderationEnums.sol";

import {IDelegateToken, TokenType} from "./interfaces/IDelegateToken.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

/// @notice A Seaport ContractOfferer
contract WrapOfferer is IWrapOfferer {
    uint256 internal constant CONTEXT_SIZE = 59;

    /// @notice Address for Seaport 1.5
    address public immutable SEAPORT;

    /// @notice Address for the delegate token
    address public immutable DELEGATE_TOKEN;

    /// @dev Used as transient storage to hold the latest receiptHash
    uint256 internal transientReceiptHash;

    error NotSeaport();
    error IncorrectReceived();
    error InvalidExpiryType();
    error InvalidReceiptTransfer();
    error InvalidReceiptId();
    error InvalidContext();
    error NoBatchWrapping();

    /// @param _SEAPORT The latest seaport address, currently using 1.5
    /// @param _DELEGATE_TOKEN The delegate token to operate on
    constructor(address _SEAPORT, address _DELEGATE_TOKEN) {
        SEAPORT = _SEAPORT;
        DELEGATE_TOKEN = _DELEGATE_TOKEN;
    }

    /**
     * -----------SEAPORT CALLBACKS-----------
     */

    modifier onlySeaport(address caller) {
        if (caller != SEAPORT) revert NotSeaport();
        _;
    }

    /// TODO: inheritdoc ContractOffererInterface
    /// @dev Identical to generateOrder, except a view function, so does not populate transient storage variables for ratifyOrder to verify against
    /// @param caller The address of the caller (Seaport)
    /// @param minimumReceived What LiquidDelegate is requested to give up
    /// @param maximumSpent What LiquidDelegate is requested to receive (spot asset)
    /// @param context ABI-packed data about the delegate token
    /// @return offer What LiquidDelegate is giving up
    /// @return consideration What LiquidDelegate is receiving
    function previewOrder(address caller, address, SpentItem[] calldata minimumReceived, SpentItem[] calldata maximumSpent, bytes calldata context)
        public
        view
        onlySeaport(caller)
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        if (!(minimumReceived.length == 1 && maximumSpent.length == 1)) revert NoBatchWrapping();
        SpentItem calldata spent = maximumSpent[0];
        SpentItem calldata received = minimumReceived[0];
        if (!(spent.itemType == ItemType.ERC721 || spent.itemType == ItemType.ERC20 || spent.itemType == ItemType.ERC1155)) revert IncorrectReceived();
        uint256 receiptHash = _parseReceiptHashFromContext(spent, context);

        offer = new SpentItem[](1);
        // The receipt transfer is spoofed, so will always be a 721. Must match the offerer's consideration exactly, which is why receiptHash exact generation matters
        offer[0] = SpentItem({itemType: ItemType.ERC721, token: address(this), identifier: receiptHash, amount: 1});

        consideration = new ReceivedItem[](1);
        // Send the spot asset to the Delegate Token, to use in create() in ratifyOrder()
        consideration[0] =
            ReceivedItem({itemType: spent.itemType, token: spent.token, identifier: spent.identifier, amount: spent.amount, recipient: payable(address(this))});
    }

    /// TODO: inheritdoc ContractOffererInterface
    /// @dev Param names are from the end user's point of view. They're giving up maximumSpent (eg 10 eth, or spot NFT), and want minimumReceived in return (eg blitmap, or receipt to become DT)
    /// @param minimumReceived The minimum items that the caller is willing to receive (the Delegate Token)
    /// @param maximumSpent The maximum items that the caller is willing to spend (the spot token)
    /// @param context ABI-packed data about the delegate token
    function generateOrder(address, SpentItem[] calldata minimumReceived, SpentItem[] calldata maximumSpent, bytes calldata context)
        external
        onlySeaport(msg.sender)
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        if (!(minimumReceived.length == 1 && maximumSpent.length == 1)) revert NoBatchWrapping();
        SpentItem calldata spent = maximumSpent[0];
        SpentItem calldata received = minimumReceived[0];
        if (!(spent.itemType == ItemType.ERC721 || spent.itemType == ItemType.ERC20 || spent.itemType == ItemType.ERC1155)) revert IncorrectReceived();
        uint256 receiptHash = _parseReceiptHashFromContext(spent, context);

        offer = new SpentItem[](1);
        // The receipt transfer is spoofed, so will always be a 721. Must match the offerer's consideration exactly, which is why receiptHash exact generation matters
        offer[0] = SpentItem({itemType: ItemType.ERC721, token: address(this), identifier: receiptHash, amount: 1});

        consideration = new ReceivedItem[](1);
        // Send the spot asset to the Delegate Token, to use in create() in ratifyOrder()
        // TODO: remove amount 0, just relaxing considerations
        consideration[0] =
            ReceivedItem({itemType: spent.itemType, token: spent.token, identifier: spent.identifier, amount: spent.amount, recipient: payable(address(this))});

        transientReceiptHash = receiptHash;
    }

    /// TODO: inheritdoc ContractOffererInterface
    /// @param consideration The consideration items
    /// @param context Encoded based on the schemaID
    function ratifyOrder(SpentItem[] calldata, ReceivedItem[] calldata consideration, bytes calldata context, bytes32[] calldata, uint256)
        external
        onlySeaport(msg.sender)
        returns (bytes4)
    {
        // Remove validated receipt, was already used to verify address(this).transferFrom() after generateOrder() but before ratifyOrder()
        // delete transientReceiptHash;

        // Address stack-too-deep by caching consideration values in memory
        ItemType itemType = consideration[0].itemType;
        address considerationToken = consideration[0].token;
        uint256 considerationIdentifier = consideration[0].identifier;
        uint256 considerationAmount = consideration[0].amount;
        if (itemType == ItemType.ERC721) {
            (, uint256 expiry, address delegateRecipient, address principalRecipient, uint96 salt) = decodeContext(context);
            IERC721(considerationToken).setApprovalForAll(address(DELEGATE_TOKEN), true);
            uint256 delegateId = IDelegateToken(DELEGATE_TOKEN).create(
                delegateRecipient, principalRecipient, TokenType.ERC721, considerationToken, considerationIdentifier, considerationAmount, "", expiry, salt
            );
        } else if (itemType == ItemType.ERC20) {
            (, uint256 expiry, address delegateRecipient, address principalRecipient, uint96 salt) = decodeContext(context);
            IERC20(considerationToken).approve(address(DELEGATE_TOKEN), considerationAmount);
            uint256 delegateId = IDelegateToken(DELEGATE_TOKEN).create(
                delegateRecipient, principalRecipient, TokenType.ERC20, considerationToken, considerationIdentifier, considerationAmount, "", expiry, salt
            );
        } else if (itemType == ItemType.ERC1155) {
            (, uint256 expiry, address delegateRecipient, address principalRecipient, uint96 salt) = decodeContext(context);
            IERC1155(considerationToken).setApprovalForAll(address(DELEGATE_TOKEN), true);
            uint256 delegateId = IDelegateToken(DELEGATE_TOKEN).create(
                delegateRecipient, principalRecipient, TokenType.ERC1155, considerationToken, considerationIdentifier, considerationAmount, "", expiry, salt
            );
        }

        return this.ratifyOrder.selector;
    }

    /// TODO: inheritdoc ContractOffererInterface
    function getSeaportMetadata() external pure returns (string memory, Schema[] memory) {
        return ("Liquid Delegate Contract Offerer", new Schema[](0));
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(ContractOffererInterface).interfaceId || interfaceId == 0x01ffc9a7; // ERC165 Interface ID for ERC165
    }

    function transferFrom(address from, address, uint256 id) public view {
        if (from != address(this)) revert InvalidReceiptTransfer();
        if (id == 0 || id != transientReceiptHash) revert InvalidReceiptId();
    }

    /**
     * -----------HELPER FUNCTIONS-----------
     */

    function getExpiry(ExpiryType expiryType, uint256 expiryValue) public view returns (uint256 expiry) {
        if (expiryType == ExpiryType.RELATIVE) {
            expiry = block.timestamp + expiryValue;
        } else if (expiryType == ExpiryType.ABSOLUTE) {
            expiry = expiryValue;
        } else {
            revert InvalidExpiryType();
        }
    }

    /// @return receiptHash The receipt hash for a given context to match with the receipt id
    function _parseReceiptHashFromContext(SpentItem calldata spotToken, bytes calldata context) internal pure returns (uint256 receiptHash) {
        (ReceiptFillerType fillerType, ExpiryType expiryType, uint40 expiryValue, address delegateRecipient, address principalRecipient, uint96 salt) =
            decodeContextForReceipt(context);

        // The receipt hash can have the zero address if the offerer doesn't know who their counterparty will be
        bool delegateSigning = fillerType == ReceiptFillerType.PrincipalOpen || fillerType == ReceiptFillerType.PrincipalClosed;
        bool matchClosed = fillerType == ReceiptFillerType.PrincipalClosed || fillerType == ReceiptFillerType.DelegateClosed;
        if (!(matchClosed || delegateSigning)) delegateRecipient = address(0);
        if (!(matchClosed || !delegateSigning)) principalRecipient = address(0);

        // Cache values in memory to avoid stack-too-deep
        address token = spotToken.token;
        uint256 identifier = spotToken.identifier;
        uint256 amount = spotToken.amount;
        receiptHash = uint256(getReceiptHash(delegateRecipient, principalRecipient, token, identifier, amount, expiryType, expiryValue));
    }

    /// @dev Builds unique ERC-712 struct hash to be passed as context data
    /// @param delegateRecipient The user to get the delegate token
    /// @param principalRecipient The user to get the principal token
    /// @param tokenAddress The token contract address
    /// @param tokenId The token id
    /// @param tokenAmount The token amount
    /// @param expiryType Whether expiration is an absolute timestamp or relative offset from order fulfillment
    /// @param expiryValue The expiration absolute timestamp or relative offset, in UTC seconds
    function getReceiptHash(
        address delegateRecipient,
        address principalRecipient,
        address tokenAddress,
        uint256 tokenId,
        uint256 tokenAmount,
        ExpiryType expiryType,
        uint256 expiryValue
    ) public pure returns (bytes32 receiptHash) {
        receiptHash = keccak256(abi.encode(tokenAddress, tokenId, tokenAmount, uint8(expiryType), delegateRecipient, principalRecipient));
    }

    /// @notice Pack information about the Liquid Delegate to be created into a reversible bytes object
    function encodeContext(
        ReceiptFillerType fillerType,
        ExpiryType expiryType,
        uint40 expiryValue,
        address delegateRecipient,
        address principalRecipient,
        uint96 salt
    ) public pure returns (bytes memory) {
        return abi.encodePacked(fillerType, expiryType, expiryValue, delegateRecipient, principalRecipient, salt);
    }

    function decodeContext(bytes calldata context)
        public
        view
        returns (ReceiptFillerType fillerType, uint256 expiry, address delegateRecipient, address principalRecipient, uint96 salt)
    {
        if (context.length != CONTEXT_SIZE) revert InvalidContext();
        fillerType = ReceiptFillerType(uint8(context[0]));
        ExpiryType expiryType = ExpiryType(uint8(context[1]));
        uint256 expiryValue = uint256(uint40(bytes5(context[2:7])));
        expiry = getExpiry(expiryType, expiryValue);
        delegateRecipient = address(bytes20(context[7:27]));
        principalRecipient = address(bytes20(context[27:47]));
        // Add tokenAddress, tokenId, tokenAmount
        // Use unique salt for a unique deterministic ID. Can add offerer address verification if needs be but hopefully won't get there
        salt = uint96(bytes12(context[47:59]));
    }

    // Extra func to avoid stack too deep
    function decodeContextForReceipt(bytes calldata context)
        public
        pure
        returns (ReceiptFillerType fillerType, ExpiryType expiryType, uint40 expiryValue, address delegateRecipient, address principalRecipient, uint96 salt)
    {
        if (context.length != CONTEXT_SIZE) revert InvalidContext();
        fillerType = ReceiptFillerType(uint8(context[0]));
        expiryType = ExpiryType(uint8(context[1]));
        expiryValue = uint40(bytes5(context[2:7]));
        delegateRecipient = address(bytes20(context[7:27]));
        principalRecipient = address(bytes20(context[27:47]));
        // Add tokenAddress, tokenId, tokenAmount
        // Use unique salt for a unique deterministic ID. Can add offerer address verification if needs be but hopefully won't get there
        salt = uint96(bytes12(context[47:59]));
    }
}
