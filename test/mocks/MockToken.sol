//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@solady/contracts/tokens/ERC20.sol";
import {Errors} from "src/interfaces/Errors.sol";

contract MockToken is ERC20 {
    string private s_name;
    string private s_symbol;
    uint8 private s_decimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        s_name = _name;
        s_symbol = _symbol;
        s_decimals = _decimals;
    }

    function name() public view override returns (string memory) {
        return s_name;
    }

    function symbol() public view override returns (string memory) {
        return s_symbol;
    }

    function decimals() public view override returns (uint8) {
        return s_decimals;
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        _burn(_from, _amount);
    }
}
