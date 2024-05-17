// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IOracle {

  function getRandomNumber(uint max, uint seed) external returns (uint);

  function getRandomNumberInRange(uint min, uint max, uint seed) external returns (uint);

}
