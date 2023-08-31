// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.4;

interface IDelegateFlashloan {
    error InvalidFlashloan();

    /**
     * @dev Receive a delegate flashloan
     * @param initiator Caller of the flashloan
     * @param flashInfo Info about the flashloan
     * @return selector The function selector for onFlashloan
     */
    function onFlashloan(address initiator, Structs.FlashInfo calldata flashInfo) external payable returns (bytes32);
}
