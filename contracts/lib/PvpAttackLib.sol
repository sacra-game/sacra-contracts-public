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
import "./ReinforcementControllerLib.sol";

library PvpAttackLib {

  //region ------------------------ Constants
  /// @notice Max total count of turns per pvp-fight
  uint internal constant MAX_COUNT_TURNS = 100;
  //endregion ------------------------ Constants

  //region ------------------------ Data types
  struct PvpFightContext {
    uint8 turn;
    IFightCalculator.AttackInfo heroAttackInfo;
    IFightCalculator.AttackInfo opponentAttackInfo;
    int32 heroBuffManaConsumed;
    int32 opponentBuffManaConsumed;
  }

  struct PvpFightParams {
    /// @notice Max count of fights between the heroes
    uint8 maxCountTurns;
    /// @notice Count of fights made (max count is limited by 100)
    uint8 countTurnsMade;
    uint48 fightId;
    /// @notice User that starts the fight
    address msgSender;
    IItemController itemController;
    IStatController statController;
    IStatController.ChangeableStats heroStats;
    IStatController.ChangeableStats opponentStats;
  }

  //endregion ------------------------ Data types

  //endregion ------------------------ Action

  /// @notice Start or continue fighting between the hero and his opponent.
  /// A series of fights takes place until the health of one heroes drops to zero.
  /// If the total number of fights reaches 100 and none of the heroes' health reaches zero,
  /// the winner is a hero with the most lives. If the numbers of lives are equal, the winner is selected randomly.
  /// @dev Assume here that both hero tokens are not burnt
  function pvpFight(
    PvpFightParams memory p,
    IPvpController.HeroData memory hero,
    IPvpController.HeroData memory opponent
  ) external returns (
    IPvpController.PvpFightResults memory fightResult
  ) {
    return _pvpFight(p, hero, opponent, CalcLib.pseudoRandom, FightLib.fight);
  }

  /// @param random_ Pass _pseudoRandom here, param is required to simplify unit testing
  /// @param fight_ Pass FightLib.fight here, param is required to simplify unit testing
  function _pvpFight(
    PvpFightParams memory p,
    IPvpController.HeroData memory hero,
    IPvpController.HeroData memory opponent,
    function (uint) internal view returns (uint) random_,
    function(
      IItemController,
      IFightCalculator.FightCall memory,
      IFightCalculator.FightCallAdd memory,
      function (uint) internal view returns (uint)
    ) internal returns (IFightCalculator.FightResult memory) fight_
  ) internal returns (
    IPvpController.PvpFightResults memory fightResult
  ) {
    PvpFightContext memory v;

    // check attackInfo and remove all unusable tokens from there
    // these attackInfo will be used as a base to generate attackInfo on each turn
    v.heroAttackInfo = _prepareAttackInfo(p.itemController, hero);
    v.opponentAttackInfo = _prepareAttackInfo(p.itemController, opponent);

    // fight until one of the heroes dies OR max count of turns is reached
    fightResult = IPvpController.PvpFightResults({
      completed: p.heroStats.life == 0 || p.opponentStats.life == 0,
      totalCountFights: p.countTurnsMade,
      healthHero: p.heroStats.life,
      healthOpponent: p.opponentStats.life,
      manaConsumedHero: 0,
      manaConsumedOpponent: 0
    });

    if (!fightResult.completed) {
      for (uint8 i; i < p.maxCountTurns; ++i) {
        IFightCalculator.FighterInfo memory heroFightInfo;
        (heroFightInfo, v.heroBuffManaConsumed) = _generateHeroFightInfo(
          p.statController,
          p.itemController,
          p.heroStats,
          v.heroAttackInfo,
          hero,
          fightResult.healthHero,
          fightResult.manaConsumedHero
        );
        IFightCalculator.FighterInfo memory opponentFightInfo;
        (opponentFightInfo, v.opponentBuffManaConsumed) = _generateHeroFightInfo(
          p.statController,
          p.itemController,
          p.opponentStats,
          v.opponentAttackInfo,
          opponent,
          fightResult.healthOpponent,
          fightResult.manaConsumedOpponent
        );
        MonsterLib._debuff(opponentFightInfo.fighterAttributes, v.heroAttackInfo, p.itemController);
        MonsterLib._debuff(heroFightInfo.fighterAttributes, v.opponentAttackInfo, p.itemController);

        // take into account all mana consumed by buff
        fightResult.manaConsumedHero = _subMana(fightResult.manaConsumedHero, -v.heroBuffManaConsumed);
        fightResult.manaConsumedOpponent = _subMana(fightResult.manaConsumedOpponent, -v.opponentBuffManaConsumed);

        v.turn = fightResult.totalCountFights; // abs index of the fight, it's important for UI
        IFightCalculator.FightResult memory result = fight_(
          p.itemController,
          IFightCalculator.FightCall({
            fighterA: heroFightInfo,
            fighterB: opponentFightInfo,
            dungeonId: 0,
            objectId: 0,
            heroAdr: hero.hero,
            heroId: hero.heroId,
            stageId: 0,
            iteration: 0,
            turn: v.turn
          }),
          IFightCalculator.FightCallAdd({
            msgSender: p.msgSender,
            fightId: p.fightId
          }),
          random_
        );
        // assume that fight_ emits PvpFightResultProcessed with all detailed info for the current turn of the fight
        // so there is no other event here

        fightResult.healthHero = uint32(result.healthA);
        fightResult.healthOpponent = uint32(result.healthB);
        fightResult.manaConsumedHero += uint32(result.manaConsumedA);
        fightResult.manaConsumedOpponent += uint32(result.manaConsumedB);
        fightResult.totalCountFights++;

        if (fightResult.healthHero == 0 || fightResult.healthOpponent == 0 || fightResult.totalCountFights >= MAX_COUNT_TURNS) {
          fightResult.completed = true;
          break;
        }
      }
    }

    return fightResult;
  }

  //endregion ------------------------ Action

  //region ------------------------ Internal logic - prepare attack info
  /// @notice Check {hero.attackInfo} passed by the hero's user and exclude any not-valid tokens
  /// Selection of magic attack/skill on this stage means that they SHOULD BE used but ONLY IF it's possible.
  function _prepareAttackInfo(IItemController ic, IPvpController.HeroData memory hero) internal view returns (
    IFightCalculator.AttackInfo memory dest
  ) {
    // assume here that hero hero.pvpStrategy has kind DEFAULT_STRATEGY_0 (we check it on staking)
    IPvpController.PvpStrategyDefault memory decoded = abi.decode(hero.pvpStrategy, (IPvpController.PvpStrategyDefault));

    dest.attackType = IFightCalculator.AttackType.MELEE;
    if (decoded.attackInfo.attackType == IFightCalculator.AttackType.MAGIC) {
      if (decoded.attackInfo.attackToken != address(0)) {
        (address h, uint hId) = ic.equippedOn(decoded.attackInfo.attackToken, decoded.attackInfo.attackTokenId);
        if (hero.hero == h && hId == hero.heroId) {
          dest.attackType = IFightCalculator.AttackType.MAGIC;
          dest.attackToken = decoded.attackInfo.attackToken;
          dest.attackTokenId = decoded.attackInfo.attackTokenId;
        }
      }
    }
    // keep only actually equipped skills
    uint len = decoded.attackInfo.skillTokens.length;
    if (len != 0) {
      uint countValidTokens = 0;
      uint[] memory indicesValidTokens = new uint[](len);
      for (uint i; i < len; ++i) {
        (address h, uint hId) = ic.equippedOn(decoded.attackInfo.skillTokens[i], decoded.attackInfo.skillTokenIds[i]);
        if (hero.hero == h && hId == hero.heroId) {
          indicesValidTokens[countValidTokens++] = i;
        }
      }
      dest.skillTokenIds = new uint[](countValidTokens);
      dest.skillTokens = new address[](countValidTokens);
      for (uint i; i < countValidTokens; ++i) {
        dest.skillTokens[i] = decoded.attackInfo.skillTokens[indicesValidTokens[i]];
        dest.skillTokenIds[i] = decoded.attackInfo.skillTokenIds[indicesValidTokens[i]];
      }
    }

    return dest;
  }

  function _generateHeroFightInfo(
    IStatController statController,
    IItemController itemController,
    IStatController.ChangeableStats memory heroStats,
    IFightCalculator.AttackInfo memory heroAttackInfo,
    IPvpController.HeroData memory hero,
    uint32 healthHero,
    uint32 manaConsumedHero
  ) internal view returns (
    IFightCalculator.FighterInfo memory,
    int32 manaConsumed
  ) {
    // use all available skills to buff
    int32[] memory heroAttributes;
    (heroAttributes, manaConsumed) = MonsterLib._buffAndGetHeroAttributes(
      heroStats.level,
      heroAttackInfo.skillTokens,
      heroAttackInfo.skillTokenIds,
      statController,
      hero.hero,
      hero.heroId
    );
    uint32 newMana = _subMana(heroStats.mana, int32(int(uint(manaConsumedHero))) + manaConsumed);

    // generate attack info
    IFightCalculator.AttackInfo memory attackInfo;
    attackInfo.attackType = IFightCalculator.AttackType.MELEE;
    if (newMana != 0) {
      if (heroAttackInfo.attackType == IFightCalculator.AttackType.MAGIC) {
        uint32 manaCost = itemController.itemMeta(heroAttackInfo.attackToken).manaCost;
        if (newMana >= manaCost) {
          attackInfo.attackType = IFightCalculator.AttackType.MAGIC;
          attackInfo.attackToken = heroAttackInfo.attackToken;
          attackInfo.attackTokenId = heroAttackInfo.attackTokenId;
          newMana -= manaCost;
          manaConsumed += int32(int(uint(manaCost)));
        }
      }
    }

    IFightCalculator.FighterInfo memory fi = IFightCalculator.FighterInfo({
      fighterAttributes: heroAttributes,

    // take into account health and mana already lost in the current fight
      fighterStats: IStatController.ChangeableStats({
      level: heroStats.level,
      lifeChances: heroStats.lifeChances,
      experience: heroStats.experience,
      mana: newMana,
      life: healthHero
    }),
      attackType: attackInfo.attackType,
      attackToken: attackInfo.attackToken,
      attackTokenId: attackInfo.attackTokenId,
      race: uint(IStatController.Race.HUMAN)
    });

    return (fi, manaConsumed);
  }

  function _subMana(uint32 mana, int32 consumedMana) internal pure returns (uint32) {
    return consumedMana < 0
      ? mana + uint32(-consumedMana)
      : AppLib.sub0(mana, uint32(consumedMana));
  }
  //endregion ------------------------ Internal logic - prepare attack info

}
