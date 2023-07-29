// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {ContractOffererInterface} from "seaport/contracts/interfaces/ContractOffererInterface.sol";

enum ExpiryType {
    RELATIVE,
    ABSOLUTE
}

enum ReceiptFillerType {
    DelegateOpen,
    DelegateClosed,
    PrincipalOpen,
    PrincipalClosed
}

interface IWrapOfferer is ContractOffererInterface {
    //slither-disable-next-line erc20-interface
    function transferFrom(address from, address to, uint256 receiptId) external;

    function getReceiptHash(address delegateRecipient, address principalRecipient, address token, uint256 id, uint256 amount, ExpiryType expiryType, uint256 expiryValue)
        external
        view
        returns (bytes32 receiptHash);
}
