// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IDelegateToken, IERC721Metadata, IERC721Receiver, IERC1155Receiver} from "./interfaces/IDelegateToken.sol";
import {IDelegateFlashloan} from "./interfaces/IDelegateFlashloan.sol";
import {IERC165} from "openzeppelin/utils/introspection/IERC165.sol";

import {ERC2981} from "openzeppelin/token/common/ERC2981.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";

import {DelegateTokenConstants as Constants} from "src/libraries/DelegateTokenConstants.sol";
import {DelegateTokenErrors as Errors} from "src/libraries/DelegateTokenErrors.sol";
import {DelegateTokenStructs as Structs, IDelegateRegistry} from "src/libraries/DelegateTokenStructs.sol";
import {DelegateTokenReverts as Reverts} from "src/libraries/DelegateTokenReverts.sol";
import {DelegateTokenStorageHelpers as StorageHelpers} from "src/libraries/DelegateTokenStorageHelpers.sol";
import {DelegateTokenRegistryHelpers as RegistryHelpers, RegistryHashes} from "src/libraries/DelegateTokenRegistryHelpers.sol";
import {DelegateTokenTransferHelpers as TransferHelpers, SafeERC20, IERC721, IERC20, IERC1155} from "src/libraries/DelegateTokenTransferHelpers.sol";
import {DelegateTokenPrincipalTokenHelpers as PrincipalTokenHelpers} from "src/libraries/DelegateTokenPrincipalTokenHelpers.sol";
import {DelegateTokenEncoding as Encoding} from "src/libraries/DelegateTokenEncoding.sol";

