// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IERC20.sol";

/// @notice Common internal utils
library AppLib {

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
}
