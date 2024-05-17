// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import {IController} from "../interfaces/IController.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IStatController} from "../interfaces/IStatController.sol";
import {IStoryController} from "../interfaces/IStoryController.sol";
import {ITreasury} from "../interfaces/ITreasury.sol";
import {IDungeonFactory} from "../interfaces/IDungeonFactory.sol";
import {IReinforcementController} from "../interfaces/IReinforcementController.sol";
import {IGameToken} from "../interfaces/IGameToken.sol";
import {IGOC} from "../interfaces/IGOC.sol";
import {IItemController} from "../interfaces/IItemController.sol";
import {IHeroController} from "../interfaces/IHeroController.sol";

/// @notice Provide context-struct with all controller addresses and routines for lazy init
/// Usage:
///       Create an instance of the structure
///               cc = ControllerContextLib.init(controller);
///       access controller directly
///               cc.controller.xxx();
///       access other contracts indirectly
///               sc = ControllerContextLib.getStatController(cc);
library ControllerContextLib {
  struct ControllerContext {
    IController controller;
    IStatController statController;
    IStoryController storyController;
    IOracle oracle;
    ITreasury treasury;
    IDungeonFactory dungeonFactory;
    IGOC gameObjectController;
    IReinforcementController reinforcementController;
    IItemController itemController;
    IHeroController heroController;
    IGameToken gameToken;
  }

  function init(IController controller) internal pure returns (ControllerContext memory cc) {
    cc.controller = controller;
    return cc;
  }

  function getStatController(ControllerContext memory cc) internal view returns (IStatController statController) {
    if (address(cc.statController) == address(0)) {
      cc.statController = IStatController(cc.controller.statController());
    }
    return cc.statController;
  }

  function getStoryController(ControllerContext memory cc) internal view returns (IStoryController storyController) {
    if (address(cc.storyController) == address(0)) {
      cc.storyController = IStoryController(cc.controller.storyController());
    }
    return cc.storyController;
  }

  function getOracle(ControllerContext memory cc) internal view returns (IOracle oracle) {
    if (address(cc.oracle) == address(0)) {
      cc.oracle = IOracle(cc.controller.oracle());
    }
    return cc.oracle;
  }

  function getTreasury(ControllerContext memory cc) internal view returns (ITreasury treasury) {
    if (address(cc.treasury) == address(0)) {
      cc.treasury = ITreasury(cc.controller.treasury());
    }
    return cc.treasury;
  }

  function getDungeonFactory(ControllerContext memory cc) internal view returns (IDungeonFactory dungeonFactory) {
    if (address(cc.dungeonFactory) == address(0)) {
      cc.dungeonFactory = IDungeonFactory(cc.controller.dungeonFactory());
    }
    return cc.dungeonFactory;
  }

  function getGameObjectController(ControllerContext memory cc) internal view returns (IGOC gameObjectController) {
    if (address(cc.gameObjectController) == address(0)) {
      cc.gameObjectController = IGOC(cc.controller.gameObjectController());
    }
    return cc.gameObjectController;
  }

  function getReinforcementController(ControllerContext memory cc) internal view returns (IReinforcementController reinforcementController) {
    if (address(cc.reinforcementController) == address(0)) {
      cc.reinforcementController = IReinforcementController(cc.controller.reinforcementController());
    }
    return cc.reinforcementController;
  }

  function getItemController(ControllerContext memory cc) internal view returns (IItemController itemController) {
    if (address(cc.itemController) == address(0)) {
      cc.itemController = IItemController(cc.controller.itemController());
    }
    return cc.itemController;
  }

  function getHeroController(ControllerContext memory cc) internal view returns (IHeroController heroController) {
    if (address(cc.heroController) == address(0)) {
      cc.heroController = IHeroController(cc.controller.heroController());
    }
    return cc.heroController;
  }

  function getGameToken(ControllerContext memory cc) internal view returns (IGameToken gameToken) {
    if (address(cc.gameToken) == address(0)) {
      cc.gameToken = IGameToken(cc.controller.gameToken());
    }
    return cc.gameToken;
  }
}