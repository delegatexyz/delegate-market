// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {IDelegateToken, Structs as IDelegateTokenStructs} from "./interfaces/IDelegateToken.sol";
import {RegistryHashes} from "delegate-registry/src/libraries/RegistryHashes.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";
import {IERC1155} from "openzeppelin/token/ERC1155/IERC1155.sol";

import {ContractOffererInterface, SpentItem, ReceivedItem, Schema} from "seaport/contracts/interfaces/ContractOffererInterface.sol";
import {
    CreateOffererStructs as Structs,
    CreateOffererEnums as Enums,
    CreateOffererErrors as Errors,
    CreateOffererHelpers as Helpers,
    CreateOffererModifiers as Modifiers
} from "./libraries/CreateOffererLib.sol";

import {ERC1155Holder} from "openzeppelin/token/ERC1155/utils/ERC1155Holder.sol";

/// @dev Experimental way to create delegate tokens with seaport and existing seaport conduit approvals
contract CreateOfferer is Modifiers, ContractOffererInterface, ERC1155Holder {
    address public immutable delegateToken;
    address public immutable principalToken;
    Structs.TransientState internal transientState;

    event SeaportCompatibleContractDeployed();

    //slither-disable-next-line missing-zero-check
    constructor(address _seaport, address _delegateToken) Modifiers(_seaport, Enums.Stage.generate) {
        delegateToken = _delegateToken;
        principalToken = IDelegateToken(_delegateToken).principalToken();
        Structs.Order memory defaultInfo =
            Structs.Order({rights: 0, expiryLength: 1, signerSalt: 1, tokenContract: address(42), expiryType: Enums.ExpiryType.absolute, targetToken: Enums.TargetToken.principal});
        transientState = Structs.TransientState({
            erc721Order: Structs.ERC721Order({tokenId: 1, info: defaultInfo}),
            erc20Order: Structs.ERC20Order({amount: 1, info: defaultInfo}),
            erc1155Order: Structs.ERC1155Order({tokenId: 1, amount: 1, info: defaultInfo}),
            receivers: Structs.Receivers({fulfiller: address(1), targetTokenReceiver: address(1)})
        });
        emit SeaportCompatibleContractDeployed();
    }

    /**
     * @notice Implementation of seaport contract offerer generateOrder
     * @param minimumReceived The "ghost" create offerer token to be ordered
     * @param maximumSpent The underlying token required during the liquid delegate create process
     * @param context The upper bits of context should be encoded with the CreateOffererStruct
     * @return offer Returns minimumReceived
     * @return consideration Returns maximumSpent but with the beneficiary specified as this contract
     */
    function generateOrder(address fulfiller, SpentItem[] calldata minimumReceived, SpentItem[] calldata maximumSpent, bytes calldata context)
        external
        checkStage(Enums.Stage.generate, Enums.Stage.transfer)
        onlySeaport(msg.sender)
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        if (context.length != 160) revert Errors.InvalidContextLength();
        Structs.Context memory decodedContext = abi.decode(context, (Structs.Context));
        (offer, consideration) = Helpers.processSpentItems(minimumReceived, maximumSpent);
        Helpers.updateTransientState(transientState, fulfiller, minimumReceived[0], maximumSpent[0], decodedContext);
    }

    /**
     * @notice Implementation of seaport contract offerer ratifyOrder
     * @param offer The delegateToken created during transfer
     * @param consideration The underlying used for create during transfer
     * @param context The upper bits of context should be encoded with the CreateOffererStruct
     */
    function ratifyOrder(SpentItem[] calldata offer, ReceivedItem[] calldata consideration, bytes calldata context, bytes32[] calldata, uint256)
        external
        checkStage(Enums.Stage.ratify, Enums.Stage.generate)
        onlySeaport(msg.sender)
        returns (bytes4)
    {
        Helpers.verifyCreate(delegateToken, offer[0].identifier, transientState.receivers, consideration[0], context);
        return this.ratifyOrder.selector;
    }

    /**
     * @notice Implementation of the ERC721 transferFrom interface to force-create delegate tokens
     * @param from Must be this contract address
     * @param targetTokenReceiver Is the receiver of the intended targetToken, the delegate / principal token
     * @param createOrderHashAsTokenId The hash that secures the intended targetToken receiver being the beneficiary of a specific delegate / principal token
     */
    //slither-disable-next-line erc20-interface
    function transferFrom(address from, address targetTokenReceiver, uint256 createOrderHashAsTokenId) external checkStage(Enums.Stage.transfer, Enums.Stage.ratify) {
        if (from != address(this)) revert Errors.FromNotCreateOfferer(from);
        transientState.receivers.targetTokenReceiver = targetTokenReceiver;
        IDelegateRegistry.DelegationType tokenType = RegistryHashes.decodeType(bytes32(createOrderHashAsTokenId));
        if (tokenType == IDelegateRegistry.DelegationType.ERC721) {
            Structs.ERC721Order memory erc721Order = transientState.erc721Order;
            if (!(erc721Order.info.targetToken == Enums.TargetToken.delegate || erc721Order.info.targetToken == Enums.TargetToken.principal)) {
                revert Errors.TargetTokenInvalid(erc721Order.info.targetToken);
            }
            Helpers.validateCreateOrderHash(targetTokenReceiver, createOrderHashAsTokenId, abi.encode(erc721Order), tokenType);
            IERC721(erc721Order.info.tokenContract).setApprovalForAll(address(delegateToken), true);
            Helpers.createAndValidateDelegateTokenId(
                delegateToken,
                createOrderHashAsTokenId,
                IDelegateTokenStructs.DelegateInfo({
                    principalHolder: erc721Order.info.targetToken == Enums.TargetToken.principal ? targetTokenReceiver : transientState.receivers.fulfiller,
                    tokenType: tokenType,
                    delegateHolder: erc721Order.info.targetToken == Enums.TargetToken.delegate ? targetTokenReceiver : transientState.receivers.fulfiller,
                    amount: 0,
                    tokenContract: erc721Order.info.tokenContract,
                    tokenId: erc721Order.tokenId,
                    rights: erc721Order.info.rights,
                    expiry: Helpers.calculateExpiry(erc721Order.info.expiryType, erc721Order.info.expiryLength)
                })
            );
            IERC721(erc721Order.info.tokenContract).setApprovalForAll(address(delegateToken), false); // saves gas
        } else if (tokenType == IDelegateRegistry.DelegationType.ERC20) {
            Structs.ERC20Order memory erc20Order = transientState.erc20Order;
            if (!(erc20Order.info.targetToken == Enums.TargetToken.delegate || erc20Order.info.targetToken == Enums.TargetToken.principal)) {
                revert Errors.TargetTokenInvalid(erc20Order.info.targetToken);
            }
            Helpers.validateCreateOrderHash(targetTokenReceiver, createOrderHashAsTokenId, abi.encode(erc20Order), tokenType);
            if (!IERC20(erc20Order.info.tokenContract).approve(address(delegateToken), erc20Order.amount)) {
                revert Errors.ERC20ApproveFailed(erc20Order.info.tokenContract);
            }
            Helpers.createAndValidateDelegateTokenId(
                delegateToken,
                createOrderHashAsTokenId,
                IDelegateTokenStructs.DelegateInfo({
                    principalHolder: erc20Order.info.targetToken == Enums.TargetToken.principal ? targetTokenReceiver : transientState.receivers.fulfiller,
                    tokenType: tokenType,
                    delegateHolder: erc20Order.info.targetToken == Enums.TargetToken.delegate ? targetTokenReceiver : transientState.receivers.fulfiller,
                    amount: erc20Order.amount,
                    tokenContract: erc20Order.info.tokenContract,
                    tokenId: 0,
                    rights: erc20Order.info.rights,
                    expiry: Helpers.calculateExpiry(erc20Order.info.expiryType, erc20Order.info.expiryLength)
                })
            );
            if (IERC20(erc20Order.info.tokenContract).allowance(address(this), address(delegateToken)) != 0) {
                revert Errors.ERC20AllowanceInvariant(erc20Order.info.tokenContract);
            }
        } else if (tokenType == IDelegateRegistry.DelegationType.ERC1155) {
            Structs.ERC1155Order memory erc1155Order = transientState.erc1155Order;
            if (!(erc1155Order.info.targetToken == Enums.TargetToken.delegate || erc1155Order.info.targetToken == Enums.TargetToken.principal)) {
                revert Errors.TargetTokenInvalid(erc1155Order.info.targetToken);
            }
            Helpers.validateCreateOrderHash(targetTokenReceiver, createOrderHashAsTokenId, abi.encode(erc1155Order), tokenType);
            IERC1155(erc1155Order.info.tokenContract).setApprovalForAll(address(delegateToken), true);
            Helpers.createAndValidateDelegateTokenId(
                delegateToken,
                createOrderHashAsTokenId,
                IDelegateTokenStructs.DelegateInfo({
                    principalHolder: erc1155Order.info.targetToken == Enums.TargetToken.principal ? targetTokenReceiver : transientState.receivers.fulfiller,
                    tokenType: tokenType,
                    delegateHolder: erc1155Order.info.targetToken == Enums.TargetToken.delegate ? targetTokenReceiver : transientState.receivers.fulfiller,
                    amount: erc1155Order.amount,
                    tokenContract: erc1155Order.info.tokenContract,
                    tokenId: erc1155Order.tokenId,
                    rights: erc1155Order.info.rights,
                    expiry: Helpers.calculateExpiry(erc1155Order.info.expiryType, erc1155Order.info.expiryLength)
                })
            );
            IERC1155(erc1155Order.info.tokenContract).setApprovalForAll(address(delegateToken), false); // saves gas
        } else {
            revert Errors.InvalidTokenType(tokenType);
        }
    }

    /**
     * @notice Implementation of seaport contract offerer previewOrder
     * @param caller Must be the seaport address
     * @param minimumReceived The "ghost" create offerer token to be ordered
     * @param maximumSpent The underlying token required during the liquid delegate create process
     * @return offer Returns minimumReceived
     * @return consideration Returns maximumSpent but with the beneficiary specified as this contract
     */
    function previewOrder(address caller, address, SpentItem[] calldata minimumReceived, SpentItem[] calldata maximumSpent, bytes calldata context)
        external
        view
        onlySeaport(caller)
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        if (context.length != 160) revert Errors.InvalidContextLength();
        (offer, consideration) = Helpers.processSpentItems(minimumReceived, maximumSpent);
    }

    /**
     * @notice Calculates the hash and id for an ERC721 order
     * @param targetTokenReceiver The receiver of the target token in the ERC721 order
     * @param conduit The conduit used in the order of the targetTokenReceiver
     * @param erc721Order The ERC721Order struct with the details of the order
     * @return createOrderHash The hash used by CreateOfferer to capture the order intent
     * @return delegateTokenId The id of the delegateToken that would be created by CreateOfferer with these parameters
     * @dev Reverts if the delegateTokenId has already been used, use a different salt in the order struct
     */
    function calculateERC721OrderHashAndId(address targetTokenReceiver, address conduit, Structs.ERC721Order calldata erc721Order)
        external
        view
        returns (uint256 createOrderHash, uint256 delegateTokenId)
    {
        (createOrderHash, delegateTokenId) =
            Helpers.calculateOrderHashAndId(delegateToken, targetTokenReceiver, conduit, abi.encode(erc721Order), IDelegateRegistry.DelegationType.ERC721);
    }

    /**
     * @notice Calculates the hash and id for an ERC721 order
     * @param targetTokenReceiver The receiver of the target token in the ERC721 order
     * @param conduit The conduit used in the order of the targetTokenReceiver
     * @param erc20Order The ERC20Order struct with the details of the order
     * @return createOrderHash The hash used by CreateOfferer to capture the order intent
     * @return delegateTokenId The id of the delegateToken that would be created by CreateOfferer with these parameters
     * @dev Reverts if the delegateTokenId has already been used, use a different salt in the order struct
     */
    function calculateERC20OrderHashAndId(address targetTokenReceiver, address conduit, Structs.ERC20Order calldata erc20Order)
        external
        view
        returns (uint256 createOrderHash, uint256 delegateTokenId)
    {
        (createOrderHash, delegateTokenId) =
            Helpers.calculateOrderHashAndId(delegateToken, targetTokenReceiver, conduit, abi.encode(erc20Order), IDelegateRegistry.DelegationType.ERC20);
    }

    /**
     * @notice Calculates the hash and id for an ERC721 order
     * @param targetTokenReceiver The receiver of the target token in the ERC721 order
     * @param conduit The conduit used in the order of the targetTokenReceiver
     * @param erc1155Order The ERC1155Order struct with the details of the order.
     * @return createOrderHash The hash used by CreateOfferer to capture the order intent
     * @return delegateTokenId The id of the delegateToken that would be created by CreateOfferer with these parameters
     * @dev Reverts if the delegateTokenId has already been used, use a different salt in the order struct
     */
    function calculateERC1155OrderHashAndId(address targetTokenReceiver, address conduit, Structs.ERC1155Order calldata erc1155Order)
        external
        view
        returns (uint256 createOrderHash, uint256 delegateTokenId)
    {
        (createOrderHash, delegateTokenId) =
            Helpers.calculateOrderHashAndId(delegateToken, targetTokenReceiver, conduit, abi.encode(erc1155Order), IDelegateRegistry.DelegationType.ERC1155);
    }

    /// @notice Implementation of seaport contract offerer getSeaportMetadata
    function getSeaportMetadata() external pure returns (string memory, Schema[] memory) {
        return ("Delegate Market Contract Offerer", new Schema[](0));
    }
}
