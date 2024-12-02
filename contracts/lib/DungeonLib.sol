// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IController.sol";
import "../interfaces/IDungeonFactory.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IFightCalculator.sol";
import "../interfaces/IGOC.sol";
import "../interfaces/IGameToken.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IItemController.sol";
import "../interfaces/IMinter.sol";
import "../interfaces/IReinforcementController.sol";
import "../interfaces/IStatController.sol";
import "../interfaces/IStoryController.sol";
import "../interfaces/IUserController.sol";
import "../openzeppelin/EnumerableMap.sol";
import "./AppLib.sol";
import "./CalcLib.sol";
import "./ControllerContextLib.sol";
import "./PackingLib.sol";
import "./RewardsPoolLib.sol";
import "./StatControllerLib.sol";
import "./StatLib.sol";

library DungeonLib {
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using EnumerableSet for EnumerableSet.UintSet;
  using CalcLib for int32;
  using PackingLib for bytes32;
  using PackingLib for uint16;
  using PackingLib for uint8;
  using PackingLib for address;
  using PackingLib for uint8[];
  using PackingLib for uint32[];
  using PackingLib for uint32;
  using PackingLib for uint64;
  using PackingLib for int32[];
  using PackingLib for int32;

  /// @dev keccak256(abi.encode(uint256(keccak256("dungeon.factory.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant DUNGEON_FACTORY_STORAGE_LOCATION = 0xae5971282b317bbed599861775fe0712755bb3b2f655bfe8fb14280d8429f600;

  /// @notice Treasure reward is available starting from level 5. We need some initial gap as protection against bots
  uint public constant MIN_LEVEL_FOR_TREASURY_DEFAULT = 5;

  /// @notice Max possible default minLevelForTreasury (= 95)
  uint internal constant MAX_NIM_LEVEL_FOR_TREASURE = StatLib.MAX_LEVEL - StatLib.BIOME_LEVEL_STEP + 1;

  //region ------------------------ Data types

  struct ObjectActionInternalData {
    address msgSender;
    address heroToken;
    IStatController statController;
    bytes data;
    uint stages;
    uint biome;
    uint heroTokenId;
    uint64 dungId;
    uint32 objectId;
    uint8 currentStage;
    bool isBattleObj;
    IGOC.ActionResult result;
    IStatController.ChangeableStats stats;
  }

  /// @notice Lazy initialization data for _claimAll
  struct ClaimContext {
    address helpHeroToken;
    address heroPayToken;
    address msgSender;
    address[] tokens;
    uint64 dungId;
    uint helpHeroId;

    /// @dev Limited by ReinforcementController._TO_HELPER_RATIO_MAX
    uint toHelperRatio;
    uint itemLength;
    uint tokenLength;
    uint[] amounts;
  }
  //endregion ------------------------ Data types

  //region ------------------------ Common

  function _S() internal pure returns (IDungeonFactory.MainState storage s) {
    assembly {
      s.slot := DUNGEON_FACTORY_STORAGE_LOCATION
    }
    return s;
  }

  /// @notice Calculate amount of treasure reward that a hero can count on
  /// @param token Treasury token
  /// @param maxAvailableBiome Max deployed biome
  /// @param treasuryBalance Total treasury of the dungeon
  /// @param lvlForMint Current level of the hero
  /// @param dungeonBiome Biome to which the dungeon belongs
  /// @param maxOpenedNgLevel Max NG_LEVEL reached by any user
  /// @param heroNgLevel Current NG_LEVEL of the user
  function dungeonTreasuryReward(
    address token,
    uint maxAvailableBiome,
    uint treasuryBalance,
    uint lvlForMint,
    uint dungeonBiome,
    uint maxOpenedNgLevel,
    uint heroNgLevel
  ) internal view returns (uint) {
    if (dungeonBiome < maxAvailableBiome || heroNgLevel < maxOpenedNgLevel) {
      return 0;
    }

    uint customMinLevel = _S().minLevelForTreasury[token];
    if (customMinLevel != 0 && lvlForMint < customMinLevel) {
      return 0;
    }

    if (lvlForMint > StatLib.MAX_LEVEL) revert IAppErrors.ErrorWrongLevel(lvlForMint);
    if (dungeonBiome > StatLib.MAX_POSSIBLE_BIOME) revert IAppErrors.ErrorIncorrectBiome(dungeonBiome);

    uint biomeLevel = dungeonBiome * StatLib.BIOME_LEVEL_STEP;

    // CalcLib.log2((StatLib.MAX_LEVEL + 1) * 1e18);
    uint maxMultiplier = 6643856189774724682;
    uint multiplier = (maxMultiplier - CalcLib.log2((StatLib.MAX_LEVEL - biomeLevel + 1) * 1e18)) / 100;
    if (multiplier >= 1e18) revert IAppErrors.ErrorWrongMultiplier(multiplier);
    uint base = treasuryBalance * multiplier / 1e18;

    if (biomeLevel < lvlForMint) {
      // reduce base on biome difference
      base = base / 2 ** (lvlForMint - biomeLevel + 10);
    }
    return base;
  }
  //endregion ------------------------ Common

  //region ------------------------ Main logic

  /// @notice Make an action with object, update hero params according results
  function objectAction(
    IDungeonFactory.DungeonStatus storage dungStatus,
    IDungeonFactory.DungeonAttributes storage dungAttributes,
    uint64 dungId,
    address msgSender,
    bytes memory data,
    IController controller,
    uint32 currentObject_
  ) external returns (
    bool isCompleted,
    uint currentStage,
    uint32 currentObject,
    bool clear
  ) {
    IGOC.ActionResult memory a;
    ControllerContextLib.ControllerContext memory cc = ControllerContextLib.init(controller);
    return _objectAction(
      ObjectActionInternalData({
        dungId: dungId,
        msgSender: msgSender,
        data: data,
        heroToken: dungStatus.heroToken,
        heroTokenId: dungStatus.heroTokenId,
        objectId: currentObject_,
        currentStage: dungStatus.currentStage,
        biome: uint(dungAttributes.biome),
        statController: ControllerContextLib.getStatController(cc),
        result: a,
        stats: IStatController.ChangeableStats(0, 0, 0, 0, 0),
        stages: uint(dungStatus.stages),
        isBattleObj: false
      }),
      dungStatus,
      dungAttributes,
      cc
    );
  }

  /// @notice Make an action with object, update hero params according results
  /// @param c Context
  /// @return isCompleted The dungeon is completed (there is no new stage to pass)
  /// @return newStage Next stage (0 if the dungeon is completed)
  /// @return currentObject Id of the current object. It's always 0 if new stage is selected (new object is not opened)
  /// @return clear True if dungStatus of the hero should be cleared and the dungeon should be added to free dungeon list
  function _objectAction(
    ObjectActionInternalData memory c,
    IDungeonFactory.DungeonStatus storage dungStatus,
    IDungeonFactory.DungeonAttributes storage dungAttributes,
    ControllerContextLib.ControllerContext memory cc
  ) internal returns (
    bool isCompleted,
    uint newStage,
    uint32 currentObject,
    bool clear
  ) {
    // isCompleted = false;
    currentObject = c.objectId;
    // newStage = 0;

    // check restrictions, most of them are checked by the caller
    if (c.objectId == 0) revert IAppErrors.ErrorNotObject2();

    c.isBattleObj = ControllerContextLib.getGameObjectController(cc).isBattleObject(c.objectId);
    c.result = ControllerContextLib.getGameObjectController(cc).action(
      c.msgSender, c.dungId, c.objectId, c.heroToken, c.heroTokenId, c.currentStage, c.data
    );

    if (c.isBattleObj) {
      _markSkillSlotsForDurabilityReduction(
        _S(),
        c.statController,
        ControllerContextLib.getItemController(cc),
        c.data,
        c.heroToken,
        c.heroTokenId
      );
    }

    c.stats = c.statController.heroStats(c.heroToken, c.heroTokenId);
    if (c.stats.mana < c.result.manaConsumed.toUint()) {
      revert IAppErrors.ErrorNotEnoughMana(c.stats.mana, c.result.manaConsumed.toUint());
    }

    if (c.result.kill || c.stats.life <= c.result.damage.toUint()) {
      c.result.kill = true;
      _changeCurrentDungeon(_S(), c.heroToken, c.heroTokenId, 0);
      IHeroController hc = ControllerContextLib.getHeroController(cc);
      hc.releaseReinforcement(c.heroToken, c.heroTokenId);

      // in case of death we need to remove rewrote objects and reset initial stages
      _resetUniqueObjects(dungStatus, dungAttributes);

      // no need to release if we completed the dungeon - we will never back on the same
      _releaseSkillSlotsForDurabilityReduction(_S(), c.heroToken, c.heroTokenId);

      // if it was the last life chance - kill the hero
      if (c.stats.lifeChances <= 1) {
        _killHero(hc, c.dungId, c.heroToken, c.heroTokenId, dungStatus.treasuryItems);
      } else {
        _afterObjCompleteForSurvivedHero(c, cc);
        _reduceLifeChances(c.statController, c.heroToken, c.heroTokenId, c.stats.life, c.stats.mana);

        // scb-1000: soft death resets used consumables
        c.statController.clearUsedConsumables(c.heroToken, c.heroTokenId);
        // also soft death reset all buffs
        c.statController.clearTemporallyAttributes(c.heroToken, c.heroTokenId);
      }

      // scb-994: increment death count counter
      uint deathCounter = c.statController.heroCustomData(c.heroToken, c.heroTokenId, StatControllerLib.DEATH_COUNT_HASH);
      c.statController.setHeroCustomData(c.heroToken, c.heroTokenId, StatControllerLib.DEATH_COUNT_HASH, deathCounter + 1);

      clear = true;
    } else {
      _increaseChangeableStats(c.statController, c.heroToken, c.heroTokenId, c.result);
      _decreaseChangeableStats(c.statController, c.heroToken, c.heroTokenId, c.result);
      _mintItems(c, cc, dungStatus.treasuryItems);
      if (c.result.completed) {
        _afterObjCompleteForSurvivedHero(c, cc);
        (isCompleted, newStage, currentObject) = _nextRoomOrComplete(c, cc, dungStatus, c.stages, dungStatus.treasuryTokens);
      }
      // clear = false;
    }

    emit IApplicationEvents.ObjectAction(c.dungId, c.result, c.currentStage, c.heroToken, c.heroTokenId, newStage);
    return (isCompleted, newStage, currentObject, clear);
  }

  /// @notice Hero exists current dungeon forcibly same as when dying but without loosing life chance and keeping all items equipped
  /// @dev Dungeon state is cleared outside
  function exitForcibly(
    address heroToken,
    uint heroTokenId,
    IDungeonFactory.DungeonStatus storage dungStatus,
    IDungeonFactory.DungeonAttributes storage dungAttributes,
    ControllerContextLib.ControllerContext memory cc
  ) internal {
    _changeCurrentDungeon(_S(), heroToken, heroTokenId, 0);
    IHeroController hc = ControllerContextLib.getHeroController(cc);
    IStatController sc = ControllerContextLib.getStatController(cc);

    hc.releaseReinforcement(heroToken, heroTokenId);
    _resetUniqueObjects(dungStatus, dungAttributes);

    // equipped items are NOT taken off
    // life => 1, mana => 0
    hc.resetLifeAndMana(heroToken, heroTokenId);

    sc.clearUsedConsumables(heroToken, heroTokenId);
    sc.clearTemporallyAttributes(heroToken, heroTokenId);
  }

  //endregion ------------------------ Main logic

  //region ------------------------ Main logic - auxiliary functions

  /// @notice If hero has dead in the dungeon, it's necessary to restore initial set of unique objects,
  ///         in other words, all changes introduces by {_nextRoomOrComplete} should be thrown away.
  function _resetUniqueObjects(
    IDungeonFactory.DungeonStatus storage dungStatus,
    IDungeonFactory.DungeonAttributes storage dungAttributes
  ) internal {
    dungStatus.stages = dungAttributes.stages;
    delete dungStatus.uniqObjects;

    uint32[] memory uniqObjects = dungAttributes.uniqObjects;
    for (uint i; i < uniqObjects.length; ++i) {
      dungStatus.uniqObjects.push(uniqObjects[i]);
    }
  }

  /// @notice Kill the hero, take hero's tokens and items
  function _killHero(
    IHeroController heroController,
    uint64 dungId,
    address heroToken,
    uint heroTokenId,
    bytes32[] storage treasuryItems
  ) internal {
    (bytes32[] memory drop) = heroController.kill(heroToken, heroTokenId);
    _putHeroItemToDungeon(dungId, drop, treasuryItems);
  }

  /// @notice All hero's items are taken by the dungeon
  function _putHeroItemToDungeon(uint64 dungId, bytes32[] memory drop, bytes32[] storage treasuryItems) internal {
    uint dropLength = drop.length;
    for (uint i; i < dropLength; ++i) {
      treasuryItems.push(drop[i]);
      (address itemAdr, uint itemId) = drop[i].unpackNftId();
      emit IApplicationEvents.AddTreasuryItem(dungId, itemAdr, itemId);
    }
  }

  /// @notice If battle object: reduce equipped items durability and clear temporally attributes
  /// @dev Not necessary to call if a hero is dead
  function _afterObjCompleteForSurvivedHero(
    ObjectActionInternalData memory context,
    ControllerContextLib.ControllerContext memory cc
  ) internal {
    if (context.isBattleObj) {
      // reduce equipped items durability
      ControllerContextLib.getItemController(cc).reduceDurability(context.heroToken, context.heroTokenId, uint8(context.biome), false);
      // clear temporally attributes
      context.statController.clearTemporallyAttributes(context.heroToken, context.heroTokenId);
    }
  }

  /// @notice Check if the dungeon is completed, calculate index of the next stage.
  /// @dev Take {rewriteNextObject} from the results of the previous action and set next objects for the dungeon
  /// @param curStages Current value of dungStatus.stages
  /// @return isCompleted The dungeon is completed
  /// @return currentStage Next stage (0 if the dungeon is completed)
  /// @return currentObj Always 0. It means, that new current object should be opened.
  function _nextRoomOrComplete(
    ObjectActionInternalData memory context,
    ControllerContextLib.ControllerContext memory cc,
    IDungeonFactory.DungeonStatus storage dungStatus,
    uint curStages,
    EnumerableMap.AddressToUintMap storage treasuryTokens
  ) internal returns (
    bool isCompleted,
    uint currentStage,
    uint32 currentObj
  ) {
    uint len = context.result.rewriteNextObject.length;

    if (context.currentStage + 1 >= curStages && len == 0) {
      // if we have reduced drop then do not mint token at all
      if (StatLib.mintDropChanceDelta(context.stats.experience, context.stats.level, context.biome) == 0) {
        _mintGameTokens(
          context.dungId,
          cc,
          StatLib.getVirtualLevel(context.stats.experience, context.stats.level, true),
          context.biome,
          treasuryTokens,
          context.heroToken,
          context.heroTokenId
        );
      }
      isCompleted = true;
    } else {
      // need to extend stages for new rewrite objects size
      uint newStages = context.currentStage + 1 + len;
      if (curStages < newStages) {
        dungStatus.stages = uint8(newStages);

        // need to extend exist array
        dungStatus.uniqObjects = new uint32[](newStages);
        // no need to write again old uniq objects, they will be updated in case of hero death
      }

      for (uint i; i < len; ++i) {
        uint32 nextObjId = context.result.rewriteNextObject[i];
        dungStatus.uniqObjects[context.currentStage + 1 + i] = nextObjId;
      }

      currentStage = context.currentStage + 1;
    }

    // currentObj is 0 by default
    return (isCompleted, currentStage, currentObj);
  }

  /// @notice Increase life, mana and lifeChances according to the action {result}
  function _increaseChangeableStats(
    IStatController statController,
    address heroToken,
    uint heroTokenId,
    IGOC.ActionResult memory result
  ) internal {
    if (result.heal != 0 || result.manaRegen != 0 || result.experience != 0 || result.lifeChancesRecovered != 0) {
      statController.changeCurrentStats(
        heroToken,
        heroTokenId,
        IStatController.ChangeableStats({
          level: 0,
          experience: result.experience,
          life: uint32(result.heal.toUint()),
          mana: uint32(result.manaRegen.toUint()),
          lifeChances: uint32(result.lifeChancesRecovered.toUint())
        }),
        true
      );
    }
  }

  /// @notice Decrease life and mana according to the action {result}
  function _decreaseChangeableStats(
    IStatController statController,
    address heroToken,
    uint heroTokenId,
    IGOC.ActionResult memory result
  ) internal {
    // decrease changeable stats
    if (result.damage != 0 || result.manaConsumed != 0) {
      statController.changeCurrentStats(
        heroToken,
        heroTokenId,
        IStatController.ChangeableStats({
          level: 0,
          experience: 0,
          life: uint32(result.damage.toUint()),
          mana: uint32(result.manaConsumed.toUint()),
          lifeChances: 0
        }),
        false
      );
    }
  }

  /// @notice Decrease lifeChances on 1, restore life and mana to full
  function _reduceLifeChances(IStatController statController, address hero, uint heroId, uint32 curLife, uint32 curMana) internal {
    uint32 lifeFull = uint32(CalcLib.toUint(statController.heroAttribute(hero, heroId, uint(IStatController.ATTRIBUTES.LIFE))));
    uint32 manaFull = uint32(CalcLib.toUint(statController.heroAttribute(hero, heroId, uint(IStatController.ATTRIBUTES.MANA))));

    // --------- reduce life chance
    statController.changeCurrentStats(
      hero,
      heroId,
      IStatController.ChangeableStats({level: 0, experience: 0, life: 0, mana: 0, lifeChances: 1}),
      false
    );

    // --------- restore life and mana to full
    statController.changeCurrentStats(
      hero,
      heroId,
      IStatController.ChangeableStats({
        level: 0,
        experience: 0,
        life: AppLib.sub0(lifeFull, curLife),
        mana: AppLib.sub0(manaFull, curMana),
        lifeChances: 0
      }),
      true
    );
  }

  /// @notice Mint mint-items from {result}, add them to {treasuryItems}
  function _mintItems(
    ObjectActionInternalData memory context,
    ControllerContextLib.ControllerContext memory cc,
    bytes32[] storage treasuryItems
  ) internal {
    uint64 dungId = context.dungId;
    IGOC.ActionResult memory result = context.result;

    IItemController ic = ControllerContextLib.getItemController(cc);

    for (uint i; i < result.mintItems.length; i++) {
      if (result.mintItems[i] == address(0)) {
        continue;
      }
      uint itemId = ic.mint(result.mintItems[i], address(this));
      treasuryItems.push(result.mintItems[i].packNftId(itemId));
      emit IApplicationEvents.AddTreasuryItem(dungId, result.mintItems[i], itemId);
    }
  }

  /// @notice Register game-token in {treasuryTokens}, mint dungeon reward
  function _mintGameTokens(
    uint64 dungId,
    ControllerContextLib.ControllerContext memory cc,
    uint lvlForMint,
    uint biome,
    EnumerableMap.AddressToUintMap storage treasuryTokens,
    address hero,
    uint heroId
  ) private {
    IHeroController heroController = ControllerContextLib.getHeroController(cc);
    uint maxOpenedNgLevel = heroController.maxOpenedNgLevel();
    uint heroNgLevel = heroController.getHeroInfo(hero, heroId).ngLevel;

    IGameToken gameToken = ControllerContextLib.getGameToken(cc);
    uint amount = IMinter(gameToken.minter()).mintDungeonReward(dungId, biome, lvlForMint);
    // Total amount of rewards should be equal to: reward = normal_reward * (1 + NG_LVL) / ng_sum
    // We have minted {amount}, so we should burn off {amount - reward}.
    // {amount} is exactly equal to {reward} only if NG_LVL is 0
    uint reward = amount * (1 + heroNgLevel) / RewardsPoolLib.getNgSum(maxOpenedNgLevel);
    if (amount > reward) {
      gameToken.burn(amount - reward);
      amount = reward;
    }
    
    _registerTreasuryToken(address(gameToken), treasuryTokens, amount);
    emit IApplicationEvents.AddTreasuryToken(dungId, address(gameToken), amount);
  }

  /// @notice Add {rewardToken} to {treasuryTokens} if it's not add there already
  function _registerTreasuryToken(address rewardToken, EnumerableMap.AddressToUintMap storage treasuryTokens, uint amount) internal {
    (bool exist, uint existAmount) = treasuryTokens.tryGet(rewardToken);

    if (!exist || existAmount + amount > 0) {
      uint balance = IERC20(rewardToken).balanceOf(address(this));
      if (balance < existAmount + amount) {
        revert IAppErrors.NotEnoughTokens(balance, existAmount + amount);
      }

      treasuryTokens.set(rewardToken, existAmount + amount);
    }
  }
  //endregion ------------------------ Main logic - auxiliary functions

  //region ------------------------ ENTER/EXIT

  /// @notice Hero enters to the dungeon. Check requirements before entering, update status of the hero and the dungeon.
  function _enter(
    ControllerContextLib.ControllerContext memory cc,
    IDungeonFactory.DungeonStatus storage dungStatus,
    IDungeonFactory.DungeonAttributes storage dungAttrs,
    uint16 dungNum,
    uint64 dungId,
    address heroToken,
    uint heroTokenId
  ) internal {
    IDungeonFactory.MainState storage s = _S();

    IStatController.ChangeableStats memory stats = ControllerContextLib.getStatController(cc).heroStats(heroToken, heroTokenId);
    uint8 dungBiome = dungAttrs.biome;

    if (ControllerContextLib.getReinforcementController(cc).isStaked(heroToken, heroTokenId)) revert IAppErrors.Staked(heroToken, heroTokenId);
    if (stats.lifeChances == 0) revert IAppErrors.ErrorHeroIsDead(heroToken, heroTokenId);
    if (s.heroCurrentDungeon[heroToken.packNftId(heroTokenId)] != 0) revert IAppErrors.ErrorAlreadyInDungeon();
    // assume here that onlyEnteredHeroOwner is already checked by the caller

    if (ControllerContextLib.getHeroController(cc).heroBiome(heroToken, heroTokenId) != dungBiome) revert IAppErrors.ErrorNotBiome();
    if (dungStatus.heroToken != address(0)) revert IAppErrors.ErrorDungeonBusy();
    if (!isDungeonEligibleForHero(s, ControllerContextLib.getStatController(cc), dungNum, uint8(stats.level), heroToken, heroTokenId)) {
      revert IAppErrors.ErrorNotEligible(heroToken, dungNum);
    }

    // remove free dungeon
    if (s.freeDungeons[dungBiome].remove(uint(dungId))) {
      emit IApplicationEvents.FreeDungeonRemoved(dungBiome, dungId);
    }

    _changeCurrentDungeon(s, heroToken, heroTokenId, dungId);
    if (dungStatus.currentStage != 0) {
      dungStatus.currentStage = uint8(0);
    }
    dungStatus.heroToken = heroToken;
    dungStatus.heroTokenId = heroTokenId;

    emit IApplicationEvents.Entered(dungId, heroToken, heroTokenId);
  }

  /// @notice Check if dungeon is eligible for the hero
  /// @param dungNum Dungeon logic id
  function isDungeonEligibleForHero(
    IDungeonFactory.MainState storage s,
    IStatController statController,
    uint16 dungNum,
    uint8 heroLevel,
    address heroToken,
    uint heroTokenId
  ) internal view returns (bool) {
    IDungeonFactory.DungeonAttributes storage dungAttr = s.dungeonAttributes[dungNum];

    // check if the hero level is in the range required by the dungeon
    {
      (uint minLevel, uint maxLevel,) = dungAttr.minMaxLevel.unpackUint8Array3();
      if (heroLevel < minLevel || heroLevel > maxLevel) {
        return false;
      }
    }

    // check if hero/global custom values are in the ranges required by the dungeon
    bytes32[] memory requiredCustomDataIndex = dungAttr.requiredCustomDataIndex;
    bytes32[] memory requiredCustomDataValue = dungAttr.requiredCustomDataValue;

    uint len = requiredCustomDataIndex.length;
    for (uint i; i < len; ++i) {
      bytes32 index = requiredCustomDataIndex[i];
      if (index == bytes32(0)) continue;

      (uint64 min, uint64 max, bool isHeroValue) = requiredCustomDataValue[i].unpackCustomDataRequirements();

      uint value = isHeroValue
        ? statController.heroCustomData(heroToken, heroTokenId, index)
        : statController.globalCustomData(index);

      if (value < uint(min) || value > uint(max)) {
        return false;
      }
    }

    return true;
  }

  /// @notice Select logic for the new dungeon
  function getDungeonLogic(
    IDungeonFactory.MainState storage s_,
    ControllerContextLib.ControllerContext memory cc,
    uint8 heroLevel,
    address heroToken,
    uint heroTokenId,
    uint random
  ) internal view returns (uint16) {
    if (heroLevel == 0) revert IAppErrors.ErrorHeroLevelStartFrom1();

    uint8 heroBiome;
    {
      IHeroController hc = ControllerContextLib.getHeroController(cc);
      heroBiome = hc.heroBiome(heroToken, heroTokenId);

      // try to get specific dungeon
      // specific dungeon for concrete level and class
      uint16 specificDungeon = s_.dungeonSpecific[_toUint8PackedArray(heroLevel / uint8(StatLib.BIOME_LEVEL_STEP) + 1, hc.heroClass(heroToken))];
      // if no specific dungeon for concrete class try to find for all classes
      if (specificDungeon == 0) {
        specificDungeon = s_.dungeonSpecific[_toUint8PackedArray(heroLevel / uint8(StatLib.BIOME_LEVEL_STEP) + 1, 0)];
      }
      // if no specific dungeon for concrete class and level try to find for all classes and all levels
      if (specificDungeon == 0) {
        // in this case we have 1 specific dungeon for all classes and levels, and only 1, suppose to be initial territory
        specificDungeon = s_.dungeonSpecific[_toUint8PackedArray(0, 0)];
      }

      if (specificDungeon != 0) {
        if (!s_.specificDungeonCompleted[heroToken.packDungeonKey(uint64(heroTokenId), specificDungeon)]
        && s_.dungeonAttributes[specificDungeon].biome == heroBiome) {
          return specificDungeon;
        }
      }
    }

    EnumerableSet.UintSet storage dungs = s_.dungeonsLogicByBiome[heroBiome];
    uint size = dungs.length();
    if (size == 0) revert IAppErrors.ErrorNoDungeonsForBiome(heroBiome);

    IStatController statController = ControllerContextLib.getStatController(cc);
    uint16 dungeonLogic;
    uint dungeonIndex = random % size;
    for (uint i; i < size; ++i) {
      dungeonLogic = uint16(dungs.at(dungeonIndex));

      if (isDungeonEligibleForHero(s_, statController, dungeonLogic, heroLevel, heroToken, heroTokenId)) {
        return dungeonLogic;
      }
      dungeonIndex++;
      if (dungeonIndex >= size) {
        dungeonIndex = 0;
      }
    }

    revert IAppErrors.ErrorNoEligibleDungeons();
  }

  /// @notice Exit the dungeon
  /// @param claim Claim treasure items and tokens
  function exitDungeon(IController controller, uint64 dungId, bool claim, address msgSender) external {
    IDungeonFactory.DungeonStatus storage dungStatus = _S().dungeonStatuses[dungId];
    ControllerContextLib.ControllerContext memory cc = ControllerContextLib.init(controller);
    address heroToken = dungStatus.heroToken;
    uint heroTokenId = dungStatus.heroTokenId;

    if (!dungStatus.isCompleted) revert IAppErrors.ErrorNotCompleted();
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
    if (IERC721(heroToken).ownerOf(heroTokenId) != msgSender) revert IAppErrors.ErrorNotOwner(heroToken, heroTokenId);
    if (_S().heroCurrentDungeon[heroToken.packNftId(heroTokenId)] != dungId) revert IAppErrors.ErrorHeroNotInDungeon();

    IHeroController heroController = ControllerContextLib.getHeroController(cc);
    (address payToken,) = heroController.payTokenInfo(heroToken);

    _setDungeonCompleted(_S(), dungStatus.dungNum, dungId, heroToken, heroTokenId);

    if (claim) {
      _claimAll(cc, msgSender, dungId, dungStatus, heroToken, heroTokenId, payToken);
    }
    _heroExit(_S(), heroController, heroToken, heroTokenId);

    if (payToken == address(0)) {
      // F2P hero doesn't have pay token, he is destroyed after exit of the dungeon
      _killHero(heroController, dungId, heroToken, heroTokenId, dungStatus.treasuryItems);
    }

    // register daily activity
    address userController = controller.userController();
    if (userController != address(0)) {
      IUserController(userController).registerPassedDungeon(msgSender);
    }

    emit IApplicationEvents.Exit(dungId, claim);
  }

  /// @notice Emergency exit: the governance can drop the hero from dungeon in emergency
  function emergencyExit(IController controller, uint64 dungId) external {
    IDungeonFactory.MainState storage s = _S();
    // assume that governance-restriction is checked on caller side
    IDungeonFactory.DungeonStatus storage dungStatus = s.dungeonStatuses[dungId];

    _heroExit(s, IHeroController(controller.heroController()), dungStatus.heroToken, dungStatus.heroTokenId);

    dungStatus.isCompleted = true;
    dungStatus.heroToken = address(0);
    dungStatus.heroTokenId = 0;

    emit IApplicationEvents.Exit(dungId, false);
  }

  //endregion ------------------------ ENTER/EXIT

  //region ------------------------ ENTER/EXIT auxiliary functions
  /// @dev this function should emit event to indicate dungeon remove
  function _setDungeonCompleted(IDungeonFactory.MainState storage s, uint16 dungNum, uint64 dungeonId, address heroToken, uint heroTokenId) internal {
    if (s.allSpecificDungeons.contains(dungNum)) {
      s.specificDungeonCompleted[heroToken.packDungeonKey(uint64(heroTokenId), dungNum)] = true;
    }
    emit IApplicationEvents.DungeonCompleted(dungNum, dungeonId, heroToken, heroTokenId);
  }

  /// @notice Change current dungeon of the hero to 0 and release his reinforcement
  function _heroExit(IDungeonFactory.MainState storage s, IHeroController heroController, address heroToken, uint heroTokenId) internal {
    _changeCurrentDungeon(s, heroToken, heroTokenId, 0);
    heroController.releaseReinforcement(heroToken, heroTokenId);
  }

  /// @notice Change current dungeon of the hero to the {dungeonId}
  function _changeCurrentDungeon(IDungeonFactory.MainState storage s, address hero, uint heroId, uint64 dungeonId) internal {
    s.heroCurrentDungeon[hero.packNftId(heroId)] = dungeonId;
    emit IApplicationEvents.HeroCurrentDungeonChanged(hero, heroId, dungeonId);
  }

  /// @notice Enumerate busy slots of the hero, find all SKILL_XXX and return their addresses and ids
  /// @return skillSlotAdr Addresses of available skills. 0 - SKILL_1, 1 - SKILL_2, 2 - SKILL_3.
  ///                      Address is zero if the hero doesn't have the corresponded skill.
  /// @return skillSlotIds Ids of available skills. 0 - SKILL_1, 1 - SKILL_2, 2 - SKILL_3
  ///                      ID is zero if the hero doesn't have the corresponded skill.
  function _getSkillSlotsForHero(IStatController statCtr, address heroToken, uint heroTokenId) internal view returns (
    address[3] memory skillSlotAdr,
    uint[3] memory skillSlotIds
  ) {
    uint8[] memory busySlots = statCtr.heroItemSlots(heroToken, uint64(heroTokenId));

    for (uint i; i < busySlots.length; ++i) {
      if (busySlots[i] == uint8(IStatController.ItemSlots.SKILL_1)) {
        (skillSlotAdr[0], skillSlotIds[0]) = statCtr.heroItemSlot(heroToken, uint64(heroTokenId), busySlots[i]).unpackNftId();
      }
      if (busySlots[i] == uint8(IStatController.ItemSlots.SKILL_2)) {
        (skillSlotAdr[1], skillSlotIds[1]) = statCtr.heroItemSlot(heroToken, uint64(heroTokenId), busySlots[i]).unpackNftId();
      }
      if (busySlots[i] == uint8(IStatController.ItemSlots.SKILL_3)) {
        (skillSlotAdr[2], skillSlotIds[2]) = statCtr.heroItemSlot(heroToken, uint64(heroTokenId), busySlots[i]).unpackNftId();
      }
    }

    return (skillSlotAdr, skillSlotIds);
  }

  /// @notice Generate map[3] for SKILL_1, SKILL_2, SKILL_3 (0 - not marked, 1 - marked)
  ///         and save the map to {s_}._skillSlotsForDurabilityReduction as packed uint8[]
  /// @dev mark skill slots for durability reduction
  /// SIP-001: take into account hero's skills only and ignore skills of the helper
  /// @param data abi.encoded IFightCalculator.AttackInfo
  function _markSkillSlotsForDurabilityReduction(
    IDungeonFactory.MainState storage s_,
    IStatController sc,
    IItemController itemController,
    bytes memory data,
    address heroToken,
    uint heroTokenId
  ) internal {
    uint8[] memory map = new uint8[](3);
    (IFightCalculator.AttackInfo memory attackInfo) = abi.decode(data, (IFightCalculator.AttackInfo));

    uint length = attackInfo.skillTokens.length;

    if (length != 0 || attackInfo.attackToken != address(0)) {

      (address[3] memory skillSlotAdr, uint[3] memory skillSlotIds) = _getSkillSlotsForHero(sc, heroToken, heroTokenId);

      for (uint i; i < length; ++i) {
        address token = attackInfo.skillTokens[i];
        uint tokenId = attackInfo.skillTokenIds[i];

        // The hero is able to use own skills OR the skills of the helper. Take into account only own hero's skills here
        (address h,) = itemController.equippedOn(token, tokenId);
        if (h == heroToken) {
          if (token == skillSlotAdr[0] && tokenId == skillSlotIds[0]) {
            map[0] = 1;
          } else if (token == skillSlotAdr[1] && tokenId == skillSlotIds[1]) {
            map[1] = 1;
          } else if (token == skillSlotAdr[2] && tokenId == skillSlotIds[2]) {
            map[2] = 1;
          }
        }
      }

      if (attackInfo.attackToken == skillSlotAdr[0] && attackInfo.attackTokenId == skillSlotIds[0]) {
        map[0] = 1;
      } else if (attackInfo.attackToken == skillSlotAdr[1] && attackInfo.attackTokenId == skillSlotIds[1]) {
        map[1] = 1;
      } else if (attackInfo.attackToken == skillSlotAdr[2] && attackInfo.attackTokenId == skillSlotIds[2]) {
        map[2] = 1;
      }
    }

    // write even empty map for clear prev values
    s_.skillSlotsForDurabilityReduction[heroToken.packNftId(heroTokenId)] = map.packUint8Array();
  }

  /// @dev clear all skill slots marks
  function _releaseSkillSlotsForDurabilityReduction(IDungeonFactory.MainState storage s_, address heroToken, uint heroTokenId) internal {
    delete s_.skillSlotsForDurabilityReduction[heroToken.packNftId(heroTokenId)];
  }

  //endregion ------------------------ ENTER/EXIT auxiliary functions

  //region ------------------------ CLAIM

  /// @notice Claim all treasure tokens and items registered for the given hero.
  ///         The tokens are send to msgSender and/or helper, or they can be send to controller or burned.
  ///         The items are transferred to msgSender or helper (random choice) or destroyed (F2P hero).
  /// @dev ClaimContext is used both for lazy initialization and to extend limits of allowed local vars.
  /// @param heroPayToken Hero pay token. It's zero for hero 5.
  function _claimAll(
    ControllerContextLib.ControllerContext memory cc,
    address msgSender,
    uint64 dungId,
    IDungeonFactory.DungeonStatus storage dungStatus,
    address heroToken,
    uint heroTokenId,
    address heroPayToken
  ) internal {
    ClaimContext memory context;

    context.msgSender = msgSender;
    context.dungId = dungId;

    (context.helpHeroToken, context.helpHeroId) = ControllerContextLib.getHeroController(cc).heroReinforcementHelp(heroToken, heroTokenId);
    context.toHelperRatio = ControllerContextLib.getReinforcementController(cc).toHelperRatio(context.helpHeroToken, context.helpHeroId);

    context.itemLength = dungStatus.treasuryItems.length;
    context.tokenLength = dungStatus.treasuryTokens.length();
    context.tokens = new address[](context.tokenLength);
    context.amounts = new uint[](context.tokenLength);

    context.heroPayToken = heroPayToken;

    // need to write tokens separately coz we need to delete them from map
    for (uint i; i < context.tokenLength; i++) {
      (context.tokens[i], context.amounts[i]) = dungStatus.treasuryTokens.at(i);
    }

    for (uint i; i < context.tokenLength; i++) {
      _claimToken(dungStatus.treasuryTokens, context, cc, context.tokens[i], context.amounts[i]);
    }

    for (uint i; i < context.itemLength; i++) {
      (address itemAdr, uint itemId) = dungStatus.treasuryItems[i].unpackNftId();
      _claimItem(context, cc, itemAdr, itemId);
    }

    delete dungStatus.treasuryItems;
  }

  /// @notice Remove {token} from treasuryTokens, transfer/burn token {amount}
  function _claimToken(
    EnumerableMap.AddressToUintMap storage treasuryTokens,
    ClaimContext memory context,
    ControllerContextLib.ControllerContext memory cc,
    address token,
    uint amount
  ) internal {
    treasuryTokens.remove(token);
    if (amount != 0) {

      if (context.heroPayToken == address(0)) {
        if (token == address(ControllerContextLib.getGameToken(cc))) {
          IGameToken(token).burn(amount);
        } else {
          IERC20(token).transfer(address(cc.controller), amount);
        }

      } else {
        uint toHelper = context.helpHeroToken == address(0)
          ? 0
          : amount * context.toHelperRatio / 100;

        uint toHeroOwner = amount - toHelper;
        if (toHeroOwner != 0) {
          IERC20(token).transfer(context.msgSender, toHeroOwner);
        }

        if (toHelper != 0) {
          IReinforcementController reinforcementController = ControllerContextLib.getReinforcementController(cc);
          IERC20(token).transfer(address(reinforcementController), toHelper);
          reinforcementController.registerTokenReward(context.helpHeroToken, context.helpHeroId, token, toHelper);
        }

        emit IApplicationEvents.ClaimToken(context.dungId, token, amount);
      }
    }
  }

  /// @notice Destroy item (for F2P) or transfer the item to helper/sender (random choice)
  function _claimItem(
    ClaimContext memory context,
    ControllerContextLib.ControllerContext memory cc,
    address token,
    uint tokenId
  ) internal {
    if (IERC721(token).ownerOf(tokenId) == address(this)) {

      if (context.heroPayToken == address(0)) {
        // if it is F2P hero destroy all drop
        ControllerContextLib.getItemController(cc).destroy(token, tokenId);
      } else {

        bool toHelper = false;
        if (context.helpHeroToken != address(0)) {
          toHelper = ControllerContextLib.getOracle(cc).getRandomNumber(100, 0) < context.toHelperRatio;
        }

        if (toHelper) {
          IReinforcementController reinforcementController = ControllerContextLib.getReinforcementController(cc);
          IERC721(token).safeTransferFrom(address(this), address(reinforcementController), tokenId);
          reinforcementController.registerNftReward(context.helpHeroToken, context.helpHeroId, token, tokenId);
        } else {
          IERC721(token).safeTransferFrom(address(this), context.msgSender, tokenId);
        }

        emit IApplicationEvents.ClaimItem(context.dungId, token, tokenId);
      }
    }
  }
  //endregion ------------------------ CLAIM

  //region ------------------------ Utils
  function _toUint8PackedArray(uint8 val0, uint8 val1) internal pure returns (bytes32 key) {
    return PackingLib.packUint8Array3(val0, val1, 0);
  }

  function _toUint8ArrayWithoutZeroes(bytes32 data) internal pure returns (uint8[] memory result) {
    uint8[] memory arr = data.unpackUint8Array();

    uint newSize;
    for (uint i; i < arr.length; ++i) {
      if (arr[i] == 0) {
        break;
      }
      newSize++;
    }

    result = new uint8[](newSize);
    for (uint i; i < newSize; ++i) {
      result[i] = arr[i];
    }
  }
  //endregion ------------------------ Utils
}
