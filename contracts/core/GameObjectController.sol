// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../openzeppelin/EnumerableSet.sol";
import "../interfaces/IGOC.sol";
import "../proxy/Controllable.sol";
import "../lib/GameObjectControllerLib.sol";
import "../lib/PackingLib.sol";
import "../lib/EventLib.sol";
import "../lib/StoryLib.sol";
import "../lib/MonsterLib.sol";
import "../lib/GOCLib.sol";

contract GameObjectController is Controllable, IGOC {
  using EnumerableSet for EnumerableSet.UintSet;
  using PackingLib for bytes32;
  using PackingLib for uint16;
  using PackingLib for uint8;
  using PackingLib for address;
  using PackingLib for uint32[];
  using PackingLib for uint32;
  using PackingLib for uint64;
  using PackingLib for int32[];
  using PackingLib for int32;

  //region ------------------------ CONSTANTS

  /// @notice Version of the contract
  string public constant VERSION = "1.1.5";
  //endregion ------------------------ CONSTANTS

  //region ------------------------ INITIALIZER

  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ INITIALIZER

  //region ------------------------ VIEWS

  function getObjectMeta(uint32 objectId) external view override returns (uint8 biome, uint8 objectSubType) {
    return GameObjectControllerLib.getObjectMeta(objectId);
  }

  function isAvailableForHero(address heroToken, uint heroTokenId, uint32 objId) external view returns (bool) {
    return GameObjectControllerLib.isAvailableForHero(IController(controller()), heroToken, heroTokenId, objId);
  }

  function isBattleObject(uint32 objectId) external view override returns (bool) {
    return GameObjectControllerLib.isBattleObject(objectId);
  }

  function getObjectTypeBySubType(uint32 objectId) external view returns (ObjectType) {
    return GameObjectControllerLib.getObjectTypeBySubType(objectId);
  }

  function getMonsterInfo(address hero, uint heroId, uint32 objectId) external view returns (IGOC.MonsterGenInfo memory mGenInfo, IGOC.GeneratedMonster memory gen) {
    return GameObjectControllerLib.getMonsterInfo(hero, heroId, objectId);
  }

  function getIteration(address heroToken, uint heroTokenId, uint32 objId) external view returns (uint) {
    return GameObjectControllerLib.getIteration(heroToken, heroTokenId, objId);
  }

  function getLastHeroFightTs(address heroToken, uint heroTokenId) external view returns (uint) {
    return GameObjectControllerLib.getLastHeroFightTs(heroToken, heroTokenId);
  }

  function getFightDelay() external view returns (uint) {
    return GameObjectControllerLib.getFightDelay();
  }

  function getStoryId(uint32 objectId) external view returns (uint16) {
    return GameObjectControllerLib.getStoryId(objectId);
  }

  function getEventInfo(uint32 objectId) external view returns (EventInfo memory) {
    return GameObjectControllerLib.getEventInfo(objectId);
  }

  function getObjectIds(uint8 biome, ObjectSubType subType) external view returns (uint[] memory) {
    return GameObjectControllerLib.getObjectIds(biome, subType);
  }

  function getMonsterMultiplier(uint8 heroNgLevel) external pure returns (uint) {
    return MonsterLib.monsterMultiplier(heroNgLevel);
  }
  //endregion ------------------------ VIEWS

  //region ------------------------ REGISTRATION

  function registerEvent(EventRegInfo memory regInfo) external {
    GameObjectControllerLib.registerEvent(IController(controller()), regInfo);
  }

  function registerStory(uint16 storyId, uint8 biome, ObjectSubType subType) external {
    GameObjectControllerLib.registerStory(IController(controller()), storyId, biome, subType);
  }

  function registerMonster(MonsterGenInfo memory monsterGenInfo) external {
    GameObjectControllerLib.registerMonster(IController(controller()), monsterGenInfo);
  }

  function removeObject(uint32 objectId) external {
    GameObjectControllerLib.removeObject(IController(controller()), objectId);
  }

  //endregion ------------------------ REGISTRATION

  //region ------------------------ OBJECT

  /// @dev Chances in range 0-1e9
  function getRandomObject(
    uint8[] memory cTypes,
    uint32[] memory chances,
    uint8 biome,
    address hero,
    uint heroId
  ) external override returns (uint32 objectId) {
    return GameObjectControllerLib.getRandomObject(IController(controller()), cTypes, chances, biome, hero, heroId);
  }

  function open(address hero, uint heroId, uint32 objectId) external override returns (uint iteration) {
    return GameObjectControllerLib.open(IController(controller()), hero, heroId, objectId);
  }

  /// @param data Answer (1 byte) or string command (3 bytes, i.e. "SKIP")
  function action(
    address sender,
    uint64 dungeonId,
    uint32 objectId,
    address hero,
    uint heroId,
    uint8 stageId,
    bytes memory data
  ) external override returns (ActionResult memory) {
    return GameObjectControllerLib.action(IController(controller()), sender, dungeonId, objectId, hero, heroId, stageId, data);
  }

  //endregion ------------------------ OBJECT

}
