// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {SpentItem, ReceivedItem} from "seaport/contracts/interfaces/ContractOffererInterface.sol";
import {ItemType} from "seaport/contracts/lib/ConsiderationEnums.sol";
import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {IDelegateToken, Structs as IDelegateTokenStructs} from "src/interfaces/IDelegateToken.sol";
import {RegistryHashes} from "delegate-registry/src/libraries/RegistryHashes.sol";
import {DelegateTokenEncoding} from "src/libraries/DelegateTokenEncoding.sol";

library CreateOffererErrors {
    error DelegateTokenIsZero();
    error PrincipalTokenIsZero();
    error NoBatchWrapping();
    error InvalidExpiryType(CreateOffererEnums.ExpiryType invalidType);
    error SeaportIsZero();
    error Locked();
    error WrongStage(CreateOffererEnums.Stage expected, CreateOffererEnums.Stage actual);
    error CallerNotSeaport(address caller);
    error DelegateTokenIdInvariant(uint256 requested, uint256 actual);
    error CreateOrderHashInvariant(uint256 requested, uint256 actual);
    error MinimumReceivedInvalid(SpentItem minimumReceived);
    error MaximumSpentInvalid(SpentItem maximumSpent);
    error FromNotCreateOfferer(address from);
    error ERC20ApproveFailed(address tokenAddress);
    error ERC20AllowanceInvariant(address tokenAddress);
    error InvalidContractNonce(uint256 actual, uint256 seaportExpected);
    error DelegateInfoInvariant();
    error TargetTokenInvalid(CreateOffererEnums.TargetToken invalidTargetToken);
}

library CreateOffererEnums {
    /// @notice Used to determine how expiryLength is interpreted in orders.
    enum ExpiryType {
        none,
        absolute,
        relative
    }

    /// @notice Used to determine which token the targetTokenReceiver gets in orders.
    enum TargetToken {
        none,
        principal,
        delegate
    }

    /// @notice Used to keep track of the stage during seaport calls on CreateOfferer.
    enum Stage {
        none,
        generate,
        transfer,
        ratify
    }

    /// @notice Used to keep track of whether a stage has been entered.
    enum Lock {
        none,
        locked,
        unlocked
    }
}

library CreateOffererStructs {
    /// @notice Used to track the stage and lock status.
    struct Stage {
        CreateOffererEnums.Stage flag;
        CreateOffererEnums.Lock lock;
    }

    /// @notice Used to keep track of the seaport contract nonce of CreateOfferer.
    struct Nonce {
        uint256 value;
    }

    /// @notice Used to keep track of the receiver of the principal / delegate tokens during a seaport call on CreateOfferer.
    struct Receivers {
        address principal;
        address delegate;
    }

    /// @notice Used in the constructor of CreateOfferer.
    struct Parameters {
        address seaport;
        address principalToken;
        address delegateToken;
    }

    /// @notice Should be abi encoded (unpacked) in context data field for seaport CreateOfferer orders.
    struct Context {
        bytes32 rights;
        uint256 signerSalt;
        uint256 expiryLength;
        CreateOffererEnums.ExpiryType expiryType;
        CreateOffererEnums.TargetToken targetToken;
        Receivers receivers;
    }

    /// @notice Contains data common to all order types.
    struct Order {
        bytes32 rights;
        uint256 expiryLength;
        uint256 signerSalt;
        address tokenContract;
        CreateOffererEnums.ExpiryType expiryType;
        CreateOffererEnums.TargetToken targetToken;
    }

    /// @notice Should be used when creating an ERC721 order.
    struct ERC721Order {
        uint256 tokenId;
        Order info;
    }

    /// @notice Should be used when creating an ERC20 order.
    struct ERC20Order {
        uint256 amount;
        Order info;
    }

    /// @notice Should be used when creating an ERC1155 order.
    struct ERC1155Order {
        uint256 amount;
        uint256 tokenId;
        Order info;
    }

    /// @notice Transient storage used during a seaport call on CreateOfferer.
    struct TransientState {
        ERC721Order erc721Order;
        ERC20Order erc20Order;
        ERC1155Order erc1155Order;
        Receivers receivers;
    }
}

