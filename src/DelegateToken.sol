// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IDelegateToken, IDelegateRegistry, IDelegateFlashloan} from "./interfaces/IDelegateToken.sol";
import {IERC721Metadata} from "openzeppelin/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC1155Receiver} from "openzeppelin/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "openzeppelin/utils/introspection/IERC165.sol";

import {PrincipalToken} from "./PrincipalToken.sol";
import {ERC2981} from "openzeppelin/token/common/ERC2981.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";

import {DelegateTokenConstants as Constants} from "src/libraries/DelegateTokenConstants.sol";
import {DelegateTokenErrors as Errors} from "src/libraries/DelegateTokenErrors.sol";
import {DelegateTokenReverts as Reverts, IERC721Receiver} from "src/libraries/DelegateTokenReverts.sol";
import {DelegateTokenStorageHelpers as StorageHelpers} from "src/libraries/DelegateTokenStorageHelpers.sol";
import {DelegateTokenRegistryHelpers as RegistryHelpers, RegistryHashes, RegistryStorage} from "src/libraries/DelegateTokenRegistryHelpers.sol";
import {DelegateTokenTransferHelpers as TransferHelpers, SafeERC20, IERC721, IERC20, IERC1155} from "src/libraries/DelegateTokenTransferHelpers.sol";
import {DelegateTokenPrincipalTokenHelpers as PrincipalTokenHelpers} from "src/libraries/DelegateTokenPrincipalTokenHelpers.sol";
import {DelegateTokenURI} from "src/libraries/DelegateTokenURI.sol";

