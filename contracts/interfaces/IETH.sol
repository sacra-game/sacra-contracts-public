// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IETH {

  function balanceOf(address target) external view returns (uint256);

  function deposit() external payable;

  function withdraw(uint256 wad) external;

  function totalSupply() external view returns (uint256);

  function approve(address guy, uint256 wad) external returns (bool);

  function transfer(address dst, uint256 wad) external returns (bool);

  function transferFrom(address src, address dst, uint256 wad) external returns (bool);

}
