// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {ERC2981} from "openzeppelin-contracts/contracts/token/common/ERC2981.sol";
import {Base64} from "openzeppelin-contracts/contracts/utils/Base64.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {INFTFlashBorrower} from "./interfaces/INFTFlashBorrower.sol";
import {INFTFlashLender} from "./interfaces/INFTFlashLender.sol";

/**
 * DONE:
 * let people modify the date to later if they are the creator
 * custom errors instead of require strings
 * remove creation fee altogether
 * make flashloan payable
 * TODO:
 * easier royalty sharing for third parties, ERC2981 specifies a single receiver
 * batch creation, be careful to avoid people paying themselves in things that should be gated. create, extend, burn, transfer
 * let people silo licensing rights and sell two different rights to two different accounts
 * add creation time for easy staking composability (and liquid staking extensions)
 * enumerate all the LDs owned by a specific individual?
 * deterministic IDs based on keccak(contractAddress, tokenId)?
 */

/**
 * Escrow should be pushed out as long as possible, because that's expensive. Want deep seller liquidity.
 * Should also let people list onchain, combine them.
 */

/**
 * @title LiquidDelegate
 * @custom:version 2.0
 * @custom:author foobar (0xfoobar)
 * @notice An ERC721 that lets users tokenize their delegation rights so they're composable & transferrable
 */
