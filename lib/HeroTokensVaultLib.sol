// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IERC20.sol";
import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IController.sol";
import "../interfaces/IGameToken.sol";
import "../openzeppelin/Math.sol";

library HeroTokensVaultLib {
  
  //region ------------------------ Constants
  uint private constant _BURN_DENOMINATOR = 100e18;
  uint private constant _TOTAL_SUPPLY_BASE = 10_000_000e18;
  //endregion ------------------------ Constants

  //region ------------------------ Restrictions
  function onlyHeroController(IController controller) internal view {
    if (controller.heroController() != msg.sender) revert IAppErrors.ErrorNotHeroController(msg.sender);
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Main logic

  /// @return Value in the range [0...100e18]
  function percentToBurn(uint totalSupply) internal pure returns (uint) {
    return Math.min(totalSupply * _BURN_DENOMINATOR / _TOTAL_SUPPLY_BASE, _BURN_DENOMINATOR);
  }

  /// @notice Split {amount} on three parts: to treasury, to governance, to burn.
  /// Last part is burnt if the token is game token, otherwise it's kept on balance,
  /// @param token It's always game token
  /// @param amount Assume that this amount is approved by {from} to this contract
  function process(IController controller, address token, uint amount, address from) internal {
    onlyHeroController(controller);

    IERC20(token).transferFrom(from, address(this), amount);

    uint toBurn = amount * percentToBurn(IERC20(token).totalSupply()) / _BURN_DENOMINATOR;
    uint toTreasury = (amount - toBurn) / 2;
    uint toGov = amount - toBurn - toTreasury;

    if (toTreasury != 0) {
      IERC20(token).transfer(controller.treasury(), toTreasury);
    }

    if (toGov != 0) {
      IERC20(token).transfer(address(controller), toGov);
    }

    if (toBurn != 0) {
      IGameToken(token).burn(toBurn);
    }

    emit IApplicationEvents.Process(token, amount, from, toBurn, toTreasury, toGov);
  }
  //endregion ------------------------ Main logic
}