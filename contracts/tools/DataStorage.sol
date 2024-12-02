// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

contract DataStorage {
    mapping(address => bytes) public data;

    function store(bytes calldata _data) external {
        data[msg.sender] = _data;
    }

    function clearData() external {
        delete data[msg.sender];
    }
}