contract DelegateToken is ReentrancyGuard, Ownable2Step, ERC2981, IDelegateToken, IERC721Metadata, IERC721Receiver, IERC1155Receiver {
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
    StorageHelpers.Uint256 internal principalMintAuthorization = StorageHelpers.Uint256(Constants.MINT_NOT_AUTHORIZED);
    StorageHelpers.Uint256 internal principalBurnAuthorization = StorageHelpers.Uint256(Constants.BURN_NOT_AUTHORIZED);

    /// @notice internal variable 11155 callbacks
    StorageHelpers.Uint256 internal erc1155PullAuthorization = StorageHelpers.Uint256(Constants.ERC1155_NOT_PULLED);

    /*//////////////////////////////////////////////////////////////
    /                      Constructor                             /
    //////////////////////////////////////////////////////////////*/

    constructor(address delegateRegistry_, address principalToken_, string memory baseURI_, address initialMetadataOwner) {
        if (delegateRegistry_ == address(0)) revert Errors.DelegateRegistryZero();
        delegateRegistry = delegateRegistry_;
        if (principalToken_ == address(0)) revert Errors.PrincipalTokenZero();
        principalToken = principalToken_;
        baseURI = baseURI_;
        if (initialMetadataOwner == address(0)) revert Errors.InitialMetadataOwnerZero();
        _transferOwnership(initialMetadataOwner);
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
        revert();
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(address operator, address, uint256, bytes calldata) external view returns (bytes4) {
        if (address(this) == operator) return IERC721Receiver.onERC721Received.selector;
        revert();
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155Received(address operator, address, uint256, uint256, bytes calldata) external returns (bytes4) {
        if (TransferHelpers.checkERC1155Pulled(erc1155PullAuthorization, operator)) return IERC1155Receiver.onERC1155Received.selector;
        revert();
    }

    /*//////////////////////////////////////////////////////////////
    /                 ERC721 Method Implementations                /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721
    /// @dev must revert if delegateTokenHolder is zero address
    function balanceOf(address delegateTokenHolder) external view returns (uint256) {
        if (delegateTokenHolder == address(0)) revert Errors.DelegateTokenHolderZero();
        return balances[delegateTokenHolder];
    }

    /// @inheritdoc IERC721
    /// @dev must revert if delegateTokenHolder is zero address
    function ownerOf(uint256 delegateTokenId) external view returns (address delegateTokenHolder) {
        delegateTokenHolder = RegistryHelpers.loadTokenHolder(delegateRegistry, delegateTokenInfo, delegateTokenId);
        if (delegateTokenHolder == address(0)) revert Errors.DelegateTokenHolderZero();
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
        Reverts.notERC721Receiver(from, to, delegateTokenId, data);
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 delegateTokenId) external {
        transferFrom(from, to, delegateTokenId);
        Reverts.notERC721Receiver(from, to, delegateTokenId);
    }

    /// @inheritdoc IERC721
    function approve(address spender, uint256 delegateTokenId) external {
        address delegateTokenHolder = RegistryHelpers.loadTokenHolder(delegateRegistry, delegateTokenInfo, delegateTokenId);
        Reverts.notOperator(accountOperator, delegateTokenHolder, delegateTokenId);
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
    /// @dev registryHash for the DelegateTokenId must point to the new registry delegation associated with the to address
    function transferFrom(address from, address to, uint256 delegateTokenId) public {
        Reverts.toIsZero(to);
        bytes32 registryHash = StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId);
        Reverts.notMinted(registryHash, delegateTokenId);
        (address delegateTokenHolder, address underlyingContract) = RegistryHelpers.loadTokenHolderAndContract(delegateRegistry, registryHash);
        if (from != delegateTokenHolder) revert Errors.FromNotDelegateTokenHolder(from, delegateTokenHolder);
        // We can use from here instead of delegateTokenHolder since we've just verified that from == delegateTokenHolder
        Reverts.notApprovedOrOperator(accountOperator, delegateTokenInfo, from, delegateTokenId);
        unchecked {
            balances[from]--;
            balances[to]++;
        } // Reasonable to expect this block to not under/overflow
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
        // Load delegation from registry
        bytes32[] memory registryHash = new bytes32[](1);
        registryHash[0] = bytes32(delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION]);
        IDelegateRegistry.Delegation[] memory delegation = IDelegateRegistry(delegateRegistry).getDelegationsFromHashes(registryHash);

        // Revert if invalid
        if (delegation[0].to == address(0)) revert Errors.NotMinted(delegateTokenId);

        // When the principal token is redeemed, the delegate token is burned. So we can query this with no try-catch
        address principalTokenOwner = PrincipalToken(principalToken).ownerOf(delegateTokenId);

        return DelegateTokenURI.build(
            baseURI, delegation[0].contract_, delegation[0].tokenId, StorageHelpers.readExpiry(delegateTokenInfo, delegateTokenId), principalTokenOwner
        );
    }

    /// @inheritdoc IDelegateToken
    function isApprovedOrOwner(address spender, uint256 delegateTokenId) external view returns (bool) {
        Reverts.notMinted(StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId), delegateTokenId);
        address delegateTokenHolder = RegistryHelpers.loadTokenHolder(delegateRegistry, delegateTokenInfo, delegateTokenId);
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
    function getDelegateInfo(uint256 delegateTokenId) external view returns (DelegateInfo memory delegateInfo) {
        bytes32[] memory registryHash = new bytes32[](1);
        registryHash[0] = bytes32(StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId));
        IDelegateRegistry.Delegation[] memory delegation = IDelegateRegistry(delegateRegistry).getDelegationsFromHashes(registryHash);
        delegateInfo.tokenType = delegation[0].type_;
        delegateInfo.tokenContract = delegation[0].contract_;
        delegateInfo.tokenId = delegation[0].tokenId;
        delegateInfo.rights = delegation[0].rights;
        delegateInfo.delegateHolder = delegation[0].to;
        delegateInfo.principalHolder = PrincipalToken(principalToken).ownerOf(delegateTokenId);
        delegateInfo.expiry = StorageHelpers.readExpiry(delegateTokenInfo, delegateTokenId);
        if (delegation[0].type_ == IDelegateRegistry.DelegationType.ERC721) delegateInfo.amount = 0;
        else delegateInfo.amount = StorageHelpers.readUnderlyingAmount(delegateTokenInfo, delegateTokenId);
    }

    /// @inheritdoc IDelegateToken
    function getDelegateId(address creator, uint256 salt) public view returns (uint256 delegateTokenId) {
        delegateTokenId = uint256(keccak256(abi.encode(creator, salt)));
        Reverts.alreadyExisted(delegateTokenInfo, delegateTokenId);
    }

    /// @inheritdoc IDelegateToken
    /// @dev must revert if delegate token did not call burn on the Principal Token for the delegateTokenId
    /// @dev must revert if principal token is not the caller
    function burnAuthorizedCallback() external {
        PrincipalTokenHelpers.checkBurnAuthorized(principalToken, principalBurnAuthorization);
    }

    /// @inheritdoc IDelegateToken
    /// @dev must revert if delegate token did not call burn on the Principal Token for the delegateTokenId
    /// @dev must revert if principal token is not the caller
    function mintAuthorizedCallback() external {
        PrincipalTokenHelpers.checkMintAuthorized(principalToken, principalMintAuthorization);
    }

    /// @inheritdoc IDelegateToken
    function create(DelegateInfo calldata delegateInfo, uint256 salt) external nonReentrant returns (uint256 delegateTokenId) {
        TransferHelpers.checkAndPullByType(erc1155PullAuthorization, delegateInfo);
        //slither-disable-next-line timestamp
        if (delegateInfo.expiry < block.timestamp) revert Errors.ExpiryTimeNotInFuture(delegateInfo.expiry, block.timestamp);
        if (delegateInfo.expiry > Constants.MAX_EXPIRY) revert Errors.ExpiryTooLarge(delegateInfo.expiry, Constants.MAX_EXPIRY);
        Reverts.toIsZero(delegateInfo.delegateHolder);
        delegateTokenId = getDelegateId(msg.sender, salt);
        Reverts.alreadyExisted(delegateTokenInfo, delegateTokenId);
        unchecked {
            //slither-disable-next-line reentrancy-benign
            balances[delegateInfo.delegateHolder]++;
        } // Infeasible that this will overflow
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
        uint256 currentExpiry = StorageHelpers.readExpiry(delegateTokenInfo, delegateTokenId);
        if (newExpiry <= currentExpiry) revert Errors.ExpiryTooSmall(newExpiry, currentExpiry);
        if (!PrincipalToken(principalToken).isApprovedOrOwner(msg.sender, delegateTokenId)) revert Errors.NotAuthorized(msg.sender, delegateTokenId);
        StorageHelpers.writeExpiry(delegateTokenInfo, delegateTokenId, newExpiry);
    }

    /// @inheritdoc IDelegateToken
    function rescind(address from, uint256 delegateTokenId) external {
        //slither-disable-next-line timestamp
        if (StorageHelpers.readExpiry(delegateTokenInfo, delegateTokenId) < block.timestamp) StorageHelpers.writeApproved(delegateTokenInfo, delegateTokenId, msg.sender);
        // approve gets deleted in transferFrom
        transferFrom(from, Constants.RESCIND_ADDRESS, delegateTokenId);
    }

    /// @inheritdoc IDelegateToken
    function withdraw(address recipient, uint256 delegateTokenId) external nonReentrant {
        bytes32 registryHash = StorageHelpers.readRegistryHash(delegateTokenInfo, delegateTokenId);
        StorageHelpers.writeRegistryHash(delegateTokenInfo, delegateTokenId, bytes32(Constants.ID_USED));
        Reverts.notMinted(registryHash, delegateTokenId);
        (address delegateTokenHolder, address underlyingContract) = RegistryHelpers.loadTokenHolderAndContract(delegateRegistry, registryHash);
        //slither-disable-next-line timestamp
        if (block.timestamp < StorageHelpers.readExpiry(delegateTokenInfo, delegateTokenId)) {
            if (
                delegateTokenHolder != Constants.RESCIND_ADDRESS && delegateTokenHolder != msg.sender
                    && msg.sender != StorageHelpers.readApproved(delegateTokenInfo, delegateTokenId)
            ) {
                revert Errors.WithdrawNotAvailable(delegateTokenId, StorageHelpers.readExpiry(delegateTokenInfo, delegateTokenId), block.timestamp);
            }
        }
        unchecked {
            balances[delegateTokenHolder]--;
        } // Reasonable to expect this not to underflow
        delete delegateTokenInfo[delegateTokenId][Constants.PACKED_INFO_POSITION]; // Deletes both expiry AND approved
        emit Transfer(delegateTokenHolder, address(0), delegateTokenId);
        IDelegateRegistry.DelegationType delegationType = RegistryHashes.decodeType(bytes32(registryHash));
        bytes32 underlyingRights = RegistryHelpers.loadRights(delegateRegistry, registryHash);
        if (delegationType == IDelegateRegistry.DelegationType.ERC721) {
            uint256 erc721UnderlyingTokenId = RegistryHelpers.loadTokenId(delegateRegistry, registryHash);
            if (
                IDelegateRegistry(delegateRegistry).delegateERC721(delegateTokenHolder, underlyingContract, erc721UnderlyingTokenId, underlyingRights, false)
                    != registryHash
            ) revert Errors.HashMismatch();
            PrincipalTokenHelpers.burn(principalToken, principalBurnAuthorization, delegateTokenId);
            IERC721(underlyingContract).transferFrom(address(this), recipient, erc721UnderlyingTokenId);
        } else if (delegationType == IDelegateRegistry.DelegationType.ERC20) {
            uint256 erc20UnderlyingAmount = StorageHelpers.readUnderlyingAmount(delegateTokenInfo, delegateTokenId);
            StorageHelpers.writeUnderlyingAmount(delegateTokenInfo, delegateTokenId, 0);
            if (
                IDelegateRegistry(delegateRegistry).delegateERC20(
                    delegateTokenHolder,
                    underlyingContract,
                    RegistryHelpers.calculateDecreasedAmount(delegateRegistry, registryHash, erc20UnderlyingAmount),
                    underlyingRights,
                    true
                ) != registryHash
            ) revert Errors.HashMismatch();
            PrincipalTokenHelpers.burn(principalToken, principalBurnAuthorization, delegateTokenId);
            SafeERC20.safeTransfer(IERC20(underlyingContract), recipient, erc20UnderlyingAmount);
        } else if (delegationType == IDelegateRegistry.DelegationType.ERC1155) {
            uint256 erc1155UnderlyingAmount = StorageHelpers.readUnderlyingAmount(delegateTokenInfo, delegateTokenId);
            StorageHelpers.writeUnderlyingAmount(delegateTokenInfo, delegateTokenId, 0);
            uint256 erc11551UnderlyingTokenId = RegistryHelpers.loadTokenId(delegateRegistry, registryHash);
            if (
                IDelegateRegistry(delegateRegistry).delegateERC1155(
                    delegateTokenHolder,
                    underlyingContract,
                    erc11551UnderlyingTokenId,
                    RegistryHelpers.calculateDecreasedAmount(delegateRegistry, registryHash, erc1155UnderlyingAmount),
                    underlyingRights,
                    true
                ) != registryHash
            ) revert Errors.HashMismatch();
            PrincipalTokenHelpers.burn(principalToken, principalBurnAuthorization, delegateTokenId);
            IERC1155(underlyingContract).safeTransferFrom(address(this), recipient, erc11551UnderlyingTokenId, erc1155UnderlyingAmount, "");
        }
    }

    /// @inheritdoc IDelegateToken
    function flashloan(IDelegateFlashloan.FlashInfo calldata info) external payable nonReentrant {
        if (msg.sender != info.delegateHolder && !isApprovedForAll(info.delegateHolder, msg.sender)) revert Errors.InvalidFlashloan();
        if (info.tokenType == IDelegateRegistry.DelegationType.ERC721) {
            // We touch registry directly to check for active delegation of the respective hash, as bubbling up to contract and all delegations is not required
            // Important to notice that we cannot rely on this method for the fungibles since delegate token doesn't ever delete the fungible delegations
            if (
                RegistryHelpers.loadFrom(delegateRegistry, RegistryHashes.erc721Hash(address(this), "", info.delegateHolder, info.tokenId, info.tokenContract))
                    == address(this)
                    || RegistryHelpers.loadFrom(
                        delegateRegistry, RegistryHashes.erc721Hash(address(this), "flashloan", info.delegateHolder, info.tokenId, info.tokenContract)
                    ) == address(this)
            ) {
                IERC721(info.tokenContract).transferFrom(address(this), info.receiver, info.tokenId);
                _callOnFlashloan(info);
                TransferHelpers.checkERC721BeforePull(info.amount, info.tokenContract, info.tokenId);
                TransferHelpers.pullERC721AfterCheck(info.tokenContract, info.tokenId);
            } else {
                revert Errors.InvalidFlashloan();
            }
        } else if (info.tokenType == IDelegateRegistry.DelegationType.ERC20) {
            uint256 availableAmount = 0;
            unchecked {
                // We sum the delegation amounts for "flashloan" and "" rights since liquid delegate doesn't allow tokens to be used for more than one rights type at a
                // time
                availableAmount = RegistryHelpers.loadAmount(
                    delegateRegistry, RegistryHashes.erc20Hash(address(this), "flashloan", info.delegateHolder, info.tokenContract)
                ) + RegistryHelpers.loadAmount(delegateRegistry, RegistryHashes.erc20Hash(address(this), "", info.delegateHolder, info.tokenContract));
            } // Unreasonable that this block will overflow
            if (info.amount > availableAmount) revert Errors.InvalidFlashloan();
            SafeERC20.safeTransfer(IERC20(info.tokenContract), info.receiver, info.amount);
            _callOnFlashloan(info);
            TransferHelpers.checkERC20BeforePull(info.amount, info.tokenContract, info.tokenId);
            TransferHelpers.pullERC20AfterCheck(info.tokenContract, info.amount);
        } else if (info.tokenType == IDelegateRegistry.DelegationType.ERC1155) {
            uint256 availableAmount = 0;
            unchecked {
                availableAmount = RegistryHelpers.loadAmount(
                    delegateRegistry, RegistryHashes.erc1155Hash(address(this), "flashloan", info.delegateHolder, info.tokenId, info.tokenContract)
                ) + RegistryHelpers.loadAmount(delegateRegistry, RegistryHashes.erc1155Hash(address(this), "", info.delegateHolder, info.tokenId, info.tokenContract));
            } // Unreasonable that this will overflow
            if (info.amount > availableAmount) revert Errors.InvalidFlashloan();
            TransferHelpers.checkERC1155BeforePull(erc1155PullAuthorization, info.amount); // Calling this before the external calls since it writes the state
            IERC1155(info.tokenContract).safeTransferFrom(address(this), info.receiver, info.tokenId, info.amount, "");
            _callOnFlashloan(info);
            TransferHelpers.pullERC1155AfterCheck(erc1155PullAuthorization, info.amount, info.tokenContract, info.tokenId);
        } else {
            revert Errors.InvalidTokenType(info.tokenType);
        }
    }

    function _callOnFlashloan(IDelegateFlashloan.FlashInfo calldata info) internal {
        if (IDelegateFlashloan(info.receiver).onFlashloan{value: msg.value}(msg.sender, info) != IDelegateFlashloan.onFlashloan.selector) {
            revert Errors.InvalidFlashloan();
        }
    }
}
