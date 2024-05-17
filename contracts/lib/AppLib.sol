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

}
