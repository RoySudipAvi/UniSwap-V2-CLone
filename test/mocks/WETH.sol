//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@solady/contracts/tokens/ERC20.sol";
import {Errors} from "src/interfaces/Errors.sol";

contract WETH is ERC20 {
    event Deposit(address indexed _from, uint256 indexed _amount);
    event Withdraw(address indexed _to, uint256 indexed _amount);

    function name() public pure override returns (string memory) {
        return "Wrapped Ether";
    }

    function symbol() public pure override returns (string memory) {
        return "WETH";
    }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 _value) external {
        require(balanceOf(msg.sender) >= _value, Errors.InsufficientAmount());
        _burn(msg.sender, _value);
        (bool success,) = msg.sender.call{value: _value}("");
        require(success, Errors.TransferFailed());
        emit Withdraw(msg.sender, _value);
    }
}
