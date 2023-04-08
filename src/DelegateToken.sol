// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import {BaseERC721} from "./lib/BaseERC721.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {Multicallable} from "solady/utils/Multicallable.sol";
import {LDMetadataManager} from "./LDMetadataManager.sol";
import {IDelegateTokenBase, ExpiryType, Rights} from "./interfaces/IDelegateToken.sol";

import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

import {ERC721} from "solmate/tokens/ERC721.sol";
import {IDelegationRegistry} from "./interfaces/IDelegationRegistry.sol";
import {PrincipalToken} from "./PrincipalToken.sol";
import {INFTFlashBorrower} from "./interfaces/INFTFlashBorrower.sol";

contract DelegateToken is IDelegateTokenBase, BaseERC721, EIP712, Multicallable, LDMetadataManager {
    using SafeCastLib for uint256;

    /// @notice The value flash borrowers need to return from `onFlashLoan` for the call to be successful.
    bytes32 public constant FLASHLOAN_CALLBACK_MAGIC = bytes32(uint256(keccak256("LiquidDelegate.v2.onFlashLoan")) - 1);

    uint256 internal constant BASE_RIGHTS_ID_MASK = 0xffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000;
    uint256 internal constant RIGHTS_ID_NONCE_BITSIZE = 56;

    /// @dev Does not require nonce/salt as every rights ID is unique and can only be burnt once.
    bytes32 internal constant BURN_PERMIT_TYPE_HASH = keccak256("BurnPermit(uint256 rightsTokenId)");

    address public immutable override DELEGATION_REGISTRY;
    address public immutable override PRINCIPAL_TOKEN;

    mapping(uint256 => Rights) internal _idsToRights;

    constructor(
        address _DELEGATION_REGISTRY,
        address _PRINCIPAL_TOKEN,
        string memory _baseURI,
        address initialMetadataOwner
    ) BaseERC721(_name(), _symbol()) LDMetadataManager(_baseURI, initialMetadataOwner) {
        DELEGATION_REGISTRY = _DELEGATION_REGISTRY;
        PRINCIPAL_TOKEN = _PRINCIPAL_TOKEN;
    }

    /*//////////////////////////////////////////////////////////////
    /            LIQUID DELEGATE TOKEN METHODS                     /
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ERC721
     */
    function transferFrom(address from, address to, uint256 id) public override {
        super.transferFrom(from, to, id);

        uint256 baseRightsId = id & BASE_RIGHTS_ID_MASK;
        uint56 nonce = uint56(id);
        if (_idsToRights[baseRightsId].nonce == nonce) {
            Rights memory rights = _idsToRights[baseRightsId];
            IDelegationRegistry(DELEGATION_REGISTRY).delegateForToken(from, rights.tokenContract, rights.tokenId, false);
            IDelegationRegistry(DELEGATION_REGISTRY).delegateForToken(to, rights.tokenContract, rights.tokenId, true);
        }
    }

    /**
     * @notice Allows principal token owner or approved operator to borrow their underlying token for the
     * duration of a single atomic transaction.
     * @param to Recipient of borrowed token, must implement the `INFTFlashBorrower`  interface.
     * @param rightsId ID of the rights the underlying token is being borrowed from.
     * @param tokenContract Address of underlying token contract.
     * @param tokenId Token ID of underlying token to be borrowed.
     * @param data Added metadata to be relayed to borrower.
     */
    function flashLoan(address to, uint256 rightsId, address tokenContract, uint256 tokenId, bytes calldata data)
        external
    {
        if (!PrincipalToken(PRINCIPAL_TOKEN).isApprovedOrOwner(msg.sender, rightsId)) revert NotAuthorized();
        if (getBaseRightsId(tokenContract, tokenId) != rightsId & BASE_RIGHTS_ID_MASK) revert InvalidFlashloan();
        ERC721(tokenContract).transferFrom(address(this), to, tokenId);

        if (INFTFlashBorrower(to).onFlashLoan(msg.sender, tokenContract, tokenId, data) != FLASHLOAN_CALLBACK_MAGIC) {
            revert InvalidFlashloan();
        }

        // Safer and cheaper to expect the token to have been returned rather than pulling it with
        // `transferFrom`.
        if (ERC721(tokenContract).ownerOf(tokenId) != address(this)) revert InvalidFlashloan();
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
        uint256 tokenId,
        ExpiryType expiryType,
        uint256 expiryValue
    ) external returns (uint256) {
        if (ERC721(tokenContract).ownerOf(tokenId) != address(this)) revert UnderlyingMissing();
        uint40 expiry = getExpiry(expiryType, expiryValue);
        return _mint(delegateRecipient, principalRecipient, tokenContract, tokenId, expiry);
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
        uint256 tokenId,
        ExpiryType expiryType,
        uint256 expiryValue
    ) external returns (uint256) {
        ERC721(tokenContract).transferFrom(msg.sender, address(this), tokenId);
        uint40 expiry = getExpiry(expiryType, expiryValue);
        return _mint(delegateRecipient, principalRecipient, tokenContract, tokenId, expiry);
    }

    /**
     * @notice Allows the principal token owner or any approved operator to extend the expiry of the
     * delegation rights.
     * @param rightsId The ID of the rights being extended.
     * @param expiryType Whether the `expiryValue` indicates an absolute timestamp or the time to
     * expiry once the transaction is mined.
     * @param expiryValue The timestamp value by which to extend / set the expiry.
     */
    function extend(uint256 rightsId, ExpiryType expiryType, uint256 expiryValue) external {
        if (!PrincipalToken(PRINCIPAL_TOKEN).isApprovedOrOwner(msg.sender, rightsId)) revert NotAuthorized();
        uint40 newExpiry = getExpiry(expiryType, expiryValue);
        uint256 baseRightsId = rightsId & BASE_RIGHTS_ID_MASK;
        uint40 currentExpiry = _idsToRights[baseRightsId].expiry;
        if (newExpiry <= currentExpiry) revert NotExtending();
        _idsToRights[baseRightsId].expiry = newExpiry;
        emit RightsExtended(baseRightsId, uint56(rightsId), currentExpiry, newExpiry);
    }

    /**
     * @notice Allows the delegate owner or any approved operator to rescind their right early,
     * allowing the principal rights owner to redeem the underlying token early.
     * @param rightsId ID of the delegate right to be burnt.
     */
    function burn(uint256 rightsId) external {
        _burnAuth(msg.sender, rightsId);
    }

    /**
     * @notice Allows the delegate owner or any approved operator to rescind their right early
     * similar to `burn`, allowing the principal rights owner to redeem the underlying token early.
     * Spender is authenticated via their signature `sig`.
     * @param spender Address of the account approving the burn.
     * @param rightsId ID of the delegate right to be burnt.
     * @param sig Signature from `spender` approving the burn. For ECDSA signatures the expected
     * format is `abi.encodePacked(r, s, v)`. ERC-1271 signatures are also accepted.
     */
    function burnWithPermit(address spender, uint256 rightsId, bytes calldata sig) external {
        if (
            !SignatureCheckerLib.isValidSignatureNowCalldata(
                spender, _hashTypedData(keccak256(abi.encode(BURN_PERMIT_TYPE_HASH, rightsId))), sig
            )
        ) {
            revert InvalidSignature();
        }
        _burnAuth(spender, rightsId);
    }

    /**
     * @notice Allows principal rights owner or approved operator to withdraw the underlying token
     * once the delegation rights have either met their expiration or been rescinded via one of the
     * `burn`/`burnWithPermit` methods. The underlying token is sent to the address specified `to`
     * address.
     * @dev Forcefully burns the associated delegate token if still in circulation.
     * @param to Recipient of the underlying token.
     * @param nonce The nonce of the associated rights, found as the last 56-bits of the rights ID
     * or by calling `getRights(uint256)`.
     * @param tokenContract Address of underlying token contract.
     * @param tokenId Token ID of underlying token to be withdrawn.
     */
    function withdrawTo(address to, uint56 nonce, address tokenContract, uint256 tokenId) external {
        uint256 baseRightsId = getBaseRightsId(tokenContract, tokenId);
        uint256 rightsId = baseRightsId | nonce;
        PrincipalToken(PRINCIPAL_TOKEN).burnIfAuthorized(msg.sender, rightsId);

        // Check whether the delegate token still exists.
        address owner = _ownerOf[rightsId];
        if (owner != address(0)) {
            // If it still exists the only valid way to withdraw is the delegation having expired.
            if (block.timestamp < _idsToRights[baseRightsId].expiry) {
                revert WithdrawNotAvailable();
            }
            _burn(owner, rightsId);
        }
        _idsToRights[baseRightsId].nonce = nonce + 1;
        emit UnderlyingWithdrawn(baseRightsId, nonce, to);
        ERC721(tokenContract).transferFrom(address(this), to, tokenId);
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    function version() public pure returns (string memory) {
        return "1";
    }

    function baseURI() public view override(IDelegateTokenBase, LDMetadataManager) returns (string memory) {
        return LDMetadataManager.baseURI();
    }

    function tokenURI(uint256 rightsTokenId) public view override returns (string memory) {
        if (_ownerOf[rightsTokenId] == address(0)) revert NotMinted();
        Rights memory rights = _idsToRights[rightsTokenId & BASE_RIGHTS_ID_MASK];

        address principalTokenOwner;
        try PrincipalToken(PRINCIPAL_TOKEN).ownerOf(rightsTokenId) returns (address retrievedOwner) {
            principalTokenOwner = retrievedOwner;
        } catch {}

        return _buildTokenURI(rights.tokenContract, rights.tokenId, rights.expiry, principalTokenOwner);
    }

    function supportsInterface(bytes4 interfaceId) public view override(LDMetadataManager, ERC721) returns (bool) {
        return ERC721.supportsInterface(interfaceId) || LDMetadataManager.supportsInterface(interfaceId);
    }

    function getRights(address tokenContract, uint256 tokenId)
        public
        view
        returns (uint256 baseRightsId, uint256 activeRightsId, Rights memory rights)
    {
        baseRightsId = getBaseRightsId(tokenContract, tokenId);
        rights = _idsToRights[baseRightsId];
        activeRightsId = baseRightsId | rights.nonce;
        if (rights.tokenContract == address(0)) revert NoRights();
    }

    function getRights(uint256 rightsId)
        public
        view
        returns (uint256 baseRightsId, uint256 activeRightsId, Rights memory rights)
    {
        baseRightsId = rightsId & BASE_RIGHTS_ID_MASK;
        rights = _idsToRights[baseRightsId];
        activeRightsId = baseRightsId | rights.nonce;
        if (rights.tokenContract == address(0)) revert NoRights();
    }

    function getBaseRightsId(address tokenContract, uint256 tokenId) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(tokenContract, tokenId))) & BASE_RIGHTS_ID_MASK;
    }

    function getExpiry(ExpiryType expiryType, uint256 expiryValue) public view returns (uint40 expiry) {
        if (expiryType == ExpiryType.Relative) {
            expiry = (block.timestamp + expiryValue).toUint40();
        } else if (expiryType == ExpiryType.Absolute) {
            expiry = expiryValue.toUint40();
        } else {
            revert InvalidExpiryType();
        }
        if (expiry <= block.timestamp) revert ExpiryTimeNotInFuture();
    }

    function _mint(
        address delegateRecipient,
        address principalRecipient,
        address tokenContract,
        uint256 tokenId,
        uint40 expiry
    ) internal returns (uint256 rightsId) {
        uint256 baseRightsId = getBaseRightsId(tokenContract, tokenId);
        Rights storage rights = _idsToRights[baseRightsId];
        uint56 nonce = rights.nonce;
        rightsId = baseRightsId | nonce;

        if (nonce == 0) {
            // First time rights for this token are set up, store everything.
            _idsToRights[baseRightsId] =
                Rights({tokenContract: tokenContract, expiry: uint40(expiry), nonce: 0, tokenId: tokenId});
        } else {
            // Rights already used once, so only need to update expiry.
            rights.expiry = uint40(expiry);
        }

        _mint(delegateRecipient, rightsId);
        IDelegationRegistry(DELEGATION_REGISTRY).delegateForToken(
            delegateRecipient, rights.tokenContract, rights.tokenId, true
        );

        PrincipalToken(PRINCIPAL_TOKEN).mint(principalRecipient, rightsId);

        emit RightsCreated(baseRightsId, nonce, expiry);
    }

    function _burnAuth(address spender, uint256 rightsId) internal {
        (bool approvedOrOwner, address owner) = _isApprovedOrOwner(spender, rightsId);
        if (!approvedOrOwner) revert NotAuthorized();
        _burn(owner, rightsId);
    }

    function _burn(address owner, uint256 rightsId) internal {
        uint256 baseRightsId = rightsId & BASE_RIGHTS_ID_MASK;
        uint56 nonce = uint56(rightsId);

        Rights memory rights = _idsToRights[baseRightsId];
        IDelegationRegistry(DELEGATION_REGISTRY).delegateForToken(owner, rights.tokenContract, rights.tokenId, false);

        _burn(rightsId);
        emit RightsBurned(baseRightsId, nonce);
    }

    function _domainNameAndVersion() internal pure override returns (string memory, string memory) {
        return (_name(), version());
    }
}
