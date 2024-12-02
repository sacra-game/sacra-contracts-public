// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IController.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IStatController.sol";
import "../interfaces/IStoryController.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IDungeonFactory.sol";
import "../interfaces/IReinforcementController.sol";
import "../interfaces/IGameToken.sol";
import "../interfaces/IGOC.sol";
import "../interfaces/IItemController.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IUserController.sol";
import "../interfaces/IGuildController.sol";
import "../interfaces/IRewardsPool.sol";

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
    IUserController userController;
    IGuildController guildController;
    IRewardsPool rewardsPool;
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

  function getUserController(ControllerContext memory cc) internal view returns (IUserController userController) {
    if (address(cc.userController) == address(0)) {
      cc.userController = IUserController(cc.controller.userController());
    }
    return cc.userController;
  }

  function getGuildController(ControllerContext memory cc) internal view returns (IGuildController guildController) {
    if (address(cc.guildController) == address(0)) {
      cc.guildController = IGuildController(cc.controller.guildController());
    }
    return cc.guildController;
  }

  function getRewardsPool(ControllerContext memory cc) internal view returns (IRewardsPool rewardsPool) {
    if (address(cc.rewardsPool) == address(0)) {
      cc.rewardsPool = IRewardsPool(cc.controller.rewardsPool());
    }
    return cc.rewardsPool;
  }
}