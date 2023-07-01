// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IDelegateTokenBase, TokenType} from "./interfaces/IDelegateToken.sol";
import {INFTFlashBorrower} from "./interfaces/INFTFlashBorrower.sol";

import {IDelegateRegistry} from "./interfaces/IDelegateRegistry.sol";

import {IERC721, IERC1155} from "./interfaces/ITokenInterfaces.sol";

import {PrincipalToken} from "./PrincipalToken.sol";
import {ERC2981} from "lib/openzeppelin-contracts/contracts/token/common/ERC2981.sol";

import {Base64} from "lib/solady/src/utils/Base64.sol";
import {LibString} from "lib/solady/src/utils/LibString.sol";
import {Owned} from "lib/solmate/src/auth/Owned.sol";
import {SafeTransferLib, ERC20} from "lib/solmate/src/utils/SafeTransferLib.sol";

interface ERC721TokenReceiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

/**
 * delegateId needs to be deterministic. hash(tokenType, contractAddress, tokenId, amount, creatorAddress, salt)
 * that points to the data being stored
 * and we also prevent delegateId reuse with a simple boolean set membership lookup
 */

contract DelegateToken is ERC721TokenReceiver, IDelegateTokenBase, ERC2981, Owned {
    // Errors
    error ToIsZero();
    error FromNotOwner();
    error NotAuthorized();
    error NotMinted();

    /// @notice The value flash borrowers need to return from `onFlashLoan` for the call to be successful.
    bytes32 public constant FLASHLOAN_CALLBACK_SUCCESS = bytes32(uint256(keccak256("INFTFlashBorrower.onFlashLoan")) - 1);

    /// @notice The v2 delegate registry
    IDelegateRegistry public immutable override delegateRegistry;

    /// @notice The principal token deployed in tandem with this delegate token
    address public immutable override principalToken;

    /// @notice Image metadata location, but attributes are stored onchain
    string public baseURI;

    /// @dev delegateId, a hash of (tokenType, tokenContract, tokenId, tokenAmount, msg.sender, salt), points a unique id to the StoragePosition
    mapping(uint256 delegateTokenId => uint256[3] info) internal delegateTokenInfo;

    /// @dev Standardizes storage positions of delegateInfo mapping data
    enum StoragePositions {
        registryHash,
        packedInfo, // PACKED (address approved, uint96 expiry)
        amount // Not used by 721 delegations
    }

    /// @dev Standardizes packedInfo storage flags to prevent double-creation and griefing
    uint256 internal constant DELEGATE_TOKEN_ID_AVAILABLE = 0;
    uint256 internal constant DELEGATE_TOKEN_ID_USED = 1;

    constructor(address delegateRegistry_, address principalToken_, string memory baseURI_, address initialMetadataOwner) Owned(initialMetadataOwner) {
        delegateRegistry = IDelegateRegistry(delegateRegistry_);
        principalToken = principalToken_;
        baseURI = baseURI_;
    }

    /*//////////////////////////////////////////////////////////////
    /                         ERC721                               /
    //////////////////////////////////////////////////////////////*/

    error InvalidDelegateTokenHolder();
    error NotERC721Receiver();

    event Transfer(address from, address to, uint256 id);
    event Approval(address indexed delegateTokenHolder, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed delegateTokenHolder, address indexed operator, bool approved);

    /// @notice mapping for ERC721 balances
    mapping(address delegateTokenHolder => uint256 balance) internal _balanceOf;

    /// @notice ERC721 balanceOf function
    /// @dev must revert if delegateTokenHolder is zero address
    /// @param delegateTokenHolder is the address to query
    /// @return balance of all the delegateTokens assigned to the holder
    function balanceOf(address delegateTokenHolder) external view returns (uint256 balance) {
        if (delegateTokenHolder == address(0)) revert InvalidDelegateTokenHolder();
        balance = _balanceOf[delegateTokenHolder];
    }

    /// @notice ERC721 ownerOf function
    /// @dev must revert if delegateTokenHolder is zero address
    /// @param delegateTokenId is the delegateToken identifier
    /// @return delegateTokenHolder that is assigned to the delegateTokenId
    function ownerOf(uint256 delegateTokenId) external view returns (address delegateTokenHolder) {
        delegateTokenHolder = delegateRegistry.readDelegationAddress(
            bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]), IDelegateRegistry.StoragePositions.to
        );
        if (delegateTokenHolder == address(0)) revert InvalidDelegateTokenHolder();
    }

    /// @notice ERC721 onERC721Received function
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4 value) {
        value = bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    /// @notice ERC721 safeTransferFrom function
    function safeTransferFrom(address from, address to, uint256 delegateTokenId, bytes memory data) public {
        transferFrom(from, to, delegateTokenId);
        if (
            to.code.length != 0
                && ERC721TokenReceiver(to).onERC721Received(msg.sender, from, delegateTokenId, data) != ERC721TokenReceiver.onERC721Received.selector
        ) {
            revert NotERC721Receiver();
        }
    }

    /// @notice ERC721 safeTransferFrom function
    function safeTransferFrom(address from, address to, uint256 delegateTokenId) external {
        safeTransferFrom(from, to, delegateTokenId, "");
    }

    /// @notice approve for all mapping
    mapping(bytes32 approveAllHash => bool enabled) internal _approveAllHashes;

    /// @notice ERC721 approve function
    function approve(address spender, uint256 delegateTokenId) external {
        // Load delegateTokenHolder of delegateTokenId
        address delegateTokenHolder = delegateRegistry.readDelegationAddress(
            bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]), IDelegateRegistry.StoragePositions.to
        );
        // Revert if the caller is not the owner and not approved all by the owner
        if (msg.sender != delegateTokenHolder && !_approveAllHashes[keccak256(abi.encode(delegateTokenHolder, msg.sender))]) revert NotAuthorized();
        // Set approval
        _writeApproved(delegateTokenId, spender);
        // Emit approval event
        emit Approval(delegateTokenHolder, spender, delegateTokenId);
    }

    /// @notice ERC721 setApprovalForAll function
    function setApprovalForAll(address operator, bool approved) external {
        // Set approve all
        _approveAllHashes[keccak256(abi.encode(msg.sender, operator))] = approved;
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
        approved = _approveAllHashes[keccak256(abi.encode(owner_, operator))];
    }

    /*//////////////////////////////////////////////////////////////
    /            LIQUID DELEGATE TOKEN METHODS                     /
    //////////////////////////////////////////////////////////////*/

    function getDelegateInfo(uint256 delegateId)
        external
        view
        returns (TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, bytes32 rights, uint256 expiry)
    {}

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
        TokenType underlyingType,
        address underlyingContract,
        uint256 underlyingTokenId,
        uint256 underlyingAmount,
        bytes32 underlyingRights,
        uint256 expiry,
        uint96 salt
    ) external payable returns (uint256 delegateTokenId) {
        // Transfer assets in before minting, also checks token type is valid
        if (underlyingType == TokenType.ERC721) {
            IERC721(underlyingContract).transferFrom(msg.sender, address(this), underlyingTokenId);
            underlyingAmount = 1;
        } else if (underlyingType == TokenType.ERC20) {
            SafeTransferLib.safeTransferFrom(ERC20(underlyingContract), msg.sender, address(this), underlyingAmount);
            underlyingTokenId = 0;
        } else if (underlyingType == TokenType.ERC1155) {
            IERC1155(underlyingContract).safeTransferFrom(msg.sender, address(this), underlyingTokenId, underlyingAmount, "");
        } else {
            revert InvalidTokenType();
        }
        // Check expiry
        if (expiry < block.timestamp) revert ExpiryTimeNotInFuture();
        if (expiry > type(uint96).max) revert ExpiryTooLarge();
        // Revert if to is the zero address
        if (delegateTokenTo == address(0)) revert ToIsZero();
        // Revert if token has already existed / been minted
        delegateTokenId = getDelegateId(underlyingType, underlyingContract, underlyingTokenId, underlyingAmount, msg.sender, salt);
        if (delegateTokenInfo[delegateTokenId][uint256(StoragePositions.packedInfo)] != DELEGATE_TOKEN_ID_AVAILABLE) revert AlreadyExisted();
        // Increment erc721 balance
        _balanceOf[delegateTokenTo]++;
        // Write expiry
        _writeExpiry(delegateTokenId, expiry);
        // Emit transfer event
        emit Transfer(address(0), delegateTokenTo, delegateTokenId);
        // Update amount, registry data, and store registry hash
        if (underlyingType == TokenType.ERC721) {
            if (underlyingAmount != 1) revert WrongAmount();
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] =
                uint256(IDelegateRegistry(delegateRegistry).delegateERC721(delegateTokenTo, underlyingContract, underlyingTokenId, underlyingRights, true));
        } else if (underlyingType == TokenType.ERC20) {
            if (underlyingAmount == 0) revert WrongAmount();
            // Store amount
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.amount)] = underlyingAmount;
            // This currently has failing invariants due to the bubbling up "specificRights" => "" rights design
            uint256 addAmount = underlyingAmount
                + IDelegateRegistry(delegateRegistry).checkDelegateForERC20(delegateTokenTo, address(this), underlyingContract, underlyingRights);
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] =
                uint256(IDelegateRegistry(delegateRegistry).delegateERC20(delegateTokenTo, underlyingContract, addAmount, underlyingRights, true));
        } else if (underlyingType == TokenType.ERC1155) {
            if (underlyingAmount == 0) revert WrongAmount();
            // Store amount
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.amount)] = underlyingAmount;
            // This currently has failing invariants due to the bubbling up "specificRights" => "" rights design
            uint256 addAmount = underlyingAmount
                + IDelegateRegistry(delegateRegistry).checkDelegateForERC1155(
                    delegateTokenTo, address(this), underlyingContract, underlyingTokenId, underlyingRights
                );
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(
                IDelegateRegistry(delegateRegistry).delegateERC1155(delegateTokenTo, underlyingContract, underlyingTokenId, addAmount, underlyingRights, true)
            );
        }
        // Mint principal token
        PrincipalToken(principalToken).mint(principalTokenTo, delegateTokenId);
    }

    /**
     * @notice Allows the principal token owner or any approved operator to extend the expiry of the
     * delegation rights.
     * @param id The ID of the rights being extended.
     * @param newExpiry The absolute timestamp to set the expiry
     */
    function extend(uint256 id, uint256 newExpiry) external {
        if (!PrincipalToken(principalToken).isApprovedOrOwner(msg.sender, id)) revert NotAuthorized();
        uint256 currentExpiry = _readExpiry(id);
        if (newExpiry <= currentExpiry) revert NotExtending();
        _writeExpiry(id, newExpiry);
    }

    /// @notice Adapted from solmate's [ERC721](https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol)
    function isApprovedOrOwner(address spender, uint256 delegateTokenId) public view returns (bool) {
        (bool approvedOrOwner, address delegateTokenHolder) = _isApprovedOrOwner(spender, delegateTokenId);
        if (delegateTokenHolder == address(0)) revert NotMinted();
        return approvedOrOwner;
    }

    function _isApprovedOrOwner(address spender, uint256 delegateTokenId) internal view returns (bool approvedOrOwner, address delegateTokenHolder) {
        delegateTokenHolder = delegateRegistry.readDelegationAddress(
            bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]), IDelegateRegistry.StoragePositions.to
        );
        approvedOrOwner = spender == delegateTokenHolder || isApprovedForAll(delegateTokenHolder, spender) || getApproved(delegateTokenId) == spender;
    }

    /**
     * @notice Allows the delegate owner or any approved operator to rescind their right early,
     * allowing the principal rights owner to redeem the underlying token early.
     * @param id ID of the delegate right to be burnt.
     */
    function burn(uint256 id) external {
        (bool approvedOrOwner, address owner_) = _isApprovedOrOwner(msg.sender, id);
        if (block.timestamp >= _readExpiry(id) || approvedOrOwner) {
            _burnWithoutValidation(owner_, id);
        } else {
            revert NotAuthorized();
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
        bytes32[] memory delegationHash = new bytes32[](1);
        delegationHash[0] = bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]);
        IDelegateRegistry.Delegation[] memory delegation = IDelegateRegistry(delegateRegistry).getDelegationsFromHashes(delegationHash);
        PrincipalToken(principalToken).burnIfAuthorized(msg.sender, delegateTokenId);
        // Load amount if type is not 721
        uint256 amount;
        if (delegation[0].type_ != IDelegateRegistry.DelegationType.ERC721) amount = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.amount)];
        // Check whether the delegate token still exists.
        if (delegation[0].to != address(0)) {
            // If it still exists the only valid way to withdraw is the delegation having expired.
            if (block.timestamp < _readExpiry(delegateTokenId) && delegation[0].to != msg.sender) {
                revert WithdrawNotAvailable();
            }
            _burnWithoutValidation(delegation[0].to, delegateTokenId);
        }
        if (delegation[0].type_ == IDelegateRegistry.DelegationType.ERC721) {
            IERC721(delegation[0].contract_).transferFrom(address(this), to, delegation[0].tokenId);
        } else if (delegation[0].type_ == IDelegateRegistry.DelegationType.ERC20) {
            SafeTransferLib.safeTransfer(ERC20(delegation[0].contract_), to, amount);
        } else if (delegation[0].type_ == IDelegateRegistry.DelegationType.ERC1155) {
            IERC1155(delegation[0].contract_).safeTransferFrom(address(this), to, delegation[0].tokenId, amount, "");
        }
    }

    /**
     * @notice Allows delegate token owner or approved operator to borrow their underlying token for the
     * duration of a single atomic transaction
     * @param receiver Recipient of borrowed token, must implement the `INFTFlashBorrower` interface
     * @param delegateId ID of the rights the underlying token is being borrowed from
     * @param data Added metadata to be relayed to borrower
     */
    function flashLoan(address receiver, uint256 delegateId, bytes calldata data) external payable {
        if (!isApprovedOrOwner(msg.sender, delegateId)) revert NotAuthorized();
        bytes32[] memory delegationHash = new bytes32[](1);
        delegationHash[0] = bytes32(delegateTokenInfo[delegateId][uint256(StoragePositions.registryHash)]);
        IDelegateRegistry.Delegation[] memory delegation = IDelegateRegistry(delegateRegistry).getDelegationsFromHashes(delegationHash);
        if (!(delegation[0].type_ == IDelegateRegistry.DelegationType.ERC721 && delegation[0].rights == "")) revert InvalidFlashloan();
        IERC721(delegation[0].contract_).transferFrom(address(this), receiver, delegation[0].tokenId);

        if (
            INFTFlashBorrower(receiver).onFlashLoan{value: msg.value}(msg.sender, delegation[0].contract_, delegation[0].tokenId, data)
                != FLASHLOAN_CALLBACK_SUCCESS
        ) {
            revert InvalidFlashloan();
        }

        // Safer and cheaper to expect the token to have been returned rather than pulling it with `transferFrom`.
        if (IERC721(delegation[0].contract_).ownerOf(delegation[0].tokenId) != address(this)) revert InvalidFlashloan();
    }

    /// @dev implements ERC721 transferFromFunction
    function transferFrom(address from, address to, uint256 delegateTokenId) public {
        // Revert if to is zero address
        if (to == address(0)) revert ToIsZero();
        // Load delegation from registry
        bytes32[] memory delegationHash = new bytes32[](1);
        delegationHash[0] = bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]);
        IDelegateRegistry.Delegation[] memory delegation = IDelegateRegistry(delegateRegistry).getDelegationsFromHashes(delegationHash);
        // Revert if from is not owner
        if (from != delegation[0].to) revert FromNotOwner();
        // Revert if caller is not the owner, authorized, or approved for the id
        if (!(msg.sender == delegation[0].to || isApprovedForAll(delegation[0].to, msg.sender) || msg.sender == _readApproved(delegateTokenId))) {
            revert NotAuthorized();
        }
        // Update _balanceOf
        _balanceOf[from]--;
        _balanceOf[to]++;
        // Set approved to zero
        _writeApproved(delegateTokenId, address(0));
        // Emit transfer event
        emit Transfer(from, to, delegateTokenId);
        // Transfer delegations, updating hash accordingly
        if (delegation[0].type_ == IDelegateRegistry.DelegationType.ERC721) {
            IDelegateRegistry(delegateRegistry).delegateERC721(from, delegation[0].contract_, delegation[0].tokenId, delegation[0].rights, false);
            // Requires update to registry where hash is returned
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] =
                uint256(IDelegateRegistry(delegateRegistry).delegateERC721(to, delegation[0].contract_, delegation[0].tokenId, delegation[0].rights, true));
        } else if (delegation[0].type_ == IDelegateRegistry.DelegationType.ERC20) {
            uint256 amount = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.amount)];
            // This currently has failing invariants due to the bubbling up "specificRights" => "" rights design
            uint256 fromAmount =
                IDelegateRegistry(delegateRegistry).checkDelegateForERC20(from, address(this), delegation[0].contract_, delegation[0].rights) - amount;
            uint256 toAmount =
                IDelegateRegistry(delegateRegistry).checkDelegateForERC20(to, address(this), delegation[0].contract_, delegation[0].rights) + amount;
            if (fromAmount == 0) IDelegateRegistry(delegateRegistry).delegateERC20(from, delegation[0].contract_, fromAmount, delegation[0].rights, false);
            else IDelegateRegistry(delegateRegistry).delegateERC20(from, delegation[0].contract_, fromAmount, delegation[0].rights, true);
            // Requires update to registry where hash is returned
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] =
                uint256(IDelegateRegistry(delegateRegistry).delegateERC20(to, delegation[0].contract_, toAmount, delegation[0].rights, true));
        } else if (delegation[0].type_ == IDelegateRegistry.DelegationType.ERC1155) {
            uint256 amount = delegateTokenInfo[delegateTokenId][uint256(StoragePositions.amount)];
            // This currently has failing invariants due to the bubbling up "specificRights" => "" rights design
            uint256 fromAmount = IDelegateRegistry(delegateRegistry).checkDelegateForERC1155(
                from, address(this), delegation[0].contract_, delegation[0].tokenId, delegation[0].rights
            ) - amount;
            uint256 toAmount = IDelegateRegistry(delegateRegistry).checkDelegateForERC1155(
                to, address(this), delegation[0].contract_, delegation[0].tokenId, delegation[0].rights
            ) + amount;
            if (fromAmount == 0) {
                IDelegateRegistry(delegateRegistry).delegateERC1155(
                    from, delegation[0].contract_, delegation[0].tokenId, fromAmount, delegation[0].rights, false
                );
            } else {
                IDelegateRegistry(delegateRegistry).delegateERC1155(
                    from, delegation[0].contract_, delegation[0].tokenId, fromAmount, delegation[0].rights, true
                );
            }
            // Requires update to registry where hash is returned
            delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)] = uint256(
                IDelegateRegistry(delegateRegistry).delegateERC1155(from, delegation[0].contract_, delegation[0].tokenId, toAmount, delegation[0].rights, true)
            );
        }
    }

    function tokenURI(uint256 delegateTokenId) public view returns (string memory) {
        // Load delegation from registry
        bytes32[] memory delegationHash = new bytes32[](1);
        delegationHash[0] = bytes32(delegateTokenInfo[delegateTokenId][uint256(StoragePositions.registryHash)]);
        IDelegateRegistry.Delegation[] memory delegation = IDelegateRegistry(delegateRegistry).getDelegationsFromHashes(delegationHash);

        // Revert if invalid
        if (delegation[0].to == address(0)) revert NotMinted();

        // When the principal token is redeemed, the delegate token is burned. So we can query this with no try-catch
        address principalTokenOwner = PrincipalToken(principalToken).ownerOf(delegateTokenId);

        return _buildTokenURI(delegation[0].contract_, delegation[0].tokenId, _readExpiry(delegateTokenId), principalTokenOwner);
    }

    function supportsInterface(bytes4 interfaceId) public pure override(ERC2981) returns (bool) {
        return interfaceId == 0x2a55205a // ERC165 Interface ID for ERC2981
            || interfaceId == 0x01ffc9a7 // ERC165 Interface ID for ERC165
            || interfaceId == 0x80ac58cd // ERC165 Interface ID for ERC721
            || interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /// @notice Deterministic function for generating a delegateId
    /// @dev Because msg.sender is fixed in addition to the freely chosen salt, addresses cannot grief each other
    /// @dev The WrapOfferer is a special case, but trivial to regenerate a unique salt via order extraData on the frontend
    function getDelegateId(TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, address creator, uint96 salt)
        public
        pure
        returns (uint256)
    {
        if (tokenAmount == 0) revert WrongAmount();
        return uint256(keccak256(abi.encode(tokenType, tokenContract, tokenId, tokenAmount, creator, salt)));
    }

    function _burnWithoutValidation(address owner, uint256 delegateId) internal {}

    ////////// Storage Write/Read Helpers ////////

    function _writeApproved(uint256 id, address approved) internal {
        uint96 expiry = uint96(delegateTokenInfo[id][uint256(StoragePositions.packedInfo)]); // Extract expiry from the lower 96 bits
        delegateTokenInfo[id][uint256(StoragePositions.packedInfo)] = (uint256(uint160(approved)) << 96) | expiry; // Pack the new approved and old expiry back into info
    }

    function _writeExpiry(uint256 id, uint256 expiry) internal {
        if (expiry > type(uint96).max) revert ExpiryTooLarge();
        address approved = address(uint160(delegateTokenInfo[id][uint256(StoragePositions.packedInfo)] >> 96)); // Extract approved from the higher 160 bits
        delegateTokenInfo[id][uint256(StoragePositions.packedInfo)] = (uint256(uint160(approved)) << 96) | expiry; // Pack the old approved and new expiry back into info
    }

    function _writeApprovedExpiry(uint256 id, address approved, uint256 expiry) internal {
        if (expiry > type(uint96).max) revert ExpiryTooLarge();
        delegateTokenInfo[id][uint256(StoragePositions.packedInfo)] = (uint256(uint160(approved)) << 96) | expiry;
    }

    function _readApproved(uint256 id) internal view returns (address approved) {
        approved = address(uint160(delegateTokenInfo[id][uint256(StoragePositions.packedInfo)] >> 96)); // Extract approved from the higher 160 bits
    }

    function _readExpiry(uint256 id) internal view returns (uint256 expiry) {
        expiry = uint96(delegateTokenInfo[id][uint256(StoragePositions.packedInfo)]); // Extract expiry from the lower 96 bits
    }

    function _readApprovedExpiry(uint256 id) internal view returns (address approved, uint256 expiry) {
        uint256 packedInfo = delegateTokenInfo[id][uint256(StoragePositions.packedInfo)];
        approved = address(uint160(packedInfo >> 96)); // Extract approved from the higher 160 bits
        expiry = uint96(packedInfo); // Extract expiry from the lower 96 bits
    }

    ////////// METADATA ////////

    function setBaseURI(string memory baseURI_) external onlyOwner {
        baseURI = baseURI_;
    }

    /// @dev Returns contract-level metadata URI for OpenSea (reference)[https://docs.opensea.io/docs/contract-level-metadata]
    function contractURI() public view returns (string memory) {
        return string.concat(baseURI, "contract");
    }

    function _buildTokenURI(address tokenContract, uint256 delegateTokenId, uint256 expiry, address principalOwner) internal view returns (string memory) {
        string memory idstr = LibString.toString(delegateTokenId);

        string memory pownerstr = principalOwner == address(0) ? "N/A" : LibString.toHexStringChecksummed(principalOwner);
        string memory status = principalOwner == address(0) || expiry <= block.timestamp ? "Expired" : "Active";

        string memory metadataStringPart1 = string.concat(
            '{"name":"Delegate Token #"',
            idstr,
            '","description":"LiquidDelegate lets you escrow your token for a chosen timeperiod and receive a liquid NFT representing the associated delegation rights. This collection represents the tokenized delegation rights.","attributes":[{"trait_type":"Collection Address","value":"',
            LibString.toHexStringChecksummed(tokenContract),
            '"},{"trait_type":"Token ID","value":"',
            idstr,
            '"},{"trait_type":"Expires At","display_type":"date","value":',
            LibString.toString(expiry)
        );
        string memory metadataStringPart2 = string.concat(
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
        string memory metadataString = string.concat(metadataStringPart1, metadataStringPart2);

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
