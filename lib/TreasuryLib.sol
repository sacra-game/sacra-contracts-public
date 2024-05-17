// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../proxy/Controllable.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IGameToken.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IAppErrors.sol";

library TreasuryLib {
  //region ------------------------ CONSTANTS
  uint public constant AUGMENT_GOV_FEE = 50;
  uint public constant REPAIR_GOV_FEE = 50;
  //endregion ------------------------ CONSTANTS

  //region ------------------------ RESTRICTIONS

  function onlyDungeonFactory(IController controller) internal view {
    if (controller.dungeonFactory() != msg.sender) revert IAppErrors.ErrorNotDungeonFactory(msg.sender);
  }
  //endregion ------------------------ RESTRICTIONS

  //region ------------------------ VIEWS

  function balanceOfToken(address token) internal view returns (uint) {
    return IERC20(token).balanceOf(address(this));
  }
  //endregion ------------------------ VIEWS

  //region ------------------------ ACTIONS

  /// @notice Send {amount} of the {token} to the {dungeon}
  function sendToDungeon(IController controller, address dungeon, address token, uint amount) internal {
    onlyDungeonFactory(controller);
    uint bal = IERC20(token).balanceOf(address(this));
    if (bal == 0 || amount > bal) revert IAppErrors.NotEnoughBalance();
    IERC20(token).transfer(dungeon, amount);
    emit IApplicationEvents.AssetsSentToDungeon(dungeon, token, amount);
  }

  /// @dev Assume approve. Move fee to treasury and governance from msg.sender.
  ///      Anyone can call
  function sendFee(IController controller, address token, uint amount, IItemController.FeeType feeType) internal {

    uint dividerGovFee = 100;
    if (feeType == IItemController.FeeType.REPAIR) {
      dividerGovFee = REPAIR_GOV_FEE;
    } else if (feeType == IItemController.FeeType.AUGMENT) {
      dividerGovFee = AUGMENT_GOV_FEE;
    }

    uint toGov = amount * dividerGovFee / 100;
    uint toTreasury = amount - toGov;
    if (toTreasury != 0) {
      address gameToken = controller.gameToken();
      if (gameToken == token) {
        IERC20(token).transferFrom(msg.sender, address(this), toTreasury);
        // for game token always burn treasury part
        IGameToken(gameToken).burn(toTreasury);
      } else {
        IERC20(token).transferFrom(msg.sender, address(this), toTreasury);
      }
    }
    if (toGov != 0) {
      IERC20(token).transferFrom(msg.sender, address(controller), toGov);
    }
  }
  //endregion ------------------------ ACTIONS

}
