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
    address msgSender;
    address guildBank;
    address[] tokens;
    /// @notice list of items sent to ItemBox
    address[] items;

    uint8 biome;
    uint8 sandboxMode;
    uint64 dungId;

    /// @dev Limited by ReinforcementController._TO_HELPER_RATIO_MAX
    uint toHelperRatio;
    uint itemLength;
    uint tokenLength;
    uint helpHeroId;

    /// @notice Percent of tax that is taken if favor of biome owner, decimals 3
    uint taxPercent;
    uint guildId;

    uint[] amounts;

    /// @notice list of items sent to ItemBox
    uint[] itemIds;
    /// @notice Actual count of items sent to the ItemBox
    uint countItems;
  }

  /// @notice Various cases of using _onHeroKilled
  enum DungeonExitMode {
    ACTION_ENDED_0,

    /// @notice Exit using special item. Life => 1, mana => 0, keep items
    FORCED_EXIT_1,

    /// @notice SCR-1446: Exit with suicide. Loose life chance, restore life and mana, keep items
    HERO_SUICIDE_2
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

  //region ------------------------ Restrictions
  function onlyOwner(address hero, uint heroId, address msgSender) internal view {
    if (IERC721(hero).ownerOf(heroId) != msgSender) revert IAppErrors.ErrorNotOwner(hero, heroId);
  }
  //region ------------------------ Restrictions


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
        statController: ControllerContextLib.statController(cc),
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

    c.isBattleObj = ControllerContextLib.gameObjectController(cc).isBattleObject(c.objectId);
    c.result = ControllerContextLib.gameObjectController(cc).action(
      c.msgSender, c.dungId, c.objectId, c.heroToken, c.heroTokenId, c.currentStage, c.data
    );

    if (c.isBattleObj) {
      _markSkillSlotsForDurabilityReduction(
        _S(),
        c.statController,
        ControllerContextLib.itemController(cc),
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

      _exitActionEnd(c, dungStatus, dungAttributes, cc);

      // scb-994: increment death count counter
      uint deathCounter = c.statController.heroCustomData(c.heroToken, c.heroTokenId, StatControllerLib.DEATH_COUNT_HASH);
      c.statController.setHeroCustomData(c.heroToken, c.heroTokenId, StatControllerLib.DEATH_COUNT_HASH, deathCounter + 1);

      clear = true;
    } else {
      _increaseChangeableStats(c.statController, c.heroToken, c.heroTokenId, c.result);
      _decreaseChangeableStats(c.statController, c.heroToken, c.heroTokenId, c.result);
      _mintItems(c, cc, dungStatus.treasuryItems);
      if (c.result.completed) {
        _afterObjCompleteForSurvivedHero(c.heroToken, c.heroTokenId, c.biome, c.isBattleObj, cc, address(c.statController));
        (isCompleted, newStage, currentObject) = _nextRoomOrComplete(c, cc, dungStatus, c.stages, dungStatus.treasuryTokens);
      }
      // clear = false;
    }

    emit IApplicationEvents.ObjectAction(c.dungId,
      IGOC.ActionResultEvent(
        {
          kill: c.result.kill,
          completed: c.result.completed,
          heroToken: c.result.heroToken,
          mintItems: c.result.mintItems,
          heal: c.result.heal,
          manaRegen: c.result.manaRegen,
          lifeChancesRecovered: c.result.lifeChancesRecovered,
          damage: c.result.damage,
          manaConsumed: c.result.manaConsumed,
          objectId: c.result.objectId,
          experience: c.result.experience,
          heroTokenId: c.result.heroTokenId,
          iteration: c.result.iteration,
          rewriteNextObject: c.result.rewriteNextObject
        }
      )
    , c.currentStage, c.heroToken, c.heroTokenId, newStage);
    return (isCompleted, newStage, currentObject, clear);
  }

  /// @notice Hero exists current dungeon forcibly
  /// @dev Dungeon state is cleared outside
  function exitSpecial(
    address hero,
    uint heroId,
    IDungeonFactory.DungeonStatus storage dungStatus,
    IDungeonFactory.DungeonAttributes storage dungAttributes,
    ControllerContextLib.ControllerContext memory cc,
    DungeonLib.DungeonExitMode exitMode
  ) internal {
    IStatController statController = ControllerContextLib.statController(cc);
    _onExitDungeon(
      hero,
      heroId,
      statController,
      statController.heroStats(hero, heroId),
      dungStatus,
      dungAttributes,
      cc,
      exitMode,
      0, // not used
      0, // not used
      false // not used
    );
  }
  //endregion ------------------------ Main logic

  //region ------------------------ Main logic - auxiliary functions
  function _exitActionEnd(
    ObjectActionInternalData memory c,
    IDungeonFactory.DungeonStatus storage dungStatus,
    IDungeonFactory.DungeonAttributes storage dungAttributes,
    ControllerContextLib.ControllerContext memory cc
  ) internal {
    _onExitDungeon(
      c.heroToken,
      c.heroTokenId,
      c.statController,
      c.stats,
      dungStatus,
      dungAttributes,
      cc,
      DungeonExitMode.ACTION_ENDED_0,
      c.dungId,
      c.biome,
      c.isBattleObj
    );
  }

  function _onExitDungeon(
    address hero,
    uint heroId,
    IStatController statController,
    IStatController.ChangeableStats memory stats,
    IDungeonFactory.DungeonStatus storage dungStatus,
    IDungeonFactory.DungeonAttributes storage dungAttributes,
    ControllerContextLib.ControllerContext memory cc,
    DungeonExitMode mode,
    uint64 dungId,
    uint biome,
    bool isBattleObj
  ) internal {
    _changeCurrentDungeon(_S(), hero, heroId, 0);

    IHeroController hc = ControllerContextLib.heroController(cc);
    hc.releaseReinforcement(hero, heroId);

    // in case of death we need to remove rewrote objects and reset initial stages
    _resetUniqueObjects(dungStatus, dungAttributes);

    bool heroDied;

    if (mode == DungeonExitMode.ACTION_ENDED_0) {
      // no need to release if we completed the dungeon - we will never back on the same
      _releaseSkillSlotsForDurabilityReduction(_S(), hero, heroId);
      heroDied = stats.lifeChances <= 1;
      if (heroDied) {
        // it was the last life chance - kill the hero
        _killHero(hc, dungId, hero, heroId, dungStatus.treasuryItems);
      } else {
        _afterObjCompleteForSurvivedHero(hero, heroId, biome, isBattleObj, cc,
          address(0) // don't call clearTemporallyAttributes, it will be called below anyway
        );
        _reduceLifeChances(statController, hero, heroId, stats.life, stats.mana);
      }
    } else if (mode == DungeonExitMode.FORCED_EXIT_1) {
      // life => 1, mana => 0, lifeChance is NOT changed, hero is NOT burnt, items are kept equipped.
      hc.resetLifeAndMana(hero, heroId);
    } else if (mode == DungeonExitMode.HERO_SUICIDE_2) {
      if (stats.lifeChances <= 1) revert IAppErrors.LastLifeChance();
      // equipped items are NOT taken off, life chance reduced, life and mana are restored to default values
      // death count counter is not incremented in this case
      _reduceLifeChances(statController, hero, heroId, stats.life, stats.mana);
    }

    if (!heroDied) {
      // scb-1000: soft death resets used consumables
      statController.clearUsedConsumables(hero, heroId);
      // also soft death reset all buffs
      statController.clearTemporallyAttributes(hero, heroId);
    }
  }

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
  /// @param statController Pass 0 to avoid calling of clearTemporallyAttributes
  function _afterObjCompleteForSurvivedHero(
    address hero,
    uint heroId,
    uint biome,
    bool isBattleObj,
    ControllerContextLib.ControllerContext memory cc,
    address statController
  ) internal {
    if (isBattleObj) {
      // reduce equipped items durability
      ControllerContextLib.itemController(cc).reduceDurability(hero, heroId, uint8(biome), false);
      if (statController != address(0)) {
        // clear temporally attributes
        IStatController(statController).clearTemporallyAttributes(hero, heroId);
      }
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

    IItemController ic = ControllerContextLib.itemController(cc);

    for (uint i; i < result.mintItems.length; i++) {
      if (result.mintItems[i] == address(0)) {
        continue;
      }
      uint itemId = ic.mint(result.mintItems[i], address(this), result.mintItemsMF.length > i ? result.mintItemsMF[i] : 0);
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
    IHeroController heroController = ControllerContextLib.heroController(cc);
    uint heroNgLevel = heroController.getHeroInfo(hero, heroId).ngLevel;

    IGameToken gameToken = ControllerContextLib.gameToken(cc);
    uint amount = IMinter(gameToken.minter()).mintDungeonReward(dungId, biome, lvlForMint);
    uint reward = AppLib._getAdjustedReward(amount, heroNgLevel);
    if (amount > reward) {
      gameToken.burn(amount - reward);
      amount = reward;
    }

    // SCR-1602: we should not combine rewards with treasury tokens ideally
    // but historically they are combined, so not rewards but whole combined amount is divided between tax/reinf/hero
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

    IStatController.ChangeableStats memory stats = ControllerContextLib.statController(cc).heroStats(heroToken, heroTokenId);
    uint8 dungBiome = dungAttrs.biome;

    if (ControllerContextLib.reinforcementController(cc).isStaked(heroToken, heroTokenId)) revert IAppErrors.Staked(heroToken, heroTokenId);
    {
      IPvpController pc = ControllerContextLib.pvpController(cc);
      if (address(pc) != address(0) && pc.isHeroStakedCurrently(heroToken, heroTokenId)) revert IAppErrors.PvpStaked();
    }

    if (stats.lifeChances == 0) revert IAppErrors.ErrorHeroIsDead(heroToken, heroTokenId);
    if (s.heroCurrentDungeon[heroToken.packNftId(heroTokenId)] != 0) revert IAppErrors.ErrorAlreadyInDungeon();
    // assume here that onlyEnteredHeroOwner is already checked by the caller

    if (ControllerContextLib.heroController(cc).heroBiome(heroToken, heroTokenId) != dungBiome) revert IAppErrors.ErrorNotBiome();
    if (dungStatus.heroToken != address(0)) revert IAppErrors.ErrorDungeonBusy();
    if (!isDungeonEligibleForHero(s, ControllerContextLib.statController(cc), dungNum, uint8(stats.level), heroToken, heroTokenId)) {
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
      IHeroController hc = ControllerContextLib.heroController(cc);
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

    IStatController statController = ControllerContextLib.statController(cc);
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
    onlyOwner(heroToken, heroTokenId, msgSender);
    if (_S().heroCurrentDungeon[heroToken.packNftId(heroTokenId)] != dungId) revert IAppErrors.ErrorHeroNotInDungeon();

    IHeroController heroController = ControllerContextLib.heroController(cc);
    (address payToken,) = heroController.payTokenInfo(heroToken);
    if (payToken == address(0)) revert IAppErrors.ZeroToken(); // old free hero is not supported anymore (i.e. hero 5, F2P)

    uint16 dungNum = dungStatus.dungNum;
    _setDungeonCompleted(_S(), dungNum, dungId, heroToken, heroTokenId);

    if (claim) {
      _claimAll(cc, msgSender, dungId, dungNum, dungStatus, heroToken, heroTokenId);
    }
    _heroExit(_S(), heroController, heroToken, heroTokenId);

    // register daily activity
    address userController = controller.userController();
    if (userController != address(0)) {
      if (heroController.sandboxMode(heroToken, heroTokenId) != uint8(IHeroController.SandboxMode.SANDBOX_MODE_1)) {
        IUserController(userController).registerPassedDungeon(msgSender);
      }
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

  /// @notice Calculate amount of biome owner tax
  /// @return taxPercent Percent of tax that is taken if favor of biome owner, decimals 3
  /// @return guildBank Address of guild bank of the biome owner
  /// @return guildId The owner of the biome
  function _getBiomeTax(
    uint8 biome,
    ControllerContextLib.ControllerContext memory cc
  ) internal returns (
    uint taxPercent,
    address guildBank,
    uint guildId
  ) {
    IPvpController pvpController = ControllerContextLib.pvpController(cc);
    if (address(pvpController) != address(0)) {
      (uint _guildId, uint _taxPercent) = pvpController.refreshBiomeTax(biome);
      if (_guildId != 0) {
        // assume that guildController cannot be 0 if pvp controller is set
        guildBank = ControllerContextLib.guildController(cc).getGuildBank(_guildId);
        if (guildBank != address(0)) {
          guildId = _guildId;
          taxPercent = _taxPercent;
        }
      }
    }

    return (taxPercent, guildBank, guildId);
  }

  /// @notice Claim all treasure tokens and items registered for the given hero.
  ///         At first the tax is taken in favor of biome owner if any.
  ///         Remain tokens are send to msgSender and/or helper, or they can be send to controller or burned.
  ///         The items are transferred to msgSender or helper (random choice) or destroyed (F2P hero).
  /// @dev ClaimContext is used both for lazy initialization and to extend limits of allowed local vars.
  function _claimAll(
    ControllerContextLib.ControllerContext memory cc,
    address msgSender,
    uint64 dungId,
    uint16 dungNum,
    IDungeonFactory.DungeonStatus storage dungStatus,
    address hero,
    uint heroId
  ) internal {
    ClaimContext memory context;

    context.msgSender = msgSender;
    context.dungId = dungId;

    (context.helpHeroToken, context.helpHeroId) = ControllerContextLib.heroController(cc).heroReinforcementHelp(hero, heroId);
    context.toHelperRatio = ControllerContextLib.reinforcementController(cc).toHelperRatio(context.helpHeroToken, context.helpHeroId);

    context.itemLength = dungStatus.treasuryItems.length;
    context.tokenLength = dungStatus.treasuryTokens.length();
    context.tokens = new address[](context.tokenLength);
    context.amounts = new uint[](context.tokenLength);

    IDungeonFactory.DungeonAttributes storage dungAttrs = _S().dungeonAttributes[dungNum];
    context.biome = dungAttrs.biome;
    (context.taxPercent, context.guildBank, context.guildId) = _getBiomeTax(context.biome, cc);

    context.sandboxMode = ControllerContextLib.heroController(cc).sandboxMode(hero, heroId);

    // need to write tokens separately coz we need to delete them from map
    for (uint i; i < context.tokenLength; i++) {
      (context.tokens[i], context.amounts[i]) = dungStatus.treasuryTokens.at(i);
    }

    for (uint i; i < context.tokenLength; i++) {
      _claimToken(dungStatus.treasuryTokens, context, cc, context.tokens[i], context.amounts[i]);
    }

    if (context.sandboxMode == uint8(IHeroController.SandboxMode.SANDBOX_MODE_1) && context.itemLength != 0) {
      context.items = new address[](context.itemLength);
      context.itemIds = new uint[](context.itemLength);
      context.countItems = 0;
    }

    for (uint i; i < context.itemLength; i++) {
      (address itemAdr, uint itemId) = dungStatus.treasuryItems[i].unpackNftId();
      if (_claimItem(context, cc, itemAdr, itemId)) {
        // the item was already sent to itemBoxController, we need to call registerItems() for it below
        context.items[context.countItems] = itemAdr;
        context.itemIds[context.countItems] = itemId;
        context.countItems += 1;
      }
    }

    if (context.sandboxMode == uint8(IHeroController.SandboxMode.SANDBOX_MODE_1) && context.countItems != 0) {
      // Too much code is required to cut two arrays to required length here.
      // It's easier to ignore unnecessary items on ItemBox side.
      ControllerContextLib.itemBoxController(cc).registerItems(hero, heroId, context.items, context.itemIds, context.countItems);
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
    address gameToken = address(ControllerContextLib.gameToken(cc));

    treasuryTokens.remove(token);
    if (amount != 0) {
      if (context.sandboxMode == uint8(IHeroController.SandboxMode.SANDBOX_MODE_1)) {
        // send treasury back to the Treasury in sandbox mode, assume that amount != 0 here
        IERC20(token).transfer(address(ControllerContextLib.treasury(cc)), amount);
        emit IApplicationEvents.SandboxReturnAmountToTreasury(context.dungId, token, amount);
      } else {
        // SCR-1602: we should split only minted rewards between tax/reinf/hero
        // but historically treasury tokens are combined with minted rewards
        // so, the whole combined amount (of the game tokens) is divided between tax/reinf/hero here

        uint amountMinusTax = amount;
        if (context.taxPercent != 0 && context.guildBank != address(0) && gameToken == token) {
          uint taxAmount = amount * context.taxPercent / 100_000;
          IERC20(token).transfer(context.guildBank, taxAmount); // assume that taxAmount is not 0 here
          amountMinusTax -= taxAmount;
          emit IApplicationEvents.BiomeTaxPaid(context.msgSender, context.biome, context.guildId, amount, context.taxPercent, taxAmount, context.dungId);
        }

        uint toHelper = context.helpHeroToken == address(0) || gameToken != token
          ? 0
          : amountMinusTax * context.toHelperRatio / 100;

        uint toHeroOwner = amountMinusTax - toHelper;
        if (toHeroOwner != 0) {
          IERC20(token).transfer(context.msgSender, toHeroOwner);
        }

        if (toHelper != 0) {
          IReinforcementController reinforcementController = ControllerContextLib.reinforcementController(cc);
          IERC20(token).transfer(address(reinforcementController), toHelper);
          reinforcementController.registerTokenReward(context.helpHeroToken, context.helpHeroId, token, toHelper, context.dungId);
        }

        emit IApplicationEvents.ClaimToken(context.dungId, token, amount);
      }
    }
  }

  /// @notice Destroy item (for F2P) or transfer the item to helper/sender (random choice)
  /// @return itemWasSentToItemBoxController True if ItemBoxController.registerItems() must be called after the call
  function _claimItem(
    ClaimContext memory context,
    ControllerContextLib.ControllerContext memory cc,
    address token,
    uint tokenId
  ) internal returns (bool itemWasSentToItemBoxController) {
    if (IERC721(token).ownerOf(tokenId) == address(this)) {

      // get tax in favor of biome owner if any
      bool toBiomeOwner = false;
      if (context.taxPercent != 0 && context.guildBank != address(0)) {
        toBiomeOwner = ControllerContextLib.oracle(cc).getRandomNumber(100_000, 0) < context.taxPercent;
      }

      bool toHelper = false;
      if (!toBiomeOwner && context.helpHeroToken != address(0)) {
        toHelper = ControllerContextLib.oracle(cc).getRandomNumber(100, 0) < context.toHelperRatio;
      }

      if (toBiomeOwner) {
        // SCR-1253: Attention: GuildBank with version below 1.0.2 was not inherited from ERC721Holder (mistake).
        // As result, safeTransferFrom doesn't work with such banks, they must be updated. So, use transferFrom here.
        IERC721(token).transferFrom(address(this), context.guildBank, tokenId);
        emit IApplicationEvents.BiomeTaxPaidNft(context.msgSender, context.biome, context.guildId, token, tokenId, context.taxPercent, context.dungId);
      } else if (toHelper) {
        IReinforcementController reinforcementController = ControllerContextLib.reinforcementController(cc);
        IERC721(token).safeTransferFrom(address(this), address(reinforcementController), tokenId);
        reinforcementController.registerNftReward(context.helpHeroToken, context.helpHeroId, token, tokenId, context.dungId);
      } else {
        if (context.sandboxMode == uint8(IHeroController.SandboxMode.SANDBOX_MODE_1)) {
          IItemBoxController itemBoxController = ControllerContextLib.itemBoxController(cc);
          IERC721(token).safeTransferFrom(address(this), address(itemBoxController), tokenId);
          itemWasSentToItemBoxController = true; // notify caller that registerItems() should be called
        } else {
          IERC721(token).safeTransferFrom(address(this), context.msgSender, tokenId);
        }
      }

      emit IApplicationEvents.ClaimItem(context.dungId, token, tokenId);
    }

    return itemWasSentToItemBoxController;
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
