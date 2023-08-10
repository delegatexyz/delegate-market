// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {IDelegateToken, Structs as IDelegateTokenStructs} from "./interfaces/IDelegateToken.sol";
import {RegistryHashes} from "delegate-registry/src/libraries/RegistryHashes.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";
import {IERC1155} from "openzeppelin/token/ERC1155/IERC1155.sol";

import {ContractOffererInterface, SpentItem, ReceivedItem, Schema} from "seaport/contracts/interfaces/ContractOffererInterface.sol";
import {ItemType} from "seaport/contracts/lib/ConsiderationEnums.sol";
import {
    CreateOffererStructs as Structs,
    CreateOffererEnums as Enums,
    CreateOffererErrors as Errors,
    CreateOffererProcess as Process
} from "src/libraries/CreateOffererLib.sol";

import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";

/// @dev experimental way to create delegate tokens with seaport and existing seaport conduit approvals
contract CreateOfferer is ReentrancyGuard, ContractOffererInterface {
    address public immutable seaport;
    address public immutable seaportConduit;
    address public immutable delegateToken;
    address public immutable principalToken;
    uint256 nonce;
    Structs.ERC721Order internal transientERC721Order;
    Structs.ERC20Order internal transientERC20Order;
    Structs.ERC1155Order internal transientERC1155Order;
    Structs.Receivers internal transientReceivers;
    Structs.Stage internal stage;

    constructor(Structs.Parameters memory parameters) {
        require(parameters.seaport != address(0), "seaportIsZero");
        seaport = parameters.seaport;
        require(parameters.seaportConduit != address(0), "seaportConduitIsZero");
        seaportConduit = parameters.seaportConduit;
        require(parameters.delegateToken != address(0), "delegateTokenIsZero");
        delegateToken = parameters.delegateToken;
        require(parameters.principalToken != address(0), "principalTokenIsZero");
        principalToken = parameters.principalToken;
        Structs.Order memory defaultInfo = Structs.Order({
            rights: 0,
            expiryLength: 1,
            signerSalt: 1,
            tokenContract: address(1),
            expiryType: Enums.ExpiryType.absolute,
            targetToken: Enums.TargetToken.principal
        });
        transientERC721Order = Structs.ERC721Order({tokenId: 1, info: defaultInfo});
        transientERC20Order = Structs.ERC20Order({amount: 1, info: defaultInfo});
        transientERC1155Order = Structs.ERC1155Order({tokenId: 1, amount: 1, info: defaultInfo});
        transientReceivers = Structs.Receivers({principal: address(1), delegate: address(1)});
        stage.flag = Enums.Stage.generate;
    }

    /**
     * @notice Implementation of seaport contract offerer generateOrder
     * @param fulfiller Seaport fulfiller must be the beneficiary of the delegate token or principal token, but not both
     * @param minimumReceived The "ghost" create offerer token to be ordered
     * @param maximumSpent The underlying token required during the liquid delegate create process
     * @param context The upper bits of context should be encoded with the CreateOffererStruct
     * @return offer Returns minimumReceived.
     * @return consideration Returns maximumSpent but with the beneficiary specified as this contract.
     */
    function generateOrder(address fulfiller, SpentItem[] calldata minimumReceived, SpentItem[] calldata maximumSpent, bytes calldata context)
        external
        nonReentrant
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        Structs.Context memory decodedContext;
        (decodedContext, offer, consideration) = Process.order(seaport, stage, msg.sender, fulfiller, minimumReceived, maximumSpent, context);
        stage.flag = Enums.Stage.transfer; // Update flag to next stage, which is transfer
        transientReceivers = decodedContext.receivers; // Store receivers for transfer stage
        IDelegateRegistry.DelegationType tokenType = RegistryHashes.decodeType(bytes32(minimumReceived[0].identifier));
        // Store transient order info by type
        if (tokenType == IDelegateRegistry.DelegationType.ERC721) {
            transientERC721Order = Structs.ERC721Order({
                tokenId: maximumSpent[0].identifier,
                info: Structs.Order({
                    rights: decodedContext.rights,
                    expiryLength: decodedContext.expiryLength,
                    signerSalt: decodedContext.signerSalt,
                    tokenContract: maximumSpent[0].token,
                    expiryType: decodedContext.expiryType,
                    targetToken: decodedContext.targetToken
                })
            });
        } else if (tokenType == IDelegateRegistry.DelegationType.ERC20) {
            transientERC20Order = Structs.ERC20Order({
                amount: maximumSpent[0].amount,
                info: Structs.Order({
                    rights: decodedContext.rights,
                    expiryLength: decodedContext.expiryLength,
                    signerSalt: decodedContext.signerSalt,
                    tokenContract: maximumSpent[0].token,
                    expiryType: decodedContext.expiryType,
                    targetToken: decodedContext.targetToken
                })
            });
        } else if (tokenType == IDelegateRegistry.DelegationType.ERC1155) {
            transientERC1155Order = Structs.ERC1155Order({
                amount: maximumSpent[0].amount,
                tokenId: maximumSpent[0].identifier,
                info: Structs.Order({
                    rights: decodedContext.rights,
                    expiryLength: decodedContext.expiryLength,
                    signerSalt: decodedContext.signerSalt,
                    tokenContract: maximumSpent[0].token,
                    expiryType: decodedContext.expiryType,
                    targetToken: decodedContext.targetToken
                })
            });
        }
    }

    /**
     * @notice Implementation of seaport contract offerer generateOrder
     * @param offer The delegateToken created during transfer
     * @param consideration The underlying used for create during transfer
     * @param context The upper bits of context should be encoded with the CreateOffererStruct
     * @param contractNonce Should match with the nonce tracked by this contract
     */
    function ratifyOrder(SpentItem[] calldata offer, ReceivedItem[] calldata consideration, bytes calldata context, bytes32[] calldata, uint256 contractNonce)
        external
        nonReentrant
        returns (bytes4)
    {
        require(offer.length == 1 && consideration.length == 1, "offer consideration lengths");
        require(msg.sender == seaport, "caller not seaport");
        require(stage.flag == Enums.Stage.ratify, "unlocked");
        require(nonce == contractNonce, "incorrect nonce");
        unchecked {
            nonce++;
        }
        stage.flag = Enums.Stage.generate; // Set stage flag back to generate
        Structs.Context memory decodedContext = abi.decode(context, (Structs.Context));
        IDelegateRegistry.DelegationType tokenType = RegistryHashes.decodeType(bytes32(offer[0].identifier));
        IDelegateTokenStructs.DelegateInfo memory requestedInfo = IDelegateTokenStructs.DelegateInfo({
            tokenType: tokenType,
            principalHolder: transientReceivers.principal,
            delegateHolder: transientReceivers.delegate,
            expiry: Process.expiry(decodedContext.expiryType, decodedContext.expiryLength),
            rights: decodedContext.rights,
            tokenContract: consideration[0].token,
            tokenId: (tokenType == IDelegateRegistry.DelegationType.ERC721 || tokenType == IDelegateRegistry.DelegationType.ERC1155) ? consideration[0].identifier : 0,
            amount: (tokenType == IDelegateRegistry.DelegationType.ERC20 || tokenType == IDelegateRegistry.DelegationType.ERC1155) ? consideration[0].amount : 0
        });
        require(
            keccak256(abi.encode(requestedInfo))
                == keccak256(abi.encode(IDelegateToken(delegateToken).getDelegateInfo(uint256(keccak256(abi.encode(address(this), offer[0].identifier)))))),
            "incorrect delegateInfo"
        ); // Checks that delegateToken was actually created with the expected details
        return this.ratifyOrder.selector;
    }

    /**
     * @notice Implementation of the ERC721 transferFrom interface to force create delegate tokens
     * @param from Must be this contract address
     * @param targetTokenReceiver Is the receiver of the intended targetToken, the delegate / principal token
     * @param createOrderHashAsTokenId The hash that secures the intended targetToken receiver being the beneficiary of a specific delegate / principal token
     */
    //slither-disable-next-line erc20-interface
    function transferFrom(address from, address targetTokenReceiver, uint256 createOrderHashAsTokenId) external nonReentrant {
        require(msg.sender == seaportConduit, "caller not conduit");
        require(from == address(this), "from not create offerer");
        require(stage.flag == Enums.Stage.transfer, "unlocked");
        stage.flag = Enums.Stage.ratify;
        Structs.Receivers memory processedReceivers;
        uint256 returnedTokenId = 0;
        uint256 delegateTokenId = uint256(keccak256(abi.encode(address(this), createOrderHashAsTokenId)));
        IDelegateRegistry.DelegationType underlyingTokenType = RegistryHashes.decodeType(bytes32(createOrderHashAsTokenId));
        if (underlyingTokenType == IDelegateRegistry.DelegationType.ERC721) {
            Structs.ERC721Order memory erc721Order = transientERC721Order;
            processedReceivers = Process.receivers(erc721Order.info.targetToken, targetTokenReceiver, transientReceivers);
            require(
                calculateCreateOrderHash(targetTokenReceiver, abi.encode(erc721Order), IDelegateRegistry.DelegationType.ERC721) == createOrderHashAsTokenId,
                "createOrderHash invariant"
            );
            IERC721(erc721Order.info.tokenContract).setApprovalForAll(address(delegateToken), true);
            returnedTokenId = IDelegateToken(delegateToken).create(
                IDelegateTokenStructs.DelegateInfo({
                    principalHolder: processedReceivers.principal,
                    tokenType: IDelegateRegistry.DelegationType.ERC721,
                    delegateHolder: processedReceivers.delegate,
                    amount: 0,
                    tokenContract: erc721Order.info.tokenContract,
                    tokenId: erc721Order.tokenId,
                    rights: erc721Order.info.rights,
                    expiry: Process.expiry(erc721Order.info.expiryType, erc721Order.info.expiryLength)
                }),
                createOrderHashAsTokenId
            );
            //slither-disable-next-line incorrect-equality,timestamp
            require(returnedTokenId == delegateTokenId, "delegateTokenId invariant");
            IERC721(erc721Order.info.tokenContract).setApprovalForAll(address(delegateToken), false); // saves gas
        } else if (underlyingTokenType == IDelegateRegistry.DelegationType.ERC20) {
            Structs.ERC20Order memory erc20Order = transientERC20Order;
            processedReceivers = Process.receivers(erc20Order.info.targetToken, targetTokenReceiver, transientReceivers);
            require(
                calculateCreateOrderHash(targetTokenReceiver, abi.encode(erc20Order), IDelegateRegistry.DelegationType.ERC20) == createOrderHashAsTokenId,
                "createOrderHash invariant"
            );
            require(IERC20(erc20Order.info.tokenContract).approve(address(delegateToken), erc20Order.amount));
            returnedTokenId = IDelegateToken(delegateToken).create(
                IDelegateTokenStructs.DelegateInfo({
                    principalHolder: processedReceivers.principal,
                    tokenType: IDelegateRegistry.DelegationType.ERC20,
                    delegateHolder: processedReceivers.delegate,
                    amount: erc20Order.amount,
                    tokenContract: erc20Order.info.tokenContract,
                    tokenId: 0,
                    rights: erc20Order.info.rights,
                    expiry: Process.expiry(erc20Order.info.expiryType, erc20Order.info.expiryLength)
                }),
                createOrderHashAsTokenId
            );
            //slither-disable-next-line incorrect-equality,timestamp
            require(returnedTokenId == delegateTokenId, "delegateTokenId invariant");
            require(IERC20(erc20Order.info.tokenContract).allowance(address(this), address(delegateToken)) == 0, "invariant");
        } else if (underlyingTokenType == IDelegateRegistry.DelegationType.ERC1155) {
            Structs.ERC1155Order memory erc1155Order = transientERC1155Order;
            processedReceivers = Process.receivers(erc1155Order.info.targetToken, targetTokenReceiver, transientReceivers);
            require(
                calculateCreateOrderHash(targetTokenReceiver, abi.encode(erc1155Order), IDelegateRegistry.DelegationType.ERC1155) == createOrderHashAsTokenId,
                "createOrderHash invariant"
            );
            IERC1155(erc1155Order.info.tokenContract).setApprovalForAll(address(delegateToken), true);
            returnedTokenId = IDelegateToken(delegateToken).create(
                IDelegateTokenStructs.DelegateInfo({
                    principalHolder: processedReceivers.principal,
                    tokenType: IDelegateRegistry.DelegationType.ERC1155,
                    delegateHolder: processedReceivers.delegate,
                    amount: erc1155Order.amount,
                    tokenContract: erc1155Order.info.tokenContract,
                    tokenId: erc1155Order.tokenId,
                    rights: erc1155Order.info.rights,
                    expiry: Process.expiry(erc1155Order.info.expiryType, erc1155Order.info.expiryLength)
                }),
                createOrderHashAsTokenId
            );
            //slither-disable-next-line incorrect-equality,timestamp
            require(returnedTokenId == delegateTokenId, "delegateTokenId invariant");
            IERC1155(erc1155Order.info.tokenContract).setApprovalForAll(address(delegateToken), false); // saves gas
        }
    }

    /**
     * @notice Implementation of seaport contract offerer previewOrder
     * @param caller Must be the seaport address.
     * @param fulfiller Seaport fulfiller must be the beneficiary of the delegate token or principal token, but not both
     * @param minimumReceived The "ghost" create offerer token to be ordered
     * @param maximumSpent The underlying token required during the liquid delegate create process
     * @param context The upper bits of context should be encoded with the CreateOffererStruct
     * @return offer Returns minimumReceived.
     * @return consideration Returns maximumSpent but with the beneficiary specified as this contract.
     */
    function previewOrder(address caller, address fulfiller, SpentItem[] calldata minimumReceived, SpentItem[] calldata maximumSpent, bytes calldata context)
        external
        view
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        //slither-disable-next-line unused-return
        (, offer, consideration) = Process.order(seaport, stage, caller, fulfiller, minimumReceived, maximumSpent, context);
    }

    /// @notice Implementation of seaport contract offerer getSeaportMetadata
    function getSeaportMetadata() external pure returns (string memory, Schema[] memory) {
        return ("Liquid Delegate Contract Offerer", new Schema[](0));
    }

    /**
     * @notice Calculates the hash that links a targetTokenReceiver with a delegate token create order
     * @param targetTokenReceiver The address intended to receiver the target token
     * @param createOrderInfo Bytes of abi encode run on the create order struct for a given token type
     * @param tokenType IDelegateRegistry.DelegationType corresponding to the create order struct token type
     */
    function calculateCreateOrderHash(address targetTokenReceiver, bytes memory createOrderInfo, IDelegateRegistry.DelegationType tokenType)
        public
        pure
        returns (uint256)
    {
        uint256 hashWithoutType = uint256(keccak256(abi.encode(targetTokenReceiver, createOrderInfo)));
        return (hashWithoutType << 8) | uint256(tokenType);
    }
}
