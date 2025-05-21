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
import "../interfaces/IPvpController.sol";
import "../interfaces/IItemBoxController.sol";

/// @notice Provide context-struct with all controller addresses and routines for lazy init
/// Usage:
///       Create an instance of the structure
///               cc = ControllerContextLib.init(controller);
///       access controller directly
///               cc.controller.xxx();
///       access other contracts indirectly
///               sc = ControllerContextLib.statController(cc);
library ControllerContextLib {
  //region ----------------- Data types
  enum CacheIndex {
    STAT_CONTROLLER_0,
    STORY_CONTROLLER_1,
    ORACLE_2,
    TREASURY_3,
    DUNGEON_FACTORY_4,
    GOC_5,
    REINFORCEMENT_CONTROLLER_6,
    ITEM_CONTROLLER_7,
    HERO_CONTROLLER_8,
    GAME_TOKEN_9,
    USER_CONTROLLER_10,
    GUILD_CONTROLLER_11,
    PVP_CONTROLLER_12,
    REWARDS_POOL_13,
    ITEM_BOX_CONTROLLER_14
  }

  uint constant private CACHE_SIZE = 15;

  struct ControllerContext {
    /// @notice Direct access to the controller
    IController controller;

    /// @notice All lazy-initialized addresses in order of {CacheIndex}
    address[CACHE_SIZE] cache;
  }
  //endregion ----------------- Data types

  //region ----------------- Initialization and _lazyInit
  function init(IController controller) internal pure returns (ControllerContext memory cc) {
    cc.controller = controller;
    return cc;
  }

  function _lazyInit(
    ControllerContext memory cc,
    CacheIndex index,
    function () external view returns(address) getter
  ) internal view returns (address) {
    address a = cc.cache[uint(index)];
    if (a != address(0)) return a;

    cc.cache[uint(index)] = getter();
    return cc.cache[uint(index)];
  }
  //endregion ----------------- Initialization and _lazyInit

  //region ----------------- Access with lazy initialization
  function statController(ControllerContext memory cc) internal view returns (IStatController) {
    return IStatController(_lazyInit(cc, CacheIndex.STAT_CONTROLLER_0, cc.controller.statController));
  }

  function storyController(ControllerContext memory cc) internal view returns (IStoryController) {
    return IStoryController(_lazyInit(cc, CacheIndex.STORY_CONTROLLER_1, cc.controller.storyController));
  }

  function oracle(ControllerContext memory cc) internal view returns (IOracle) {
    return IOracle(_lazyInit(cc, CacheIndex.ORACLE_2, cc.controller.oracle));
  }

  function treasury(ControllerContext memory cc) internal view returns (ITreasury) {
    return ITreasury(_lazyInit(cc, CacheIndex.TREASURY_3, cc.controller.treasury));
  }

  function dungeonFactory(ControllerContext memory cc) internal view returns (IDungeonFactory) {
    return IDungeonFactory(_lazyInit(cc, CacheIndex.DUNGEON_FACTORY_4, cc.controller.dungeonFactory));
  }

  function gameObjectController(ControllerContext memory cc) internal view returns (IGOC) {
    return IGOC(_lazyInit(cc, CacheIndex.GOC_5, cc.controller.gameObjectController));
  }

  function reinforcementController(ControllerContext memory cc) internal view returns (IReinforcementController) {
    return IReinforcementController(_lazyInit(cc, CacheIndex.REINFORCEMENT_CONTROLLER_6, cc.controller.reinforcementController));
  }

  function itemController(ControllerContext memory cc) internal view returns (IItemController) {
    return IItemController(_lazyInit(cc, CacheIndex.ITEM_CONTROLLER_7, cc.controller.itemController));
  }

  function heroController(ControllerContext memory cc) internal view returns (IHeroController) {
    return IHeroController(_lazyInit(cc, CacheIndex.HERO_CONTROLLER_8, cc.controller.heroController));
  }

  function gameToken(ControllerContext memory cc) internal view returns (IGameToken) {
    return IGameToken(_lazyInit(cc, CacheIndex.GAME_TOKEN_9, cc.controller.gameToken));
  }

  function userController(ControllerContext memory cc) internal view returns (IUserController) {
    return IUserController(_lazyInit(cc, CacheIndex.USER_CONTROLLER_10, cc.controller.userController));
  }

  function guildController(ControllerContext memory cc) internal view returns (IGuildController) {
    return IGuildController(_lazyInit(cc, CacheIndex.GUILD_CONTROLLER_11, cc.controller.guildController));
  }

  function pvpController(ControllerContext memory cc) internal view returns (IPvpController) {
    return IPvpController(_lazyInit(cc, CacheIndex.PVP_CONTROLLER_12, cc.controller.pvpController));
  }

  function rewardsPool(ControllerContext memory cc) internal view returns (IRewardsPool) {
    return IRewardsPool(_lazyInit(cc, CacheIndex.REWARDS_POOL_13, cc.controller.rewardsPool));
  }

  function itemBoxController(ControllerContext memory cc) internal view returns (IItemBoxController) {
    return IItemBoxController(_lazyInit(cc, CacheIndex.ITEM_BOX_CONTROLLER_14, cc.controller.itemBoxController));
  }
  //endregion ----------------- Access with lazy initialization
}