// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IDelegateToken, IDelegateRegistry} from "./interfaces/IDelegateToken.sol";
import {IDelegateFlashloan} from "./interfaces/IDelegateFlashloan.sol";
import {IERC1155} from "openzeppelin/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "openzeppelin/token/ERC1155/IERC1155Receiver.sol";
import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {PrincipalToken} from "./PrincipalToken.sol";
import {ERC2981} from "openzeppelin/token/common/ERC2981.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";

import {DelegateTokenConstants as Constants} from "./libraries/DelegateTokenConstants.sol";
import {RegistryHashes} from "delegate-registry/src/libraries/RegistryHashes.sol";
import {RegistryStorage} from "delegate-registry/src/libraries/RegistryStorage.sol";
import {Base64} from "openzeppelin/utils/Base64.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

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
    uint256 internal mintAuthorized = Constants.MINT_NOT_AUTHORIZED;
    uint256 internal burnAuthorized = Constants.BURN_NOT_AUTHORIZED;

    /// @notice internal variables for 721 / 11155 callbacks
    uint256 internal erc1155Pulled = Constants.ERC1155_NOT_PULLED;
    uint256 internal erc721Pulled = Constants.ERC721_NOT_PULLED;

    /*//////////////////////////////////////////////////////////////
    /                      Constructor                             /
    //////////////////////////////////////////////////////////////*/

    constructor(address delegateRegistry_, address principalToken_, string memory baseURI_, address initialMetadataOwner) {
        if (delegateRegistry_ == address(0)) revert DelegateRegistryZero();
        delegateRegistry = delegateRegistry_;
        if (principalToken_ == address(0)) revert PrincipalTokenZero();
        principalToken = principalToken_;
        baseURI = baseURI_;
        if (initialMetadataOwner == address(0)) revert InitialMetadataOwnerZero();
        _transferOwnership(initialMetadataOwner);
    }

    /*//////////////////////////////////////////////////////////////
    /                    Supported Interfaces                      /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDelegateToken
    function supportsInterface(bytes4 interfaceId) public pure override(ERC2981, IDelegateToken) returns (bool) {
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
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4) {
        if (erc1155Pulled == Constants.ERC1155_PULLED) {
            erc1155Pulled = Constants.ERC1155_NOT_PULLED;
            return IERC1155Receiver.onERC1155Received.selector;
        }
        return 0;
    }

    /// @inheritdoc IERC1155Receiver
    /// @dev return 0 if length is not equal to one since this contract only works with single erc1155 transfers
    function onERC1155BatchReceived(address, address, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata) external returns (bytes4) {
        if (erc1155Pulled == Constants.ERC1155_PULLED && ids.length == 1 && amounts.length == 1) {
            erc1155Pulled = Constants.ERC1155_NOT_PULLED;
            return IERC1155Receiver.onERC1155Received.selector;
        }
        return 0;
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        if (erc721Pulled == Constants.ERC721_PULLED) {
            erc721Pulled = Constants.ERC721_NOT_PULLED;
            return IERC721Receiver.onERC721Received.selector;
        }
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
    /                 ERC721 Method Implementations                /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721
    /// @dev must revert if delegateTokenHolder is zero address
    function balanceOf(address delegateTokenHolder) external view returns (uint256) {
        if (delegateTokenHolder == address(0)) revert DelegateTokenHolderZero();
        return balances[delegateTokenHolder];
    }

    /// @inheritdoc IERC721
    /// @dev must revert if delegateTokenHolder is zero address
    function ownerOf(uint256 delegateTokenId) external view returns (address delegateTokenHolder) {
        delegateTokenHolder = _loadDelegateTokenHolder(delegateTokenId);
        if (delegateTokenHolder == address(0)) revert DelegateTokenHolderZero();
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 delegateTokenId, bytes calldata data) external {
        transferFrom(from, to, delegateTokenId);
        _revertIfNotERC721Receiver(from, to, delegateTokenId, data);
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 delegateTokenId) external {
        transferFrom(from, to, delegateTokenId);
        _revertIfNotERC721Receiver(from, to, delegateTokenId, "");
    }

    /// @inheritdoc IERC721
    function approve(address spender, uint256 delegateTokenId) external {
        address delegateTokenHolder = _loadDelegateTokenHolder(delegateTokenId);
        _revertIfNotOperator(delegateTokenHolder, delegateTokenId);
        _writeApproved(delegateTokenId, spender);
        emit Approval(delegateTokenHolder, spender, delegateTokenId);
    }

    /// @inheritdoc IERC721
    function setApprovalForAll(address operator, bool approved) external {
        accountOperator[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @inheritdoc IERC721
    function getApproved(uint256 delegateTokenId) public view returns (address) {
        _revertIfNotMinted(_loadRegistryHash(delegateTokenId), delegateTokenId);
        return _readApproved(delegateTokenId);
    }

    /// @inheritdoc IERC721
    function isApprovedForAll(address account, address operator) public view returns (bool) {
        return accountOperator[account][operator];
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
        _revertIfToIsZero(to);
        uint256 registryHash = _loadRegistryHash(delegateTokenId);
        _revertIfNotMinted(registryHash, delegateTokenId);
        (address delegateTokenHolder, address underlyingContract) = _loadDelegateTokenHolderAndUnderlyingContract(registryHash);
        if (from != delegateTokenHolder) revert FromNotDelegateTokenHolder(from, delegateTokenHolder);
        // We can use from here instead of delegateTokenHolder since we've just verified that from == delegateTokenHolder
        _revertIfNotApprovedOrOperator(from, delegateTokenId);
        // Update balances
        unchecked {
            balances[from]--;
            balances[to]++;
        } // Reasonable to expect this block to not under/overflow
        _writeApproved(delegateTokenId, address(0));
        emit Transfer(from, to, delegateTokenId);
        _transferByType(from, delegateTokenId, registryHash, to, underlyingContract);
    }

    function _transferByType(address from, uint256 delegateTokenId, uint256 registryHash, address to, address underlyingContract) internal {
        bytes32 newRegistryHash = 0;
        IDelegateRegistry.DelegationType underlyingType = RegistryHashes.decodeType(bytes32(registryHash));
        bytes32 underlyingRights = _loadRegistryRights(registryHash);
        if (underlyingType == IDelegateRegistry.DelegationType.ERC721) {
            uint256 erc721UnderlyingTokenId = _loadRegistryTokenId(registryHash);
            newRegistryHash = RegistryHashes.erc721Hash(address(this), underlyingRights, to, erc721UnderlyingTokenId, underlyingContract);
            _writeRegistryHash(delegateTokenId, newRegistryHash);
            if (
                IDelegateRegistry(delegateRegistry).delegateERC721(from, underlyingContract, erc721UnderlyingTokenId, underlyingRights, false) != bytes32(registryHash)
                    || IDelegateRegistry(delegateRegistry).delegateERC721(to, underlyingContract, erc721UnderlyingTokenId, underlyingRights, true) != newRegistryHash
            ) revert HashMismatch();
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC20) {
            newRegistryHash = RegistryHashes.erc20Hash(address(this), underlyingRights, to, underlyingContract);
            _writeRegistryHash(delegateTokenId, newRegistryHash);
            uint256 erc20UnderlyingAmount = _readUnderlyingAmount(delegateTokenId);
            if (
                IDelegateRegistry(delegateRegistry).delegateERC20(
                    from, underlyingContract, _calculateRegistryDecreasedAmount(registryHash, erc20UnderlyingAmount), underlyingRights, true
                ) != bytes32(registryHash)
                    || IDelegateRegistry(delegateRegistry).delegateERC20(
                        to, underlyingContract, _calculateRegistryIncreasedAmount(uint256(newRegistryHash), erc20UnderlyingAmount), underlyingRights, true
                    ) != newRegistryHash
            ) {
                revert HashMismatch();
            }
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC1155) {
            uint256 erc1155UnderlyingId = _loadRegistryTokenId(registryHash);
            newRegistryHash = RegistryHashes.erc1155Hash(address(this), underlyingRights, to, erc1155UnderlyingId, underlyingContract);
            _writeRegistryHash(delegateTokenId, newRegistryHash);
            uint256 erc1155UnderlyingAmount = _readUnderlyingAmount(delegateTokenId);
            if (
                (
                    IDelegateRegistry(delegateRegistry).delegateERC1155(
                        from, underlyingContract, erc1155UnderlyingId, _calculateRegistryDecreasedAmount(registryHash, erc1155UnderlyingAmount), underlyingRights, true
                    )
                ) != bytes32(registryHash)
                    || IDelegateRegistry(delegateRegistry).delegateERC1155(
                        to,
                        underlyingContract,
                        erc1155UnderlyingId,
                        _calculateRegistryIncreasedAmount(uint256(newRegistryHash), erc1155UnderlyingAmount),
                        underlyingRights,
                        true
                    ) != newRegistryHash
            ) revert HashMismatch();
        }
    }

    /*//////////////////////////////////////////////////////////////
    /                EXTENDED ERC721 METHODS                       /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDelegateToken
    function isApprovedOrOwner(address spender, uint256 delegateTokenId) public view returns (bool) {
        _revertIfNotMinted(_loadRegistryHash(delegateTokenId), delegateTokenId);
        address delegateTokenHolder = _loadDelegateTokenHolder(delegateTokenId);
        return spender == delegateTokenHolder || isApprovedForAll(delegateTokenHolder, spender) || getApproved(delegateTokenId) == spender;
    }

    /*//////////////////////////////////////////////////////////////
    /            LIQUID DELEGATE TOKEN METHODS                     /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDelegateToken
    /// @dev must revert if delegate token did not call burn on the Principal Token for the delegateTokenId
    /// @dev must revert if principal token is not the caller
    function burnAuthorizedCallback() external {
        _checkPrincipalTokenCaller();
        if (burnAuthorized != Constants.BURN_AUTHORIZED) revert BurnNotAuthorized();
        burnAuthorized = Constants.BURN_NOT_AUTHORIZED;
    }

    /// @inheritdoc IDelegateToken
    /// @dev must revert if delegate token did not call burn on the Principal Token for the delegateTokenId
    /// @dev must revert if principal token is not the caller
    function mintAuthorizedCallback() external {
        if (mintAuthorized != Constants.MINT_AUTHORIZED) revert MintNotAuthorized();
        mintAuthorized = Constants.MINT_NOT_AUTHORIZED;
        _checkPrincipalTokenCaller();
    }

    /// @notice helper function to revert if caller is not Principal Token
    /// @dev must revert if msg.sender is not the principal token
    function _checkPrincipalTokenCaller() internal view {
        if (msg.sender != principalToken) revert CallerNotPrincipalToken();
    }

    /// @notice helper function for burning a principal token
    /// @dev must revert if burnAuthorized has already been set to BURN_AUTHORIZED flag
    function _principalTokenBurn(uint256 delegateTokenId) internal {
        if (burnAuthorized == Constants.BURN_AUTHORIZED) revert BurnAuthorized();
        burnAuthorized = Constants.BURN_AUTHORIZED;
        PrincipalToken(principalToken).burn(msg.sender, delegateTokenId);
    }

    /// @notice helper function for minting a principal token
    /// @dev must revert if mintAuthorized has already been set to MINT_AUTHORIZED flag
    function _principalTokenMint(address principalRecipient, uint256 delegateTokenId) internal {
        if (mintAuthorized == Constants.MINT_AUTHORIZED) revert MintAuthorized();
        mintAuthorized = Constants.MINT_AUTHORIZED;
        PrincipalToken(principalToken).mint(principalRecipient, delegateTokenId);
    }

    /// @inheritdoc IDelegateToken
    function getDelegateInfo(uint256 delegateTokenId) external view returns (DelegateInfo memory delegateInfo) {
        // Load delegation from registry
        bytes32[] memory registryHash = new bytes32[](1);
        registryHash[0] = bytes32(_loadRegistryHash(delegateTokenId));
        IDelegateRegistry.Delegation[] memory delegation = IDelegateRegistry(delegateRegistry).getDelegationsFromHashes(registryHash);
        delegateInfo.tokenType = delegation[0].type_;
        delegateInfo.tokenContract = delegation[0].contract_;
        delegateInfo.tokenId = delegation[0].tokenId;
        delegateInfo.rights = delegation[0].rights;
        delegateInfo.delegateHolder = delegation[0].to;
        delegateInfo.principalHolder = PrincipalToken(principalToken).ownerOf(delegateTokenId);
        // Read expiry
        delegateInfo.expiry = _readExpiry(delegateTokenId);
        // Load tokenAmount
        if (delegation[0].type_ == IDelegateRegistry.DelegationType.ERC721) delegateInfo.amount = 1;
        else delegateInfo.amount = delegateTokenInfo[delegateTokenId][Constants.UNDERLYING_AMOUNT_POSITION];
    }

    /// @inheritdoc IDelegateToken
    function create(DelegateInfo calldata delegateInfo, uint256 salt) external nonReentrant returns (uint256 delegateTokenId) {
        // Pulls tokens in before minting, reverts if invalid token type, underlyingAmount or underlyingTokenId
        _pullAndCheckByType(delegateInfo.tokenType, delegateInfo.amount, delegateInfo.tokenContract, delegateInfo.tokenId);
        // Check expiry
        //slither-disable-next-line timestamp
        if (delegateInfo.expiry < block.timestamp) revert ExpiryTimeNotInFuture(delegateInfo.expiry, block.timestamp);
        if (delegateInfo.expiry > Constants.MAX_EXPIRY) revert ExpiryTooLarge(delegateInfo.expiry, Constants.MAX_EXPIRY);
        // Revert if to is the zero address
        _revertIfToIsZero(delegateInfo.delegateHolder);
        delegateTokenId = getDelegateId(msg.sender, salt);
        _revertIfAlreadyExisted(delegateTokenId);
        // Increment erc721 balance
        unchecked {
            balances[delegateInfo.delegateHolder]++;
        } // Infeasible that this will overflow
        // Write expiry
        _writeExpiry(delegateTokenId, delegateInfo.expiry);
        // Emit transfer event
        emit Transfer(address(0), delegateInfo.delegateHolder, delegateTokenId);
        // Update amount, registry data, and store registry hash
        _createByType(
            delegateInfo.tokenType,
            delegateTokenId,
            delegateInfo.delegateHolder,
            delegateInfo.amount,
            delegateInfo.tokenContract,
            delegateInfo.rights,
            delegateInfo.tokenId
        );
        // Mint principal token
        _principalTokenMint(delegateInfo.principalHolder, delegateTokenId);
    }

    function _pullAndCheckByType(IDelegateRegistry.DelegationType underlyingType, uint256 underlyingAmount, address underlyingContract, uint256 underlyingTokenId)
        internal
    {
        if (underlyingType == IDelegateRegistry.DelegationType.ERC721) {
            _pullAndCheckERC721(underlyingAmount, underlyingContract, underlyingTokenId);
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC20) {
            _pullAndCheckERC20(underlyingAmount, underlyingContract, underlyingTokenId);
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC1155) {
            _pullAndCheckERC1155(underlyingAmount, underlyingContract, underlyingTokenId);
        } else {
            revert InvalidTokenType(underlyingType);
        }
    }

    function _pullAndCheckERC721(uint256 underlyingAmount, address underlyingContract, uint256 underlyingTokenId) internal {
        if (underlyingAmount != 0) revert WrongAmountForType(IDelegateRegistry.DelegationType.ERC721, underlyingAmount);
        if (erc721Pulled == Constants.ERC721_NOT_PULLED) erc721Pulled = Constants.ERC721_PULLED;
        else revert ERC721Pulled();
        IERC721(underlyingContract).safeTransferFrom(msg.sender, address(this), underlyingTokenId);
        if (erc721Pulled == Constants.ERC721_PULLED) revert ERC721NotPulled();
    }

    function _pullAndCheckERC20(uint256 underlyingAmount, address underlyingContract, uint256 underlyingTokenId) internal {
        if (underlyingAmount == 0) revert WrongAmountForType(IDelegateRegistry.DelegationType.ERC20, underlyingAmount);
        if (underlyingTokenId != 0) revert WrongTokenIdForType(IDelegateRegistry.DelegationType.ERC20, underlyingTokenId);
        // Following does a sense check on the allowance which should fail for a typical 721 / 1155 and pass for a typical 20
        if (IERC20(underlyingContract).allowance(msg.sender, address(this)) < underlyingAmount) revert InsufficientAllowanceOrInvalidToken();
        SafeERC20.safeTransferFrom(IERC20(underlyingContract), msg.sender, address(this), underlyingAmount);
    }

    function _pullAndCheckERC1155(uint256 underlyingAmount, address underlyingContract, uint256 underlyingTokenId) internal {
        if (underlyingAmount == 0) revert WrongAmountForType(IDelegateRegistry.DelegationType.ERC1155, underlyingAmount);
        if (erc1155Pulled == Constants.ERC1155_NOT_PULLED) erc1155Pulled = Constants.ERC1155_PULLED;
        else revert ERC1155Pulled();
        IERC1155(underlyingContract).safeTransferFrom(msg.sender, address(this), underlyingTokenId, underlyingAmount, "");
        if (erc721Pulled == Constants.ERC721_PULLED) revert ERC721NotPulled();
    }

    function _createByType(
        IDelegateRegistry.DelegationType underlyingType,
        uint256 delegateTokenId,
        address delegateTokenTo,
        uint256 underlyingAmount,
        address underlyingContract,
        bytes32 underlyingRights,
        uint256 underlyingTokenId
    ) internal {
        bytes32 newRegistryHash = 0;
        if (underlyingType == IDelegateRegistry.DelegationType.ERC721) {
            // Store hash, computing registry hash deterministically
            newRegistryHash = RegistryHashes.erc721Hash(address(this), underlyingRights, delegateTokenTo, underlyingTokenId, underlyingContract);
            delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION] = uint256(newRegistryHash);
            // Update Registry
            if (newRegistryHash != IDelegateRegistry(delegateRegistry).delegateERC721(delegateTokenTo, underlyingContract, underlyingTokenId, underlyingRights, true)) {
                revert HashMismatch();
            }
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC20) {
            // Store amount
            delegateTokenInfo[delegateTokenId][Constants.UNDERLYING_AMOUNT_POSITION] = underlyingAmount;
            // Store hash, computing registry hash deterministically
            newRegistryHash = RegistryHashes.erc20Hash(address(this), underlyingRights, delegateTokenTo, underlyingContract);
            delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION] = uint256(newRegistryHash);
            // Calculate increasedAmount, reading directly from registry storage
            bytes32 newRegistryLocation = RegistryHashes.location(newRegistryHash);
            unchecked {
                uint256 erc20IncreasedAmount = uint256(
                    IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(newRegistryLocation) + uint256(RegistryStorage.Positions.amount)))
                ) + underlyingAmount;
                // Update registry, reverts if returned hashes aren't correct
                if (
                    newRegistryHash
                        != IDelegateRegistry(delegateRegistry).delegateERC20(delegateTokenTo, underlyingContract, erc20IncreasedAmount, underlyingRights, true)
                ) {
                    revert HashMismatch();
                }
            } // Reasonable to expect this block not to overflow
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC1155) {
            // Store amount
            delegateTokenInfo[delegateTokenId][Constants.UNDERLYING_AMOUNT_POSITION] = underlyingAmount;
            // Store hash, computing registry hash deterministically
            newRegistryHash = RegistryHashes.erc1155Hash(address(this), underlyingRights, delegateTokenTo, underlyingTokenId, underlyingContract);
            delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION] = uint256(newRegistryHash);
            // Calculate toAmount, reading directly from registry storage
            bytes32 newRegistryLocation = RegistryHashes.location(newRegistryHash);
            unchecked {
                uint256 erc1155IncreasedAmount = uint256(
                    IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(newRegistryLocation) + uint256(RegistryStorage.Positions.amount)))
                ) + underlyingAmount;
                // Update registry, reverts if returned hashes aren't correct
                if (
                    newRegistryHash
                        != IDelegateRegistry(delegateRegistry).delegateERC1155(
                            delegateTokenTo, underlyingContract, underlyingTokenId, erc1155IncreasedAmount, underlyingRights, true
                        )
                ) revert HashMismatch();
            } // Reasonable to expect this block not to overflow
        }
    }

    /// @inheritdoc IDelegateToken
    function extend(uint256 delegateTokenId, uint256 newExpiry) external {
        if (!PrincipalToken(principalToken).isApprovedOrOwner(msg.sender, delegateTokenId)) revert NotAuthorized(msg.sender, delegateTokenId);
        uint256 currentExpiry = _readExpiry(delegateTokenId);
        if (newExpiry <= currentExpiry) revert ExpiryTooSmall(newExpiry, currentExpiry);
        _writeExpiry(delegateTokenId, newExpiry);
    }

    /// @inheritdoc IDelegateToken
    function rescind(address from, uint256 delegateTokenId) external {
        //slither-disable-next-line timestamp
        if (_readExpiry(delegateTokenId) < block.timestamp) {
            if (from == address(0)) revert FromIsZero();
            _writeApproved(delegateTokenId, msg.sender); // This should be fine as the approve for the token gets delete in transferFrom
            transferFrom(from, Constants.RESCIND_ADDRESS, delegateTokenId);
        } else {
            transferFrom(from, Constants.RESCIND_ADDRESS, delegateTokenId);
        }
    }

    /// @inheritdoc IDelegateToken
    function withdraw(address recipient, uint256 delegateTokenId) external nonReentrant {
        // Load registryHash and check nft is valid
        uint256 registryHash = delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION];
        _revertIfNotMinted(registryHash, delegateTokenId);
        // Set registry hash to delegate token id used
        delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION] = Constants.ID_USED;
        // Load delegateTokenHolder from registry
        bytes32 registryLocation = RegistryHashes.location(bytes32(registryHash));
        (address delegateTokenHolder, address underlyingContract) = _loadDelegateTokenHolderAndUnderlyingContract(registryHash);
        // If it still exists the only valid way to withdraw is the delegation having expired or delegateTokenHolder rescinded to this contract
        // Also allows withdraw if the caller is approved or holder of delegate token
        {
            uint256 expiry = _readExpiry(delegateTokenId);
            //slither-disable-next-line timestamp
            if (block.timestamp < expiry) {
                if (delegateTokenHolder != Constants.RESCIND_ADDRESS && delegateTokenHolder != msg.sender && msg.sender != _readApproved(delegateTokenId)) {
                    revert WithdrawNotAvailable(delegateTokenId, expiry, block.timestamp);
                }
            }
        }
        // Decrement balance of holder
        unchecked {
            balances[delegateTokenHolder]--;
        } // Reasonable to expect this not to underflow
        // Delete approved and expiry
        delete delegateTokenInfo[delegateTokenId][Constants.PACKED_INFO_POSITION];
        // Emit transfer to zero address
        emit Transfer(delegateTokenHolder, address(0), delegateTokenId);
        // Decode token type
        IDelegateRegistry.DelegationType delegationType = RegistryHashes.decodeType(bytes32(registryHash));
        // Fetch underlying contract and rights from registry
        bytes32 underlyingRights = IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.rights)));
        _withdrawByType(recipient, registryLocation, delegateTokenId, bytes32(registryHash), delegateTokenHolder, delegationType, underlyingContract, underlyingRights);
    }

    function _withdrawByType(
        address recipient,
        bytes32 registryLocation,
        uint256 delegateTokenId,
        bytes32 registryHash,
        address delegateTokenHolder,
        IDelegateRegistry.DelegationType delegationType,
        address underlyingContract,
        bytes32 underlyingRights
    ) internal {
        if (delegationType == IDelegateRegistry.DelegationType.ERC721) {
            uint256 erc721UnderlyingTokenId =
                uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.tokenId))));
            if (
                registryHash
                    != IDelegateRegistry(delegateRegistry).delegateERC721(delegateTokenHolder, underlyingContract, erc721UnderlyingTokenId, underlyingRights, false)
            ) revert HashMismatch();
            _principalTokenBurn(delegateTokenId);
            IERC721(underlyingContract).transferFrom(address(this), recipient, erc721UnderlyingTokenId);
        } else if (delegationType == IDelegateRegistry.DelegationType.ERC20) {
            // Load and then delete delegatedAmount
            uint256 erc20DelegatedAmount = delegateTokenInfo[delegateTokenId][Constants.UNDERLYING_AMOUNT_POSITION];
            delete delegateTokenInfo[delegateTokenId][Constants.UNDERLYING_AMOUNT_POSITION];
            // Calculate decrementedAmount, reading directly from registry storage
            unchecked {
                uint256 erc20DecrementedAmount = uint256(
                    IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.amount)))
                ) - erc20DelegatedAmount;
                // Update registry, reverts if returned hashes aren't correct
                if (
                    registryHash
                        != (IDelegateRegistry(delegateRegistry).delegateERC20(delegateTokenHolder, underlyingContract, erc20DecrementedAmount, underlyingRights, true))
                ) revert HashMismatch();
            } // Reasonable to expect this block not to underflow
            _principalTokenBurn(delegateTokenId);
            SafeERC20.safeTransfer(IERC20(underlyingContract), recipient, erc20DelegatedAmount);
        } else if (delegationType == IDelegateRegistry.DelegationType.ERC1155) {
            // Load and then delete delegatedAmount
            uint256 erc1155DelegatedAmount = delegateTokenInfo[delegateTokenId][Constants.UNDERLYING_AMOUNT_POSITION];
            delete delegateTokenInfo[delegateTokenId][Constants.UNDERLYING_AMOUNT_POSITION];
            // Load tokenId from registry
            uint256 erc11551UnderlyingTokenId =
                uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.tokenId))));
            // Calculate decrementedAmount, reading directly from registry storage
            unchecked {
                uint256 erc1155DecrementedAmount = uint256(
                    IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.amount)))
                ) - erc1155DelegatedAmount;
                // Update registry, reverts if returned hashes aren't correct
                if (
                    registryHash
                        != IDelegateRegistry(delegateRegistry).delegateERC1155(
                            delegateTokenHolder, underlyingContract, erc11551UnderlyingTokenId, erc1155DecrementedAmount, underlyingRights, true
                        )
                ) revert HashMismatch();
            } // Reasonable to expect this not to underflow
            _principalTokenBurn(delegateTokenId);
            IERC1155(underlyingContract).safeTransferFrom(address(this), recipient, erc11551UnderlyingTokenId, erc1155DelegatedAmount, "");
        }
    }

    /// @inheritdoc IDelegateToken
    function flashloan(
        address owner,
        address receiver,
        IDelegateRegistry.DelegationType delegationType,
        address underlyingContract,
        uint256 underlyingTokenId,
        bytes calldata data
    ) external payable nonReentrant {
        if (msg.sender != owner && !isApprovedForAll(owner, msg.sender)) revert InvalidFlashloan();
        // We now use owner for the checkDelegate calls since this has been verified as a valid operator or owner == msg.sender
        if (delegationType == IDelegateRegistry.DelegationType.ERC721) {
            _flashloanERC721(owner, receiver, underlyingContract, underlyingTokenId, data);
        } else if (delegationType == IDelegateRegistry.DelegationType.ERC20) {
            _flashloanERC20(owner, receiver, underlyingContract, data);
        } else if (delegationType == IDelegateRegistry.DelegationType.ERC1155) {
            _flashloanERC1155(owner, receiver, underlyingContract, underlyingTokenId, data);
        } else {
            revert InvalidTokenType(delegationType);
        }
    }

    /// @dev helper function for flashloan of ERC721 type
    function _flashloanERC721(address owner, address receiver, address underlyingContract, uint256 underlyingTokenId, bytes calldata data) internal {
        // We touch registry directly to check for active delegation of the respective hash, as bubbling up to contract and all delegations is not required
        if (
            _loadRegistryFrom(uint256(RegistryHashes.erc721Hash(address(this), "", owner, underlyingTokenId, underlyingContract))) == address(this)
                || _loadRegistryFrom(uint256(RegistryHashes.erc721Hash(address(this), "flashloan", owner, underlyingTokenId, underlyingContract))) == address(this)
        ) {
            IERC721(underlyingContract).transferFrom(address(this), receiver, underlyingTokenId);
            if (
                IDelegateFlashloan(receiver).onFlashloan{value: msg.value}(
                    msg.sender, IDelegateRegistry.DelegationType.ERC721, underlyingContract, underlyingTokenId, 1, data
                ) != IDelegateFlashloan.onFlashloan.selector
            ) {
                revert InvalidFlashloan();
            }
            if (IERC721(underlyingContract).ownerOf(underlyingTokenId) != address(this)) revert InvalidFlashloan();
        } else {
            revert InvalidFlashloan();
        }
    }

    /// @dev helper function for flashloan of ERC20 type
    function _flashloanERC20(address owner, address receiver, address underlyingContract, bytes calldata data) internal {
        // We sum the delegation amounts for "flashloan" and "" rights since liquid delegate doesn't allow tokens to be used for more than one rights type at a time
        uint256 flashAmount = _loadRegistryAmount(uint256(RegistryHashes.erc20Hash(address(this), "flashloan", owner, underlyingContract)))
            + _loadRegistryAmount(uint256(RegistryHashes.erc20Hash(address(this), "", owner, underlyingContract)));
        uint256 returnBalance = IERC20(underlyingContract).balanceOf(address(this));
        SafeERC20.safeTransfer(IERC20(underlyingContract), receiver, flashAmount);
        if (
            IDelegateFlashloan(receiver).onFlashloan{value: msg.value}(msg.sender, IDelegateRegistry.DelegationType.ERC20, underlyingContract, 1, flashAmount, data)
                != IDelegateFlashloan.onFlashloan.selector
        ) {
            revert InvalidFlashloan();
        }
        if (IERC20(underlyingContract).balanceOf(address(this)) != returnBalance) revert InvalidFlashloan();
    }

    /// @dev helper function for flashloan of ERC1155 type
    function _flashloanERC1155(address owner, address receiver, address underlyingContract, uint256 underlyingTokenId, bytes calldata data) internal {
        uint256 flashAmount = _loadRegistryAmount(uint256(RegistryHashes.erc1155Hash(address(this), "flashloan", owner, underlyingTokenId, underlyingContract)))
            + _loadRegistryAmount(uint256(RegistryHashes.erc1155Hash(address(this), "", owner, underlyingTokenId, underlyingContract)));
        uint256 returnBalance = IERC1155(underlyingContract).balanceOf(address(this), underlyingTokenId);
        IERC1155(underlyingContract).safeTransferFrom(address(this), receiver, underlyingTokenId, flashAmount, data);
        if (
            IDelegateFlashloan(receiver).onFlashloan{value: msg.value}(
                msg.sender, IDelegateRegistry.DelegationType.ERC1155, underlyingContract, underlyingTokenId, flashAmount, data
            ) != IDelegateFlashloan.onFlashloan.selector
        ) {
            revert InvalidFlashloan();
        }
        if (IERC1155(underlyingContract).balanceOf(address(this), underlyingTokenId) != returnBalance) revert InvalidFlashloan();
    }

    /// @inheritdoc IDelegateToken
    function getDelegateId(address creator, uint256 salt) public view returns (uint256 delegateTokenId) {
        delegateTokenId = uint256(keccak256(abi.encode(creator, salt)));
        _revertIfAlreadyExisted(delegateTokenId);
    }

    ////////// Storage Write/Read Helpers ////////

    function _writeApproved(uint256 id, address approved) internal {
        uint96 expiry = uint96(delegateTokenInfo[id][Constants.PACKED_INFO_POSITION]); // Extract expiry from the lower 96 bits
        delegateTokenInfo[id][Constants.PACKED_INFO_POSITION] = (uint256(uint160(approved)) << 96) | expiry; // Pack the new approved and old expiry back into info
    }

    function _writeExpiry(uint256 id, uint256 expiry) internal {
        if (expiry > Constants.MAX_EXPIRY) revert ExpiryTooLarge(expiry, Constants.MAX_EXPIRY);
        address approved = address(uint160(delegateTokenInfo[id][Constants.PACKED_INFO_POSITION] >> 96)); // Extract approved from the higher 160 bits
        delegateTokenInfo[id][Constants.PACKED_INFO_POSITION] = (uint256(uint160(approved)) << 96) | expiry; // Pack the old approved and new expiry back into info
    }

    function _writeRegistryHash(uint256 delegateTokenId, bytes32 registryHash) internal {
        delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION] = uint256(registryHash);
    }

    function _readApproved(uint256 id) internal view returns (address approved) {
        approved = address(uint160(delegateTokenInfo[id][Constants.PACKED_INFO_POSITION] >> 96)); // Extract approved from the higher 160 bits
    }

    function _readExpiry(uint256 id) internal view returns (uint256) {
        return uint96(delegateTokenInfo[id][Constants.PACKED_INFO_POSITION]); // Extract expiry from the lower 96 bits
    }

    function _readUnderlyingAmount(uint256 delegateTokenId) internal view returns (uint256) {
        return delegateTokenInfo[delegateTokenId][Constants.UNDERLYING_AMOUNT_POSITION];
    }

    ////////// Registry Helpers ////////

    function _loadRegistryHash(uint256 delegateTokenId) internal view returns (uint256) {
        return delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION];
    }

    function _loadDelegateTokenHolder(uint256 delegateTokenId) internal view returns (address delegateTokenHolder) {
        unchecked {
            return RegistryStorage.unpackAddress(
                IDelegateRegistry(delegateRegistry).readSlot(
                    bytes32(uint256(RegistryHashes.location(bytes32(_loadRegistryHash(delegateTokenId)))) + uint256(RegistryStorage.Positions.secondPacked))
                )
            );
        } // Reasonable to not expect this to overflow
    }

    function _loadDelegateTokenHolderAndUnderlyingContract(uint256 registryHash) internal view returns (address delegateTokenHolder, address underlyingContract) {
        unchecked {
            uint256 registryLocation = uint256(RegistryHashes.location(bytes32(registryHash)));
            //slither-disable-next-line unused-return
            (, delegateTokenHolder, underlyingContract) = RegistryStorage.unPackAddresses(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(registryLocation + uint256(RegistryStorage.Positions.firstPacked))),
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(registryLocation + uint256(RegistryStorage.Positions.secondPacked)))
            );
        }
    }

    function _loadRegistryFrom(uint256 registryHash) internal view returns (address) {
        unchecked {
            return RegistryStorage.unpackAddress(
                IDelegateRegistry(delegateRegistry).readSlot(
                    bytes32(uint256(RegistryHashes.location(bytes32(registryHash))) + uint256(RegistryStorage.Positions.firstPacked))
                )
            );
        }
    }

    function _loadRegistryAmount(uint256 registryHash) internal view returns (uint256) {
        unchecked {
            return uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(RegistryHashes.location(bytes32(registryHash))) + uint256(RegistryStorage.Positions.amount)))
            );
        }
    }

    function _loadRegistryRights(uint256 registryHash) internal view returns (bytes32) {
        unchecked {
            return
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(RegistryHashes.location(bytes32(registryHash))) + uint256(RegistryStorage.Positions.rights)));
        }
    }

    function _loadRegistryTokenId(uint256 registryHash) internal view returns (uint256) {
        unchecked {
            return uint256(
                IDelegateRegistry(delegateRegistry).readSlot(
                    bytes32(uint256(RegistryHashes.location(bytes32(registryHash))) + uint256(RegistryStorage.Positions.tokenId))
                )
            );
        }
    }

    function _calculateRegistryDecreasedAmount(uint256 registryHash, uint256 decreaseAmount) internal view returns (uint256) {
        unchecked {
            return uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(RegistryHashes.location(bytes32(registryHash))) + uint256(RegistryStorage.Positions.amount)))
            ) - decreaseAmount;
        }
    }

    function _calculateRegistryIncreasedAmount(uint256 registryHash, uint256 increaseAmount) internal view returns (uint256) {
        unchecked {
            return uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(RegistryHashes.location(bytes32(registryHash))) + uint256(RegistryStorage.Positions.amount)))
            ) + increaseAmount;
        }
    }

    ////////// Revert helpers ////////

    function _revertIfNotERC721Receiver(address from, address to, uint256 delegateTokenId, bytes memory data) internal {
        if (to.code.length != 0 && IERC721Receiver(to).onERC721Received(msg.sender, from, delegateTokenId, data) != IERC721Receiver.onERC721Received.selector) {
            revert NotERC721Receiver(to);
        }
    }

    function _revertIfAlreadyExisted(uint256 delegateTokenId) internal view {
        if (delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION] != Constants.ID_AVAILABLE) revert AlreadyExisted(delegateTokenId);
    }

    function _revertIfNotMinted(uint256 registryHash, uint256 delegateTokenId) internal pure {
        if (registryHash == Constants.ID_AVAILABLE || registryHash == Constants.ID_USED) revert NotMinted(delegateTokenId);
    }

    function _revertIfToIsZero(address to) internal pure {
        if (to == address(0)) revert ToIsZero();
    }

    function _revertIfNotApprovedOrOperator(address account, uint256 delegateTokenId) internal view {
        if (!(msg.sender == account || isApprovedForAll(account, msg.sender) || msg.sender == _readApproved(delegateTokenId))) {
            revert NotAuthorized(msg.sender, delegateTokenId);
        }
    }

    function _revertIfNotOperator(address account, uint256 delegateTokenId) internal view {
        if (!(msg.sender == account || isApprovedForAll(account, msg.sender))) {
            revert NotAuthorized(msg.sender, delegateTokenId);
        }
    }

    ////////// METADATA ////////

    function name() external pure returns (string memory) {
        return "Delegate Token";
    }

    function symbol() external pure returns (string memory) {
        return "DT";
    }

    /// @inheritdoc IDelegateToken
    function setBaseURI(string calldata uri) external onlyOwner {
        baseURI = uri;
    }

    /// @inheritdoc IDelegateToken
    function contractURI() external view returns (string memory) {
        return string.concat(baseURI, "contract");
    }

    function tokenURI(uint256 delegateTokenId) external view returns (string memory) {
        // Load delegation from registry
        bytes32[] memory registryHash = new bytes32[](1);
        registryHash[0] = bytes32(delegateTokenInfo[delegateTokenId][Constants.REGISTRY_HASH_POSITION]);
        IDelegateRegistry.Delegation[] memory delegation = IDelegateRegistry(delegateRegistry).getDelegationsFromHashes(registryHash);

        // Revert if invalid
        if (delegation[0].to == address(0)) revert NotMinted(delegateTokenId);

        // When the principal token is redeemed, the delegate token is burned. So we can query this with no try-catch
        address principalTokenOwner = PrincipalToken(principalToken).ownerOf(delegateTokenId);

        return _buildTokenURI(delegation[0].contract_, delegation[0].tokenId, _readExpiry(delegateTokenId), principalTokenOwner);
    }

    function _buildTokenURI(address tokenContract, uint256 delegateTokenId, uint256 expiry, address principalOwner) internal view returns (string memory) {
        string memory idstr = Strings.toString(delegateTokenId);

        string memory pownerstr = principalOwner == address(0) ? "N/A" : Strings.toHexString(principalOwner);
        //slither-disable-next-line timestamp
        string memory status = principalOwner == address(0) || expiry <= block.timestamp ? "Expired" : "Active";

        string memory firstPartOfMetadataString = string.concat(
            '{"name":"Delegate Token #"',
            idstr,
            '","description":"LiquidDelegate lets you escrow your token for a chosen timeperiod and receive a liquid NFT representing the associated delegation rights. This collection represents the tokenized delegation rights.","attributes":[{"trait_type":"Collection Address","value":"',
            Strings.toHexString(tokenContract),
            '"},{"trait_type":"Token ID","value":"',
            idstr,
            '"},{"trait_type":"Expires At","display_type":"date","value":',
            Strings.toString(expiry)
        );
        string memory secondPartOfMetadataString = string.concat(
            '},{"trait_type":"Principal Owner Address","value":"',
            pownerstr,
            '"},{"trait_type":"Delegate Status","value":"',
            status,
            '"}]',
            ',"image":"',
            baseURI,
            "rights/",
            idstr,
            '"}'
        );
        // Build via two substrings to avoid stack-too-deep
        string memory metadataString = string.concat(firstPartOfMetadataString, secondPartOfMetadataString);

        return string.concat("data:application/json;base64,", Base64.encode(bytes(metadataString)));
    }

    /// @dev See {ERC2981-_setDefaultRoyalty}.
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @dev See {ERC2981-_deleteDefaultRoyalty}.
    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }
}
