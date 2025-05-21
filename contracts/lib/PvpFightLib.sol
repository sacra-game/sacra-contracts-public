// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IAppErrors.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IGuildController.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IPvpController.sol";
import "../interfaces/IReinforcementController.sol";
import "../interfaces/IGuildStakingAdapter.sol";
import "./CalcLib.sol";
import "./ControllerContextLib.sol";
import "./ScoreLib.sol";
import "./MonsterLib.sol";
import "./AppLib.sol";
import "./PackingLib.sol";
import "./PvpControllerLib.sol";
import "./PvpAttackLib.sol";
import "./ReinforcementControllerLib.sol";

library PvpFightLib {
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using EnumerableMap for EnumerableMap.UintToUintMap;

  //region ------------------------ Constants
  /// @notice Max total count of turns per pvp-fight
  uint internal constant MAX_COUNT_TURNS = 100;

  /// @notice Heroes do real damage to each other in PVP (items can be broken, hp/mp can be reduced, loser looses 1 life chance)
  bool internal constant REAL_DAMAGE_IN_FIGHTS = true;
  //endregion ------------------------ Constants

  //region ------------------------ Data types

  struct HeroContext {
    bool isWinner;
    IPvpController.PvpFightStatus fightStatus;
    /// @notice Target domination biome of the hero's guild
    uint8 targetBiome;
    uint32 statLife;
    uint32 statMana;
    /// @notice Score of the hero's opponent received by the hero's guild
    uint prize;
    IPvpController.HeroData heroData;
    IStatController.ChangeableStats stats;
    IPvpController.PvpUserState userState;
  }

  struct StartFightContext {
    bool technicalDefeat;
    uint32 week;
    IGuildController guildController;
    IStatController statController;
    IItemController itemController;
    IUserController userController;
    IHeroController heroController;
    HeroContext hero;
    HeroContext opponent;
    IPvpController.PvpFightResults fightResult;
  }

  struct PrepareFightLocal {
    uint8 biome;
    uint32 week;
    address opponent;
    IGuildController guildController;
    bytes32 opponentPackedHero;
    uint opponentGuildId;
  }

  struct SavePvpResultsOnCompletionLocal {
    bool alive;
    bool keepStaked;
    bool died;
  }

  struct SaveFightResultsInput {
    address user;
    address otherUser;
    bool isHero;
  }
  //endregion ------------------------ Data types

  //region ------------------------ PvP actions

  /// @notice Find opponent for the user's hero, prepare the fight
  /// @dev Normally the fight is prepared automatically on hero registration.
  /// In some cases it doesn't happen and the preparation should be made manually.
  /// Ex: Two guilds had peaceful relation. Users of the both guilds registered their heroes.
  /// As soon as there are no other guilds, the fights are not initialized.
  /// The guilds change their relation to "war". Now users should initialize the fights manually.
  /// @param random_ CalcLib.pseudoRandom, required for unit tests
  function prepareFight(
    address msgSender,
    IController controller,
    uint blockTimestamp,
    function (uint) internal view returns (uint) random_
  ) internal {
    PvpControllerLib._onlyNotPaused(controller);
    PrepareFightLocal memory v;

    v.guildController = IGuildController(controller.guildController());
    v.week = PvpControllerLib.getCurrentEpochWeek(blockTimestamp);
    (, v.biome) = PvpControllerLib._getTargetDominationBiomeWithCheck(msgSender, v.guildController, v.week, true);

    IPvpController.EpochData storage epochData = PvpControllerLib._S().epochData[v.week];
    IPvpController.PvpUserState memory userState = epochData.pvpUserState[msgSender];
    PvpControllerLib._onlyUserWithRegisteredPvpHeroWithoutFights(userState);

    (v.opponent, v.opponentPackedHero, v.opponentGuildId) = PvpControllerLib._findPvpOpponent(v.guildController, v.biome, epochData, userState.guildId, random_);
    if (v.opponent == address(0)) revert IAppErrors.PvpFightOpponentNotFound();

    IPvpController.HeroData memory heroData = _getHeroData(epochData.epochBiomeData[userState.biome], userState.guildId, msgSender);
    PvpControllerLib._setupPvpFight(v.biome, epochData, msgSender, v.opponent, userState.guildId, v.opponentGuildId, PvpControllerLib.SetupPvpFightParams({
      week: v.week,
      hero: heroData.hero,
      heroId: heroData.heroId,
      opponentPackedHero: v.opponentPackedHero
    }));
  }

  /// @notice Start set of fight turns. Each set can include no more than {maxCountTurns} turns.
  /// The whole fight = {set of turns}, set of turn = {turns}, 1 transaction = 1 set of turns.
  /// Heroes must fight until one of the heroes has zero lives left.
  /// Total number of turns cannot exceed {MAX_COUNT_TURNS}.
  /// In this case, the hero with the most lives is chosen as the winner.
  function startFight(address msgSender, IController controller, uint blockTimestamp, uint8 maxCountTurns) external {
    _doMultipleTurns(msgSender, controller, blockTimestamp, maxCountTurns, CalcLib.pseudoRandom, _pvpFight);
  }
  //endregion ------------------------ PvP actions

  //region ------------------------ PvP fight
  /// @dev Wrapper function for {PvpAttackLib.pvpFight} to be able to pass it into {_doMultipleTurns}
  function _pvpFight(
    PvpAttackLib.PvpFightParams memory p,
    IPvpController.HeroData memory hero,
    IPvpController.HeroData memory opponent
  ) internal returns (IPvpController.PvpFightResults memory fightResult) {
    return PvpAttackLib.pvpFight(p, hero, opponent);
  }

  /// @notice Execute no more than {maxCountTurns} turns
  /// @param maxCountTurns Max number of turns that can be performed during this call
  /// @param random_ Pass _pseudoRandom here, the param is required to simplify unit testing
  /// @param fight_ Pass {_pvpFight} here, the param is required to simplify unit testing
  function _doMultipleTurns(
    address msgSender,
    IController controller,
    uint blockTimestamp,
    uint8 maxCountTurns,
    function (uint) internal view returns (uint) random_,
    function (
      PvpAttackLib.PvpFightParams memory,
      IPvpController.HeroData memory,
      IPvpController.HeroData memory
    ) internal returns (IPvpController.PvpFightResults memory) fight_
  ) internal {
    PvpControllerLib._onlyNotPaused(controller);

    StartFightContext memory v;

    v.itemController = IItemController(controller.itemController());
    v.userController = IUserController(controller.userController());
    v.guildController = IGuildController(controller.guildController());
    v.statController = IStatController(controller.statController());
    v.heroController = IHeroController(controller.heroController());
    v.week = PvpControllerLib.getCurrentEpochWeek(blockTimestamp);

    IPvpController.EpochData storage epochData = PvpControllerLib._S().epochData[v.week];

    // set up v.XXX.biome, v.XXX.userState and v.XXX.fightData for each hero
    IPvpController.PvpFightData memory heroFightData = _initBiomeUserStateFightData(msgSender, v, epochData, true);
    IPvpController.PvpFightData memory opponentFightData = _initBiomeUserStateFightData(heroFightData.fightOpponent, v, epochData, false);

    IPvpController.EpochBiomeData storage epochBiomeData = epochData.epochBiomeData[v.hero.userState.biome];

    // set up v.XXX.heroData and v.XXX.stats for each hero
    _initStatsHeroData(msgSender, v, epochBiomeData, heroFightData, true);
    _initStatsHeroData(heroFightData.fightOpponent, v, epochBiomeData, opponentFightData, false);

    // ---------------- technical defeat
    // pvp-fight was started then the guild has changed domination request to different biome
    // pvp-fight is continued, but now fight's biome is different from target one => technical defeat of the hero
    // such situation is possible for any hero and even for the both at the same time
    (v.technicalDefeat, v.hero.isWinner) = _checkTechnicalDefeat(
      v.hero.userState.biome != v.hero.targetBiome,
      v.opponent.userState.biome != v.opponent.targetBiome,
      random_
    );

    // ---------------- fights
    if (v.technicalDefeat) {
      v.opponent.isWinner = !v.hero.isWinner;
      v.fightResult = IPvpController.PvpFightResults({
        healthHero: v.hero.isWinner ? v.hero.stats.life : 0,
        healthOpponent: v.opponent.isWinner ? v.opponent.stats.life : 0,
        completed: true,
        totalCountFights: heroFightData.countTurns,
        manaConsumedHero: v.hero.isWinner ? 0 : v.hero.stats.mana,
        manaConsumedOpponent: v.opponent.isWinner ? 0 : v.opponent.stats.mana
      });
    } else {
      v.fightResult = fight_(
        PvpAttackLib.PvpFightParams({
          msgSender: msgSender,
          fightId: v.hero.userState.fightId,
          statController: v.statController,
          itemController: v.itemController,
          maxCountTurns: maxCountTurns,
          heroStats: v.hero.stats,
          opponentStats : v.opponent.stats,
          countTurnsMade: heroFightData.countTurns // opponent has exactly same count of turns
        }),
        v.hero.heroData,
        v.opponent.heroData
      );

      if (v.fightResult.completed) {
        (v.hero.isWinner, v.opponent.isWinner) = _getWinners(v.fightResult, random_);
      }
    }

    // ---------------- save results
    _saveFightResults(SaveFightResultsInput(msgSender, heroFightData.fightOpponent, true), v, epochData, epochBiomeData);
    _saveFightResults(SaveFightResultsInput(heroFightData.fightOpponent, msgSender, false), v, epochData, epochBiomeData);

    if (v.fightResult.completed) {
      _emitFightCompleted(v);
    }
  }

  /// @notice Initialize v.XXX.heroData, v.XXX.stats, v.XXX.statLife/Mana for the given hero
  function _initStatsHeroData(
    address user,
    StartFightContext memory v,
    IPvpController.EpochBiomeData storage epochBiomeData,
    IPvpController.PvpFightData memory fightData,
    bool isHero
  ) internal view {
    HeroContext memory h = isHero ? v.hero : v.opponent;

    // v.opponentGuildId can be 0 if the opponent was removed from the guild
    // in this case opponentData will contain zeros too => technical defeat with looserScore = 0
    h.heroData = _getHeroData(epochBiomeData, h.userState.guildId, user);

    // get hero and opponent states
    h.stats = v.statController.heroStats(h.heroData.hero, h.heroData.heroId);

    // store current stat-values - these are values for the moment before starting the fight
    h.statLife = h.stats.life;
    h.statMana = h.stats.mana;

    // override life and mana in hero state if the fight has been started and now it is being continued
    if (fightData.fightStatus == IPvpController.PvpFightStatus.FIGHTING_2) {
      h.stats.life = fightData.health;
      h.stats.mana = fightData.mana;
    }
  }

  /// @notice Initialize v.XXX.biome, v.XXX.userState and fightData for the given hero
  function _initBiomeUserStateFightData(address user, StartFightContext memory v, IPvpController.EpochData storage epochData, bool isHero) internal view returns (
    IPvpController.PvpFightData memory heroFightData
  ){
    HeroContext memory h = isHero ? v.hero : v.opponent;

    (, h.targetBiome) = PvpControllerLib._getTargetDominationBiomeWithCheck(user, v.guildController, v.week, isHero);
    h.userState = epochData.pvpUserState[user];
    if (h.userState.activeFightIndex1 == 0) {
      // ensure that the fighting is prepared and not completed
      revert IAppErrors.PvpFightIsNotPrepared(h.targetBiome, v.week, user);
    }
    heroFightData = PvpControllerLib.getFightDataByIndex(v.week, user, h.userState.activeFightIndex1 - 1);

    if (
      heroFightData.fightStatus == IPvpController.PvpFightStatus.WINNER_3
      || heroFightData.fightStatus == IPvpController.PvpFightStatus.LOSER_4
    ) revert IAppErrors.PvpFightIsCompleted(h.targetBiome, v.week, user);
  }

  function _saveFightResults(
    SaveFightResultsInput memory p,
    StartFightContext memory v,
    IPvpController.EpochData storage epochData,
    IPvpController.EpochBiomeData storage epochBiomeData
  ) internal {
    HeroContext memory h = p.isHero ? v.hero : v.opponent;
    HeroContext memory other = p.isHero ? v.opponent : v.hero;

    if (v.fightResult.completed) {
      // update final state (the fight is completed)
      h.fightStatus = h.isWinner ? IPvpController.PvpFightStatus.WINNER_3 : IPvpController.PvpFightStatus.LOSER_4;

      // looser always lost all mp and hp
      if (!h.isWinner) {
        if (p.isHero) {
          v.fightResult.healthHero = 0;
          v.fightResult.manaConsumedHero = v.hero.stats.mana;
        } else {
          v.fightResult.healthOpponent = 0;
          v.fightResult.manaConsumedOpponent = v.opponent.stats.mana;
        }
      }

      // update winner guild points for biome domination
      // Possible edge cases: hero/opponent is the winner, but his guild has different target now.
      // In such cases guild doesn't receive guild points of the winner
      h.prize = h.isWinner && h.userState.biome == h.targetBiome
        // apply penalty for repeat domination to the the number of pvp-points
        ? PvpControllerLib._getPointsWithPenalty(
          v.heroController.score(other.heroData.hero, other.heroData.heroId),
          PvpControllerLib._S().biomeState[h.targetBiome].dominationCounter
        )
        : 0;

      _savePvpResultsOnCompletion(p, v, epochData, epochBiomeData, REAL_DAMAGE_IN_FIGHTS);

      // reset all buffs and clear usage of the consumables
      v.statController.clearTemporallyAttributes(h.heroData.hero, h.heroData.heroId);
      v.statController.clearUsedConsumables(h.heroData.hero, h.heroData.heroId);

    } else {
      // update intermediate state (the fight is not completed, new set of fight is required)
      h.fightStatus = IPvpController.PvpFightStatus.FIGHTING_2;
    }

    epochData.fightData[p.user][h.userState.activeFightIndex1 - 1] = IPvpController.PvpFightData({
      fightStatus: h.fightStatus,
      fightOpponent: p.otherUser,
      countTurns: v.fightResult.totalCountFights,
      health: p.isHero ? v.fightResult.healthHero : v.fightResult.healthOpponent,
      mana: AppLib.sub0(h.stats.mana, p.isHero ? v.fightResult.manaConsumedHero : v.fightResult.manaConsumedOpponent)
    });
  }

  /// @notice Save results of completed PVP fight: update guild points, register daily activity, update core stat,
  /// reduce durability, add the winner to the list of heroes free for fight.
  /// @param realDamageAllowed For tests, the value is REAL_DAMAGE_IN_FIGHTS
  function _savePvpResultsOnCompletion(
    SaveFightResultsInput memory p,
    StartFightContext memory c,
    IPvpController.EpochData storage epochData,
    IPvpController.EpochBiomeData storage epochBiomeData,
    bool realDamageAllowed
  ) internal {
    SavePvpResultsOnCompletionLocal memory v;

    HeroContext memory h = p.isHero ? c.hero : c.opponent;
    uint32 fightResultHealth = p.isHero ? c.fightResult.healthHero : c.fightResult.healthOpponent;
    uint32 fightResultConsumedMana = p.isHero ? c.fightResult.manaConsumedHero : c.fightResult.manaConsumedOpponent;

    // update guild points counter for the guild of the winner
    if (h.isWinner) {
      (bool exist, uint guildPoints) = epochBiomeData.guildPoints.tryGet(h.userState.guildId);
      epochBiomeData.guildPoints.set(h.userState.guildId, (exist ? guildPoints : 0) + h.prize);

      // update global guild points counter
      // assume here, that uint64 is enough to store any sums of scores
      if (h.prize != 0) {
        c.guildController.incPvpCounter(h.userState.guildId, uint64(h.prize));
      }
    }

    // both users register daily activity
    c.userController.registerPvP(p.user, h.isWinner);

    v.alive = h.isWinner;

    // winner is kept staked OR can be auto-removed if maxFights-limit is reached
    // loser's hero is auto-removed always and should be staked again
    v.keepStaked = v.alive && (h.userState.maxFights == 0 || h.userState.maxFights > h.userState.countFights + 1);
    v.died = !v.alive && h.stats.lifeChances <= 1;

    if (realDamageAllowed) {
      // update hp, mp, lc

      if (fightResultHealth == 0 && v.alive) {
        // winner has new life = 0 => he loses life chance in the same way as the looser and should be removed
        v.alive = false;
        v.keepStaked = false;
      }

      if (!v.died) {
        { // decrease life, mana and probably life-chance
          IStatController.ChangeableStats memory cs = IStatController.ChangeableStats({
            level: 0,
            experience: 0,
            life: AppLib.sub0(h.statLife, fightResultHealth),
          // the fight consists from many turns, here:
          // v.heroStatMana = mana before starting the fight (== starting the turn)
          // v.heroStats.mana = mana at the moment of the beginning current set of fights
          // v.fightResult.manaConsumedHero = mana consumed during current set of fights
          // mana = total value of mana consumed from starting the fight
            mana: AppLib.sub0(h.statMana, (AppLib.sub0(h.stats.mana, fightResultConsumedMana))),
            lifeChances: v.alive ? 0 : 1
          });
          c.statController.changeCurrentStats(h.heroData.hero, h.heroData.heroId, cs, false);
        }

        if (!v.alive) {
          // hero has lost once life chance, but result life chance > 0 => restore life and mana
          IStatController.ChangeableStats memory cs = IStatController.ChangeableStats({
            level: 0,
            experience: 0,
            life: _getHeroAttribute(c.statController, h, IStatController.ATTRIBUTES.LIFE),
            mana: _getHeroAttribute(c.statController, h, IStatController.ATTRIBUTES.MANA),
            lifeChances: 0
          });
          c.statController.changeCurrentStats(h.heroData.hero, h.heroData.heroId, cs, true);
        }
      }
      // reduce durability of all equipped items (including all skills), take off broken items
      c.itemController.reduceDurability(h.heroData.hero, h.heroData.heroId, h.userState.biome, true);
    }

    if (v.keepStaked) {
      // update user state
      epochData.pvpUserState[p.user] = IPvpController.PvpUserState({
        activeFightIndex1: 0,
        biome: h.userState.biome,
        guildId: h.userState.guildId,
        numHeroesStaked: epochData.pvpUserState[p.user].numHeroesStaked,
        countFights: h.userState.countFights + 1, // overflow is not possible, see keepStaked above
        maxFights: h.userState.maxFights,
        fightId: 0 // there is no active fight anymore
      });

      // add the (only live) winner back to the list of the users free for pvp
      epochBiomeData.freeUsers[h.userState.guildId].add(p.user);
    } else {
      PvpControllerLib._removePvpHero(c.week, epochData, epochBiomeData, h.userState, p.user, false);
    }

    if (realDamageAllowed && v.died) {
      _killHero(c.heroController, c.guildController, h, (p.isHero ? c.opponent : c.hero).userState.guildId);
    }
  }

  function _getHeroAttribute(IStatController statController, HeroContext memory h, IStatController.ATTRIBUTES attribute) internal view returns (uint32) {
    return uint32(uint(int(statController.heroAttribute(h.heroData.hero, h.heroData.heroId, uint(attribute)))));
  }

  /// @notice Kill the hero and send all items to the winner's guild bank
  function _killHero(IHeroController heroController, IGuildController guildController, HeroContext memory hero, uint opponentGuildId) internal {
    bytes32[] memory dropItems = heroController.kill(hero.heroData.hero, hero.heroData.heroId);
    uint len = dropItems.length;
    if (len != 0) {
      address guildBank = guildController.getGuildBank(
        hero.isWinner
          // the hero is winner but he is dead, all drop is sent to the bank of the hero's guild
          ? hero.userState.guildId
          // the hero is looser and he is dead, all drop is send to the bank of the opponent's guild
          : opponentGuildId
      );

      if (guildBank == address(0)) revert IAppErrors.ZeroAddress(); // weird case, it should never appear

      address[] memory items = new address[](len);
      uint[] memory itemIds = new uint[](len);
      for (uint i; i < len; ++i) {
        (items[i], itemIds[i]) = PackingLib.unpackNftId(dropItems[i]);

        // SCR-1253: Attention: GuildBank with version below 1.0.2 was not inherited from ERC721Holder (mistake).
        // As result, safeTransferFrom doesn't work with such banks, they must be updated. So, use transferFrom here.
        IERC721(items[i]).transferFrom(address(this), guildBank, itemIds[i]);
      }
      emit IApplicationEvents.AddPvpFightItems(hero.userState.fightId, items, itemIds);
    }
  }

  /// @notice The hero with greater health is the winner. If healths are the same the winner is selected randomly
  /// If both heroes have zero lives assume that they are both winners.
  function _getWinners(
    IPvpController.PvpFightResults memory fightResult,
    function (uint) internal view returns (uint) random_
  ) internal view returns (bool isHeroWinner, bool isOpponentWinner) {
    if (fightResult.healthHero > fightResult.healthOpponent) {
      isHeroWinner = true;
    } else if (fightResult.healthHero < fightResult.healthOpponent) {
      isOpponentWinner = true;
    } else {
      if (fightResult.healthHero == 0) {
        // special case: both heroes have zero health => they are both WINNERS
        isHeroWinner = true;
        isOpponentWinner = true;
      } else {
        // special case: both heroes have same NOT ZERO health => the winner is selected randomly
        isHeroWinner = random_(1) == 0;
        isOpponentWinner = !isHeroWinner;
      }
    }

    return (isHeroWinner, isOpponentWinner);
  }

  function _getHeroData(IPvpController.EpochBiomeData storage epochBiomeData, uint guildId, address user) internal view returns (
    IPvpController.HeroData memory heroData
  ) {
    (bool exist, uint packedHeroAsInt) = epochBiomeData.registeredHeroes[guildId].tryGet(user);
    if (! exist) revert IAppErrors.ErrorHeroIsNotRegistered(address(0)); // edge case (?)

    bytes32 packedHero = bytes32(packedHeroAsInt);
    (heroData.hero, heroData.heroId) = PackingLib.unpackNftId(packedHero);
    heroData.pvpStrategy = epochBiomeData.pvpStrategy[packedHero];

    return heroData;
  }

  /// @notice Check if technical defeat detected (the defeat without actual fighting)
  /// @param heroHasTechnicalDefeat Special case: the hero has technical defeat
  /// if he fights in biome X but his guild has changed domination request to biome Y
  /// @param opponentHasTechnicalDefeat Special case: the opponent has technical defeat
  /// if he fights in biome X but his guild has changed domination request to biome Y
  /// @return technicalDefeat Technical defeat is detected
  /// @return isHeroWinner Hero is the winner in the detected technical defeat
  function _checkTechnicalDefeat(
    bool heroHasTechnicalDefeat,
    bool opponentHasTechnicalDefeat,
    function (uint) internal view returns (uint) random_
  ) internal view returns (
    bool technicalDefeat,
    bool isHeroWinner
  ) {
    technicalDefeat = heroHasTechnicalDefeat || opponentHasTechnicalDefeat;
    if (technicalDefeat) {
      if (heroHasTechnicalDefeat) {
        if (opponentHasTechnicalDefeat) {
          // both heroes have technical defeats, the winner is selected randomly
          isHeroWinner = random_(1) == 0;
        } else {
          // the opponent is the winner, by default: isHeroWinner = false;
        }
      } else {
        isHeroWinner = true;
      }
    }

    return (technicalDefeat, isHeroWinner);
  }

  //endregion ------------------------ PvP fight

  //region ------------------------ Events
  function _emitFightCompleted(StartFightContext memory v) internal {
    emit IApplicationEvents.PvpFightCompleted(
      v.fightResult,
      v.hero.userState.fightId,
      [v.hero.heroData.hero, v.opponent.heroData.hero],
      [v.hero.userState.guildId, v.opponent.userState.guildId],
      [v.hero.isWinner, v.opponent.isWinner],
      [v.hero.prize, v.opponent.prize],
      v.technicalDefeat
    );
  }

  //endregion ------------------------ Events
}