contract DelegateToken is ReentrancyGuard, Ownable2Step, ERC2981, IDelegateToken {
    /*//////////////////////////////////////////////////////////////
    /                           Immutables                         /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDelegateToken
    address public immutable override delegateRegistry;

    /// @inheritdoc IDelegateToken
    address public immutable override principalToken;

    /*//////////////////////////////////////////////////////////////
    /                            Storage                           /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDelegateToken
    string public baseURI;

    /// @dev delegateId, a hash of (msg.sender, salt), points a unique id to the StoragePosition
    mapping(uint256 delegateTokenId => uint256[3] info) internal delegateTokenInfo;

    /// @notice mapping for ERC721 balances
    mapping(address delegateTokenHolder => uint256 balance) internal balances;

    /// @notice approve for all mapping
    mapping(address account => mapping(address operator => bool enabled)) internal accountOperator;

    /// @notice internal variables for Principle Token callbacks
    Structs.Uint256 internal principalMintAuthorization = Structs.Uint256(Constants.MINT_NOT_AUTHORIZED);
    Structs.Uint256 internal principalBurnAuthorization = Structs.Uint256(Constants.BURN_NOT_AUTHORIZED);

    /// @notice internal variable 11155 callbacks
    Structs.Uint256 internal erc1155PullAuthorization = Structs.Uint256(Constants.ERC1155_NOT_PULLED);

    /*//////////////////////////////////////////////////////////////
    /                      Constructor                             /
    //////////////////////////////////////////////////////////////*/

    constructor(Structs.DelegateTokenParameters memory parameters) {
        if (parameters.delegateRegistry == address(0)) revert Errors.DelegateRegistryZero();
        if (parameters.principalToken == address(0)) revert Errors.PrincipalTokenZero();
        if (parameters.initialMetadataOwner == address(0)) revert Errors.InitialMetadataOwnerZero();
        delegateRegistry = parameters.delegateRegistry;
        principalToken = parameters.principalToken;
        baseURI = parameters.baseURI;
        _transferOwnership(parameters.initialMetadataOwner);
    }

    /*//////////////////////////////////////////////////////////////
    /                    Supported Interfaces                      /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override(ERC2981, IERC165) returns (bool) {
        return interfaceId == 0x2a55205a // ERC165 Interface ID for ERC2981
            || interfaceId == 0x01ffc9a7 // ERC165 Interface ID for ERC165
            || interfaceId == 0x80ac58cd // ERC165 Interface ID for ERC721
            || interfaceId == 0x5b5e139f // ERC165 Interface ID for ERC721Metadata
            || interfaceId == 0x4e2312e0; // ERC165 Interface ID for ERC1155 Token receiver
    }

    /*//////////////////////////////////////////////////////////////
    /                    Token Receiver methods                    /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC1155Receiver
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure returns (bytes4) {
        Reverts.batchERC1155TransferUnsupported();
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(address operator, address, uint256, bytes calldata) external view returns (bytes4) {
        Reverts.invalidERC721TransferOperator(operator);
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155Received(address operator, address, uint256, uint256, bytes calldata) external returns (bytes4) {
        TransferHelpers.revertInvalidERC1155PullCheck(erc1155PullAuthorization, operator);
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /*//////////////////////////////////////////////////////////////
    /                 ERC721 Method Implementations                /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721
    function balanceOf(address delegateTokenHolder) external view returns (uint256) {
        Reverts.delegateTokenHolderZero(delegateTokenHolder);
        return balances[delegateTokenHolder];
    }

    /// @inheritdoc IERC721
    function ownerOf(uint256 delegateTokenId) external view returns (address delegateTokenHolder) {
        delegateTokenHolder = RegistryHelpers.loadTokenHolder(delegateRegistry, StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId));
        Reverts.delegateTokenHolderZero(delegateTokenHolder);
    }

    /// @inheritdoc IERC721
    function getApproved(uint256 delegateTokenId) public view returns (address) {
        Reverts.notMinted(StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId), delegateTokenId);
        return StorageHelpers.readApproved(delegateTokenInfo, delegateTokenId);
    }

    /// @inheritdoc IERC721
    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return accountOperator[account][operator];
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 delegateTokenId, bytes calldata data) external {
        transferFrom(from, to, delegateTokenId);
        Reverts.onInvalidERC721ReceiverCallback(from, to, delegateTokenId, data);
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 delegateTokenId) external {
        transferFrom(from, to, delegateTokenId);
        Reverts.onInvalidERC721ReceiverCallback(from, to, delegateTokenId);
    }

    /// @inheritdoc IERC721
    function approve(address spender, uint256 delegateTokenId) external {
        bytes32 registryHash = StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId);
        Reverts.notMinted(registryHash, delegateTokenId);
        address delegateTokenHolder = RegistryHelpers.loadTokenHolder(delegateRegistry, registryHash);
        Reverts.notOperator(accountOperator, delegateTokenHolder);
        StorageHelpers.writeApproved(delegateTokenInfo, delegateTokenId, spender);
        emit Approval(delegateTokenHolder, spender, delegateTokenId);
    }

    /// @inheritdoc IERC721
    function setApprovalForAll(address operator, bool approved) external {
        accountOperator[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @inheritdoc IERC721
    /// @dev should revert if msg.sender does not meet one of the following:
    ///         - msg.sender is from address
    ///         - from has approved msg.sender for all
    ///         - msg.sender is approved for the delegateTokenId
    /// @dev balances should be incremented / decremented for from / to
    /// @dev approved for the delegateTokenId should be deleted (reset)
    /// @dev must emit the ERC721 Transfer(from, to, delegateTokenId) event
    /// @dev toAmount stored in the related registry delegation must be retrieved directly from registry storage and
    ///      not via the CheckDelegate method to avoid invariants with "[specific rights]" and "" classes
    /// @dev registryHash for the DelegateTokenId must point to the new registry delegation associated with the to
    /// address
    function transferFrom(address from, address to, uint256 delegateTokenId) public {
        Reverts.toIsZero(to);
        bytes32 registryHash = StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId);
        Reverts.notMinted(registryHash, delegateTokenId);
        (address delegateTokenHolder, address underlyingContract) = RegistryHelpers.loadTokenHolderAndContract(delegateRegistry, registryHash);
        Reverts.fromNotDelegateTokenHolder(from, delegateTokenHolder);
        // We can use from here instead of delegateTokenHolder since we've just verified that from ==
        // delegateTokenHolder
        StorageHelpers.revertNotApprovedOrOperator(accountOperator, delegateTokenInfo, from, delegateTokenId);
        StorageHelpers.incrementBalance(balances, to);
        StorageHelpers.decrementBalance(balances, from);
        StorageHelpers.writeApproved(delegateTokenInfo, delegateTokenId, address(0));
        emit Transfer(from, to, delegateTokenId);
        IDelegateRegistry.DelegationType underlyingType = RegistryHashes.decodeType(registryHash);
        bytes32 underlyingRights = RegistryHelpers.loadRights(delegateRegistry, registryHash);
        bytes32 newRegistryHash = 0;
        if (underlyingType == IDelegateRegistry.DelegationType.ERC721) {
            uint256 underlyingTokenId = RegistryHelpers.loadTokenId(delegateRegistry, registryHash);
            newRegistryHash = RegistryHashes.erc721Hash(address(this), underlyingRights, to, underlyingTokenId, underlyingContract);
            StorageHelpers.writeRegistryHash(delegateTokenInfo, delegateTokenId, newRegistryHash);
            RegistryHelpers.transferERC721(delegateRegistry, registryHash, from, newRegistryHash, to, underlyingRights, underlyingContract, underlyingTokenId);
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC20) {
            newRegistryHash = RegistryHashes.erc20Hash(address(this), underlyingRights, to, underlyingContract);
            StorageHelpers.writeRegistryHash(delegateTokenInfo, delegateTokenId, newRegistryHash);
            RegistryHelpers.transferERC20(
                delegateRegistry,
                registryHash,
                from,
                newRegistryHash,
                to,
                StorageHelpers.readUnderlyingAmount(delegateTokenInfo, delegateTokenId),
                underlyingRights,
                underlyingContract
            );
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC1155) {
            uint256 underlyingTokenId = RegistryHelpers.loadTokenId(delegateRegistry, registryHash);
            newRegistryHash = RegistryHashes.erc1155Hash(address(this), underlyingRights, to, underlyingTokenId, underlyingContract);
            StorageHelpers.writeRegistryHash(delegateTokenInfo, delegateTokenId, newRegistryHash);
            RegistryHelpers.transferERC1155(
                delegateRegistry,
                registryHash,
                from,
                newRegistryHash,
                to,
                StorageHelpers.readUnderlyingAmount(delegateTokenInfo, delegateTokenId),
                underlyingRights,
                underlyingContract,
                underlyingTokenId
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
    /                EXTENDED ERC721 METHODS                       /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721Metadata
    function name() external pure returns (string memory) {
        return "Delegate Token";
    }

    /// @inheritdoc IERC721Metadata
    function symbol() external pure returns (string memory) {
        return "DT";
    }

    /// @inheritdoc IERC721Metadata
    function tokenURI(uint256 delegateTokenId) external view returns (string memory) {
        bytes32 registryHash = StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId);
        Reverts.notMinted(registryHash, delegateTokenId);
        return Encoding.tokenURI(
            baseURI,
            RegistryHelpers.loadContract(delegateRegistry, registryHash),
            RegistryHelpers.loadTokenId(delegateRegistry, registryHash),
            StorageHelpers.readExpiry(delegateTokenInfo, delegateTokenId),
            IERC721(principalToken).ownerOf(delegateTokenId)
        );
    }

    /// @inheritdoc IDelegateToken
    function isApprovedOrOwner(address spender, uint256 delegateTokenId) external view returns (bool) {
        bytes32 registryHash = StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId);
        Reverts.notMinted(registryHash, delegateTokenId);
        address delegateTokenHolder = RegistryHelpers.loadTokenHolder(delegateRegistry, registryHash);
        return spender == delegateTokenHolder || isApprovedForAll(delegateTokenHolder, spender) || getApproved(delegateTokenId) == spender;
    }

    /// @inheritdoc IDelegateToken
    function setBaseURI(string calldata uri) external onlyOwner {
        baseURI = uri;
    }

    /// @inheritdoc IDelegateToken
    function contractURI() external view returns (string memory) {
        return string.concat(baseURI, "contract");
    }

    /// @dev See {ERC2981-_setDefaultRoyalty}.
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @dev See {ERC2981-_deleteDefaultRoyalty}.
    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }

    /*//////////////////////////////////////////////////////////////
    /            LIQUID DELEGATE TOKEN METHODS                     /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDelegateToken
    function getDelegateInfo(uint256 delegateTokenId) external view returns (Structs.DelegateInfo memory delegateInfo) {
        bytes32 registryHash = StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId);
        Reverts.notMinted(registryHash, delegateTokenId);
        delegateInfo.tokenType = RegistryHashes.decodeType(registryHash);
        (delegateInfo.delegateHolder, delegateInfo.tokenContract) = RegistryHelpers.loadTokenHolderAndContract(delegateRegistry, registryHash);
        delegateInfo.rights = RegistryHelpers.loadRights(delegateRegistry, registryHash);
        delegateInfo.principalHolder = IERC721(principalToken).ownerOf(delegateTokenId);
        delegateInfo.expiry = StorageHelpers.readExpiry(delegateTokenInfo, delegateTokenId);
        if (delegateInfo.tokenType == IDelegateRegistry.DelegationType.ERC20) delegateInfo.tokenId = 0;
        else delegateInfo.tokenId = RegistryHelpers.loadTokenId(delegateRegistry, registryHash);
        if (delegateInfo.tokenType == IDelegateRegistry.DelegationType.ERC721) delegateInfo.amount = 0;
        else delegateInfo.amount = StorageHelpers.readUnderlyingAmount(delegateTokenInfo, delegateTokenId);
    }

    /// @inheritdoc IDelegateToken
    function getDelegateId(address caller, uint256 salt) public view returns (uint256 delegateTokenId) {
        delegateTokenId = Encoding.delegateId(caller, salt);
        Reverts.alreadyExisted(delegateTokenInfo, delegateTokenId);
    }

    /// @inheritdoc IDelegateToken
    function burnAuthorizedCallback() external {
        PrincipalTokenHelpers.checkBurnAuthorized(principalToken, principalBurnAuthorization);
    }

    /// @inheritdoc IDelegateToken
    function mintAuthorizedCallback() external {
        PrincipalTokenHelpers.checkMintAuthorized(principalToken, principalMintAuthorization);
    }

    /// @inheritdoc IDelegateToken
    function create(Structs.DelegateInfo calldata delegateInfo, uint256 salt) external nonReentrant returns (uint256 delegateTokenId) {
        TransferHelpers.checkAndPullByType(erc1155PullAuthorization, delegateInfo);
        Reverts.invalidExpiry(delegateInfo.expiry);
        Reverts.toIsZero(delegateInfo.delegateHolder);
        delegateTokenId = getDelegateId(msg.sender, salt);
        StorageHelpers.incrementBalance(balances, delegateInfo.delegateHolder);
        StorageHelpers.writeExpiry(delegateTokenInfo, delegateTokenId, delegateInfo.expiry);
        emit Transfer(address(0), delegateInfo.delegateHolder, delegateTokenId);
        bytes32 newRegistryHash = 0;
        if (delegateInfo.tokenType == IDelegateRegistry.DelegationType.ERC721) {
            newRegistryHash = RegistryHashes.erc721Hash(address(this), delegateInfo.rights, delegateInfo.delegateHolder, delegateInfo.tokenId, delegateInfo.tokenContract);
            StorageHelpers.writeRegistryHash(delegateTokenInfo, delegateTokenId, newRegistryHash);
            RegistryHelpers.delegateERC721(delegateRegistry, newRegistryHash, delegateInfo);
        } else if (delegateInfo.tokenType == IDelegateRegistry.DelegationType.ERC20) {
            StorageHelpers.writeUnderlyingAmount(delegateTokenInfo, delegateTokenId, delegateInfo.amount);
            newRegistryHash = RegistryHashes.erc20Hash(address(this), delegateInfo.rights, delegateInfo.delegateHolder, delegateInfo.tokenContract);
            StorageHelpers.writeRegistryHash(delegateTokenInfo, delegateTokenId, newRegistryHash);
            RegistryHelpers.delegateERC20(delegateRegistry, newRegistryHash, delegateInfo);
        } else if (delegateInfo.tokenType == IDelegateRegistry.DelegationType.ERC1155) {
            StorageHelpers.writeUnderlyingAmount(delegateTokenInfo, delegateTokenId, delegateInfo.amount);
            newRegistryHash =
                RegistryHashes.erc1155Hash(address(this), delegateInfo.rights, delegateInfo.delegateHolder, delegateInfo.tokenId, delegateInfo.tokenContract);
            StorageHelpers.writeRegistryHash(delegateTokenInfo, delegateTokenId, newRegistryHash);
            RegistryHelpers.delegateERC1155(delegateRegistry, newRegistryHash, delegateInfo);
        }
        PrincipalTokenHelpers.mint(principalToken, principalMintAuthorization, delegateInfo.principalHolder, delegateTokenId);
    }

    /// @inheritdoc IDelegateToken
    function extend(uint256 delegateTokenId, uint256 newExpiry) external {
        Reverts.notMinted(StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId), delegateTokenId);
        Reverts.invalidExpiry(newExpiry);
        StorageHelpers.revertInvalidExpiryUpdate(delegateTokenInfo, delegateTokenId, newExpiry);
        PrincipalTokenHelpers.notPrincipalOperator(principalToken, delegateTokenId);
        StorageHelpers.writeExpiry(delegateTokenInfo, delegateTokenId, newExpiry);
    }

    /// @inheritdoc IDelegateToken
    function rescind(uint256 delegateTokenId) external {
        //slither-disable-next-line timestamp
        if (StorageHelpers.readExpiry(delegateTokenInfo, delegateTokenId) < block.timestamp) {
            StorageHelpers.writeApproved(delegateTokenInfo, delegateTokenId, msg.sender);
            // approve gets reset in transferFrom or this write gets undone if this function call reverts
        }
        transferFrom(
            RegistryHelpers.loadTokenHolder(delegateRegistry, StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId)),
            IERC721(principalToken).ownerOf(delegateTokenId),
            delegateTokenId
        );
    }

    /// @inheritdoc IDelegateToken
    function withdraw(uint256 delegateTokenId) external nonReentrant {
        bytes32 registryHash = StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId);
        StorageHelpers.writeRegistryHash(delegateTokenInfo, delegateTokenId, bytes32(Constants.ID_USED));
        // Sets registry pointer to used flag
        Reverts.notMinted(registryHash, delegateTokenId);
        (address delegateTokenHolder, address underlyingContract) = RegistryHelpers.loadTokenHolderAndContract(delegateRegistry, registryHash);
        StorageHelpers.revertInvalidWithdrawalConditions(delegateTokenInfo, accountOperator, delegateTokenId, delegateTokenHolder);
        StorageHelpers.decrementBalance(balances, delegateTokenHolder);
        delete delegateTokenInfo[delegateTokenId][Constants.PACKED_INFO_POSITION]; // Deletes both expiry AND approved
        emit Transfer(delegateTokenHolder, address(0), delegateTokenId);
        IDelegateRegistry.DelegationType delegationType = RegistryHashes.decodeType(registryHash);
        bytes32 underlyingRights = RegistryHelpers.loadRights(delegateRegistry, registryHash);
        if (delegationType == IDelegateRegistry.DelegationType.ERC721) {
            uint256 erc721UnderlyingTokenId = RegistryHelpers.loadTokenId(delegateRegistry, registryHash);
            RegistryHelpers.revokeERC721(delegateRegistry, registryHash, delegateTokenHolder, underlyingContract, erc721UnderlyingTokenId, underlyingRights);
            PrincipalTokenHelpers.burn(principalToken, principalBurnAuthorization, delegateTokenId);
            IERC721(underlyingContract).transferFrom(address(this), msg.sender, erc721UnderlyingTokenId);
        } else if (delegationType == IDelegateRegistry.DelegationType.ERC20) {
            uint256 erc20UnderlyingAmount = StorageHelpers.readUnderlyingAmount(delegateTokenInfo, delegateTokenId);
            StorageHelpers.writeUnderlyingAmount(delegateTokenInfo, delegateTokenId, 0); // Deletes amount
            RegistryHelpers.revokeERC20(delegateRegistry, registryHash, delegateTokenHolder, underlyingContract, erc20UnderlyingAmount, underlyingRights);
            PrincipalTokenHelpers.burn(principalToken, principalBurnAuthorization, delegateTokenId);
            SafeERC20.safeTransfer(IERC20(underlyingContract), msg.sender, erc20UnderlyingAmount);
        } else if (delegationType == IDelegateRegistry.DelegationType.ERC1155) {
            uint256 erc1155UnderlyingAmount = StorageHelpers.readUnderlyingAmount(delegateTokenInfo, delegateTokenId);
            StorageHelpers.writeUnderlyingAmount(delegateTokenInfo, delegateTokenId, 0); // Deletes amount
            uint256 erc11551UnderlyingTokenId = RegistryHelpers.loadTokenId(delegateRegistry, registryHash);
            RegistryHelpers.revokeERC1155(
                delegateRegistry, registryHash, delegateTokenHolder, underlyingContract, erc11551UnderlyingTokenId, erc1155UnderlyingAmount, underlyingRights
            );
            PrincipalTokenHelpers.burn(principalToken, principalBurnAuthorization, delegateTokenId);
            IERC1155(underlyingContract).safeTransferFrom(address(this), msg.sender, erc11551UnderlyingTokenId, erc1155UnderlyingAmount, "");
        }
    }

    /// @inheritdoc IDelegateToken
    function flashloan(Structs.FlashInfo calldata info) external payable nonReentrant {
        Reverts.notOperator(accountOperator, info.delegateHolder);
        if (info.tokenType == IDelegateRegistry.DelegationType.ERC721) {
            RegistryHelpers.revertERC721FlashUnavailable(delegateRegistry, info);
            IERC721(info.tokenContract).transferFrom(address(this), info.receiver, info.tokenId);
            _revertOnCallingInvalidFlashloan(info);
            TransferHelpers.checkERC721BeforePull(info.amount, info.tokenContract, info.tokenId);
            TransferHelpers.pullERC721AfterCheck(info.tokenContract, info.tokenId);
        } else if (info.tokenType == IDelegateRegistry.DelegationType.ERC20) {
            RegistryHelpers.revertERC20FlashAmountUnavailable(delegateRegistry, info);
            SafeERC20.safeTransfer(IERC20(info.tokenContract), info.receiver, info.amount);
            _revertOnCallingInvalidFlashloan(info);
            TransferHelpers.checkERC20BeforePull(info.amount, info.tokenContract, info.tokenId);
            TransferHelpers.pullERC20AfterCheck(info.tokenContract, info.amount);
        } else if (info.tokenType == IDelegateRegistry.DelegationType.ERC1155) {
            RegistryHelpers.revertERC1155FlashAmountUnavailable(delegateRegistry, info);
            TransferHelpers.checkERC1155BeforePull(erc1155PullAuthorization, info.amount);
            IERC1155(info.tokenContract).safeTransferFrom(address(this), info.receiver, info.tokenId, info.amount, "");
            _revertOnCallingInvalidFlashloan(info);
            TransferHelpers.pullERC1155AfterCheck(erc1155PullAuthorization, info.amount, info.tokenContract, info.tokenId);
        }
    }

    function _revertOnCallingInvalidFlashloan(Structs.FlashInfo calldata info) internal {
        if (IDelegateFlashloan(info.receiver).onFlashloan{value: msg.value}(msg.sender, info) != IDelegateFlashloan.onFlashloan.selector) {
            revert IDelegateFlashloan.InvalidFlashloan();
        }
    }
}
