// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IERC721Metadata} from "openzeppelin/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Receiver} from "openzeppelin/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "openzeppelin/token/ERC1155/IERC1155Receiver.sol";
import {IERC2981} from "openzeppelin/interfaces/IERC2981.sol";

import {DelegateTokenStructs as Structs} from "src/libraries/DelegateTokenLib.sol";

interface IDelegateToken is IERC721Metadata, IERC721Receiver, IERC1155Receiver, IERC2981 {
    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * To prevent doubled event emissions, the latest version of the DelegateToken uses the ERC721 Transfer(from, to,
     * id) event standard to infer meaning that was
     * previously double covered by "RightsCreated" and "RightsBurned" events
     * A Transfer event with from = address(0) is a "create" event
     * A Transfer event with to = address(0) is a "withdraw" event
     */

    /// @notice Emitted when a principal token holder extends the expiry of the delegate token
    event ExpiryExtended(uint256 indexed delegateTokenId, uint256 previousExpiry, uint256 newExpiry);

    /*//////////////////////////////////////////////////////////////
                      VIEW & INTROSPECTION
    //////////////////////////////////////////////////////////////*/

    /// @notice The v2 delegate registry address
    function delegateRegistry() external view returns (address);

    /// @notice The principal token deployed in tandem with this delegate token
    function principalToken() external view returns (address);

    /// @notice Image metadata location, but attributes are stored onchain
    function baseURI() external view returns (string memory);

    /// @notice Adapted from solmate's
    /// [ERC721](https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol)
    function isApprovedOrOwner(address spender, uint256 delegateTokenId) external view returns (bool);

    /**
     * @notice Fetches the info struct of a delegate token
     * @param delegateTokenId The id of the delegateToken to query info for
     * @return delegateInfo The DelegateInfo struct
     */
    function getDelegateInfo(uint256 delegateTokenId) external view returns (Structs.DelegateInfo memory delegateInfo);

    /**
     * @notice Deterministic function for generating a delegateId. Because msg.sender is fixed in addition to the freely
     * chosen salt, addresses cannot grief each other.
     * The WrapOfferer is a special case, but trivial to regenerate a unique salt
     * @param creator should be the caller of create
     * @param salt allows the creation of a new unique id
     * @return delegateId
     */
    function getDelegateId(address creator, uint256 salt) external view returns (uint256 delegateId);

    /// @notice Returns contract-level metadata URI for OpenSea
    /// (reference)[https://docs.opensea.io/docs/contract-level-metadata]
    function contractURI() external view returns (string memory);

    /*//////////////////////////////////////////////////////////////
                         STATE CHANGING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create rights token pair pulling underlying token from `msg.sender`.
     * @param delegateInfo struct containing the details of the delegate token to be created
     * @param salt A randomly chosen value, never repeated, to generate unique delegateIds for a particular
     * `msg.sender`.
     * @return delegateTokenId New rights ID that is also the token ID of both the newly created principal and
     * delegate tokens.
     */
    function create(Structs.DelegateInfo calldata delegateInfo, uint256 salt) external returns (uint256 delegateTokenId);

    /**
     * @notice Allows the principal token owner or any approved operator to extend the expiry of the
     * delegation rights.
     * @param delegateTokenId The ID of the rights being extended.
     * @param newExpiry The absolute timestamp to set the expiry
     */
    function extend(uint256 delegateTokenId, uint256 newExpiry) external;

    /**
     * @notice Allows the delegate owner or any approved operator to return a delegate token to the principal rights holder early, allowing the principal
     * rights holder to redeem the underlying token(s) early.
     * Allows anyone to forcefully return the delegate token to the principal rights holder if the delegate token has expired
     * @param delegateTokenId ID of the delegate right to be rescinded
     */
    function rescind(uint256 delegateTokenId) external;

    /**
     * @notice Allows principal rights owner or approved operator to withdraw the underlying token
     * once the delegation rights have either met their expiration or been rescinded.
     * Can also be called early if the caller is approved or owner of the delegate token (i.e. they wouldn't need to
     * call rescind & withdraw), or approved operator of the delegate token holder
     * "Burns" the delegate token, principal token, and returns the underlying tokens to the caller.
     * @param delegateTokenId id of the corresponding delegate token
     */
    function withdraw(uint256 delegateTokenId) external;

    /**
     * @notice Allows delegate token owner or approved operator to borrow their underlying tokens for the duration of a
     * single atomic transaction.
     * @param info IDelegateFlashloan FlashInfo struct
     */
    function flashloan(Structs.FlashInfo calldata info) external payable;

    /// @notice Callback function for principal token during the create flow
    function burnAuthorizedCallback() external;

    /// @notice Callback function for principal token during the withdraw flow
    function mintAuthorizedCallback() external;
}
