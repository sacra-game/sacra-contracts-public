// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;


interface IMinter {

  function amountForDungeon(uint dungeonBiomeLevel, uint heroLevel) external view returns (uint);

  function mintDungeonReward(uint64 dungeonId, uint dungeonBiomeLevel, uint heroLevel) external returns (uint amount);

}
