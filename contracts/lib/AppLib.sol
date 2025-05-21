// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IERC20.sol";
import "../interfaces/IERC721.sol";

/// @notice Common internal utils, shared constants
library AppLib {

  /// @notice Biome owner has the right to receive 1% tax on any income in the biome. Decimals 3.
  /// The final value of tax is in the range [1..10]%, it depends on total liquidity staked by the guild
  uint internal constant BIOME_TAX_PERCENT_MIN = 1_000; // 1%

  /// @notice Max possible value of biome owner tax percent, decimals 3.
  uint internal constant BIOME_TAX_PERCENT_MAX = 10_000; // 10%

  /// @notice Make infinite approve of {token} to {spender} if the approved amount is less than {amount}
  /// @dev Should NOT be used for third-party pools
  function approveIfNeeded(address token, uint amount, address spender) internal {
    if (IERC20(token).allowance(address(this), spender) < amount) {
      IERC20(token).approve(spender, type(uint).max);
    }
  }

  /// @dev Remove from array the item with given id and move the last item on it place
  ///      Use with mapping for keeping indexes in correct ordering
  function removeIndexed(
    uint256[] storage array,
    mapping(uint256 => uint256) storage indexes,
    uint256 id
  ) internal {
    uint256 lastId = array[array.length - 1];
    uint256 index = indexes[id];
    indexes[lastId] = index;
    indexes[id] = type(uint256).max;
    array[index] = lastId;
    array.pop();
  }

  /// @notice Return a-b OR zero if a < b
  function sub0(uint32 a, uint32 b) internal pure returns (uint32) {
    return a > b ? a - b : 0;
  }

  /// @notice Adjust the dungeon completion reward based on the hero's NG level
  function _getAdjustedReward(uint amount, uint heroNgLevel) internal pure returns (uint) {
    uint rewardPercent = heroNgLevel == 0
      ? 40
      : heroNgLevel == 1
        ? 60
        : heroNgLevel == 2
            ? 80
            : 100;
    return amount * rewardPercent / 100;
  }

  function _ownerOf(address hero, uint heroId) internal view returns (address) {
    return IERC721(hero).ownerOf(heroId);
  }

}
