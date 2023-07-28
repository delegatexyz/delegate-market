// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {IERC721Metadata} from "openzeppelin/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC1155Receiver} from "openzeppelin/token/ERC1155/IERC1155Receiver.sol";

interface IDelegateToken is IERC721Metadata, IERC1155Receiver {
    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * To prevent doubled event emissions, the latest version of the DelegateToken uses the ERC721 Transfer(from, to, id) event standard to infer meaning that was
     * previously double covered by "RightsCreated" and "RightsBurned" events
     * A Transfer event with from = address(0) is a "create" event
     * A Transfer event with to = address(0) is a "withdraw" event
     * A Transfer event with to = address(1) is a "rescind" event
     */

    /// @notice Emitted when a principal token holder extends the expiry of the delegate token
    event ExpiryExtended(uint256 indexed delegateTokenId, uint256 previousExpiry, uint256 newExpiry);

    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/

    error DelegateRegistryZero();
    error PrincipalTokenZero();
    error DelegateTokenHolderZero();
    error InitialMetadataOwnerZero();
    error ToIsZero();
    error FromIsZero();
    error TokenAmountIsZero();

    error NotERC721Receiver(address to);

    error NotAuthorized(address caller, uint256 delegateTokenId);

    error FromNotDelegateTokenHolder(address from, address delegateTokenHolder);

    error HashMisMatch();

    error NotMinted(uint256 delegateTokenId);
    error AlreadyExisted(uint256 delegateTokenId);
    error WithdrawNotAvailable(uint256 delegateTokenId, uint256 expiry, uint256 timestamp);

    error ExpiryTimeNotInFuture(uint256 expiry, uint256 timestamp);
    error ExpiryTooLarge(uint256 expiry, uint256 maximum);
    error ExpiryTooSmall(uint256 expiry, uint256 minimum);

    error WrongAmountForType(IDelegateRegistry.DelegationType tokenType, uint256 wrongAmount);
    error InvalidTokenType(IDelegateRegistry.DelegationType tokenType);

    error InvalidFlashloan();

    /*//////////////////////////////////////////////////////////////
                      VIEW & INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    /// @dev see https://eips.ethereum.org/EIPS/eip-165
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    /// @notice The value flash borrowers need to return from `onFlashLoan` for the call to be successful.
    function flashLoanCallBackSuccess() external pure returns (bytes32);

    /// @notice The v2 delegate registry address
    function delegateRegistry() external view returns (address);

    /// @notice The principal token deployed in tandem with this delegate token
    function principalToken() external view returns (address);

    /// @notice Image metadata location, but attributes are stored onchain
    function baseURI() external view returns (string memory);

    /// @notice Adapted from solmate's [ERC721](https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol)
    function isApprovedOrOwner(address spender, uint256 delegateTokenId) external view returns (bool);

    /// @notice Struct for creating delegate tokens and returning their information
    struct DelegateInfo {
        address principalHolder;
        IDelegateRegistry.DelegationType tokenType;
        address delegateHolder;
        uint256 amount;
        address tokenContract;
        uint256 tokenId;
        bytes32 rights;
        uint256 expiry;
    }

    /**
     * @notice Fetches the info struct of a delegate token
     * @param delegateTokenId The id of the delegateToken to query info for
     * @return delegateInfo The DelegateInfo struct
     */
    function getDelegateInfo(uint256 delegateTokenId) external view returns (DelegateInfo memory delegateInfo);

    /**
     * @notice Deterministic function for generating a delegateId. Because msg.sender is fixed in addition to the freely chosen salt, addresses cannot grief each other.
     * The WrapOfferer is a special case, but trivial to regenerate a unique salt
     * @dev TODO: reverts if the delegate id has been used
     * @param creator should be the caller of create
     * @param salt allows the creation of a new unique id
     * @return delegateId
     */
    function getDelegateId(address creator, uint256 salt) external view returns (uint256 delegateId);

    /// @notice Returns contract-level metadata URI for OpenSea (reference)[https://docs.opensea.io/docs/contract-level-metadata]
    function contractURI() external view returns (string memory);

    /*//////////////////////////////////////////////////////////////
                         STATE CHANGING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create rights token pair pulling underlying token from `msg.sender`.
     * @param delegateInfo struct containing the details of the delegate token to be created
     * @param salt A randomly chosen value, never repeated, to generate unique delegateIds for a particular `msg.sender`.
     * @return delegateTokenId New rights ID that is also the token ID of both the newly created principal and
     * delegate tokens.
     */
    function create(DelegateInfo calldata delegateInfo, uint256 salt) external returns (uint256 delegateTokenId);

    /**
     * @notice Allows the principal token owner or any approved operator to extend the expiry of the
     * delegation rights.
     * @param delegateTokenId The ID of the rights being extended.
     * @param newExpiry The absolute timestamp to set the expiry
     */
    function extend(uint256 delegateTokenId, uint256 newExpiry) external;

    /**
     * @notice Allows the delegate owner or any approved operator to rescind their right early, allowing the principal rights owner to redeem the underlying token early.
     * Allows anyone to forcefully rescind the delegate token if it has expired
     * @param from The delegate token holder of the token to be rescinded
     * @param delegateTokenId ID of the delegate right to be rescinded
     */
    function rescind(address from, uint256 delegateTokenId) external;

    /**
     * @notice Allows principal rights owner or approved operator to withdraw the underlying token
     * once the delegation rights have either met their expiration or been rescinded.
     * Can also be called early if the caller is approved or owner of the delegate token (i.e. they wouldn't need to call rescind & withdraw)
     * "Burns" the delegate token, principal token, and returns the underlying tokens.
     * @param recipient Recipient of the underlying tokens.
     * @param delegateTokenId id of the corresponding delegate token
     */
    function withdraw(address recipient, uint256 delegateTokenId) external;

    /**
     * @notice Allows delegate token owner or approved operator to borrow their underlying token for the
     * duration of a single atomic transaction
     * @param receiver Recipient of borrowed token, must implement the `INFTFlashBorrower` interface
     * @param delegateId ID of the rights the underlying token is being borrowed from
     * @param data Added metadata to be relayed to borrower
     * @dev TODO: implement ERC20 and ERC1155 versions of this
     */
    function flashLoan(address receiver, uint256 delegateId, bytes calldata data) external payable;

    /**
     * @notice Allows the owner of DelegateToken contract to set baseURI
     * @param uri will be set as the new baseURI
     */
    function setBaseURI(string calldata uri) external;
}