/// @notice Contains the modifiers used by CreateOfferer.
abstract contract CreateOffererModifiers {
    address public immutable seaport;
    /// @notice Used by checkStage to track stage sequence and stage locks.
    CreateOffererStructs.Stage internal stage;

    /**
     * @param setSeaport Should be the address of the seaport version being used
     * @param firstStage Should be the first stage of the seaport flow, which is generateOrder
     */
    constructor(address setSeaport, CreateOffererEnums.Stage firstStage) {
        if (setSeaport == address(0)) revert CreateOffererErrors.SeaportIsZero();
        seaport = setSeaport;
        stage = CreateOffererStructs.Stage({flag: firstStage, lock: CreateOffererEnums.Lock.unlocked});
    }

    /**
     * @notice Prevents reentrancy into marked functions and allows stages to be called in sequence.
     * @param currentStage Should be the stage being marked by the modifier.
     * @param nextStage Should be the stage to be entered after ths stage being marked by the modifier.
     */
    modifier checkStage(CreateOffererEnums.Stage currentStage, CreateOffererEnums.Stage nextStage) {
        CreateOffererStructs.Stage memory cacheStage = stage;
        if (cacheStage.flag != currentStage) revert CreateOffererErrors.WrongStage(currentStage, cacheStage.flag);
        if (cacheStage.lock != CreateOffererEnums.Lock.unlocked) revert CreateOffererErrors.Locked();
        stage.lock = CreateOffererEnums.Lock.locked;
        _;
        stage = CreateOffererStructs.Stage({flag: nextStage, lock: CreateOffererEnums.Lock.unlocked});
    }

    /**
     * @notice Restricts a caller to seaport.
     * @param caller Should be msg.sender or intended caller for a preview function.
     */
    modifier onlySeaport(address caller) {
        if (caller != seaport) revert CreateOffererErrors.CallerNotSeaport(caller);
        _;
    }
}