contract LiquidDelegate is ERC721, ERC2981, INFTFlashLender {
    using Strings for uint256;
    using Strings for address;

    /// @notice The expected return value from flashloan borrowers
    bytes32 public constant CALLBACK_SUCCESS = keccak256("INFTFlashBorrower.onFlashLoan");

    /// @notice The delegate.cash contract
    address public immutable DELEGATION_REGISTRY;

    struct Rights {
        address depositor;
        uint96 expiration;
        address contract_;
        uint256 tokenId;
        uint256 amount;
        address referrer;
    }

    /// @notice A mapping pointing NFT ids to Rights structs
    mapping(uint256 => Rights) public idsToRights;

    /// @notice An incrementing counter to create unique ids for each escrow deposit created
    uint256 public nextLiquidDelegateId = 1;

    /// @notice The address which can modify royalties
    address internal royaltyOwner;

    /// @notice The address which can modify metadata images
    address internal metadataOwner;

    /// @notice The URI that serves metadata images
    string internal baseURI;

    /// @notice Emitted on each deposit creation
    event RightsCreated(uint256 indexed liquidDelegateId, address indexed depositor, address indexed contract_, uint256 tokenId, uint256 expiration);

    /// @notice Emitted on each deposit burning
    event RightsBurned(uint256 indexed liquidDelegateId, address indexed depositor, address indexed contract_, uint256 tokenId, uint256 expiration);

    error AccessControl();
    error InvalidBurn();
    error InvalidExtension();
    error InvalidFlashLoan();
    error LiquidDelegateExpired();
    error SendEtherFailed();
    error WrongFee();

    constructor(address _DELEGATION_REGISTRY, address _owner, string memory _baseURI) ERC721("LiquidDelegate", "RIGHTS") {
        DELEGATION_REGISTRY = _DELEGATION_REGISTRY;
        baseURI = _baseURI;
        metadataOwner = _owner;
        royaltyOwner = _owner;
        _setDefaultRoyalty(_owner, 1000);
    }

    /// @dev See {IERC165-supportsInterface}.
    function supportsInterface(bytes4 interfaceId) public pure override(ERC721, ERC2981) returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165 Interface ID for ERC165
            || interfaceId == 0x80ac58cd // ERC165 Interface ID for ERC721
            || interfaceId == 0x5b5e139f // ERC165 Interface ID for ERC721Metadata
            || interfaceId == 0x2a55205a; // ERC165 Interface ID for ERC2981
    }

    /**
     * ----------- DEPOSIT CREATION AND BURN -----------
     */

    /// @notice Use this to deposit a timelocked escrow and create a liquid claim on its delegation rights
    /// @dev Creation fee is not enforced to save gas, however the main frontend can add a small fee to the payable function
    /// @param contract_ The collection contract to deposit from
    /// @param tokenId The tokenId from the collection to deposit
    /// @param expiration The timestamp that the liquid delegate will expire and return the escrowed NFT
    /// @param referrer Set to the zero address by default, alternate frontends can populate this to receive half the creation fee
    function create(address contract_, uint256 tokenId, uint96 expiration, address payable referrer) external payable {
        ERC721(contract_).transferFrom(msg.sender, address(this), tokenId);
        idsToRights[nextLiquidDelegateId] =
            Rights({depositor: msg.sender, contract_: contract_, tokenId: tokenId, amount: 0, expiration: expiration, referrer: referrer});
        _mint(msg.sender, nextLiquidDelegateId);
        emit RightsCreated(nextLiquidDelegateId++, msg.sender, contract_, tokenId, expiration);
    }

    /// @notice Burn delegation rights and return escrowed NFT to owner
    /// @dev Can be triggered by the owner at any time, or anyone after deposit expiry
    /// @param liquidDelegateId The id of the liquid delegate to burn
    function burn(uint256 liquidDelegateId) external {
        Rights memory rights = idsToRights[liquidDelegateId];
        if (!(ownerOf(liquidDelegateId) == msg.sender || block.timestamp >= rights.expiration)) {
            revert InvalidBurn();
        }
        _burn(liquidDelegateId);
        ERC721(rights.contract_).transferFrom(address(this), rights.depositor, rights.tokenId);
        emit RightsBurned(liquidDelegateId, rights.depositor, rights.contract_, rights.tokenId, rights.expiration);
        delete idsToRights[liquidDelegateId];
    }

    function extend(uint256 liquidDelegateId, uint96 newExpiration) external {
        Rights memory rights = idsToRights[liquidDelegateId];
        if (!(rights.depositor == msg.sender && newExpiration > rights.expiration)) {
            revert InvalidExtension();
        }
        idsToRights[liquidDelegateId].expiration = newExpiration;
    }

    /// @notice Flashloan a delegated asset to its liquid owner.
    /// @dev Backup functionality if the underlying utility doesn't support delegate.cash yet
    /// @param liquidDelegateId The id of the liquid delegate to flashloan the escrowed NFT for
    /// @param receiver The address of the receiver implementing the INFTFlashBorrower interface
    /// @param data Unused here
    function flashLoan(uint256 liquidDelegateId, INFTFlashBorrower receiver, bytes calldata data) external payable {
        Rights memory rights = idsToRights[liquidDelegateId];
        if (ownerOf(liquidDelegateId) != msg.sender) {
            revert InvalidFlashLoan();
        }
        ERC721(rights.contract_).transferFrom(address(this), address(receiver), rights.tokenId);
        if (receiver.onFlashLoan{value: msg.value}(msg.sender, rights.contract_, rights.tokenId, data) != CALLBACK_SUCCESS) {
            revert InvalidFlashLoan();
        }
        ERC721(rights.contract_).transferFrom(address(receiver), address(this), rights.tokenId);
    }

    /**
     * ----------- DELEGATION -----------
     */

    /// @notice Move the airdrop claim right
    /// @dev Whenever the airdrop claim NFT transfers, update the delegation rights
    /// @param from The address to transfer from
    /// @param to The address to transfer to
    /// @param id The token id to transfer
    function transferFrom(address from, address to, uint256 id) public override {
        Rights memory rights = idsToRights[id];
        if (block.timestamp >= rights.expiration) {
            revert LiquidDelegateExpired();
        }
        // Reassign delegation powers
        IDelegateRegistry(DELEGATION_REGISTRY).delegateERC721(from, rights.contract_, rights.tokenId, "", false);
        IDelegateRegistry(DELEGATION_REGISTRY).delegateERC721(to, rights.contract_, rights.tokenId, "", true);
        super.transferFrom(from, to, id);
    }

    /// @dev Delegate when a liquid delegate is minted
    /// @param to The address to mint to
    /// @param id The token id to mint
    function _mint(address to, uint256 id) internal override {
        Rights memory rights = idsToRights[id];
        IDelegateRegistry(DELEGATION_REGISTRY).delegateERC721(to, rights.contract_, rights.tokenId, "", true);
        super._mint(to, id);
    }

    /// @dev Undelegate when a liquid delegate is burned
    function _burn(uint256 id) internal override {
        Rights memory rights = idsToRights[id];
        IDelegateRegistry(DELEGATION_REGISTRY).delegateERC721(ownerOf(id), rights.contract_, rights.tokenId, "", false);
        super._burn(id);
    }

    /**
     * ----------- METADATA -----------
     */

    /// @notice Set the base URI for image generation
    /// @param _baseURI The new base URI for image generation
    function setBaseURI(string memory _baseURI) external onlyMetadataOwner {
        baseURI = _baseURI;
    }

    /// @notice Return metadata for a token
    /// @dev The attributes are immutably generated onchain, the image is fetched externally
    /// @param tokenId The tokenId to fetch metadata for
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        Rights memory rights = idsToRights[tokenId];

        string memory attributes = string.concat(
            '"attributes":[',
            '{"trait_type": "Collection Address", "value": "',
            rights.contract_.toHexString(),
            '"',
            '}, {"trait_type": "Token ID", "value": "',
            rights.tokenId.toString(),
            '"',
            '}, {"trait_type": "Expiration", "display_type": "date", "value": ',
            uint256(rights.expiration).toString(),
            '}, {"trait_type": "Depositor Address", "value": "',
            rights.depositor.toHexString(),
            '"' "}]"
        );

        string memory imageUrl = string.concat(baseURI, tokenId.toString());

        string memory metadataString = string.concat(
            '{"name": "Liquid Delegate #',
            tokenId.toString(),
            '", "description": "LiquidDelegate lets you escrow your token for a chosen timeperiod and receive a liquid NFT representing the associated delegation rights.", ',
            attributes,
            ', "image": "',
            imageUrl,
            '"}'
        );
        string memory output = string.concat("data:application/json;base64,", Base64.encode(bytes(metadataString)));

        return output;
    }

    /**
     * ----------- ROYALTIES -----------
     */

    /// @notice Claim funds
    /// @param recipient The address to send funds to
    function claimFunds(address payable recipient) external onlyRoyaltyOwner {
        _pay(recipient, address(this).balance, true);
    }

    /// @dev See {ERC2981-_setDefaultRoyalty}.
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyRoyaltyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @dev See {ERC2981-_deleteDefaultRoyalty}.
    function deleteDefaultRoyalty() external onlyRoyaltyOwner {
        _deleteDefaultRoyalty();
    }

    /**
     * ----------- OWNERS -----------
     */

    modifier onlyRoyaltyOwner() {
        if (msg.sender != royaltyOwner) {
            revert AccessControl();
        }
        _;
    }

    modifier onlyMetadataOwner() {
        if (msg.sender != metadataOwner) {
            revert AccessControl();
        }
        _;
    }

    /// @notice Update the royaltyOwner
    /// @dev Can also be used to revoke this power by setting to 0x0
    /// @param _royaltyOwner The new royalty owner
    function setRoyaltyOwner(address _royaltyOwner) external onlyRoyaltyOwner {
        royaltyOwner = _royaltyOwner;
    }

    /// @notice Update the metadataOwner
    /// @dev Can also be used to revoke this power by setting to 0x0
    /// @param _metadataOwner The new metadata owner
    function setMetadataOwner(address _metadataOwner) external onlyMetadataOwner {
        metadataOwner = _metadataOwner;
    }

    /// @notice The address which can set royalties
    function owner() external view returns (address) {
        return royaltyOwner;
    }

    /// @dev Send ether
    function _pay(address payable recipient, uint256 amount, bool errorOnFail) internal {
        (bool sent,) = recipient.call{value: amount}("");
        if (!(sent || errorOnFail)) {
            revert SendEtherFailed();
        }
    }
}
