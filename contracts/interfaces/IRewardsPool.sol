// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IRewardsPool {

  /// @custom:storage-location erc7201:rewards.pool.main
  struct MainState {
    mapping(address token => uint baseAmountValue) baseAmounts;
  }

  function balanceOfToken(address token) external view returns (uint);

  function rewardAmount(address token, uint maxBiome, uint maxNgLevel, uint biome, uint heroNgLevel) external view returns (uint);

  function sendReward(address token, uint rewardAmount_, address receiver) external;

  function lostProfitPercent(uint maxBiome, uint maxNgLevel, uint heroNgLevel) external view returns (uint percent);
}
