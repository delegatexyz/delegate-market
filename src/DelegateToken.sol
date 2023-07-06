// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IDelegateToken, IDelegateRegistry} from "./interfaces/IDelegateToken.sol";
import {INFTFlashBorrower} from "./interfaces/INFTFlashBorrower.sol";
import {IERC721, ERC165, ERC721TokenReceiver, IERC1155, ERC1155TokenReceiver} from "./interfaces/ITokenInterfaces.sol";

import {PrincipalToken} from "./PrincipalToken.sol";
import {ERC2981} from "openzeppelin-contracts/contracts/token/common/ERC2981.sol";

import {RegistryHashes} from "delegate-registry/src/libraries/RegistryHashes.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";

/**
 * delegateId needs to be deterministic. hash(tokenType, contractAddress, tokenId, amount, creatorAddress, salt)
 * that points to the data being stored
 * and we also prevent delegateId reuse with a simple boolean set membership lookup
 */

contract DelegateToken is IDelegateToken, ERC165, ERC2981, Owned {
    /*//////////////////////////////////////////////////////////////
    /                  Constants & Immutables                      /
    //////////////////////////////////////////////////////////////*/

    /// @notice The value flash borrowers need to return from `onFlashLoan` for the call to be successful.
    bytes32 public constant FLASHLOAN_CALLBACK_SUCCESS = bytes32(uint256(keccak256("INFTFlashBorrower.onFlashLoan")) - 1);

    /// @notice The v2 delegate registry
    address public immutable override delegateRegistry;

    /// @notice The principal token deployed in tandem with this delegate token
    address public immutable override principalToken;

    /// @notice Image metadata location, but attributes are stored onchain
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
    uint96 internal constant MAX_EXPIRY = type(uint96).max;

    /// @dev Standardizes packedInfo storage flags to prevent double-creation and griefing
    uint256 internal constant DELEGATE_TOKEN_ID_AVAILABLE = 0;
    uint256 internal constant DELEGATE_TOKEN_ID_USED = 1;

    /// @notice mapping for ERC721 balances
    mapping(address delegateTokenHolder => uint256 balance) internal balances;

    /// @notice approve for all mapping
    mapping(bytes32 approveAllHash => bool enabled) internal approvals;

    /*//////////////////////////////////////////////////////////////
    /                      Constructor                             /
    //////////////////////////////////////////////////////////////*/

    constructor(address delegateRegistry_, address principalToken_, string memory baseURI_, address initialMetadataOwner) Owned(initialMetadataOwner) {
        if (delegateRegistry_ == address(0)) revert DelegateRegistryZero();
        delegateRegistry = delegateRegistry_;
        if (principalToken_ == address(0)) revert PrincipalTokenZero();
        principalToken = principalToken_;
        baseURI = baseURI_;
    }

    /*//////////////////////////////////////////////////////////////
    /                    Supported Interfaces                      /
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public pure override(ERC2981, ERC165) returns (bool) {
        return interfaceId == 0x2a55205a // ERC165 Interface ID for ERC2981
            || interfaceId == 0x01ffc9a7 // ERC165 Interface ID for ERC165
            || interfaceId == 0x80ac58cd // ERC165 Interface ID for ERC721
            || interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /*//////////////////////////////////////////////////////////////
    /                    Token Receiver methods                    /
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC721 onERC721Received function
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }

    /// @notice ERC1155 onERC1155Received function
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return ERC1155TokenReceiver.onERC1155Received.selector;
    }

    /// @notice ERC1155 onERC1155BatchReceived function
    /// @dev return 0 if length is not equal to one since this contract only works with single erc1155 transfers
    function onERC1155BatchReceived(address, address, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata) external pure returns (bytes4) {
        if (ids.length == 1 && amounts.length == 1) return ERC1155TokenReceiver.onERC1155BatchReceived.selector;
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
    /                 ERC721 Method Implementations                /
    //////////////////////////////////////////////////////////////*/

    /// @notice ERC721 balanceOf function
    /// @dev must revert if delegateTokenHolder is zero address
    /// @param delegateTokenHolder is the address to query
    /// @return balance of all the delegateTokens assigned to the holder
    function balanceOf(address delegateTokenHolder) external view returns (uint256 balance) {
        if (delegateTokenHolder == address(0)) revert DelegateTokenHolderZero();
        balance = balances[delegateTokenHolder];
    }

    /// @notice ERC721 ownerOf function
    /// @dev must revert if delegateTokenHolder is zero address
    /// @param delegateTokenId is the delegateToken identifier
    /// @return delegateTokenHolder that is assigned to the delegateTokenId
    function ownerOf(uint256 delegateTokenId) external view returns (address delegateTokenHolder) {
        bytes32 registryLocation = RegistryHashes._computeLocation(bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]));
        delegateTokenHolder =
            address(uint160(uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.to))))));
        if (delegateTokenHolder == address(0)) revert DelegateTokenHolderZero();
    }

    /// @notice ERC721 safeTransferFrom function
    function safeTransferFrom(address from, address to, uint256 delegateTokenId, bytes memory data) public {
        transferFrom(from, to, delegateTokenId);
        if (to.code.length != 0 && ERC721TokenReceiver(to).onERC721Received(msg.sender, from, delegateTokenId, data) != ERC721TokenReceiver.onERC721Received.selector) {
            revert NotERC721Receiver(to);
        }
    }

    /// @notice ERC721 safeTransferFrom function
    function safeTransferFrom(address from, address to, uint256 delegateTokenId) external {
        safeTransferFrom(from, to, delegateTokenId, "");
    }

    /// @notice ERC721 approve function
    function approve(address spender, uint256 delegateTokenId) external {
        // Load delegateTokenHolder of delegateTokenId
        bytes32 registryLocation = RegistryHashes._computeLocation(bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]));
        address delegateTokenHolder =
            address(uint160(uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.to))))));
        // Revert if the caller is not the owner and not approved all by the owner
        if (msg.sender != delegateTokenHolder && !approvals[keccak256(abi.encode(delegateTokenHolder, msg.sender))]) revert NotAuthorized(msg.sender, delegateTokenId);
        // Set approval
        _writeApproved(delegateTokenId, spender);
        // Emit approval event
        emit Approval(delegateTokenHolder, spender, delegateTokenId);
    }

    /// @notice ERC721 setApprovalForAll function
    function setApprovalForAll(address operator, bool approved) external {
        // Set approve all
        approvals[keccak256(abi.encode(msg.sender, operator))] = approved;
        // Emit approval event
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @notice ERC721 getApproved function
    /// TODO: revert if token ID is not valid
    function getApproved(uint256 delegateTokenId) public view returns (address approved) {
        approved = _readApproved(delegateTokenId);
    }

    /// @notice ERC721 isApprovedForAll function
    function isApprovedForAll(address owner_, address operator) public view returns (bool approved) {
        approved = approvals[keccak256(abi.encode(owner_, operator))];
    }

    /// @dev implements ERC721 transferFromFunction
    /// @param from, should revert if not owner of the delegateTokenId
    /// @param to, should revert if the zero address
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
        // Revert if to is zero address
        if (to == address(0)) revert ToIsZero();
        // Load delegateTokenHolder from delegate registry
        bytes32 delegationHash = bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]);
        bytes32 registryLocation = RegistryHashes._computeLocation(bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]));
        address delegateTokenHolder =
            address(uint160(uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.to))))));
        // Revert if from is not delegateTokenHolder
        if (from != delegateTokenHolder) revert FromNotDelegateTokenHolder(from, delegateTokenHolder);
        // Revert if caller is not the delegateTokenHolder, authorized, or approved for the id
        // We can use from here instead of delegateTokenHolder since we've just verified that from == delegateTokenHolder
        if (!(msg.sender == from || isApprovedForAll(from, msg.sender) || msg.sender == _readApproved(delegateTokenId))) {
            revert NotAuthorized(msg.sender, delegateTokenId);
        }
        // Update balances
        balances[from]--;
        balances[to]++;
        // Set approved to zero
        _writeApproved(delegateTokenId, address(0));
        // Emit transfer event
        emit Transfer(from, to, delegateTokenId);
        // Decode delegation type from hash and initialize newDelegationHash
        IDelegateRegistry.DelegationType underlyingType = RegistryHashes._decodeLastByteToType(delegationHash);
        bytes32 newDelegationHash = 0;
        // Load contract and rights from delegate registry
        address underlyingContract = address(
            uint160(uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.contract_)))))
        );
        bytes32 underlyingRights = IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.rights)));
        // Update registry according to type
        // TODO: consider implementation of transfer function for registry
        _transferByType(delegateTokenId, registryLocation, from, delegationHash, to, newDelegationHash, underlyingType, underlyingContract, underlyingRights);
    }

    function _transferByType(
        uint256 delegateTokenId,
        bytes32 registryLocation,
        address from,
        bytes32 delegationHash,
        address to,
        bytes32 newDelegationHash,
        IDelegateRegistry.DelegationType underlyingType,
        address underlyingContract,
        bytes32 underlyingRights
    ) internal {
        if (underlyingType == IDelegateRegistry.DelegationType.ERC721) {
            // Load token id from delegate registry
            uint256 erc721UnderlyingId =
                uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.tokenId))));
            // Update hash, using deterministic registry hash calculation
            newDelegationHash = RegistryHashes._computeERC721(underlyingContract, to, underlyingRights, erc721UnderlyingId, address(this));
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(newDelegationHash);
            // Update registry, reverts if returned hashes aren't correct
            if (
                IDelegateRegistry(delegateRegistry).delegateERC721(from, underlyingContract, erc721UnderlyingId, underlyingRights, false) != delegationHash
                    || IDelegateRegistry(delegateRegistry).delegateERC721(to, underlyingContract, erc721UnderlyingId, underlyingRights, true) != newDelegationHash
            ) revert HashMisMatch();
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC20) {
            // Update hash, using deterministic registry hash calculation
            newDelegationHash = RegistryHashes._computeERC20(underlyingContract, to, underlyingRights, address(this));
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(newDelegationHash);
            // Fetch current amount
            uint256 erc20Amount = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
            // Calculate fromAmount and toAmount, reading directly from registry storage
            uint256 erc20FromAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.amount)))
            ) - erc20Amount;
            bytes32 newRegistryLocation = RegistryHashes._computeLocation(newDelegationHash);
            uint256 erc20ToAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(newRegistryLocation) + uint256(IDelegateRegistry.StoragePositions.amount)))
            ) + erc20Amount;
            // Update registry, reverts if returned hashes aren't correct
            if (
                delegationHash
                    != (
                        erc20FromAmount == 0
                            ? IDelegateRegistry(delegateRegistry).delegateERC20(from, underlyingContract, erc20FromAmount, underlyingRights, false)
                            : IDelegateRegistry(delegateRegistry).delegateERC20(from, underlyingContract, erc20FromAmount, underlyingRights, true)
                    ) || newDelegationHash != IDelegateRegistry(delegateRegistry).delegateERC20(to, underlyingContract, erc20ToAmount, underlyingRights, true)
            ) revert HashMisMatch();
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC1155) {
            // Load tokenId from delegate registry
            uint256 erc1155UnderlyingId =
                uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.tokenId))));
            // Update hash, using deterministic registry hash calculation
            newDelegationHash = RegistryHashes._computeERC1155(underlyingContract, to, underlyingRights, erc1155UnderlyingId, address(this));
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(newDelegationHash);
            // Fetch current amount
            uint256 erc1155Amount = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
            // Calculate fromAmount and toAmount, reading directly from registry storage
            uint256 erc1155FromAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.amount)))
            ) - erc1155Amount;
            bytes32 newRegistryLocation = RegistryHashes._computeLocation(newDelegationHash);
            uint256 erc1155ToAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(newRegistryLocation) + uint256(IDelegateRegistry.StoragePositions.amount)))
            ) + erc1155Amount;
            // Update registry, reverts if returned hashes aren't correct
            if (
                delegationHash
                    != (
                        erc1155FromAmount == 0
                            ? IDelegateRegistry(delegateRegistry).delegateERC1155(from, underlyingContract, erc1155UnderlyingId, erc1155FromAmount, underlyingRights, false)
                            : IDelegateRegistry(delegateRegistry).delegateERC1155(from, underlyingContract, erc1155UnderlyingId, erc1155FromAmount, underlyingRights, true)
                    )
                    || newDelegationHash
                        != IDelegateRegistry(delegateRegistry).delegateERC1155(to, underlyingContract, erc1155UnderlyingId, erc1155ToAmount, underlyingRights, true)
            ) revert HashMisMatch();
        }
    }

    /*//////////////////////////////////////////////////////////////
    /                EXTENDED ERC721 METHODS                       /
    //////////////////////////////////////////////////////////////*/

    /// @notice Adapted from solmate's [ERC721](https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol)
    function isApprovedOrOwner(address spender, uint256 delegateTokenId) public view returns (bool) {
        (bool approvedOrOwner, address delegateTokenHolder) = _isApprovedOrOwner(spender, delegateTokenId);
        if (delegateTokenHolder == address(0)) revert NotMinted(delegateTokenId);
        return approvedOrOwner;
    }

    function _isApprovedOrOwner(address spender, uint256 delegateTokenId) internal view returns (bool approvedOrOwner, address delegateTokenHolder) {
        bytes32 registryLocation = RegistryHashes._computeLocation(bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]));
        delegateTokenHolder =
            address(uint160(uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.to))))));
        approvedOrOwner = spender == delegateTokenHolder || isApprovedForAll(delegateTokenHolder, spender) || getApproved(delegateTokenId) == spender;
    }

    /*//////////////////////////////////////////////////////////////
    /            LIQUID DELEGATE TOKEN METHODS                     /
    //////////////////////////////////////////////////////////////*/

    function getDelegateInfo(uint256 delegateTokenId)
        external
        view
        returns (IDelegateRegistry.DelegationType delegationType, address tokenContract, uint256 tokenId, uint256 tokenAmount, bytes32 rights, uint256 expiry)
    {
        // Load delegation from registry
        bytes32[] memory delegationHash = new bytes32[](1);
        delegationHash[0] = bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]);
        IDelegateRegistry.Delegation[] memory delegation = IDelegateRegistry(delegateRegistry).getDelegationsFromHashes(delegationHash);
        delegationType = delegation[0].type_;
        tokenContract = delegation[0].contract_;
        tokenId = delegation[0].tokenId;
        rights = delegation[0].rights;
        // Read expiry
        expiry = _readExpiry(delegateTokenId);
        // Load tokenAmount
        if (delegationType == IDelegateRegistry.DelegationType.ERC721) tokenAmount = 1;
        else tokenAmount = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
    }

    /**
     * @notice Create rights token pair pulling underlying token from `msg.sender`.
     * @param delegateTokenTo Recipient of delegate rights token.
     * @param principalTokenTo Recipient of principal rights token.
     * @param underlyingContract Address of underlying token contract.
     * @param underlyingTokenId Token ID of underlying token to be escrowed.
     * @param expiry The absolute timestamp of the expiry
     * @param salt A randomly chosen value, never repeated, to generate unique delegateIds even on fungibles. Not stored since random choice will avoid collisions
     * @return delegateTokenId New rights ID that is also the token ID of both the newly created principal and
     * delegate tokens.
     */
    function create(
        address delegateTokenTo,
        address principalTokenTo,
        IDelegateRegistry.DelegationType underlyingType,
        address underlyingContract,
        uint256 underlyingTokenId,
        uint256 underlyingAmount,
        bytes32 underlyingRights,
        uint256 expiry,
        uint96 salt
    ) external payable returns (uint256 delegateTokenId) {
        // Pulls tokens in before minting, reverts if invalid token type, parses underlyingAmount and underlyingTokenId
        (underlyingAmount, underlyingTokenId) = _pullAndParse(underlyingType, underlyingAmount, underlyingContract, underlyingTokenId);
        // Check expiry
        if (expiry < block.timestamp) revert ExpiryTimeNotInFuture(expiry, block.timestamp);
        if (expiry > MAX_EXPIRY) revert ExpiryTooLarge(expiry, MAX_EXPIRY);
        // Revert if to is the zero address
        if (delegateTokenTo == address(0)) revert ToIsZero();
        // Revert if token has already existed / been minted
        delegateTokenId = getDelegateId(underlyingType, underlyingContract, underlyingTokenId, underlyingAmount, msg.sender, salt);
        if (delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] != DELEGATE_TOKEN_ID_AVAILABLE) revert AlreadyExisted(delegateTokenId);
        // Increment erc721 balance
        balances[delegateTokenTo]++;
        // Write expiry
        _writeExpiry(delegateTokenId, expiry);
        // Emit transfer event
        emit Transfer(address(0), delegateTokenTo, delegateTokenId);
        // Update amount, registry data, and store registry hash
        _createByType(underlyingType, delegateTokenId, delegateTokenTo, underlyingAmount, underlyingContract, underlyingRights, underlyingTokenId);
        // Mint principal token
        PrincipalToken(principalToken).mint(principalTokenTo, delegateTokenId);
    }

    function _pullAndParse(IDelegateRegistry.DelegationType underlyingType, uint256 underlyingAmount, address underlyingContract, uint256 underlyingTokenId)
        internal
        returns (uint256, uint256)
    {
        if (underlyingType == IDelegateRegistry.DelegationType.ERC721) {
            IERC721(underlyingContract).transferFrom(msg.sender, address(this), underlyingTokenId);
            return (1, underlyingTokenId);
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC20) {
            // Revert if underlyingAmount is zero
            if (underlyingAmount == 0) revert WrongAmountForType(IDelegateRegistry.DelegationType.ERC20, underlyingAmount);
            SafeTransferLib.safeTransferFrom(ERC20(underlyingContract), msg.sender, address(this), underlyingAmount);
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
            newDelegationHash = RegistryHashes._computeERC721(underlyingContract, delegateTokenTo, underlyingRights, underlyingTokenId, address(this));
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(newDelegationHash);
            // Update Registry
            if (newDelegationHash != IDelegateRegistry(delegateRegistry).delegateERC721(delegateTokenTo, underlyingContract, underlyingTokenId, underlyingRights, true)) {
                revert HashMisMatch();
            }
        } else if (underlyingType == IDelegateRegistry.DelegationType.ERC20) {
            // Store amount
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)] = underlyingAmount;
            // Store hash, computing registry hash deterministically
            newDelegationHash = RegistryHashes._computeERC20(underlyingContract, delegateTokenTo, underlyingRights, address(this));
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(newDelegationHash);
            // Calculate increasedAmount, reading directly from registry storage
            bytes32 newRegistryLocation = RegistryHashes._computeLocation(newDelegationHash);
            uint256 erc20IncreasedAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(newRegistryLocation) + uint256(IDelegateRegistry.StoragePositions.amount)))
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
            newDelegationHash = RegistryHashes._computeERC1155(underlyingContract, delegateTokenTo, underlyingRights, underlyingTokenId, address(this));
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(newDelegationHash);
            // Calculate toAmount, reading directly from registry storage
            bytes32 newRegistryLocation = RegistryHashes._computeLocation(newDelegationHash);
            uint256 erc1155IncreasedAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(newRegistryLocation) + uint256(IDelegateRegistry.StoragePositions.amount)))
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

    /**
     * @notice Allows the principal token owner or any approved operator to extend the expiry of the
     * delegation rights.
     * @param delegateTokenId The ID of the rights being extended.
     * @param newExpiry The absolute timestamp to set the expiry
     */
    function extend(uint256 delegateTokenId, uint256 newExpiry) external {
        if (!PrincipalToken(principalToken).isApprovedOrOwner(msg.sender, delegateTokenId)) revert NotAuthorized(msg.sender, delegateTokenId);
        uint256 currentExpiry = _readExpiry(delegateTokenId);
        if (newExpiry <= currentExpiry) revert ExpiryTooSmall(newExpiry, currentExpiry);
        _writeExpiry(delegateTokenId, newExpiry);
    }

    /**
     * @notice Allows the delegate owner or any approved operator to rescind their right early,
     * allowing the principal rights owner to redeem the underlying token early.
     * @notice Allows anyone to forcefully rescind the delegate token if it has expired
     * @param delegateTokenId ID of the delegate right to be rescinded
     */
    function rescind(address from, uint256 delegateTokenId) external {
        if (_readExpiry(delegateTokenId) < block.timestamp) {
            if (from == address(0)) revert FromIsZero();
            _writeApproved(delegateTokenId, msg.sender);
            transferFrom(from, address(this), delegateTokenId);
        } else {
            transferFrom(from, address(this), delegateTokenId);
        }
    }

    /**
     * @notice Allows principal rights owner or approved operator to withdraw the underlying token
     * once the delegation rights have either met their expiration or been rescinded via one of the
     * `burn`/`burnWithPermit` methods. The underlying token is sent to the address specified `to`
     * address.
     * @dev Forcefully burns the associated delegate token if still in circulation.
     * @param to Recipient of the underlying token.
     * @param delegateTokenId ID of the delegate right to be withdrawn.
     */
    function withdrawTo(address to, uint256 delegateTokenId) external {
        // Load delegationHash
        bytes32 delegationHash = bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]);
        // Revert if delegation already burned or not minted
        if (delegationHash == bytes32(DELEGATE_TOKEN_ID_AVAILABLE) || delegationHash == bytes32(DELEGATE_TOKEN_ID_USED)) revert NotMinted(delegateTokenId);
        // Set registry hash to delegate token id used
        delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = DELEGATE_TOKEN_ID_USED;
        // Load delegateTokenHolder from registry
        bytes32 registryLocation = RegistryHashes._computeLocation(delegationHash);
        address delegateTokenHolder =
            address(uint160(uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.to))))));
        // If it still exists the only valid way to withdraw is the delegation having expired or delegateTokenHolder rescinded to this contract
        if (block.timestamp < _readExpiry(delegateTokenId) && delegateTokenHolder != address(this)) {
            revert WithdrawNotAvailable(delegateTokenId, _readExpiry(delegateTokenId), block.timestamp);
        }
        // Decrement balance of holder
        balances[delegateTokenHolder]--;
        // Delete approved, reasonable to assume that this contract hasn't approved anything :)
        if (delegateTokenHolder != address(this)) _writeApproved(delegateTokenId, address(0));
        // Emit transfer to zero address
        emit Transfer(delegateTokenHolder, address(0), delegateTokenId);
        // Decode token type
        IDelegateRegistry.DelegationType delegationType = RegistryHashes._decodeLastByteToType(delegationHash);
        // Fetch underlying contract and rights from registry
        address underlyingContract = address(
            uint160(uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.contract_)))))
        );
        bytes32 underlyingRights = IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.rights)));
        _withdrawByType(to, registryLocation, delegateTokenId, delegationHash, delegateTokenHolder, delegationType, underlyingContract, underlyingRights);
    }

    function _withdrawByType(
        address to,
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
                uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.tokenId))));
            if (
                delegationHash
                    != IDelegateRegistry(delegateRegistry).delegateERC721(delegateTokenHolder, underlyingContract, erc721UnderlyingTokenId, underlyingRights, false)
            ) revert HashMisMatch();
            PrincipalToken(principalToken).burnIfAuthorized(msg.sender, delegateTokenId);
            IERC721(underlyingContract).transferFrom(address(this), to, erc721UnderlyingTokenId);
        } else if (delegationType == IDelegateRegistry.DelegationType.ERC20) {
            // Load and then delete delegatedAmount
            uint256 erc20DelegatedAmount = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
            delete delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
            // Calculate decrementedAmount, reading directly from registry storage
            uint256 erc20DecrementedAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.amount)))
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
            SafeTransferLib.safeTransfer(ERC20(underlyingContract), to, erc20DelegatedAmount);
        } else if (delegationType == IDelegateRegistry.DelegationType.ERC1155) {
            // Load and then delete delegatedAmount
            uint256 erc1155DelegatedAmount = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
            delete delegateTokenInfo[delegateTokenId][uint256(StoragePositions.delegatedAmount)];
            // Load tokenId from registry
            uint256 erc11551UnderlyingTokenId =
                uint256(IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.tokenId))));
            // Calculate decrementedAmount, reading directly from registry storage
            uint256 erc1155DecrementedAmount = uint256(
                IDelegateRegistry(delegateRegistry).readSlot(bytes32(uint256(registryLocation) + uint256(IDelegateRegistry.StoragePositions.amount)))
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
            IERC1155(underlyingContract).safeTransferFrom(address(this), to, erc11551UnderlyingTokenId, erc1155DelegatedAmount, "");
        }
    }

    /**
     * @notice Allows delegate token owner or approved operator to borrow their underlying token for the
     * duration of a single atomic transaction
     * @param receiver Recipient of borrowed token, must implement the `INFTFlashBorrower` interface
     * @param delegateId ID of the rights the underlying token is being borrowed from
     * @param data Added metadata to be relayed to borrower
     * TODO: implement ERC20 and ERC1155 versions of this
     */
    function flashLoan(address receiver, uint256 delegateId, bytes calldata data) external payable {
        if (!isApprovedOrOwner(msg.sender, delegateId)) revert NotAuthorized(msg.sender, delegateId);
        bytes32[] memory delegationHash = new bytes32[](1);
        delegationHash[0] = bytes32(delegateTokenInfo[delegateId][uint256(StoragePositions.registryHash)]);
        IDelegateRegistry.Delegation[] memory delegation = IDelegateRegistry(delegateRegistry).getDelegationsFromHashes(delegationHash);
        if (!(delegation[0].type_ == IDelegateRegistry.DelegationType.ERC721 && delegation[0].rights == "")) revert InvalidFlashloan();
        IERC721(delegation[0].contract_).transferFrom(address(this), receiver, delegation[0].tokenId);

        if (INFTFlashBorrower(receiver).onFlashLoan{value: msg.value}(msg.sender, delegation[0].contract_, delegation[0].tokenId, data) != FLASHLOAN_CALLBACK_SUCCESS) {
            revert InvalidFlashloan();
        }

        // Safer and cheaper to expect the token to have been returned rather than pulling it with `transferFrom`.
        if (IERC721(delegation[0].contract_).ownerOf(delegation[0].tokenId) != address(this)) revert InvalidFlashloan();
    }

    /// @notice Deterministic function for generating a delegateId
    /// @dev Because msg.sender is fixed in addition to the freely chosen salt, addresses cannot grief each other
    /// @dev The WrapOfferer is a special case, but trivial to regenerate a unique salt via order extraData on the frontend
    function getDelegateId(IDelegateRegistry.DelegationType delegationType, address tokenContract, uint256 tokenId, uint256 tokenAmount, address creator, uint96 salt)
        public
        pure
        returns (uint256)
    {
        if (tokenAmount == 0) revert TokenAmountIsZero();
        return uint256(keccak256(abi.encode(delegationType, tokenContract, tokenId, tokenAmount, creator, salt)));
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

    ////////// METADATA ////////

    function setBaseURI(string calldata baseURI_) external onlyOwner {
        baseURI = baseURI_;
    }

    /// @dev Returns contract-level metadata URI for OpenSea (reference)[https://docs.opensea.io/docs/contract-level-metadata]
    function contractURI() public view returns (string memory) {
        return string.concat(baseURI, "contract");
    }

    function tokenURI(uint256 delegateTokenId) public view returns (string memory) {
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
        string memory idstr = LibString.toString(delegateTokenId);

        string memory pownerstr = principalOwner == address(0) ? "N/A" : LibString.toHexStringChecksummed(principalOwner);
        string memory status = principalOwner == address(0) || expiry <= block.timestamp ? "Expired" : "Active";

        string memory firstPartOfMetadataString = string.concat(
            '{"name":"Delegate Token #"',
            idstr,
            '","description":"LiquidDelegate lets you escrow your token for a chosen timeperiod and receive a liquid NFT representing the associated delegation rights. This collection represents the tokenized delegation rights.","attributes":[{"trait_type":"Collection Address","value":"',
            LibString.toHexStringChecksummed(tokenContract),
            '"},{"trait_type":"Token ID","value":"',
            idstr,
            '"},{"trait_type":"Expires At","display_type":"date","value":',
            LibString.toString(expiry)
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
