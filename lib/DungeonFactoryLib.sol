// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IERC721.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IStatController.sol";
import "../interfaces/IDungeonFactory.sol";
import "../interfaces/IGameToken.sol";
import "../interfaces/IMinter.sol";
import "../interfaces/IReinforcementController.sol";
import "../interfaces/IGOC.sol";
import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../proxy/Controllable.sol";
import "../lib/StringLib.sol";
import "../lib/DungeonLib.sol";
import "../relay/ERC2771Context.sol";
import "../lib/ControllerContextLib.sol";

library DungeonFactoryLib {
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using PackingLib for bytes32;
  using PackingLib for uint16;
  using PackingLib for uint8;
  using PackingLib for address;
  using PackingLib for uint32[];
  using PackingLib for uint32;
  using PackingLib for uint64;
  using PackingLib for int32[];
  using PackingLib for int32;

  //region ------------------------ Data types
  struct ObjectActionLocal {
    bool isCompleted;
    bool needClear;
    uint32 currentObjectId;
    uint32 newCurrentObjectId;
    uint newCurrentStage;
  }

  //endregion ------------------------ Data types

  //region ------------------------ RESTRICTIONS

  function onlyDeployer(IController controller) internal view {
    if (!controller.isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }

  function _onlyEoa(bool isEoa) internal pure {
    if (!isEoa) revert IAppErrors.ErrorOnlyEoa();
  }

  function onlyHeroController(IController controller) internal view {
    if (IController(controller).heroController() != msg.sender) revert IAppErrors.ErrorNotHeroController(msg.sender);
  }

  function _checkOwnerRegisteredNotPaused(
    address heroToken,
    uint heroTokenId,
    address msgSender,
    ControllerContextLib.ControllerContext memory cc
  ) internal view {
    if (IERC721(heroToken).ownerOf(heroTokenId) != msgSender) revert IAppErrors.ErrorNotHeroOwner(heroToken, msgSender);
    if (ControllerContextLib.getHeroController(cc).heroClass(heroToken) == 0) revert IAppErrors.ErrorHeroIsNotRegistered(heroToken);
    if (cc.controller.onPause()) revert IAppErrors.ErrorPaused();
  }

  //endregion ------------------------ RESTRICTIONS

  //region ------------------------ VIEWS
  function _S() internal pure returns (IDungeonFactory.MainState storage s) {
    return DungeonLib._S();
  }

  function dungeonAttributes(uint16 dungNum) internal view returns (IDungeonFactory.DungeonAttributes memory) {
    return _S().dungeonAttributes[dungNum];
  }

  function dungeonStatus(uint64 dungeonId) internal view returns (
    uint16 dungNum,
    bool isCompleted,
    address heroToken,
    uint heroTokenId,
    uint32 currentObject,
    uint8 currentStage,
    address[] memory treasuryTokens_,
    uint[] memory treasuryTokensAmounts_,
    bytes32[] memory treasuryItems,
    uint8 stages,
    uint32[] memory uniqObjects
  ) {
    IDungeonFactory.DungeonStatus storage dungStatus = _S().dungeonStatuses[dungeonId];

    dungNum = dungStatus.dungNum;
    isCompleted = dungStatus.isCompleted;
    heroToken = dungStatus.heroToken;
    heroTokenId = dungStatus.heroTokenId;
    currentObject = dungStatus.currentObject;
    currentStage = dungStatus.currentStage;
    treasuryItems = dungStatus.treasuryItems;
    stages = dungStatus.stages;
    uniqObjects = dungStatus.uniqObjects;

    uint tokensLength = dungStatus.treasuryTokens.length();

    treasuryTokens_ = new address[](tokensLength);
    treasuryTokensAmounts_ = new uint[](tokensLength);

    for (uint i; i < tokensLength; ++i) {
      (treasuryTokens_[i], treasuryTokensAmounts_[i]) = dungStatus.treasuryTokens.at(i);
    }
  }

  function dungeonCounter() internal view returns (uint64) {
    return _S().dungeonCounter;
  }

  function maxBiomeCompleted(address heroToken, uint heroTokenId) internal view returns (uint8) {
    return _S().maxBiomeCompleted[heroToken.packNftId(heroTokenId)];
  }

  function currentDungeon(address heroToken, uint heroTokenId) internal view returns (uint64) {
    return _S().heroCurrentDungeon[heroToken.packNftId(heroTokenId)];
  }

  function minLevelForTreasury(address token) internal view returns (uint) {
    return _S().minLevelForTreasury[token];
  }

  function skillSlotsForDurabilityReduction(address heroToken, uint heroTokenId) internal view returns (
    uint8[] memory result
  ) {
    return _S().skillSlotsForDurabilityReduction[heroToken.packNftId(heroTokenId)].unpackUint8Array();
  }

  /// @return Length of the items in freeDungeons map for the given {biome}
  function freeDungeonsByLevelLength(uint biome) internal view returns (uint) {
    return _S().freeDungeons[biome].length();
  }

  /// @param index Index of the free dungeon inside freeDungeons map
  /// @return dungeonId
  function freeDungeonsByLevel(uint index, uint biome) internal view returns (uint64) {
    return uint64(_S().freeDungeons[biome].at(index));
  }

  function getDungeonTreasuryAmount(IController controller, address token, uint heroLevel, uint biome)
  internal view returns (
    uint totalAmount,
    uint amountForDungeon,
    uint mintAmount
  ) {
    totalAmount = ITreasury(controller.treasury()).balanceOfToken(token);
    mintAmount = IMinter(IGameToken(controller.gameToken()).minter()).amountForDungeon(biome, heroLevel);
    amountForDungeon = DungeonLib.dungeonTreasuryReward(
      token,
      uint(_S().maxBiome),
      totalAmount,
      uint8(heroLevel),
      uint8(biome)
    );
  }

  /// @notice Check if biome boss completed by the hero.
  /// @dev isBiomeBossCompleted would be more correct title, but isBiomeBoss is already used
  function isBiomeBoss(IController controller, address heroToken, uint heroTokenId)
  internal view returns (bool) {
    uint8 heroBiome = IHeroController(controller.heroController()).heroBiome(heroToken, heroTokenId);
    return _S().bossCompleted[heroToken.packMapObject(uint64(heroTokenId), heroBiome)];
  }
  //endregion ------------------------ VIEWS

  //region ------------------------ ACTIONS
  function launch(
    bool isEoa,
    IController controller,
    address msgSender,
    address heroToken,
    uint heroTokenId,
    address treasuryToken
  ) external returns (uint64 dungeonId) {
    _onlyEoa(isEoa);
    return _launch(controller, msgSender, heroToken, heroTokenId, treasuryToken);
  }

  function launchForNewHero(
    IController controller,
    address msgSender,
    address heroToken,
    uint heroTokenId
  ) external returns (uint64 dungeonId) {
    onlyHeroController(controller);
    return _launch(controller, msgSender, heroToken, heroTokenId, controller.gameToken());
  }

  /// @notice Create new dungeon and enter to it. Treasury reward is sent by treasury to the dungeon.
  function _launch(
    IController controller,
    address msgSender,
    address heroToken,
    uint heroTokenId,
    address treasuryToken
  ) internal returns (uint64 dungeonId) {
    IDungeonFactory.MainState storage s = _S();
    ControllerContextLib.ControllerContext memory cc = ControllerContextLib.init(controller);

    // check part of restrictions; other part is checked inside DungeonLib._enter
    _checkOwnerRegisteredNotPaused(heroToken, heroTokenId, msgSender, cc);
    if (!controller.validTreasuryTokens(treasuryToken)) revert IAppErrors.ErrorNotValidTreasureToken(treasuryToken);

    // select a logic for new dungeon
    uint8 heroLevel = uint8(ControllerContextLib.getStatController(cc).heroStats(heroToken, heroTokenId).level);
    uint16 dungNum = DungeonLib.getDungeonLogic(
      s,
      cc,
      heroLevel,
      heroToken,
      heroTokenId,
      ControllerContextLib.getOracle(cc).getRandomNumber(1e18, heroLevel)
    );

    // register new dungeon
    dungeonId = s.dungeonCounter + 1;
    s.dungeonCounter = dungeonId;

    IDungeonFactory.DungeonAttributes storage dungAttr = s.dungeonAttributes[dungNum];
    IDungeonFactory.DungeonStatus storage dungStatus = s.dungeonStatuses[dungeonId];

    if (dungStatus.isCompleted) revert IAppErrors.ErrorDungeonCompleted();

    dungStatus.dungeonId = dungeonId;
    dungStatus.dungNum = dungNum;
    dungStatus.stages = dungAttr.stages;
    dungStatus.uniqObjects = dungAttr.uniqObjects;

    emit IApplicationEvents.DungeonRegistered(dungNum, dungeonId);

    // enter to the dungeon
    DungeonLib._enter(cc, dungStatus, dungAttr, dungNum, dungeonId, heroToken, heroTokenId);

    // when entered, open the first object for reduce txs
    _openObject(cc, msgSender, dungeonId);

    // send treasury to the dungeon
    uint treasuryAmount = DungeonLib.dungeonTreasuryReward(
      treasuryToken,
      uint(_S().maxBiome),
      ControllerContextLib.getTreasury(cc).balanceOfToken(treasuryToken),
      heroLevel,
      dungAttr.biome
    );

    if (treasuryAmount != 0) {
      ControllerContextLib.getTreasury(cc).sendToDungeon(address(this), treasuryToken, treasuryAmount);
      DungeonLib._registerTreasuryToken(treasuryToken, s.dungeonStatuses[dungeonId].treasuryTokens, treasuryAmount);
    }

    emit IApplicationEvents.DungeonLaunched(dungNum, dungeonId, heroToken, heroTokenId, treasuryToken, treasuryAmount);
  }

  /// @notice Set boss completed for the given hero and given biome.
  /// @dev Set custom data for the hero: BOSS_COMPLETED_ = 1
  function setBossCompleted(IController controller, uint32 objectId, address heroToken, uint heroTokenId, uint8 heroBiome) internal {
    if (controller.gameObjectController() != msg.sender) revert IAppErrors.ErrorNotGoc();

    IDungeonFactory.MainState storage s = _S();

    if (!s.bossCompleted[heroToken.packMapObject(uint64(heroTokenId), heroBiome)]) {
      s.bossCompleted[heroToken.packMapObject(uint64(heroTokenId), heroBiome)] = true;
    }

    if (s.maxBiomeCompleted[heroToken.packNftId(heroTokenId)] < heroBiome) {
      s.maxBiomeCompleted[heroToken.packNftId(heroTokenId)] = heroBiome;
    }

    bytes32 index = _getBossCompletedIndex(heroBiome);
    IStatController(controller.statController()).setHeroCustomData(heroToken, heroTokenId, index, 1);

    emit IApplicationEvents.BossCompleted(objectId, heroBiome, heroToken, heroTokenId);
  }
  //endregion ------------------------ ACTIONS

  //region ------------------------ DUNGEON LOGIC - GOV ACTIONS

  /// @notice Register ordinal or specific dungeon
  /// @dev can be called for exist dungeon - will rewrite dungeon data
  /// @param dungNum Dungeon logic id
  /// @param biome Assume biome > 0
  /// @param isSpecific The dungeon is specific, so it shouldn't be registered in dungeonsLogicByBiome
  function registerDungeonLogic(
    IController controller,
    uint16 dungNum,
    uint8 biome,
    IDungeonFactory.DungeonGenerateInfo calldata genInfo,
    uint8 specReqBiome,
    uint8 specReqHeroClass,
    bool isSpecific
  ) internal {
    onlyDeployer(controller);
    IDungeonFactory.MainState storage s = _S();

    uint len = genInfo.objChancesByStages.length;
    if (len != genInfo.objTypesByStages.length || len != genInfo.uniqObjects.length) revert IAppErrors.ErrorNotStages();

    for (uint i; i < len; ++i) {
      if (genInfo.objChancesByStages[i].length != genInfo.objTypesByStages[i].length) revert IAppErrors.ErrorNotChances();
    }

    IDungeonFactory.DungeonAttributes storage info = s.dungeonAttributes[dungNum];

    if (biome > s.maxBiome) {
      s.maxBiome = biome;
    }

    info.stages = uint8(len); // info.stages can be increased later by chamber story
    info.biome = biome;

    info.uniqObjects = genInfo.uniqObjects;
    info.minMaxLevel = DungeonLib._toUint8PackedArray(genInfo.minLevel, genInfo.maxLevel);

    info.requiredCustomDataIndex = genInfo.requiredCustomDataIndex;
    bytes32[] storage requiredCustomDataValue = info.requiredCustomDataValue;

    for (uint i; i < genInfo.requiredCustomDataMinValue.length; ++i) {
      requiredCustomDataValue.push(
        PackingLib.packCustomDataRequirements(
          genInfo.requiredCustomDataMinValue[i],
          genInfo.requiredCustomDataMaxValue[i],
          genInfo.requiredCustomDataIsHero[i]
        )
      );
    }

    for (uint i; i < len; ++i) {
      info.info.objTypesByStages.push(PackingLib.packUint8Array(genInfo.objTypesByStages[i]));
      info.info.objChancesByStages.push(genInfo.objChancesByStages[i]);
    }

    if (isSpecific) {
      bytes32 packedId = DungeonLib._toUint8PackedArray(specReqBiome, specReqHeroClass);
      if (s.dungeonSpecific[packedId] != 0) revert IAppErrors.DungeonAlreadySpecific(dungNum);
      s.dungeonSpecific[packedId] = dungNum;

      if (s.allSpecificDungeons.contains(dungNum)) revert IAppErrors.DungeonAlreadySpecific2(dungNum);

      s.allSpecificDungeons.add(dungNum);

      emit IApplicationEvents.DungeonSpecificLogicRegistered(dungNum, specReqBiome, specReqHeroClass);
    } else {
      s.dungeonsLogicByBiome[info.biome].add(dungNum);
    }

    emit IApplicationEvents.DungeonLogicRegistered(dungNum, genInfo);
  }

  /// @dev Remove the dungeon logic (both ordinal and specific logics are supported)
  /// @param dungNum Dungeon logic id
  function removeDungeonLogic(IController controller, uint16 dungNum, uint8 specReqBiome, uint8 specReqHeroClass) internal {
    onlyDeployer(controller);
    IDungeonFactory.MainState storage s = _S();

    uint8 biome = s.dungeonAttributes[dungNum].biome;
    delete s.dungeonAttributes[dungNum];

    if (s.dungeonsLogicByBiome[biome].contains(dungNum)) {
      s.dungeonsLogicByBiome[biome].remove(dungNum);
      emit IApplicationEvents.DungeonLogicRemoved(dungNum);
    }

    if (s.allSpecificDungeons.contains(dungNum)) {
      bytes32 packedId = DungeonLib._toUint8PackedArray(specReqBiome, specReqHeroClass);
      if (s.dungeonSpecific[packedId] != dungNum) revert IAppErrors.WrongSpecificDungeon();

      delete s.dungeonSpecific[packedId];
      s.allSpecificDungeons.remove(dungNum);
      emit IApplicationEvents.DungeonSpecificLogicRemoved(dungNum, specReqBiome, specReqHeroClass);
    }
  }

  /// @dev Set eligible hero level for treasury tokens
  function setMinLevelForTreasury(IController controller, address token, uint heroLevel) internal {
    onlyDeployer(controller);

    if (heroLevel < DungeonLib.MIN_LEVEL_FOR_TREASURY_DEFAULT) {
      revert IAppErrors.ErrorLevelTooLow(heroLevel);
    }

    _S().minLevelForTreasury[token] = heroLevel;
    emit IApplicationEvents.MinLevelForTreasuryChanged(token, heroLevel);
  }

  /// @dev Governance can drop hero from dungeon in emergency case
  function emergencyExit(IController controller, uint64 dungId) internal {
    onlyDeployer(controller);
    DungeonLib.emergencyExit(controller, dungId);
  }
  //endregion ------------------------ DUNGEON LOGIC - GOV ACTIONS

  //region ------------------------ DUNGEON LOGIC - USER ACTIONS

  /// @notice Enter to the exist dungeon
  function enter(bool isEoa, IController controller, address msgSender, uint64 dungId, address heroToken, uint heroTokenId) external {
    IDungeonFactory.MainState storage s = _S();
    ControllerContextLib.ControllerContext memory cc = ControllerContextLib.init(controller);
    IDungeonFactory.DungeonStatus storage dungStatus = s.dungeonStatuses[dungId];

    // check part of restrictions; other part is checked inside DungeonLib._enter
    _onlyEoa(isEoa);
    _checkOwnerRegisteredNotPaused(heroToken, heroTokenId, msgSender, cc);
    if (dungStatus.isCompleted) revert IAppErrors.ErrorDungeonCompleted();

    // enter to the dungeon
    uint16 dungNum = dungStatus.dungNum;
    DungeonLib._enter(cc, dungStatus, s.dungeonAttributes[dungNum], dungNum, dungId, heroToken, heroTokenId);

    // when entered, open the first object for reduce txs
    _openObject(cc, msgSender, dungId);
  }

  function openObject(bool isEoa, IController controller, address msgSender, uint64 dungId) internal {
    _onlyEoa(isEoa);
    ControllerContextLib.ControllerContext memory cc = ControllerContextLib.init(controller);
    _openObject(cc, msgSender, dungId);
  }

  /// @notice Set new current object for the dungeon
  function _openObject(ControllerContextLib.ControllerContext memory cc, address msgSender, uint64 dungId) internal {
    IDungeonFactory.MainState storage s = _S();
    IDungeonFactory.DungeonStatus storage dungStatus = s.dungeonStatuses[dungId];
    IDungeonFactory.DungeonAttributes storage dungAttributes = s.dungeonAttributes[dungStatus.dungNum];

    IGOC goc = ControllerContextLib.getGameObjectController(cc);

    // check restrictions
    if (dungStatus.currentObject != 0) revert IAppErrors.ErrorNotReady();
    (address dungHero, uint dungHeroId) = _checkCurrentHero(dungStatus, msgSender, cc);

    // select new object and set it as current object in the dungeon
    uint currentStage = dungStatus.currentStage;
    uint32 objectId = _generateObject(dungAttributes, dungStatus, currentStage, goc, dungHero, dungHeroId);
    if (objectId == 0) revert IAppErrors.ErrorNotObject1();
    dungStatus.currentObject = objectId;

    // generate some info for UI
    uint iteration = goc.open(dungHero, dungHeroId, objectId);
    emit IApplicationEvents.ObjectOpened(dungId, dungHero, dungHeroId, objectId, iteration, currentStage);
  }

  /// @notice Do action and handle results
  /// @param data AttackInfo struct encoded using abi.encode
  function objectAction(bool isEoa, IController controller, address msgSender, uint64 dungId, bytes memory data) internal {
    IDungeonFactory.MainState storage s = _S();

    ControllerContextLib.ControllerContext memory cc = ControllerContextLib.init(controller);
    ObjectActionLocal memory v;

    IDungeonFactory.DungeonStatus storage dungStatus = s.dungeonStatuses[dungId];
    IDungeonFactory.DungeonAttributes storage dungAttributes = s.dungeonAttributes[dungStatus.dungNum];

    // check restrictions, some restrictions are checked inside objectAction
    _onlyEoa(isEoa);
    _checkCurrentHero(dungStatus, msgSender, cc);

    v.currentObjectId = dungStatus.currentObject;

    (v.isCompleted, v.newCurrentStage, v.newCurrentObjectId, v.needClear) = DungeonLib.objectAction(
      dungStatus,
      dungAttributes,
      dungId,
      msgSender,
      data,
      controller, // we pass controller, not cc, because objectAction is external
      v.currentObjectId
    );

    if (v.isCompleted) {
      dungStatus.isCompleted = true;
    }

    if (v.newCurrentStage != 0) {
      dungStatus.currentStage = uint8(v.newCurrentStage);
    }

    if (v.newCurrentObjectId != v.currentObjectId) {
      dungStatus.currentObject = v.newCurrentObjectId;
    }

    if (v.needClear) {
      _clear(dungStatus, dungAttributes.biome, dungId);
    }

    // if dungeon is not ended and current object is empty we can open next object for reduce users transactions
    if (!v.isCompleted && dungStatus.currentObject == 0 && !v.needClear) {
      _openObject(cc, msgSender, dungId);
    }
  }

  /// @notice Exit from completed dungeon
  function exit(bool isEoa, IController controller, address msgSender, uint64 dungId, bool claim) internal {
    _onlyEoa(isEoa);
    DungeonLib.exitDungeon(controller, dungId, claim, msgSender);
  }
  //endregion ------------------------ DUNGEON LOGIC - USER ACTIONS

  //region ------------------------ DUNGEON LOGIC - INTERNAL LOGIC

  /// @notice Generate object for the current stage
  /// @return objectId Either uniqObj or randomly generated object if uniqObj is not specified for the stage
  function _generateObject(
    IDungeonFactory.DungeonAttributes storage dungAttributes,
    IDungeonFactory.DungeonStatus storage dungStatus,
    uint currentStage,
    IGOC goc,
    address heroToken,
    uint heroTokenId
  ) internal returns (uint32 objectId) {
    if (currentStage >= dungStatus.stages) revert IAppErrors.ErrorWrongStage(currentStage);

    objectId = dungStatus.uniqObjects[currentStage];
    if (objectId == 0) {
      IDungeonFactory.ObjectGenerateInfo memory info = dungAttributes.info;
      objectId = goc.getRandomObject(
        DungeonLib._toUint8ArrayWithoutZeroes(info.objTypesByStages[currentStage]),
        info.objChancesByStages[currentStage],
        dungAttributes.biome,
        heroToken,
        heroTokenId
      );
    }
  }

  /// @notice Clear hero info in dungeon status, add dungeon to the list of free dungeons
  function _clear(IDungeonFactory.DungeonStatus storage dungStatus, uint8 biome, uint64 dungId) internal {
    delete dungStatus.heroToken;
    delete dungStatus.heroTokenId;
    delete dungStatus.currentObject;
    delete dungStatus.currentStage;
    _addFreeDungeon(biome, dungId);
    emit IApplicationEvents.Clear(dungId);
  }

  /// @notice Check: hero is registered, not dead, in the dungeon, sender is the owner, the dungeon is not completed,
  /// controller is not paused
  /// @return heroToken Token of the hero who is in the dungeon
  /// @return heroTokenId Token ID of the hero who is in the dungeon
  function _checkCurrentHero(
    IDungeonFactory.DungeonStatus storage dungStatus,
    address msgSender,
    ControllerContextLib.ControllerContext memory cc
  ) internal view returns (address heroToken, uint heroTokenId) {

    heroToken = dungStatus.heroToken;
    heroTokenId = dungStatus.heroTokenId;

    if (dungStatus.isCompleted) revert IAppErrors.ErrorDungeonCompleted();
    _checkOwnerRegisteredNotPaused(heroToken, heroTokenId, msgSender, cc);

    if (!ControllerContextLib.getStatController(cc).isHeroAlive(heroToken, heroTokenId)) revert IAppErrors.ErrorHeroIsDead(heroToken, heroTokenId);
    if (currentDungeon(heroToken, heroTokenId) != dungStatus.dungeonId) revert IAppErrors.ErrorHeroNotInDungeon();
  }

  /// @notice Add the {dungeonId} to the list of free dungeons (available to pass) of the given {biome}
  function _addFreeDungeon(uint8 biome, uint64 dungeonId) internal {
    if (!_S().freeDungeons[biome].add(dungeonId)) revert IAppErrors.ErrorDungeonIsFreeAlready();
    emit IApplicationEvents.FreeDungeonAdded(biome, dungeonId);
  }
  //endregion ------------------------ DUNGEON LOGIC - INTERNAL LOGIC

  //region ------------------------ Utils
  /// @dev We need separate utility function for tests
  function _getBossCompletedIndex(uint8 heroBiome) internal pure returns (bytes32) {
    return bytes32(abi.encodePacked("BOSS_COMPLETED_", StringLib._toString(heroBiome)));
  }
  //endregion ------------------------ Utils

}
