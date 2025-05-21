// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../openzeppelin/EnumerableSet.sol";
import "../interfaces/IGOC.sol";
import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IUserController.sol";
import "../interfaces/IHeroController.sol";
import "../proxy/Controllable.sol";
import "../lib/PackingLib.sol";
import "../lib/EventLib.sol";
import "../lib/StoryLib.sol";
import "../lib/MonsterLib.sol";
import "../lib/GOCLib.sol";

interface ArbSys {
  function arbBlockNumber() external view returns (uint256);
}

library GameObjectControllerLib {
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
  /// @dev keccak256(abi.encode(uint256(keccak256("game.object.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant MAIN_STORAGE_LOCATION = 0xfa9e067a92ca4a9057b7b4465a8f29d633e1758238bd3a4a8ec5d0f904f6b900;
  //endregion ------------------------ CONSTANTS

  //region ------------------------ RESTRICTIONS

  function onlyDeployer(IController controller) internal view {
    if (!controller.isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }

  function onlyDungeonFactory(address dungeonFactory) internal view {
    if (dungeonFactory != msg.sender) revert IAppErrors.ErrorNotDungeonFactory(msg.sender);
  }
  //endregion ------------------------ RESTRICTIONS

  //region ------------------------ VIEWS

  function _S() internal pure returns (IGOC.MainState storage s) {
    assembly {
      s.slot := MAIN_STORAGE_LOCATION
    }
    return s;
  }

  function getObjectMeta(uint32 objectId) internal view returns (uint8 biome, uint8 objectSubType) {
    return GOCLib.unpackObjectMeta(_S().objectMeta[objectId]);
  }

  function isAvailableForHero(IController controller, address heroToken, uint heroTokenId, uint32 objId) internal view returns (bool) {
    (, uint8 objectSubType) = getObjectMeta(objId);
    return GOCLib.isAvailableForHero(IStoryController(controller.storyController()), objId, objectSubType, heroToken, heroTokenId);
  }

  function isBattleObject(uint32 objectId) internal view returns (bool) {
    (,uint8 objectSubType) = GOCLib.unpackObjectMeta(_S().objectMeta[objectId]);
    return GOCLib.getObjectTypeBySubType(IGOC.ObjectSubType(objectSubType)) == IGOC.ObjectType.MONSTER;
  }

  function getObjectTypeBySubType(uint32 objectId) internal view returns (IGOC.ObjectType) {
    (,uint8 objectSubType) = GOCLib.unpackObjectMeta(_S().objectMeta[objectId]);
    return GOCLib.getObjectTypeBySubType(IGOC.ObjectSubType(objectSubType));
  }

  function getMonsterInfo(address hero, uint heroId, uint32 objectId) internal view returns (IGOC.MonsterGenInfo memory mGenInfo, IGOC.GeneratedMonster memory gen) {
    uint iteration = _S().iterations[hero.packIterationKey(uint64(heroId), objectId)];
    mGenInfo = MonsterLib.unpackMonsterInfo(_S().monsterInfos[objectId]);
    gen = MonsterLib.unpackGeneratedMonster(_S().monsterInfos[objectId]._generatedMonsters[hero.packNftId(heroId)][iteration]);
  }

  function getIteration(address heroToken, uint heroTokenId, uint32 objId) internal view returns (uint) {
    return _S().iterations[_iterationKey(heroToken, heroTokenId, objId)];
  }

  function getLastHeroFightTs(address heroToken, uint heroTokenId) internal view returns (uint) {
    return _S().lastHeroFightTs[heroToken.packNftId(heroTokenId)];
  }

  function getFightDelay() internal view returns (uint) {
    return _S().fightDelay;
  }

  function getStoryId(uint32 objectId) internal view returns (uint16) {
    return _S().storyIds[objectId];
  }

  function getEventInfo(uint32 objectId) internal view returns (IGOC.EventInfo memory) {
    return _S().eventInfos[objectId];
  }

  function getObjectIds(uint8 biome, IGOC.ObjectSubType subType) internal view returns (uint[] memory) {
    return _S().objectIds[GOCLib.packObjectMeta(biome, uint8(subType))].values();
  }
  //endregion ------------------------ VIEWS

  //region ------------------------ REGISTRATION

  function registerEvent(IController controller, IGOC.EventRegInfo memory regInfo) internal {
    onlyDeployer(controller);
    _checkMintItems(regInfo.mintItems, regInfo.mintItemsChances);
    uint32 objectId = _registerMetaId(regInfo.biome, regInfo.subType, regInfo.eventId);
    EventLib.eventRegInfoToInfo(regInfo, _S().eventInfos[objectId]);
    emit IApplicationEvents.EventRegistered(objectId, regInfo);
  }

  function registerStory(IController controller, uint16 storyId, uint8 biome, IGOC.ObjectSubType subType) internal {
    onlyDeployer(controller);
    uint32 objectId = _registerMetaId(biome, subType, storyId);
    _S().storyIds[objectId] = storyId;
    emit IApplicationEvents.StoryRegistered(objectId, storyId);
  }

  function registerMonster(IController controller, IGOC.MonsterGenInfo memory monsterGenInfo) internal {
    onlyDeployer(controller);
    _checkMintItems(monsterGenInfo.mintItems, monsterGenInfo.mintItemsChances);
    uint32 objectId = _registerMetaId(monsterGenInfo.biome, monsterGenInfo.subType, monsterGenInfo.monsterId);

    delete _S().monsterInfos[objectId];

    MonsterLib.packMonsterInfo(monsterGenInfo, _S().monsterInfos[objectId]);
    emit IApplicationEvents.MonsterRegistered(objectId, monsterGenInfo);
  }

  function removeObject(IController controller, uint32 objectId) internal {
    onlyDeployer(controller);
    bytes32 meta = _S().objectMeta[objectId];
    delete _S().objectMeta[objectId];
    _S().objectIds[meta].remove(objectId);

    emit IApplicationEvents.ObjectRemoved(objectId);
  }
  //endregion ------------------------ REGISTRATION

  //region ------------------------ OBJECT ACTIONS

  /// @param cTypes Array of object subtypes, see IGOC.ObjectSubType.XXX
  /// @param chances Chances in range 0-1e9, chances are corresponded to {cTypes} array
  function getRandomObject(
    IController c,
    uint8[] memory cTypes,
    uint32[] memory chances,
    uint8 biome,
    address hero,
    uint heroId
  ) internal returns (uint32 objectId) {
    onlyDungeonFactory(c.dungeonFactory());
    return GOCLib.getRandomObject(
      _S(),
      IStoryController(c.storyController()),
      cTypes,
      chances,
      biome,
      hero,
      heroId
    );
  }

  /// @notice Open {object}: increase iteration, [generate monsters]
  function open(IController controller, address hero, uint heroId, uint32 objectId) internal returns (uint iteration) {
    onlyDungeonFactory(controller.dungeonFactory());

    iteration = _increaseIteration(hero, heroId, objectId);

    (, uint8 objectSubType) = getObjectMeta(objectId);
    uint8 t = uint8(GOCLib.getObjectTypeBySubType(IGOC.ObjectSubType(objectSubType)));

    if (t == uint8(IGOC.ObjectType.EVENT)) {
      // noop
    } else if (t == uint8(IGOC.ObjectType.MONSTER)) {
      IHeroController.HeroInfo memory heroInfo = IHeroController(controller.heroController()).getHeroInfo(hero, heroId);
      MonsterLib.initialGeneration(_S().monsterInfos[objectId], hero, heroId, iteration, heroInfo.ngLevel);
    } else if (t == uint8(IGOC.ObjectType.STORY)) {
      // noop
    } else {
      revert IAppErrors.UnknownObjectTypeGocLib1(t);
    }
  }

  /// @notice Execute event/story/monster action
  /// @param data Object type-specified data packed using abi.encode.
  /// For events: bool (accept / not accept results)
  /// For monsters: AttackInfo
  /// For story: bytes32 (answer id) OR command "SKIP" (4 bytes)
  function action(
    IController controller,
    address sender,
    uint64 dungeonId,
    uint32 objectId,
    address hero,
    uint heroId,
    uint8 stageId,
    bytes memory data
  ) internal returns (IGOC.ActionResult memory) {
    ControllerContextLib.ControllerContext memory cc = ControllerContextLib.init(controller);
    onlyDungeonFactory(address(ControllerContextLib.dungeonFactory(cc)));

    IGOC.ActionContext memory ctx;

    ctx.objectId = objectId;
    ctx.sender = sender;
    ctx.heroToken = hero;
    ctx.heroTokenId = heroId;
    ctx.stageId = stageId;
    ctx.data = data;
    (ctx.biome, ctx.objectSubType) = getObjectMeta(objectId);
    ctx.heroNgLevel = ControllerContextLib.heroController(cc).getHeroInfo(hero, heroId).ngLevel;

    ctx.dungeonId = dungeonId;
    ctx.iteration = _S().iterations[_iterationKey(hero, heroId, objectId)];
    ctx.controller = controller;

    IGOC.ActionResult memory r;
    uint8 t = uint8(GOCLib.getObjectTypeBySubType(IGOC.ObjectSubType(ctx.objectSubType)));
    ctx.salt = block.number;

    // for L2 chains need to get correct block number from precompiled contracts
    if(block.chainid == uint(111188)) {
      ctx.salt = ArbSys(address(100)).arbBlockNumber();
    }

    if (t == uint8(IGOC.ObjectType.EVENT)) {
      r = EventLib.action(ctx, _S().eventInfos[objectId]);
    } else if (t == uint8(IGOC.ObjectType.MONSTER)) {
      _checkAndRefreshFightTs(hero, heroId);
      (r, ctx.salt) = MonsterLib.action(ctx, _S().monsterInfos[objectId]);
    } else if (t == uint8(IGOC.ObjectType.STORY)) {
      r = StoryLib.action(cc, ctx, _S().storyIds[ctx.objectId]);
    } else {
      revert IAppErrors.UnknownObjectTypeGocLib2(t);
    }

    r.objectId = ctx.objectId;
    r.heroToken = hero;
    r.heroTokenId = heroId;
    r.iteration = ctx.iteration;

    emit IApplicationEvents.ObjectResultEvent(dungeonId, objectId, IGOC.ObjectType(t), hero, heroId, stageId, ctx.iteration, data,
      IGOC.ActionResultEvent(
        {
          kill: r.kill,
          completed: r.completed,
          heroToken: r.heroToken,
          mintItems: r.mintItems,
          heal: r.heal,
          manaRegen: r.manaRegen,
          lifeChancesRecovered: r.lifeChancesRecovered,
          damage: r.damage,
          manaConsumed: r.manaConsumed,
          objectId: r.objectId,
          experience: r.experience,
          heroTokenId: r.heroTokenId,
          iteration: r.iteration,
          rewriteNextObject: r.rewriteNextObject
        }
      )
      , ctx.salt);
    return r;
  }
//endregion ------------------------ OBJECT ACTIONS

  //region ------------------------ Utils

  /// @notice Generate object ID using (biome, subType, id)
  /// @param biome Biome to which the object belongs. [1..99]
  /// @param subType Subtype of the object, see IGOC.ObjectSubType.XXX. [1..99]
  /// @param id Id of the event / story / monster. [1..10_000]
  function _genObjectId(uint8 biome, uint8 subType, uint16 id) internal pure returns (uint32 objectId) {
    if (biome == 0 || subType == 0 || id == 0) revert IAppErrors.ZeroValueNotAllowed();
    if (biome >= 100) revert IAppErrors.GenObjectIdBiomeOverflow(biome);
    if (uint(subType) >= 100) revert IAppErrors.GenObjectIdSubTypeOverflow(subType);
    if (id > 10_000) revert IAppErrors.GenObjectIdIdOverflow(id);
    objectId = uint32(biome) * 1_000_000 + uint32(subType) * 10_000 + uint32(id);
  }

  /// @notice Register the object in objectMeta and objectIds
  /// @param biome Biome to which the object belongs. [1..99]
  /// @param subType Subtype of the object, [1..99]
  /// @param id Id of the event / story / monster. [1..10_000]
  /// @return objectId Object id generated by {_genObjectId}
  function _registerMetaId(uint8 biome, IGOC.ObjectSubType subType, uint16 id) internal returns (uint32 objectId) {
    IGOC.MainState storage s = _S();
    objectId = _genObjectId(biome, uint8(subType), id);
    bytes32 meta = GOCLib.packObjectMeta(biome, uint8(subType));
    s.objectMeta[objectId] = meta;
    s.objectIds[meta].add(objectId);
  }

  /// @notice Update last-hero-fight-timestamp
  function _checkAndRefreshFightTs(address heroToken, uint heroTokenId) internal {
    IGOC.MainState storage s = _S();
    bytes32 key = heroToken.packNftId(heroTokenId);
    if (s.lastHeroFightTs[key] + s.fightDelay > block.timestamp) revert IAppErrors.FightDelay();
    s.lastHeroFightTs[key] = block.timestamp;
  }

  function _increaseIteration(address heroToken, uint heroTokenId, uint32 objId) internal returns (uint iteration) {
    IGOC.MainState storage s = _S();
    bytes32 key = _iterationKey(heroToken, heroTokenId, objId);
    iteration = s.iterations[key] + 1;
    s.iterations[key] = iteration;
  }

  function _iterationKey(address heroToken, uint heroTokenId, uint32 objId) internal pure returns (bytes32) {
    return heroToken.packIterationKey(uint64(heroTokenId), objId);
  }

  /// @notice Validate passed {mintItems_} and {mintItemsChances_}
  function _checkMintItems(address[] memory mintItems_, uint32[] memory mintItemsChances_) internal pure {
    uint length = mintItems_.length;
    if (mintItemsChances_.length != length) revert IAppErrors.LengthsMismatch();

    for (uint i; i < length; ++i) {
      if (mintItems_[i] == address(0)) revert IAppErrors.ZeroAddress();
      if (mintItemsChances_[i] == 0) revert IAppErrors.ZeroChance();
      if (mintItemsChances_[i] > CalcLib.MAX_CHANCE) revert IAppErrors.TooHighChance(mintItemsChances_[i]);
    }
  }

  //endregion ------------------------ Utils
}
