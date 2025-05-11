//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface Errors {
    error InsufficientAmount();
    error Overflow();
    error IdenticalTokenAddress();
    error InvalidAddress();
    error PairAddressExists();
    error Expired();
    error InsufficientLiquidity();
    error InvalidAddressPath();
    error TransferFailed();
    error ExcessiveInputAmount();
}
