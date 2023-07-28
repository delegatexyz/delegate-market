// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {CommonBase} from "forge-std/Base.sol";

contract WETH is ERC20("WETH", "WETH"), CommonBase {
    function mint(address to, uint256 wad) external {
        vm.deal(address(this), address(this).balance + wad);
        _mint(to, wad);
    }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) external {
        _burn(msg.sender, wad);
        (bool success,) = msg.sender.call{value: wad}("");
        require(success);
    }
}
