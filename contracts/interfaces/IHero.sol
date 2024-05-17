// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IHero {

  function isHero() external pure returns (bool);

  function mintFor(address recipient) external returns (uint tokenId);

  function burn(uint tokenId) external;

}
