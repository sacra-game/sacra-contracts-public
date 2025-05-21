// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

/// @notice Restored from 0x889677E6d07D22a53dac907d204ecBB08E38B529 (sonic)
interface IXMyrdGauge {
  function CONTROLLABLE_VERSION() external view returns (string memory);

  function MULTI_POOL_VERSION() external view returns (string memory);

  function REWARDS_PERIOD() external view returns (uint256);

  function VERSION() external view returns (string memory);

  function activePeriod() external view returns (uint256);

  function addStakingToken(address) external pure;

  function balanceOf(address, address) external view returns (uint256);

  function controller() external view returns (address);

  function created() external view returns (uint256);

  function createdBlock() external view returns (uint256);

  function defaultRewardToken() external view returns (address);

  function derivedBalance(address stakingToken, address account) external view returns (uint256);

  function derivedBalances(address, address) external view returns (uint256);

  function derivedSupply(address) external view returns (uint256);

  function duration() external view returns (uint256);

  function earned(address stakingToken, address rewardToken, address account) external view returns (uint256);

  function getAllRewards(address account) external;

  function getPeriod() external view returns (uint256);

  function getReward(address account, address[] memory tokens) external;

  function handleBalanceChange(address account) external;

  function increaseRevision(address oldLogic) external;

  function init(address controller_, address xMyrd_, address myrd_ ) external;

  function isController(address value_) external view returns (bool);

  function isGovernance(address value_) external view returns (bool);

  function isRewardToken(address, address) external view returns (bool);

  function isStakeToken(address token) external view returns (bool);

  function lastTimeRewardApplicable(address stakingToken, address rewardToken) external view returns (uint256);

  function lastUpdateTime(address, address) external view returns (uint256);

  function left(address stakingToken, address rewardToken) external view returns (uint256);

  function notifyRewardAmount(address token, uint256 amount) external;

  function periodFinish(address, address) external view returns (uint256);

  function previousImplementation() external view returns (address);

  function registerRewardToken(address stakeToken, address rewardToken) external;

  function removeRewardToken(address stakeToken, address rewardToken) external;

  function revision() external view returns (uint256);

  function rewardPerToken(address stakingToken, address rewardToken) external view returns (uint256);

  function rewardPerTokenStored(address, address) external view returns (uint256);

  function rewardRate(address, address) external view returns (uint256);

  function rewardTokens(address, uint256) external view returns (address);

  function rewardTokensLength(address token) external view returns (uint256);

  function rewards(address, address, address) external view returns (uint256);

  function rewardsRedirect(address) external view returns (address);

  function setRewardsRedirect(address account, address recipient) external;

  function totalSupply(address) external view returns (uint256);

  function updatePeriod(uint256 amount_) external;

  function userRewardPerTokenPaid(address, address, address) external view returns (uint256);

  function xMyrd() external view returns (address);
}