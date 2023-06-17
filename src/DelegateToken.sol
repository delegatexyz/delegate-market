// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IDelegateTokenBase, ExpiryType, TokenType} from "./interfaces/IDelegateToken.sol";
import {INFTFlashBorrower} from "./interfaces/INFTFlashBorrower.sol";

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";
import {ERC2981} from "openzeppelin-contracts/contracts/token/common/ERC2981.sol";

import {BaseERC721, ERC721} from "./BaseERC721.sol";
import {PrincipalToken} from "./PrincipalToken.sol";

import {Base64} from "solady/utils/Base64.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Owned} from "solmate/auth/Owned.sol";

/**
 * delegateId needs to be deterministic. hash(tokentype, contractaddress, tokenid, amount, creatoraddress, nonce)
 * that points to the data being stored
 * and we also prevent delegateId reuse with a simple boolean set membership lookup
 */

contract DelegateToken is IDelegateTokenBase, BaseERC721, EIP712, ERC2981, Owned {
    using LibString for address;
    using LibString for uint256;

    /// @notice The value flash borrowers need to return from `onFlashLoan` for the call to be successful.
    bytes32 public constant FLASHLOAN_CALLBACK_SUCCESS = bytes32(uint256(keccak256("INFTFlashBorrower.onFlashLoan")) - 1);

    /// @dev Does not require nonce/salt as every rights ID is unique and can only be burnt once.
    bytes32 internal constant BURN_PERMIT_TYPE_HASH = keccak256("BurnPermit(uint256 rightsTokenId)");

    /// @notice The v2 delegate registry
    address public immutable override DELEGATE_REGISTRY;

    /// @notice The principal token deployed in tandem with this delegate token
    address public immutable override PRINCIPAL_TOKEN;

    /// @notice Image metadata location, but attributes are stored onchain
    string public baseURI;

    /// @dev delegateId, a hash of (tokenType, tokenContract, tokenId, tokenAmount, creator, nonce), points a unique id to the StoragePosition
    mapping(uint256 delegateId => uint256[3] delegateInfo) public rights;

    /// @dev Store all previously created delegateIds to prevent double-creation and griefing
    mapping(uint256 delegateId => bool used) internal _used;

    // TODO: do we need to store the nonce? just used for creating delegateId
    enum StoragePositions {
        info, // PACKED (address tokenContract, uint40 expiry, uint48 nonce, uint8 tokenType)
        tokenId,
        amount
    }

    constructor(address _DELEGATE_REGISTRY, address _PRINCIPAL_TOKEN, string memory baseURI_, address initialMetadataOwner)
        BaseERC721(_name(), _symbol())
        Owned(initialMetadataOwner)
    {
        DELEGATE_REGISTRY = _DELEGATE_REGISTRY;
        PRINCIPAL_TOKEN = _PRINCIPAL_TOKEN;
        baseURI = baseURI_;
    }

    /*//////////////////////////////////////////////////////////////
    /            LIQUID DELEGATE TOKEN METHODS                     /
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create rights token pair pulling underlying token from caller.
     * @param delegateRecipient Recipient of delegate rights token.
     * @param principalRecipient Recipient of principal rights token.
     * @param tokenContract Address of underlying token contract.
     * @param tokenId Token ID of underlying token to be escrowed.
     * @param expiryType Whether the `expiryValue` indicates an absolute timestamp or the time to
     * expiry once the transaction is mined.
     * @param expiryValue The timestamp of the expiry, relative/absolute according to `expiryType`.
     * @return New rights ID that is also the token ID of both the newly created principal and
     * delegate tokens.
     */
    function create(
        address delegateRecipient,
        address principalRecipient,
        TokenType tokenType,
        address tokenContract,
        uint256 tokenId,
        uint256 tokenAmount,
        ExpiryType expiryType,
        uint256 expiryValue,
        uint96 nonce
    ) external payable returns (uint256) {
        if (tokenType == TokenType.ERC721) {
            IERC721(tokenContract).transferFrom(msg.sender, address(this), tokenId);
            tokenAmount = 0;
        } else if (tokenType == TokenType.ERC20) {
            // TODO: Handle nonstandard tokens like USDT and BNB
            IERC20(tokenContract).transferFrom(msg.sender, address(this), tokenAmount);
            tokenId = 0;
        } else if (tokenType == TokenType.ERC1155) {
            IERC1155(tokenContract).safeTransferFrom(msg.sender, address(this), tokenId, tokenAmount, "");
        }
        uint256 expiry = getExpiry(expiryType, expiryValue);
        return _create(delegateRecipient, principalRecipient, tokenType, tokenContract, tokenId, tokenAmount, expiry, nonce);
    }

    /**
     * @notice Creates rights token pair if token has already been deposited. **Do not** attempt to use as normal wallet.
     * @param delegateRecipient Recipient of delegate rights token
     * @param principalRecipient Recipient of principal rights token
     * @param tokenContract Address of underlying token contract
     * @param tokenId Token ID of underlying token to be escrowed
     * @param expiryType Whether the `expiryValue` indicates an absolute timestamp or the time to
     * expiry once the transaction is mined
     * @param expiryValue The timestamp value relative/absolute according to `expiryType`
     * @return New rights ID that is also the token ID of both the newly created principal and
     * delegate tokens.
     */
    function createUnprotected(
        address delegateRecipient,
        address principalRecipient,
        TokenType tokenType,
        address tokenContract,
        uint256 tokenId,
        uint256 tokenAmount,
        ExpiryType expiryType,
        uint256 expiryValue,
        uint96 nonce
    ) external payable returns (uint256) {}

    /**
     * @notice Allows the principal token owner or any approved operator to extend the expiry of the
     * delegation rights.
     * @param delegateId The ID of the rights being extended.
     * @param expiryType Whether the `expiryValue` indicates an absolute timestamp or the time to
     * expiry once the transaction is mined.
     * @param expiryValue The timestamp value by which to extend / set the expiry.
     */
    function extend(uint256 delegateId, ExpiryType expiryType, uint256 expiryValue) external {
        if (!PrincipalToken(PRINCIPAL_TOKEN).isApprovedOrOwner(msg.sender, delegateId)) revert NotAuthorized();
        uint256 newExpiry = getExpiry(expiryType, expiryValue);
        (TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, uint256 currentExpiry, uint256 nonce) = getRightsInfo(delegateId);
        if (newExpiry <= currentExpiry) revert NotExtending();
        _writeRightsInfo(delegateId, tokenType, tokenContract, tokenId, tokenAmount, newExpiry, nonce);
    }

    /**
     * @notice Allows the delegate owner or any approved operator to rescind their right early,
     * allowing the principal rights owner to redeem the underlying token early.
     * @param delegateId ID of the delegate right to be burnt.
     */
    function burn(uint256 delegateId) external {
        _burnAuth(msg.sender, delegateId);
    }

    /**
     * @notice Allows principal rights owner or approved operator to withdraw the underlying token
     * once the delegation rights have either met their expiration or been rescinded via one of the
     * `burn`/`burnWithPermit` methods. The underlying token is sent to the address specified `to`
     * address.
     * @dev Forcefully burns the associated delegate token if still in circulation.
     * @param to Recipient of the underlying token.
     * @param delegateId ID of the delegate right to be withdrawn.
     */
    function withdrawTo(address to, uint256 delegateId) external {
        (TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, uint256 expiry, uint256 nonce) = getRightsInfo(delegateId);
        PrincipalToken(PRINCIPAL_TOKEN).burnIfAuthorized(msg.sender, delegateId);

        // Check whether the delegate token still exists.
        address owner = _ownerOf[delegateId];
        if (owner != address(0)) {
            // If it still exists the only valid way to withdraw is the delegation having expired.
            if (block.timestamp < expiry && owner != msg.sender) {
                revert WithdrawNotAvailable();
            }
            _burn(owner, delegateId);
        }
        // TODO: Should we clear old data when withdrawing?
        _writeRightsInfo(delegateId, tokenType, tokenContract, tokenId, tokenAmount, expiry, nonce);
        IERC721(tokenContract).transferFrom(address(this), to, tokenId);
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
        (TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, uint256 expiry, uint256 nonce) = getRightsInfo(delegateId);
        // TODO: Check delegateId not expired
        IERC721(tokenContract).transferFrom(address(this), receiver, tokenId);

        if (INFTFlashBorrower(receiver).onFlashLoan{value: msg.value}(msg.sender, tokenContract, tokenId, data) != FLASHLOAN_CALLBACK_SUCCESS) {
            revert InvalidFlashloan();
        }

        // Safer and cheaper to expect the token to have been returned rather than pulling it with `transferFrom`.
        if (IERC721(tokenContract).ownerOf(tokenId) != address(this)) revert InvalidFlashloan();
    }

    /**
     * @inheritdoc BaseERC721
     */
    function transferFrom(address from, address to, uint256 id) public override {
        super.transferFrom(from, to, id);

        // Load info from storage
        (TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, uint256 expiry, uint256 nonce) = getRightsInfo(id);
        if (nonce == uint56(id)) {
            IDelegateRegistry(DELEGATE_REGISTRY).delegateERC721(from, tokenContract, tokenId, "", false);
            IDelegateRegistry(DELEGATE_REGISTRY).delegateERC721(to, tokenContract, tokenId, "", true);
        }
    }

    /// INTERNAL STORAGE HELPERS

    function _writeRightsInfo(
        uint256 delegateId,
        TokenType tokenType,
        address tokenContract,
        uint256 tokenId,
        uint256 tokenAmount,
        uint256 expiry,
        uint256 nonce
    ) internal {
        if (expiry > type(uint40).max) revert ExpiryTooLarge();
        if (nonce > type(uint48).max) revert NonceTooLarge();
        rights[delegateId][uint256(StoragePositions.info)] = (uint256(uint160(tokenContract)) << 96) | (expiry << 56) | (nonce << 48) | (uint256(tokenType));
        rights[delegateId][uint256(StoragePositions.tokenId)] = tokenId;
        rights[delegateId][uint256(StoragePositions.amount)] = tokenAmount;
    }

    function getRightsInfo(uint256 delegateId)
        public
        view
        returns (TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, uint256 expiry, uint256 nonce)
    {
        uint256 info = rights[delegateId][uint256(StoragePositions.info)];
        tokenContract = address(uint160((info >> 96)));
        expiry = uint40(info << 160 >> 216);
        nonce = uint56(info << 200 >> 208);
        // TODO: double-check this bitshift
        tokenType = TokenType(uint8(info << 248 >> 248));
        tokenId = rights[delegateId][uint256(StoragePositions.tokenId)];
        tokenAmount = rights[delegateId][uint256(StoragePositions.amount)];
    }

    function tokenURI(uint256 delegateId) public view override returns (string memory) {
        if (_ownerOf[delegateId] == address(0)) revert NotMinted();

        // When the principal token is redeemed, the delegate token is burned. So we can query this with no try-catch
        address principalTokenOwner = PrincipalToken(PRINCIPAL_TOKEN).ownerOf(delegateId);

        // Load info
        (TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, uint256 expiry, uint256 nonce) = getRightsInfo(delegateId);

        return _buildTokenURI(tokenContract, rights[delegateId][uint256(StoragePositions.tokenId)], expiry, principalTokenOwner);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        // TODO: Hardcode these
        return false;
    }

    function getDelegateId(TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, address creator, uint96 nonce)
        public
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(tokenType, tokenContract, tokenId, tokenAmount, creator, nonce)));
    }

    function getExpiry(ExpiryType expiryType, uint256 expiryValue) public view returns (uint256 expiry) {
        if (expiryType == ExpiryType.RELATIVE) {
            expiry = block.timestamp + expiryValue;
        } else if (expiryType == ExpiryType.ABSOLUTE) {
            expiry = expiryValue;
        } else {
            revert InvalidExpiryType();
        }
        if (expiry <= block.timestamp) revert ExpiryTimeNotInFuture();
        if (expiry > type(uint40).max) revert ExpiryTooLarge();
    }

    function _create(
        address delegateRecipient,
        address principalRecipient,
        TokenType tokenType,
        address tokenContract_,
        uint256 tokenId_,
        uint256 tokenAmount_,
        uint256 expiry_,
        uint96 nonce
    ) internal returns (uint256 delegateId) {
        delegateId = getDelegateId(tokenType, tokenContract_, tokenId_, tokenAmount_, msg.sender, nonce);
        _writeRightsInfo(delegateId, tokenType, tokenContract_, tokenId_, tokenAmount_, expiry_, nonce);

        _mint(delegateRecipient, delegateId);
        if (tokenType == TokenType.ERC721) {
            IDelegateRegistry(DELEGATE_REGISTRY).delegateERC721(delegateRecipient, tokenContract_, tokenId_, "", true);
        } else if (tokenType == TokenType.ERC20) {
            if (tokenAmount_ == 0) revert ZeroAmount();
            IDelegateRegistry(DELEGATE_REGISTRY).delegateERC20(delegateRecipient, tokenContract_, tokenAmount_, "", true);
        } else if (tokenType == TokenType.ERC1155) {
            if (tokenAmount_ == 0) revert ZeroAmount();
            IDelegateRegistry(DELEGATE_REGISTRY).delegateERC1155(delegateRecipient, tokenContract_, tokenId_, tokenAmount_, "", true);
        } else {
            revert InvalidTokenType();
        }

        PrincipalToken(PRINCIPAL_TOKEN).mint(principalRecipient, delegateId);
    }

    function _burnAuth(address spender, uint256 delegateId) internal {
        (TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, uint256 expiry, uint256 nonce) = getRightsInfo(delegateId);
        (bool approvedOrOwner, address owner) = _isApprovedOrOwner(spender, delegateId);
        if (block.timestamp >= expiry || approvedOrOwner) {
            _burn(owner, delegateId);
        } else {
            revert NotAuthorized();
        }
    }

    function _burn(address owner, uint256 delegateId) internal {
        (TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount, uint256 expiry, uint256 nonce) = getRightsInfo(delegateId);
        IDelegateRegistry(DELEGATE_REGISTRY).delegateERC721(owner, tokenContract, rights[delegateId][uint256(StoragePositions.tokenId)], "", false);

        _burn(delegateId);
    }

    /// DTMetadataManager stuff here

    /// EIP712 INFO HELPERS

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    function _domainNameAndVersion() internal pure override returns (string memory, string memory) {
        return (_name(), version());
    }

    function _name() internal pure virtual returns (string memory) {
        return "Delegate Token";
    }

    function _symbol() internal pure virtual returns (string memory) {
        return "DT";
    }

    function version() public pure returns (string memory) {
        return "1";
    }

    function setBaseURI(string memory baseURI_) external onlyOwner {
        baseURI = baseURI_;
    }

    /// @dev Returns contract-level metadata URI for OpenSea (reference)[https://docs.opensea.io/docs/contract-level-metadata]
    function contractURI() public view returns (string memory) {
        return string.concat(baseURI, "contract");
    }

    function _buildTokenURI(address tokenContract, uint256 id, uint256 expiry, address principalOwner) internal view returns (string memory) {
        string memory idstr = id.toString();

        string memory pownerstr = principalOwner == address(0) ? "N/A" : principalOwner.toHexStringChecksummed();
        string memory status = principalOwner == address(0) || expiry <= block.timestamp ? "Expired" : "Active";

        string memory metadataStringPart1 = string.concat(
            '{"name":"',
            _name(),
            " #",
            idstr,
            '","description":"LiquidDelegate lets you escrow your token for a chosen timeperiod and receive a liquid NFT representing the associated delegation rights. This collection represents the tokenized delegation rights.","attributes":[{"trait_type":"Collection Address","value":"',
            tokenContract.toHexStringChecksummed(),
            '"},{"trait_type":"Token ID","value":"',
            idstr,
            '"},{"trait_type":"Expires At","display_type":"date","value":',
            expiry.toString()
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
