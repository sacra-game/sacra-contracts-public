// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IItem {

  function isItem() external pure returns (bool);

  function mintFor(address recipient) external returns (uint tokenId);

  function burn(uint tokenId) external;

  function controlledTransfer(address from, address to, uint tokenId) external;
}
