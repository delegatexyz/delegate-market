// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IDelegateRegistry} from "delegate-registry/src/IDelegateRegistry.sol";
import {IDelegateToken, Structs as DelegateTokenStructs} from "src/interfaces/IDelegateToken.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";
import {IERC1155} from "openzeppelin/token/ERC1155/IERC1155.sol";

import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";

enum ExpiryType {
    none,
    absolute,
    relative
}

struct OrderInfo {
    address signer;
    IDelegateRegistry.DelegationType underlyingTokenType;
    ExpiryType expiryType;
    address underlyingTokenContract;
    uint256 underlyingAmount;
    uint256 underlyingTokenId;
    bytes32 underlyingRights;
    uint256 expiryLength;
    uint256 signerSalt;
}

/// @dev experimental alternative to create offerer
/// TODO: add functions to allow fulfil type rather match seaport orders, direct approvals with CreateRouter would be required as it would be the seaport "fulfiller"
contract CreateRouter is ReentrancyGuard {
    address public immutable seaport;
    address public immutable delegateToken;
    OrderInfo internal transientOrderInfo;

    constructor(address seaport_, address setDelegateToken) {
        require(seaport_ != address(0), "seaportIsZero");
        seaport = seaport_;
        require(setDelegateToken != address(0), "delegateTokenIsZero");
        delegateToken = setDelegateToken;
    }

    function transferFrom(address from, address to, uint256 data) external nonReentrant returns (bool) {
        require(from == address(this));
        OrderInfo memory orderInfo = transientOrderInfo;
        delete transientOrderInfo;
        orderInfo.signer = to;
        uint256 orderHash;
        {
            orderHash = uint256(keccak256(abi.encode(orderInfo)));
            require(orderHash == data, "order hash");
        }
        uint256 delegateTokenId = IDelegateToken(delegateToken).getDelegateId(address(this), orderHash);
        uint256 expiry;
        if (orderInfo.expiryType == ExpiryType.relative) {
            expiry = block.timestamp + orderInfo.expiryLength;
        } else {
            expiry = orderInfo.expiryLength;
        }
        IDelegateRegistry.DelegationType underlyingTokenType = orderInfo.underlyingTokenType;
        address underlyingTokenContract = orderInfo.underlyingTokenContract;
        uint256 returnedTokenId = 0;
        if (underlyingTokenType == IDelegateRegistry.DelegationType.ERC721) {
            IERC721(underlyingTokenContract).setApprovalForAll(address(delegateToken), true);
            returnedTokenId = IDelegateToken(delegateToken).create(
                DelegateTokenStructs.DelegateInfo(
                    to, IDelegateRegistry.DelegationType.ERC721, to, 0, underlyingTokenContract, orderInfo.underlyingTokenId, bytes32(orderInfo.underlyingRights), expiry
                ),
                orderHash
            );
            //slither-disable-next-line incorrect-equality,timestamp
            require(returnedTokenId == delegateTokenId, "delegateTokenId invariant");
            IERC721(underlyingTokenContract).setApprovalForAll(address(delegateToken), false); // Deleting approval saves gas
        } else if (underlyingTokenType == IDelegateRegistry.DelegationType.ERC20) {
            require(IERC20(underlyingTokenContract).approve(address(delegateToken), orderInfo.underlyingAmount));
            returnedTokenId = IDelegateToken(delegateToken).create(
                DelegateTokenStructs.DelegateInfo(
                    to, IDelegateRegistry.DelegationType.ERC20, to, orderInfo.underlyingAmount, orderInfo.underlyingTokenContract, 0, orderInfo.underlyingRights, expiry
                ),
                orderHash
            );
            //slither-disable-next-line incorrect-equality,timestamp
            require(returnedTokenId == delegateTokenId, "delegateTokenId invariant");
            require(IERC20(underlyingTokenContract).allowance(address(this), address(delegateToken)) == 0, "invariant");
        } else if (underlyingTokenType == IDelegateRegistry.DelegationType.ERC1155) {
            IERC1155(underlyingTokenContract).setApprovalForAll(address(delegateToken), true);
            returnedTokenId = IDelegateToken(delegateToken).create(
                DelegateTokenStructs.DelegateInfo(
                    to,
                    IDelegateRegistry.DelegationType.ERC1155,
                    to,
                    orderInfo.underlyingAmount,
                    orderInfo.underlyingTokenContract,
                    orderInfo.underlyingTokenId,
                    orderInfo.underlyingRights,
                    expiry
                ),
                orderHash
            );
            //slither-disable-next-line incorrect-equality,timestamp
            require(returnedTokenId == delegateTokenId, "delegateTokenId invariant");
            IERC1155(underlyingTokenContract).setApprovalForAll(address(delegateToken), false); // Deleting approval saves gas
        }
        return true;
    }

    function storeOrderInfo(OrderInfo calldata orderInfo) external {
        transientOrderInfo = orderInfo;
    }

    function isValidSignature(bytes32, bytes calldata data) external view returns (bytes4) {
        require(msg.sender == seaport, "caller not seaport");
        require(keccak256(abi.encode(transientOrderInfo)) == keccak256(data), "bad transient info");
        return bytes4(keccak256("isValidSignature(bytes32,bytes)"));
    }
}
