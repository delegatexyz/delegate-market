// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IDelegateToken, IDelegateRegistry} from "./interfaces/IDelegateToken.sol";
import {INFTFlashBorrower} from "./interfaces/INFTFlashBorrower.sol";
import {IERC1155} from "openzeppelin/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "openzeppelin/token/ERC1155/IERC1155Receiver.sol";
import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {PrincipalToken} from "./PrincipalToken.sol";
import {ERC2981} from "openzeppelin/token/common/ERC2981.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";

import {RegistryHashes} from "delegate-registry/src/libraries/RegistryHashes.sol";
import {RegistryStorage} from "delegate-registry/src/libraries/RegistryStorage.sol";
import {Base64} from "openzeppelin/utils/Base64.sol";
import {Strings} from "openzeppelin/utils/Strings.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";

contract DelegateToken is ReentrancyGuard, Ownable2Step, ERC2981, IDelegateToken {
    /*//////////////////////////////////////////////////////////////
    /                  Constants & Immutables                      /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDelegateToken
    bytes32 public constant flashLoanCallBackSuccess = bytes32(uint256(keccak256("INFTFlashBorrower.onFlashLoan")) - 1);

    /// @inheritdoc IDelegateToken
    address public immutable override delegateRegistry;

    /// @inheritdoc IDelegateToken
    address public immutable override principalToken;

    /// @inheritdoc IDelegateToken
    string public baseURI;

    /*//////////////////////////////////////////////////////////////
    /                            Storage                           /
    //////////////////////////////////////////////////////////////*/

    /// @dev delegateId, a hash of (tokenType, tokenContract, tokenId, tokenAmount, msg.sender, salt), points a unique id to the StoragePosition
    mapping(uint256 delegateTokenId => uint256[3] info) internal delegateTokenInfo;

    /// @dev Standardizes storage positions of delegateInfo mapping data
    enum StoragePositions {
        registryHash,
        packedInfo, // PACKED (address approved, uint96 expiry)
        delegatedAmount // Not used by 721 delegations
    }

    /// @dev Use this to syntactically store the max of the expiry
    uint256 internal constant MAX_EXPIRY = type(uint96).max;

    /// @dev Standardizes registryHash storage flags to prevent double-creation and griefing
    uint256 internal constant DELEGATE_TOKEN_ID_AVAILABLE = 0;
    uint256 internal constant DELEGATE_TOKEN_ID_USED = 1;

    /// @notice mapping for ERC721 balances
    mapping(address delegateTokenHolder => uint256 balance) internal balances;

    /// @notice approve for all mapping, cheaper to use uint256 rather than bool
    mapping(bytes32 approveAllHash => uint256 enabled) internal approvals;

    /// @dev Standardizes approvalAll flags
    uint256 internal constant APPROVE_ALL_DISABLED = 0;
    uint256 internal constant APPROVE_ALL_ENABLED = 1;

    /// @notice Standardizes rescind address
    address internal constant RESCIND_ADDRESS = address(1);

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
        super._transferOwnership(initialMetadataOwner); // Transfer ownership to initialMetadataOwner
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
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @inheritdoc IERC1155Receiver
    /// @dev return 0 if length is not equal to one since this contract only works with single erc1155 transfers
    function onERC1155BatchReceived(address, address, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata) external pure returns (bytes4) {
        if (ids.length == 1 && amounts.length == 1) return IERC1155Receiver.onERC1155BatchReceived.selector;
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
    /                 ERC721 Method Implementations                /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC721
    /// @dev must revert if delegateTokenHolder is zero address
    function balanceOf(address delegateTokenHolder) external view returns (uint256 balance) {
        if (delegateTokenHolder == address(0)) revert DelegateTokenHolderZero();
        balance = balances[delegateTokenHolder];
    }

    /// @inheritdoc IERC721
    /// @dev must revert if delegateTokenHolder is zero address
    function ownerOf(uint256 delegateTokenId) external view returns (address delegateTokenHolder) {
        delegateTokenHolder = _loadTokenHolder(RegistryHashes.location(bytes32(_loadRegistryHash(delegateTokenId))));
        if (delegateTokenHolder == address(0)) revert DelegateTokenHolderZero();
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 delegateTokenId, bytes memory data) external {
        transferFrom(from, to, delegateTokenId);
        if (to.code.length != 0 && IERC721Receiver(to).onERC721Received(msg.sender, from, delegateTokenId, data) != IERC721Receiver.onERC721Received.selector) {
            revert NotERC721Receiver(to);
        }
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 delegateTokenId) external {
        transferFrom(from, to, delegateTokenId);
        if (to.code.length != 0 && IERC721Receiver(to).onERC721Received(msg.sender, from, delegateTokenId, "") != IERC721Receiver.onERC721Received.selector) {
            revert NotERC721Receiver(to);
        }
    }

    /// @inheritdoc IERC721
    function approve(address spender, uint256 delegateTokenId) external {
        address delegateTokenHolder = _loadTokenHolder(RegistryHashes.location(bytes32(_loadRegistryHash(delegateTokenId))));
        // Revert if the caller is not the owner and not approved all by the owner
        if (msg.sender != delegateTokenHolder && approvals[keccak256(abi.encode(delegateTokenHolder, msg.sender))] == APPROVE_ALL_DISABLED) {
            revert NotAuthorized(msg.sender, delegateTokenId);
        }
        _writeApproved(delegateTokenId, spender);
        emit Approval(delegateTokenHolder, spender, delegateTokenId);
    }

    /// @inheritdoc IERC721
    function setApprovalForAll(address operator, bool approved) external {
        approvals[keccak256(abi.encode(msg.sender, operator))] = approved == true ? APPROVE_ALL_ENABLED : APPROVE_ALL_DISABLED;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @inheritdoc IERC721
    function getApproved(uint256 delegateTokenId) public view returns (address) {
        _revertIfNotMinted(_loadRegistryHash(delegateTokenId), delegateTokenId);
        return _readApproved(delegateTokenId);
    }

    /// @inheritdoc IERC721
    function isApprovedForAll(address owner_, address operator) public view returns (bool) {
        return approvals[keccak256(abi.encode(owner_, operator))] == APPROVE_ALL_ENABLED ? true : false;
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
        if (to == address(0)) revert ToIsZero();
        uint256 registryHash = _loadRegistryHash(delegateTokenId);
        _revertIfNotMinted(registryHash, delegateTokenId);
        bytes32 registryLocation = RegistryHashes.location(bytes32(registryHash));
        (address delegateTokenHolder, address underlyingContract) = _loadTokenHolderAndUnderlyingContract(registryLocation);
        if (from != delegateTokenHolder) revert FromNotDelegateTokenHolder(from, delegateTokenHolder);
        // We can use from here instead of delegateTokenHolder since we've just verified that from == delegateTokenHolder
        if (!(msg.sender == from || isApprovedForAll(from, msg.sender) || msg.sender == _readApproved(delegateTokenId))) {
            revert NotAuthorized(msg.sender, delegateTokenId);
        }
        // Update balances
        balances[from]--;
        balances[to]++;
        // Reset approved
        _writeApproved(delegateTokenId, address(0));
        emit Transfer(from, to, delegateTokenId);
        // Decode delegation type from hash
        IDelegateRegistry.DelegationType underlyingType = RegistryHashes.decodeType(bytes32(registryHash));
        bytes32 underlyingRights = IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.rights)));
        _transferByType(delegateTokenId, registryLocation, from, bytes32(registryHash), to, underlyingType, underlyingContract, underlyingRights);
    }

    function _transferByType(
        uint256 delegateTokenId,
        bytes32 registryLocation,
        address from,
        bytes32 delegationHash,
        address to,
        IDelegateRegistry.DelegationType underlyingType,
        address underlyingContract,
        bytes32 underlyingRights
    ) internal {
        bytes32 newDelegationHash = 0;
        if (underlyingType == IDelegateRegistry.DelegationType.ERC721) {
            // Load token id from delegate registry
            uint256 erc721UnderlyingId =
                uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.tokenId))));
            // Update hash, using deterministic registry hash calculation
            newDelegationHash = RegistryHashes.erc721Hash(address(this), underlyingRights, to, erc721UnderlyingId, underlyingContract);
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(newDelegationHash);
            // Update registry, reverts if returned hashes aren't correct
            if (
                IDelegateRegistry(delegateRegistry).delegateERC721(from, underlyingContract, erc721UnderlyingId, underlyingRights, false) != delegationHash
                    || IDelegateRegistry(delegateRegistry).delegateERC721(to, underlyingContract, erc721UnderlyingId, underlyingRights, true) != newDelegationHash
            ) revert HashMisMatch();
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC20) {
            // Update hash, using deterministic registry hash calculation
            newDelegationHash = RegistryHashes.erc20Hash(address(this), underlyingRights, to, underlyingContract);
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(newDelegationHash);
            // Fetch current amount
            uint256 erc20Amount = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
            // Calculate fromAmount and toAmount, reading directly from registry storage
            uint256 erc20FromAmount =
                uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.amount)))) - erc20Amount;
            // Update registry
            if (
                delegationHash
                    != (
                        erc20FromAmount == 0
                            ? IDelegateRegistry(delegateRegistry).delegateERC20(from, underlyingContract, erc20FromAmount, underlyingRights, false)
                            : IDelegateRegistry(delegateRegistry).delegateERC20(from, underlyingContract, erc20FromAmount, underlyingRights, true)
                    )
            ) revert HashMisMatch();
            // Calculate toAmount
            uint256 erc20ToAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(RegistryHashes.location(newDelegationHash)) + uint256(RegistryStorage.Positions.amount)))
            ) + erc20Amount;
            // Update registry, reverts if returned hashes aren't correct
            if (newDelegationHash != IDelegateRegistry(delegateRegistry).delegateERC20(to, underlyingContract, erc20ToAmount, underlyingRights, true)) {
                revert HashMisMatch();
            }
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC1155) {
            // Load tokenId from delegate registry
            uint256 erc1155UnderlyingId =
                uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.tokenId))));
            // Update hash, using deterministic registry hash calculation
            newDelegationHash = RegistryHashes.erc1155Hash(address(this), underlyingRights, to, erc1155UnderlyingId, underlyingContract);
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(newDelegationHash);
            // Fetch current amount
            uint256 erc1155Amount = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
            // Calculate fromAmount and toAmount, reading directly from registry storage
            uint256 erc1155FromAmount =
                uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.amount)))) - erc1155Amount;
            // Update registry
            if (
                delegationHash
                    != (
                        erc1155FromAmount == 0
                            ? IDelegateRegistry(delegateRegistry).delegateERC1155(from, underlyingContract, erc1155UnderlyingId, erc1155FromAmount, underlyingRights, false)
                            : IDelegateRegistry(delegateRegistry).delegateERC1155(from, underlyingContract, erc1155UnderlyingId, erc1155FromAmount, underlyingRights, true)
                    )
            ) revert HashMisMatch();
            // Calculate to amount
            uint256 erc1155ToAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(RegistryHashes.location(newDelegationHash)) + uint256(RegistryStorage.Positions.amount)))
            ) + erc1155Amount;
            // Update registry
            if (
                newDelegationHash
                    != IDelegateRegistry(delegateRegistry).delegateERC1155(to, underlyingContract, erc1155UnderlyingId, erc1155ToAmount, underlyingRights, true)
            ) revert HashMisMatch();
        }
    }

    /*//////////////////////////////////////////////////////////////
    /                EXTENDED ERC721 METHODS                       /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDelegateToken
    function isApprovedOrOwner(address spender, uint256 delegateTokenId) public view returns (bool) {
        (bool approvedOrOwner, address delegateTokenHolder) = _isApprovedOrOwner(spender, delegateTokenId);
        if (delegateTokenHolder == address(0)) revert NotMinted(delegateTokenId);
        return approvedOrOwner;
    }

    /// @notice Adapted from solmate's [ERC721](https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol)
    function _isApprovedOrOwner(address spender, uint256 delegateTokenId) internal view returns (bool approvedOrOwner, address delegateTokenHolder) {
        delegateTokenHolder = _loadTokenHolder(RegistryHashes.location(bytes32(_loadRegistryHash(delegateTokenId))));
        approvedOrOwner = spender == delegateTokenHolder || isApprovedForAll(delegateTokenHolder, spender) || getApproved(delegateTokenId) == spender;
    }

    /*//////////////////////////////////////////////////////////////
    /            LIQUID DELEGATE TOKEN METHODS                     /
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDelegateToken
    function getDelegateInfo(uint256 delegateTokenId) external view returns (DelegateInfo memory delegateInfo) {
        // Load delegation from registry
        bytes32[] memory delegationHash = new bytes32[](1);
        delegationHash[0] = bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]);
        IDelegateRegistry.Delegation[] memory delegation = IDelegateRegistry(delegateRegistry).getDelegationsFromHashes(delegationHash);
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
        else delegateInfo.amount = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
    }

    /// @inheritdoc IDelegateToken
    function create(DelegateInfo calldata delegateInfo, uint256 salt) external nonReentrant returns (uint256 delegateTokenId) {
        // Pulls tokens in before minting, reverts if invalid token type, parses underlyingAmount and underlyingTokenId
        (uint256 underlyingAmount, uint256 underlyingTokenId) =
            _pullAndParse(delegateInfo.tokenType, delegateInfo.amount, delegateInfo.tokenContract, delegateInfo.tokenId);
        // Check expiry
        if (delegateInfo.expiry < block.timestamp) revert ExpiryTimeNotInFuture(delegateInfo.expiry, block.timestamp);
        if (delegateInfo.expiry > MAX_EXPIRY) revert ExpiryTooLarge(delegateInfo.expiry, MAX_EXPIRY);
        // Revert if to is the zero address
        if (delegateInfo.delegateHolder == address(0)) revert ToIsZero();
        // Revert if token has already existed / been minted
        delegateTokenId = getDelegateId(msg.sender, salt);
        if (delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] != DELEGATE_TOKEN_ID_AVAILABLE) revert AlreadyExisted(delegateTokenId);
        // Increment erc721 balance
        balances[delegateInfo.delegateHolder]++;
        // Write expiry
        _writeExpiry(delegateTokenId, delegateInfo.expiry);
        // Emit transfer event
        emit Transfer(address(0), delegateInfo.delegateHolder, delegateTokenId);
        // Update amount, registry data, and store registry hash
        _createByType(
            delegateInfo.tokenType, delegateTokenId, delegateInfo.delegateHolder, underlyingAmount, delegateInfo.tokenContract, delegateInfo.rights, underlyingTokenId
        );
        // Mint principal token
        PrincipalToken(principalToken).mint(delegateInfo.principalHolder, delegateTokenId);
    }

    function _pullAndParse(IDelegateRegistry.DelegationType underlyingType, uint256 underlyingAmount, address underlyingContract, uint256 underlyingTokenId)
        internal
        returns (uint256 parsedUnderlyingAmount, uint256 parsedUnderlyingTokenId)
    {
        if (underlyingType == IDelegateRegistry.DelegationType.ERC721) {
            IDelegateToken(underlyingContract).transferFrom(msg.sender, address(this), underlyingTokenId);
            return (1, underlyingTokenId);
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC20) {
            // Revert if underlyingAmount is zero
            if (underlyingAmount == 0) revert WrongAmountForType(IDelegateRegistry.DelegationType.ERC20, underlyingAmount);
            SafeERC20.safeTransferFrom(IERC20(underlyingContract), msg.sender, address(this), underlyingAmount);
            return (underlyingAmount, 0);
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC1155) {
            // Revert if underlyingAmount is zero
            if (underlyingAmount == 0) revert WrongAmountForType(IDelegateRegistry.DelegationType.ERC1155, underlyingAmount);
            IERC1155(underlyingContract).safeTransferFrom(msg.sender, address(this), underlyingTokenId, underlyingAmount, "");
            return (underlyingAmount, underlyingTokenId);
        } else {
            revert InvalidTokenType(underlyingType);
        }
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
        bytes32 newDelegationHash = 0;
        if (underlyingType == IDelegateRegistry.DelegationType.ERC721) {
            // Store hash, computing registry hash deterministically
            newDelegationHash = RegistryHashes.erc721Hash(address(this), underlyingRights, delegateTokenTo, underlyingTokenId, underlyingContract);
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(newDelegationHash);
            // Update Registry
            if (newDelegationHash != IDelegateRegistry(delegateRegistry).delegateERC721(delegateTokenTo, underlyingContract, underlyingTokenId, underlyingRights, true)) {
                revert HashMisMatch();
            }
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC20) {
            // Store amount
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)] = underlyingAmount;
            // Store hash, computing registry hash deterministically
            newDelegationHash = RegistryHashes.erc20Hash(address(this), underlyingRights, delegateTokenTo, underlyingContract);
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(newDelegationHash);
            // Calculate increasedAmount, reading directly from registry storage
            bytes32 newRegistryLocation = RegistryHashes.location(newDelegationHash);
            uint256 erc20IncreasedAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(newRegistryLocation) + uint256(RegistryStorage.Positions.amount)))
            ) + underlyingAmount;
            // Update registry, reverts if returned hashes aren't correct
            if (newDelegationHash != IDelegateRegistry(delegateRegistry).delegateERC20(delegateTokenTo, underlyingContract, erc20IncreasedAmount, underlyingRights, true))
            {
                revert HashMisMatch();
            }
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC1155) {
            // Store amount
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)] = underlyingAmount;
            // Store hash, computing registry hash deterministically
            newDelegationHash = RegistryHashes.erc1155Hash(address(this), underlyingRights, delegateTokenTo, underlyingTokenId, underlyingContract);
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(newDelegationHash);
            // Calculate toAmount, reading directly from registry storage
            bytes32 newRegistryLocation = RegistryHashes.location(newDelegationHash);
            uint256 erc1155IncreasedAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(newRegistryLocation) + uint256(RegistryStorage.Positions.amount)))
            ) + underlyingAmount;
            // Update registry, reverts if returned hashes aren't correct
            if (
                newDelegationHash
                    != IDelegateRegistry(delegateRegistry).delegateERC1155(
                        delegateTokenTo, underlyingContract, underlyingTokenId, erc1155IncreasedAmount, underlyingRights, true
                    )
            ) revert HashMisMatch();
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
        if (_readExpiry(delegateTokenId) < block.timestamp) {
            if (from == address(0)) revert FromIsZero();
            _writeApproved(delegateTokenId, msg.sender); // This should be fine as the approve for the token gets delete in transferFrom
            transferFrom(from, RESCIND_ADDRESS, delegateTokenId);
        } else {
            transferFrom(from, RESCIND_ADDRESS, delegateTokenId);
        }
    }

    /// @inheritdoc IDelegateToken
    function withdraw(address recipient, uint256 delegateTokenId) external nonReentrant {
        // Load registryHash and check nft is valid
        uint256 registryHash = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)];
        _revertIfNotMinted(registryHash, delegateTokenId);
        // Set registry hash to delegate token id used
        delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = DELEGATE_TOKEN_ID_USED;
        // Load delegateTokenHolder from registry
        bytes32 registryLocation = RegistryHashes.location(bytes32(registryHash));
        (address delegateTokenHolder, address underlyingContract) = _loadTokenHolderAndUnderlyingContract(registryLocation);
        // If it still exists the only valid way to withdraw is the delegation having expired or delegateTokenHolder rescinded to this contract
        // Also allows withdraw if the caller is approved or holder of delegate token
        if (
            block.timestamp < _readExpiry(delegateTokenId) && delegateTokenHolder != RESCIND_ADDRESS && delegateTokenHolder != msg.sender
                && msg.sender != _readApproved(delegateTokenId)
        ) {
            revert WithdrawNotAvailable(delegateTokenId, _readExpiry(delegateTokenId), block.timestamp);
        }
        // Decrement balance of holder
        balances[delegateTokenHolder]--;
        // Delete approved and expiry
        delete delegateTokenInfo[delegateTokenId][uint256(StoragePositions.packedInfo)];
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
        bytes32 delegationHash,
        address delegateTokenHolder,
        IDelegateRegistry.DelegationType delegationType,
        address underlyingContract,
        bytes32 underlyingRights
    ) internal {
        if (delegationType == IDelegateRegistry.DelegationType.ERC721) {
            uint256 erc721UnderlyingTokenId =
                uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.tokenId))));
            if (
                delegationHash
                    != IDelegateRegistry(delegateRegistry).delegateERC721(delegateTokenHolder, underlyingContract, erc721UnderlyingTokenId, underlyingRights, false)
            ) revert HashMisMatch();
            PrincipalToken(principalToken).burnIfAuthorized(msg.sender, delegateTokenId);
            IDelegateToken(underlyingContract).transferFrom(address(this), recipient, erc721UnderlyingTokenId);
        } else if (delegationType == IDelegateRegistry.DelegationType.ERC20) {
            // Load and then delete delegatedAmount
            uint256 erc20DelegatedAmount = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
            delete delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
            // Calculate decrementedAmount, reading directly from registry storage
            uint256 erc20DecrementedAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.amount)))
            ) - erc20DelegatedAmount;
            // Update registry, reverts if returned hashes aren't correct
            if (
                delegationHash
                    != (
                        erc20DecrementedAmount == 0
                            ? IDelegateRegistry(delegateRegistry).delegateERC20(delegateTokenHolder, underlyingContract, erc20DecrementedAmount, underlyingRights, false)
                            : IDelegateRegistry(delegateRegistry).delegateERC20(delegateTokenHolder, underlyingContract, erc20DecrementedAmount, underlyingRights, true)
                    )
            ) revert HashMisMatch();
            PrincipalToken(principalToken).burnIfAuthorized(msg.sender, delegateTokenId);
            SafeERC20.safeTransfer(IERC20(underlyingContract), recipient, erc20DelegatedAmount);
        } else if (delegationType == IDelegateRegistry.DelegationType.ERC1155) {
            // Load and then delete delegatedAmount
            uint256 erc1155DelegatedAmount = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
            delete delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
            // Load tokenId from registry
            uint256 erc11551UnderlyingTokenId =
                uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.tokenId))));
            // Calculate decrementedAmount, reading directly from registry storage
            uint256 erc1155DecrementedAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.amount)))
            ) - erc1155DelegatedAmount;
            // Update registry, reverts if returned hashes aren't correct
            if (
                delegationHash
                    != (
                        erc1155DecrementedAmount == 0
                            ? IDelegateRegistry(delegateRegistry).delegateERC1155(
                                delegateTokenHolder, underlyingContract, erc11551UnderlyingTokenId, erc1155DecrementedAmount, underlyingRights, false
                            )
                            : IDelegateRegistry(delegateRegistry).delegateERC1155(
                                delegateTokenHolder, underlyingContract, erc11551UnderlyingTokenId, erc1155DecrementedAmount, underlyingRights, true
                            )
                    )
            ) revert HashMisMatch();
            PrincipalToken(principalToken).burnIfAuthorized(msg.sender, delegateTokenId);
            IERC1155(underlyingContract).safeTransferFrom(address(this), recipient, erc11551UnderlyingTokenId, erc1155DelegatedAmount, "");
        }
    }

    /// @inheritdoc IDelegateToken
    /// @dev TODO: implement ERC20 and ERC1155 versions of this
    function flashLoan(address receiver, uint256 delegateId, bytes calldata data) external payable nonReentrant {
        if (!isApprovedOrOwner(msg.sender, delegateId)) revert NotAuthorized(msg.sender, delegateId);
        bytes32[] memory delegationHash = new bytes32[](1);
        delegationHash[0] = bytes32(delegateTokenInfo[delegateId][uint256(StoragePositions.registryHash)]);
        IDelegateRegistry.Delegation[] memory delegation = IDelegateRegistry(delegateRegistry).getDelegationsFromHashes(delegationHash);
        if (!(delegation[0].type_ == IDelegateRegistry.DelegationType.ERC721 && delegation[0].rights == "")) revert InvalidFlashloan();
        IDelegateToken(delegation[0].contract_).transferFrom(address(this), receiver, delegation[0].tokenId);

        if (INFTFlashBorrower(receiver).onFlashLoan{value: msg.value}(msg.sender, delegation[0].contract_, delegation[0].tokenId, data) != flashLoanCallBackSuccess) {
            revert InvalidFlashloan();
        }

        // Safer and cheaper to expect the token to have been returned rather than pulling it with `transferFrom`.
        if (IDelegateToken(delegation[0].contract_).ownerOf(delegation[0].tokenId) != address(this)) revert InvalidFlashloan();
    }

    /// @dev TODO: revert if delegate id has been used
    function getDelegateId(address creator, uint256 salt) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(creator, salt)));
    }

    ////////// Storage Write/Read Helpers ////////

    function _writeApproved(uint256 id, address approved) internal {
        uint96 expiry = uint96(delegateTokenInfo[id][uint256(StoragePositions.packedInfo)]); // Extract expiry from the lower 96 bits
        delegateTokenInfo[id][uint256(StoragePositions.packedInfo)] = (uint256(uint160(approved)) << 96) | expiry; // Pack the new approved and old expiry back into info
    }

    function _writeExpiry(uint256 id, uint256 expiry) internal {
        if (expiry > MAX_EXPIRY) revert ExpiryTooLarge(expiry, MAX_EXPIRY);
        address approved = address(uint160(delegateTokenInfo[id][uint256(StoragePositions.packedInfo)] >> 96)); // Extract approved from the higher 160 bits
        delegateTokenInfo[id][uint256(StoragePositions.packedInfo)] = (uint256(uint160(approved)) << 96) | expiry; // Pack the old approved and new expiry back into info
    }

    function _readApproved(uint256 id) internal view returns (address approved) {
        approved = address(uint160(delegateTokenInfo[id][uint256(StoragePositions.packedInfo)] >> 96)); // Extract approved from the higher 160 bits
    }

    function _readExpiry(uint256 id) internal view returns (uint256 expiry) {
        expiry = uint96(delegateTokenInfo[id][uint256(StoragePositions.packedInfo)]); // Extract expiry from the lower 96 bits
    }

    ////////// Other helpers ////////

    function _revertIfNotMinted(uint256 registryHash, uint256 delegateTokenId) internal pure {
        if (registryHash == DELEGATE_TOKEN_ID_AVAILABLE || registryHash == DELEGATE_TOKEN_ID_USED) revert NotMinted(delegateTokenId);
    }

    function _loadRegistryHash(uint256 delegateTokenId) internal view returns (uint256) {
        return delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)];
    }

    function _loadTokenHolder(bytes32 registryLocation) internal view returns (address delegateTokenHolder) {
        return RegistryStorage.unpackAddress(
            IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.secondPacked)))
        );
    }

    function _loadTokenHolderAndUnderlyingContract(bytes32 registryLocation) internal view returns (address delegateTokenHolder, address underlyingContract) {
        (, delegateTokenHolder, underlyingContract) = RegistryStorage.unPackAddresses(
            IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.firstPacked))),
            IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(RegistryStorage.Positions.secondPacked)))
        );
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
        bytes32[] memory delegationHash = new bytes32[](1);
        delegationHash[0] = bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]);
        IDelegateRegistry.Delegation[] memory delegation = IDelegateRegistry(delegateRegistry).getDelegationsFromHashes(delegationHash);

        // Revert if invalid
        if (delegation[0].to == address(0)) revert NotMinted(delegateTokenId);

        // When the principal token is redeemed, the delegate token is burned. So we can query this with no try-catch
        address principalTokenOwner = PrincipalToken(principalToken).ownerOf(delegateTokenId);

        return _buildTokenURI(delegation[0].contract_, delegation[0].tokenId, _readExpiry(delegateTokenId), principalTokenOwner);
    }

    function _buildTokenURI(address tokenContract, uint256 delegateTokenId, uint256 expiry, address principalOwner) internal view returns (string memory) {
        string memory idstr = Strings.toString(delegateTokenId);

        string memory pownerstr = principalOwner == address(0) ? "N/A" : Strings.toHexString(principalOwner);
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