/// @notice Contains helper function used by CreateOfferer.
library CreateOffererHelpers {
    /**
     * @notice Updates Receivers struct with the intents of the targetTokenReceiver.
     * @param tokenReceivers Receivers struct storage pointer to be updated.
     * @param targetTokenReceiver Address to receive the target token.
     * @param targetToken Either delegate / principal token receiver to be overridden with targetTokenReceiver in the Receivers struct.
     * @dev If targetToken == principal, tokenReceivers.principal will be overridden with targetTokenReceiver, tokenReceivers.delegate will be preserved (and vice versa).
     * @dev Should revert for invalid targetToken.
     * @return updatedReceivers updated storage result provided in memory for use.
     */
    function updateReceivers(CreateOffererStructs.Receivers storage tokenReceivers, address targetTokenReceiver, CreateOffererEnums.TargetToken targetToken)
        internal
        returns (CreateOffererStructs.Receivers memory updatedReceivers)
    {
        if (targetToken == CreateOffererEnums.TargetToken.principal) {
            updatedReceivers = CreateOffererStructs.Receivers({principal: targetTokenReceiver, delegate: tokenReceivers.delegate});
            tokenReceivers.principal = targetTokenReceiver;
        } else if (targetToken == CreateOffererEnums.TargetToken.delegate) {
            updatedReceivers = CreateOffererStructs.Receivers({principal: tokenReceivers.principal, delegate: targetTokenReceiver});
            tokenReceivers.delegate = targetTokenReceiver;
        } else {
            revert CreateOffererErrors.TargetTokenInvalid(targetToken);
        }
    }

    /**
     * @notice Validates and updates a Nonce struct.
     * @param nonce The storage pointer to the Nonce struct to be validated and updated.
     * @param contractNonce Used to valid against the expected nonce in storage.
     * @dev Should revert if contractNonce is not the same as the storage nonce.
     * @dev Should increment storage nonce if validation succeeds.
     */
    function processNonce(CreateOffererStructs.Nonce storage nonce, uint256 contractNonce) internal {
        if (nonce.value != contractNonce) revert CreateOffererErrors.InvalidContractNonce(nonce.value, contractNonce);
        unchecked {
            nonce.value++;
        } // Infeasible this will overflow if starting point is zero
    }

    /**
     * @notice Updates a TransientState struct in storage with order data.
     * @param transientState The storage pointer to the TransientState struct to be updated.
     * @param minimumReceived Used to decode the token id of the CreateOfferer "ghost" token offer.
     * @param maximumSpent Contains the information of the underlying token to be used in create.
     * @param decodedContext Is the Context struct decoded and provides additional data need for the Order structs.
     * @dev Only one of the transient order data types will be updated.
     */
    function updateTransientState(
        CreateOffererStructs.TransientState storage transientState,
        SpentItem calldata minimumReceived,
        SpentItem calldata maximumSpent,
        CreateOffererStructs.Context memory decodedContext
    ) internal {
        transientState.receivers = decodedContext.receivers;
        IDelegateRegistry.DelegationType tokenType = RegistryHashes.decodeType(bytes32(minimumReceived.identifier));
        if (tokenType == IDelegateRegistry.DelegationType.ERC721) {
            transientState.erc721Order = CreateOffererStructs.ERC721Order({
                tokenId: maximumSpent.identifier,
                info: CreateOffererStructs.Order({
                    rights: decodedContext.rights,
                    expiryLength: decodedContext.expiryLength,
                    signerSalt: decodedContext.signerSalt,
                    tokenContract: maximumSpent.token,
                    expiryType: decodedContext.expiryType,
                    targetToken: decodedContext.targetToken
                })
            });
        } else if (tokenType == IDelegateRegistry.DelegationType.ERC20) {
            transientState.erc20Order = CreateOffererStructs.ERC20Order({
                amount: maximumSpent.amount,
                info: CreateOffererStructs.Order({
                    rights: decodedContext.rights,
                    expiryLength: decodedContext.expiryLength,
                    signerSalt: decodedContext.signerSalt,
                    tokenContract: maximumSpent.token,
                    expiryType: decodedContext.expiryType,
                    targetToken: decodedContext.targetToken
                })
            });
        } else if (tokenType == IDelegateRegistry.DelegationType.ERC1155) {
            transientState.erc1155Order = CreateOffererStructs.ERC1155Order({
                amount: maximumSpent.amount,
                tokenId: maximumSpent.identifier,
                info: CreateOffererStructs.Order({
                    rights: decodedContext.rights,
                    expiryLength: decodedContext.expiryLength,
                    signerSalt: decodedContext.signerSalt,
                    tokenContract: maximumSpent.token,
                    expiryType: decodedContext.expiryType,
                    targetToken: decodedContext.targetToken
                })
            });
        }
    }

    /**
     * @notice Creates a delegateToken pair and verifies the expected delegateTokenId.
     * @param delegateToken Should be the address of the DelegateToken contract.
     * @param createOrderHash Is the CreateOfferer order hash that will be used to verify the delegateTokenId is as expected.
     * @param delegateInfo A DelegateToken struct used in calls to the create function.
     * @dev Must revert if delegateId returned from create call is not the same as expected with createOrderHash.
     */
    function createAndValidateDelegateTokenId(address delegateToken, uint256 createOrderHash, IDelegateTokenStructs.DelegateInfo memory delegateInfo) internal {
        uint256 actualDelegateId = IDelegateToken(delegateToken).create(delegateInfo, createOrderHash);
        uint256 requestedDelegateId = DelegateTokenEncoding.delegateId(address(this), createOrderHash);
        if (actualDelegateId != requestedDelegateId) {
            revert CreateOffererErrors.DelegateTokenIdInvariant(requestedDelegateId, actualDelegateId);
        }
    }

    /**
     * @notice Calculates the CreateOfferer hash, agnostic to the type.
     * @param delegateToken Should be the address of the DelegateToken contract.
     * @param targetTokenReceiver The receiver of the targetToken in orderInfo.
     * @param conduit The address of the conduit that should conduct the create on transferFrom on seaport calling CreateOfferer.
     * @param orderInfo Should be abi encoded (unpacked) with the relevant token type Order struct.
     * @param delegationType Delegation type that should correspond to the token type encoded into orderInfo.
     * @dev Should revert if a delegateToken has already been created with the parameters above.
     */
    function calculateOrderHashAndId(
        address delegateToken,
        address targetTokenReceiver,
        address conduit,
        bytes memory orderInfo,
        IDelegateRegistry.DelegationType delegationType
    ) internal view returns (uint256 createOrderHash, uint256 delegateTokenId) {
        createOrderHash = CreateOffererHelpers.calculateOrderHash(targetTokenReceiver, conduit, orderInfo, delegationType);
        delegateTokenId = IDelegateToken(delegateToken).getDelegateId(address(this), createOrderHash); // This should revert if already existed
    }

    /**
     * @notice Verifies the properties of a delegateToken against the first element of a seaport ContractOfferer ratify order calldata.
     * @param delegateToken Should be the address of the DelegateToken contract.
     * @param offer The offer specified in the ratify order call data (used to define the delegateToken contract and to deterministically calculate the delegateTokenId).
     * @param consideration The consideration specified in the ratify order call data (used as input data of the underlying used to create the delegate token).
     * @param context Should contain an unpacked encoding of the Context struct which provides additional order data for comparison.
     * @dev Should revert if the delegateToken with tokenId in the offer does not match with the expected result.
     */
    function verifyCreate(address delegateToken, SpentItem calldata offer, ReceivedItem calldata consideration, bytes calldata context) internal view {
        IDelegateRegistry.DelegationType tokenType = RegistryHashes.decodeType(bytes32(offer.identifier));
        CreateOffererStructs.Context memory decodedContext = abi.decode(context, (CreateOffererStructs.Context));
        //slither-disable-start timestamp
        if (
            keccak256(
                abi.encode(
                    IDelegateTokenStructs.DelegateInfo({
                        tokenType: tokenType,
                        principalHolder: decodedContext.receivers.principal,
                        delegateHolder: decodedContext.receivers.delegate,
                        expiry: CreateOffererHelpers.calculateExpiry(decodedContext.expiryType, decodedContext.expiryLength),
                        rights: decodedContext.rights,
                        tokenContract: consideration.token,
                        tokenId: (tokenType == IDelegateRegistry.DelegationType.ERC721 || tokenType == IDelegateRegistry.DelegationType.ERC1155)
                            ? consideration.identifier
                            : 0,
                        amount: (tokenType == IDelegateRegistry.DelegationType.ERC20 || tokenType == IDelegateRegistry.DelegationType.ERC1155) ? consideration.amount : 0
                    })
                )
            ) != keccak256(abi.encode(IDelegateToken(delegateToken).getDelegateInfo(DelegateTokenEncoding.delegateId(address(this), offer.identifier))))
        ) revert CreateOffererErrors.DelegateInfoInvariant();
        //slither-disable-end timestamp
    }

    /**
     * @notice Calculates an effective expiry for an order at the time of execution.
     * @param expiryType Defines the type of expiry, should be relative or absolute.
     * @param expiryLength Length of the expiry given its reference point.
     * @dev Must revert if the expiryType is invalid.
     * @dev The reference for relative expiry types is block.timestamp.
     */
    function calculateExpiry(CreateOffererEnums.ExpiryType expiryType, uint256 expiryLength) internal view returns (uint256) {
        if (expiryType == CreateOffererEnums.ExpiryType.relative) {
            return block.timestamp + expiryLength;
        } else if (expiryType == CreateOffererEnums.ExpiryType.absolute) {
            return expiryLength;
        } else {
            revert CreateOffererErrors.InvalidExpiryType(expiryType);
        }
    }

    /**
     * @notice Processes SpentItems calldata in a seaport call to CreateOfferer.
     * @param minimumReceived The corresponding calldata in generateOrder and previewOrder
     * @param maximumSpent The corresponding calldata in generateOrder and previewOrder.
     * @return offer Which is the "ghost" token provided by CreateOfferer.
     * @return consideration Which is the same as minimumReceived with the address of the contract appended as the receiver.
     * @dev Must revert if calldata arrays are not length 1.
     * @dev Must revert if minimumReceived does not reflect the properties of the CreateOfferer "ghost" token.
     * @dev Must revert if maximumSpent does not use a token type supported by CreateOfferer and DelegateToken.
     */
    function processSpentItems(SpentItem[] calldata minimumReceived, SpentItem[] calldata maximumSpent)
        internal
        view
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        if (!(minimumReceived.length == 1 && maximumSpent.length == 1)) revert CreateOffererErrors.NoBatchWrapping();
        if (minimumReceived[0].itemType != ItemType.ERC721 || minimumReceived[0].token != address(this) || minimumReceived[0].amount != 1) {
            revert CreateOffererErrors.MinimumReceivedInvalid(minimumReceived[0]);
        }
        if (maximumSpent[0].itemType != ItemType.ERC721 && maximumSpent[0].itemType != ItemType.ERC20 && maximumSpent[0].itemType != ItemType.ERC1155) {
            revert CreateOffererErrors.MaximumSpentInvalid(maximumSpent[0]);
        }
        offer = new SpentItem[](1);
        offer[0] = SpentItem({
            itemType: minimumReceived[0].itemType,
            token: minimumReceived[0].token,
            identifier: minimumReceived[0].identifier,
            amount: minimumReceived[0].amount
        });
        consideration = new ReceivedItem[](1);
        consideration[0] = ReceivedItem({
            itemType: maximumSpent[0].itemType,
            token: maximumSpent[0].token,
            identifier: maximumSpent[0].identifier,
            amount: maximumSpent[0].amount,
            recipient: payable(address(this))
        });
    }

    /**
     * @notice Validates an expected CreateOfferer order hash against actual order data used and the current caller.
     * @param targetTokenReceiver Should be the receiver of the targetToken in the encodedOrder.
     * @param createOrderHash Is the order hash to be validated against.
     * @param encodedOrder Should be the unpacked encoding of the order data used.
     * @param tokenType Should correspond to the order type of encodedOrder.
     * @dev Must revert if the hash does not match up against the order data used.
     */
    function validateCreateOrderHash(address targetTokenReceiver, uint256 createOrderHash, bytes memory encodedOrder, IDelegateRegistry.DelegationType tokenType)
        internal
        view
    {
        uint256 actualCreateOrderHash = CreateOffererHelpers.calculateOrderHash(targetTokenReceiver, msg.sender, encodedOrder, tokenType);
        if (actualCreateOrderHash != createOrderHash) {
            revert CreateOffererErrors.CreateOrderHashInvariant(createOrderHash, actualCreateOrderHash);
        }
    }

    /**
     * @notice The order hash system used by CreateOfferer.
     * @param targetTokenReceiver Should be the intended receiver of the targetToken in createOrderInfo.
     * @param conduit Should be the intended conduit to be used in the corresponding seaport order.
     * @param createOrderInfo should be the unpacked encoding for a given token type order info.
     * @param tokenType Should match with the token type used in the encoded createOrderInfo.
     * @dev tokenType is encoded in the last byte of the hash after it has been shifted left by a byte.
     */
    function calculateOrderHash(address targetTokenReceiver, address conduit, bytes memory createOrderInfo, IDelegateRegistry.DelegationType tokenType)
        internal
        pure
        returns (uint256)
    {
        uint256 hashWithoutType = uint256(keccak256(abi.encode(targetTokenReceiver, conduit, createOrderInfo)));
        return (hashWithoutType << 8) | uint256(tokenType);
    }
}
