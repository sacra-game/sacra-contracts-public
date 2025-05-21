// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

interface IGuildStakingAdapter {

  /// @notice Calculate relative increment of the biome tax for the given guild owner, [0..1e18]
  /// 0 - no increment (default 1% is used), 1 - max possible increment (i.e. 5%)
  function getExtraFeeRatio(uint guildId) external view returns (uint);

}
