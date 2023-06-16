// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IDelegateTokenBase, ExpiryType, ViewRights, TokenType} from "./interfaces/IDelegateToken.sol";
import {INFTFlashBorrower} from "./interfaces/INFTFlashBorrower.sol";

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/IERC1155.sol";

import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

import {BaseERC721, ERC721} from "./BaseERC721.sol";
import {PrincipalToken} from "./PrincipalToken.sol";

import {EIP712} from "solady/utils/EIP712.sol";

import {ERC2981} from "openzeppelin-contracts/contracts/token/common/ERC2981.sol";
import {Owned} from "solmate/auth/Owned.sol";

import {LibString} from "solady/utils/LibString.sol";
import {Base64} from "solady/utils/Base64.sol";

contract DelegateToken is IDelegateTokenBase, BaseERC721, EIP712, ERC2981, Owned {
    using LibString for address;
    using LibString for uint256;

    /// @notice The value flash borrowers need to return from `onFlashLoan` for the call to be successful.
    bytes32 public constant FLASHLOAN_CALLBACK_SUCCESS = bytes32(uint256(keccak256("INFTFlashBorrower.onFlashLoan")) - 1);

    uint256 internal constant BASE_RIGHTS_ID_MASK = 0xffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000;
    uint256 internal constant RIGHTS_ID_NONCE_BITSIZE = 56;

    /// @dev Does not require nonce/salt as every rights ID is unique and can only be burnt once.
    bytes32 internal constant BURN_PERMIT_TYPE_HASH = keccak256("BurnPermit(uint256 rightsTokenId)");

    address public immutable override DELEGATION_REGISTRY;
    address public immutable override PRINCIPAL_TOKEN;

    mapping(uint256 delegateId => uint256[3] rights) internal _rights;

    string internal _baseURI;

    error InvalidTokenType();

    enum StoragePositions {
        info, // PACKED (address tokenContract, uint40 expiry, uint56 nonce)
        tokenId,
        amount
    }

    function _writeRightsInfo(uint256 baseDelegateId, uint256 expiry, uint256 nonce, address tokenContract) internal {
        if (expiry > type(uint40).max) revert ExpiryTooLarge();
        if (nonce > type(uint56).max) revert NonceTooLarge();
        _rights[baseDelegateId][uint256(StoragePositions.info)] = ((uint256(uint160(tokenContract)) << 96) | (expiry << 56) | (nonce));
    }

    function _readRightsInfo(uint256 baseDelegateId) internal view returns (uint256 expiry, uint256 nonce, address tokenContract) {
        uint256 info = _rights[baseDelegateId][uint256(StoragePositions.info)];
        tokenContract = address(uint160((info >> 96)));
        expiry = uint40(info << 160 >> 216);
        nonce = uint56(info << 200 >> 200);
    }

    constructor(address _DELEGATION_REGISTRY, address _PRINCIPAL_TOKEN, string memory __baseURI, address initialMetadataOwner)
        BaseERC721(_name(), _symbol())
        Owned(initialMetadataOwner)
    {
        DELEGATION_REGISTRY = _DELEGATION_REGISTRY;
        PRINCIPAL_TOKEN = _PRINCIPAL_TOKEN;
        _baseURI = __baseURI;
    }

    /*//////////////////////////////////////////////////////////////
    /            LIQUID DELEGATE TOKEN METHODS                     /
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ERC721
     */
    function transferFrom(address from, address to, uint256 id) public override {
        super.transferFrom(from, to, id);

        uint256 baseDelegateId = id & BASE_RIGHTS_ID_MASK;
        // uint256 nonce = uint56(id);
        // Load info from storage
        (, uint256 nonce, address tokenContract) = _readRightsInfo(baseDelegateId);
        if (nonce == uint56(id)) {
            uint256 tokenId = _rights[baseDelegateId][uint256(StoragePositions.tokenId)];
            IDelegateRegistry(DELEGATION_REGISTRY).delegateERC721(from, tokenContract, tokenId, "", false);
            IDelegateRegistry(DELEGATION_REGISTRY).delegateERC721(to, tokenContract, tokenId, "", true);
        }
    }

    /**
     * @notice Allows delegate token owner or approved operator to borrow their underlying token for the
     * duration of a single atomic transaction
     * @param receiver Recipient of borrowed token, must implement the `INFTFlashBorrower` interface
     * @param delegateId ID of the rights the underlying token is being borrowed from
     * @param tokenContract Address of underlying token contract
     * @param tokenId Token ID of underlying token to be borrowed
     * @param data Added metadata to be relayed to borrower
     */
    function flashLoan(address receiver, uint256 delegateId, address tokenContract, uint256 tokenId, bytes calldata data) external payable {
        if (!isApprovedOrOwner(msg.sender, delegateId)) revert NotAuthorized();
        if (getBaseDelegateId(TokenType.ERC721, tokenContract, tokenId, 0) != delegateId & BASE_RIGHTS_ID_MASK) revert InvalidFlashloan();
        IERC721(tokenContract).transferFrom(address(this), receiver, tokenId);

        if (INFTFlashBorrower(receiver).onFlashLoan{value: msg.value}(msg.sender, tokenContract, tokenId, data) != FLASHLOAN_CALLBACK_SUCCESS) {
            revert InvalidFlashloan();
        }

        // Safer and cheaper to expect the token to have been returned rather than pulling it with `transferFrom`.
        if (IERC721(tokenContract).ownerOf(tokenId) != address(this)) revert InvalidFlashloan();
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
        address tokenContract,
        TokenType tokenType,
        uint256 tokenId,
        uint256 tokenAmount,
        ExpiryType expiryType,
        uint256 expiryValue
    ) external payable returns (uint256) {
        if (tokenType == TokenType.ERC721) {
            if (IERC721(tokenContract).ownerOf(tokenId) != address(this)) revert UnderlyingMissing();
        } else {
            revert InvalidTokenType();
        }        
        uint256 expiry = getExpiry(expiryType, expiryValue);
        return _mint(delegateRecipient, principalRecipient, tokenType, tokenContract, tokenId, tokenAmount, expiry);
    }

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
        address tokenContract,
        TokenType tokenType,
        uint256 tokenId,
        uint256 tokenAmount,
        ExpiryType expiryType,
        uint256 expiryValue
    ) external payable returns (uint256) {
        if (tokenType == TokenType.ERC721) {
            IERC721(tokenContract).transferFrom(msg.sender, address(this), tokenId);
            tokenAmount = 0;
        } else if (tokenType == TokenType.ERC20) {
            // TODO: Handle nonstandard tokens like USDT and BNB
            IERC20(tokenContract).transferFrom(msg.sender, address(this), tokenAmount);
            tokenId = 0;
        } else if (tokenType == TokenType.ERC1155) {
            IERC1155(tokenContract).safeTransferFrom(msg.sender, address(this), tokenId, tokenAmount);
        }
        uint256 expiry = getExpiry(expiryType, expiryValue);
        return _mint(delegateRecipient, principalRecipient, tokenType, tokenContract, tokenId, tokenAmount, expiry);
    }

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
        uint256 baseDelegateId = delegateId & BASE_RIGHTS_ID_MASK;
        (uint256 currentExpiry, uint256 nonce, address tokenContract) = _readRightsInfo(baseDelegateId);
        if (newExpiry <= currentExpiry) revert NotExtending();
        _writeRightsInfo(delegateId, newExpiry, nonce, tokenContract);
        emit RightsExtended(baseDelegateId, delegateId, currentExpiry, newExpiry);
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
     * @notice Allows the delegate owner or any approved operator to rescind their right early
     * similar to `burn`, allowing the principal rights owner to redeem the underlying token early.
     * Spender is authenticated via their signature `sig`.
     * @param spender Address of the account approving the burn.
     * @param delegateId ID of the delegate right to be burnt.
     * @param sig Signature from `spender` approving the burn. For ECDSA signatures the expected
     * format is `abi.encodePacked(r, s, v)`. ERC-1271 signatures are also accepted.
     */
    function burnWithPermit(address spender, uint256 delegateId, bytes calldata sig) external {
        if (!SignatureCheckerLib.isValidSignatureNowCalldata(spender, _hashTypedData(keccak256(abi.encode(BURN_PERMIT_TYPE_HASH, delegateId))), sig)) {
            revert InvalidSignature();
        }
        _burnAuth(spender, delegateId);
    }

    /**
     * @notice Allows principal rights owner or approved operator to withdraw the underlying token
     * once the delegation rights have either met their expiration or been rescinded via one of the
     * `burn`/`burnWithPermit` methods. The underlying token is sent to the address specified `to`
     * address.
     * @dev Forcefully burns the associated delegate token if still in circulation.
     * @param to Recipient of the underlying token.
     * @param tokenContract Address of underlying token contract.
     * @param tokenId Token ID of underlying token to be withdrawn.
     */
    function withdrawTo(address to, address tokenContract, uint256 tokenId) external {
        uint256 baseDelegateId = getBaseDelegateId(tokenContract, tokenId);
        (uint256 expiry, uint256 nonce,) = _readRightsInfo(baseDelegateId);
        uint256 delegateId = baseDelegateId | nonce;
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
        _writeRightsInfo(baseDelegateId, expiry, nonce + 1, tokenContract);
        emit UnderlyingWithdrawn(baseDelegateId, uint56(nonce), to);
        IERC721(tokenContract).transferFrom(address(this), to, tokenId);
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    function version() public pure returns (string memory) {
        return "1";
    }

    function baseURI() public view override(IDelegateTokenBase) returns (string memory) {
        return _baseURI;
    }

    function tokenURI(uint256 rightsTokenId) public view override returns (string memory) {
        if (_ownerOf[rightsTokenId] == address(0)) revert NotMinted();

        // When the principal token is redeemed, the delegate token is burned. So we can query this with no try-catch
        address principalTokenOwner = PrincipalToken(PRINCIPAL_TOKEN).ownerOf(rightsTokenId);

        uint256 baseDelegateId = rightsTokenId & BASE_RIGHTS_ID_MASK;
        // Load info
        (uint256 expiry,, address tokenContract) = _readRightsInfo(baseDelegateId);

        return _buildTokenURI(tokenContract, _rights[baseDelegateId][uint256(StoragePositions.tokenId)], expiry, principalTokenOwner);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        // TODO: Hardcode these
        return false;
    }

    function getRights(address tokenContract_, uint256 tokenId)
        public
        view
        returns (uint256 baseDelegateId, uint256 activeDelegateId, ViewRights memory rights)
    {
        baseDelegateId = getBaseDelegateId(tokenContract_, tokenId);
        (uint256 expiry, uint256 nonce, address tokenContract) = _readRightsInfo(baseDelegateId);
        rights = ViewRights({tokenContract: tokenContract, expiry: expiry, nonce: nonce, tokenId: _rights[baseDelegateId][uint256(StoragePositions.tokenId)]});
        activeDelegateId = baseDelegateId | nonce;
        if (tokenContract == address(0)) revert NoRights();
    }

    function getRights(uint256 delegateId) public view returns (uint256 baseDelegateId, uint256 activeDelegateId, ViewRights memory rights) {
        baseDelegateId = delegateId & BASE_RIGHTS_ID_MASK;
        (uint256 expiry, uint256 nonce, address tokenContract) = _readRightsInfo(baseDelegateId);
        rights = ViewRights({tokenContract: tokenContract, expiry: expiry, nonce: nonce, tokenId: _rights[baseDelegateId][uint256(StoragePositions.tokenId)]});
        activeDelegateId = baseDelegateId | nonce;
        if (tokenContract == address(0)) revert NoRights();
    }

    function getBaseDelegateId(TokenType tokenType, address tokenContract, uint256 tokenId, uint256 tokenAmount) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(tokenType, tokenContract, tokenId, tokenAmount))) & BASE_RIGHTS_ID_MASK;
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

    function _mint(address delegateRecipient, address principalRecipient, TokenType tokenType, address tokenContract_, uint256 tokenId_, uint256 amount, uint256 expiry_)
        internal
        returns (uint256 delegateId)
    {
        uint256 baseDelegateId = getBaseDelegateId(tokenType, tokenContract_, tokenId_, tokenAmount);
        (, uint256 nonce,) = _readRightsInfo(baseDelegateId);
        delegateId = baseDelegateId | nonce;

        if (nonce == 0) {
            // First time rights for this token are set up, store everything.
            _writeRightsInfo(baseDelegateId, expiry_, nonce, tokenContract_);
            _rights[baseDelegateId][uint256(StoragePositions.tokenId)] = tokenId_;
        } else {
            // Rights already used once, so only need to update expiry.
            _writeRightsInfo(baseDelegateId, expiry_, nonce, tokenContract_);
        }

        _mint(delegateRecipient, delegateId);
        IDelegateRegistry(DELEGATION_REGISTRY).delegateERC721(delegateRecipient, tokenContract_, tokenId_, "", true);

        PrincipalToken(PRINCIPAL_TOKEN).mint(principalRecipient, delegateId);

        emit RightsCreated(baseDelegateId, uint56(nonce), expiry_);
    }

    function _burnAuth(address spender, uint256 delegateId) internal {
        (,, ViewRights memory rights) = getRights(delegateId);
        uint256 expiry = rights.expiry;
        (bool approvedOrOwner, address owner) = _isApprovedOrOwner(spender, delegateId);
        if (block.timestamp >= expiry || approvedOrOwner) {
            _burn(owner, delegateId);
        } else {
            revert NotAuthorized();
        }
    }

    function _burn(address owner, uint256 delegateId) internal {
        uint256 baseDelegateId = delegateId & BASE_RIGHTS_ID_MASK;
        uint56 nonce = uint56(delegateId);

        (,, address tokenContract) = _readRightsInfo(baseDelegateId);
        IDelegateRegistry(DELEGATION_REGISTRY).delegateERC721(owner, tokenContract, _rights[baseDelegateId][uint256(StoragePositions.tokenId)], "", false);

        _burn(delegateId);
        emit RightsBurned(baseDelegateId, nonce);
    }

    /// DTMetadataManager stuff here

    function _domainNameAndVersion() internal pure override returns (string memory, string memory) {
        return (_name(), version());
    }

    function _name() internal pure virtual returns (string memory) {
        return "Delegate Token";
    }

    function _symbol() internal pure virtual returns (string memory) {
        return "DT";
    }

    function setBaseURI(string memory baseURI_) external onlyOwner {
        _baseURI = baseURI_;
    }

    /// @dev Returns contract-level metadata URI for OpenSea (reference)[https://docs.opensea.io/docs/contract-level-metadata]
    function contractURI() public view returns (string memory) {
        return string.concat(_baseURI, "contract");
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
            _baseURI,
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
