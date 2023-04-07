// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ContractOffererInterface} from "seaport/interfaces/ContractOffererInterface.sol";
import {ExpiryType} from "./ILiquidDelegateV2.sol";

enum ReceiptFillerType {
    DelegateOpen,
    DelegateClosed,
    PrincipalOpen,
    PrincipalClosed
}

/// @author philogy <https://github.com/philogy>
interface IWrapOfferer is ContractOffererInterface {
    function transferFrom(address from, address to, uint256 receiptId) external;

    function getReceiptHash(
        address delegateRecipient,
        address principalRecipient,
        address token,
        uint256 id,
        ExpiryType expiryType,
        uint256 expiryValue,
        uint40 nonce
    ) external view returns (bytes32 receiptHash);

    function getNonceUsed(address owner, uint256 nonce) external view returns (bool);

    function encodeContext(
        ReceiptFillerType fillerType,
        ExpiryType expiryType,
        uint40 expiryValue,
        address delegateRecipient,
        address principalRecipient,
        uint40 nonce,
        bytes memory signature
    ) external view returns (bytes memory);

    function decodeContext(bytes calldata context)
        external
        view
        returns (
            ReceiptFillerType fillerType,
            ExpiryType expiryType,
            uint40 expiryValue,
            address delegateRecipient,
            address principalRecipient,
            uint40 nonce,
            bytes memory signature
        );
}
