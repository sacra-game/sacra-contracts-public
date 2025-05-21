// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IStatController.sol";
import "../interfaces/IItemController.sol";
import "../interfaces/IFightCalculator.sol";
import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../lib/StatLib.sol";
import "../lib/CalcLib.sol";
import "../lib/PackingLib.sol";
import "../solady/FixedPointMathLib.sol";

library FightLib {
  using PackingLib for bytes32;
  using CalcLib for int32;

  //region ------------------------ Data types
  struct AttackResult {
    int32 defenderHealth;
    int32 damage;
    int32 lifeStolen;
    int32 reflectDamage;
    uint8 critical;
    uint8 missed;
    uint8 blocked;
  }
  //endregion ------------------------ Data types

  //region ------------------------ Constants
  uint internal constant MAX_FIGHT_CYCLES = 100;
  int32 internal constant RESISTANCE_DENOMINATOR = 100;
  int32 internal constant _MAX_RESIST = 90;

  /// @notice SIP-002 constant: desired capacity
  uint internal constant CAPACITY_RESISTS_DEFS = 90;
  /// @notice SIP-002 constant: desired capacity
  uint internal constant CAPACITY_CRITICAL_HIT_STATUSES = 100;
  /// @notice SIP-002 constant: the factor of how fast the value will reach the capacity
  uint internal constant K_FACTOR = 100;
  /// @notice ln(2), decimals 18
  int internal constant LN2 = 693147180559945309;

  //endregion ------------------------ Constants

  //region ------------------------ Main logic

  /// @dev Items ownership must be checked before
  ///      it is no write actions but we need to emit an event for properly handle the battle on UI
  ///      return huge structs more expensive that call an event here
  /// @param random_ Pass _pseudoRandom here, param is required for unit tests
  function fight(
    IItemController ic,
    IFightCalculator.FightCall memory callData,
    IFightCalculator.FightCallAdd memory callDataAdd,
    function (uint) internal view returns (uint) random_
  ) internal returns (
    IFightCalculator.FightResult memory
  ) {
    IFightCalculator.FightInfoInternal memory fResult = prepareFightInternalInfo(ic, callData.fighterA, callData.fighterB);

    fightProcessing(fResult, random_);

    if (callDataAdd.fightId == 0) {
      // not pvp fight
      emit IApplicationEvents.FightResultProcessed(callDataAdd.msgSender, fResult, callData, callData.iteration);
    } else {
      // pvp fight
      emit IApplicationEvents.PvpFightResultProcessed(callDataAdd.fightId, callDataAdd.msgSender, fResult, callData.turn, callData.heroAdr, callData.heroId);
    }

    return IFightCalculator.FightResult({
      healthA: fResult.fighterA.health,
      healthB: fResult.fighterB.health,
      manaConsumedA: fResult.fighterA.manaConsumed,
      manaConsumedB: fResult.fighterB.manaConsumed
    });
  }
  //endregion ------------------------ Main logic

  //region ------------------------ High level of internal logic
  function fightProcessing(
    IFightCalculator.FightInfoInternal memory fResult,
    function (uint) internal view returns (uint) random_
  ) internal view {

    bool firstA = calcFirstHit(fResult);

    setStatuses(fResult, firstA, random_);
    setStatuses(fResult, !firstA, random_);

    reduceAttributesByStatuses(fResult.fighterA.info.fighterAttributes, fResult.fighterA.statuses, fResult.fighterB.info.fighterAttributes);
    reduceAttributesByStatuses(fResult.fighterB.info.fighterAttributes, fResult.fighterB.statuses, fResult.fighterA.info.fighterAttributes);

    AttackResult memory resultA = processAttack(fResult, true, random_);
    AttackResult memory resultB = processAttack(fResult, false, random_);

    fResult.fighterA.statuses.gotCriticalHit = resultA.critical != 0;
    fResult.fighterA.statuses.missed = resultA.missed != 0;
    fResult.fighterA.statuses.hitBlocked = resultA.blocked != 0;

    fResult.fighterB.statuses.gotCriticalHit = resultB.critical != 0;
    fResult.fighterB.statuses.missed = resultB.missed != 0;
    fResult.fighterB.statuses.hitBlocked = resultB.blocked != 0;

    reduceHp(
      firstA ? resultA : resultB,
      firstA ? resultB : resultA,
      firstA ? fResult.fighterA : fResult.fighterB,
      firstA ? fResult.fighterB : fResult.fighterA
    );

    // restore health from stolen life
    stealLife(fResult.fighterA, resultA);
    stealLife(fResult.fighterB, resultB);
  }

  function processAttack(
    IFightCalculator.FightInfoInternal memory fResult,
    bool isA,
    function (uint) internal view returns (uint) random_
  ) internal view returns (AttackResult memory attackResult) {

    int32 defenderHealth = isA ? fResult.fighterB.health : fResult.fighterA.health;

    if (skipTurn(fResult, isA)) {
      return AttackResult({
        defenderHealth: defenderHealth,
        damage: 0,
        lifeStolen: 0,
        reflectDamage: 0,
        critical: 0,
        missed: 0,
        blocked: 0
      });
    }

    IFightCalculator.FighterInfo memory attackerInfo = isA ? fResult.fighterA.info : fResult.fighterB.info;
    IFightCalculator.FighterInfo memory defenderInfo = isA ? fResult.fighterB.info : fResult.fighterA.info;

    if (attackerInfo.attackType == IFightCalculator.AttackType.MELEE) {
      attackResult = meleeDamageCalculation(attackerInfo, defenderInfo, defenderHealth, random_);
    } else if (attackerInfo.attackType == IFightCalculator.AttackType.MAGIC) {
      attackResult = magicDamageCalculation(
        attackerInfo,
        defenderInfo,
        isA ? fResult.fighterA.magicAttack : fResult.fighterB.magicAttack,
        defenderHealth,
        random_
      );
    } else {
      revert IAppErrors.NotAType(uint(attackerInfo.attackType));
    }
  }
  //endregion ------------------------ High level of internal logic

  //region ------------------------ Internal logic
  function prepareFightInternalInfo(
    IItemController ic,
    IFightCalculator.FighterInfo memory fighterA,
    IFightCalculator.FighterInfo memory fighterB
  ) internal view returns (IFightCalculator.FightInfoInternal memory) {
    IFightCalculator.FightInfoInternal memory fInfo;
    _setFightData(ic, fighterA, fInfo.fighterA);
    _setFightData(ic, fighterB, fInfo.fighterB);
    return fInfo;
  }

  /// @dev A part of prepareFightInternalInfo
  function _setFightData(
    IItemController ic,
    IFightCalculator.FighterInfo memory fighter,
    IFightCalculator.Fighter memory dest
  ) internal view {
    dest.info = fighter;
    dest.health = int32(fighter.fighterStats.life);
    if (fighter.attackToken != address(0)) {
      if (fighter.attackType != IFightCalculator.AttackType.MAGIC) revert IAppErrors.NotMagic();
      dest.magicAttack = ic.itemAttackInfo(fighter.attackToken, fighter.attackTokenId);
    }
    // dest.manaConsumed is 0 by default, in current implementation we don't need to change it
  }

  /// @param random_ Either _pseudoRandom or pseudo-random for ut
  function statusChance(
    IFightCalculator.FighterInfo memory attackerInfo,
    IItemController.AttackInfo memory attackerMA,
    IStatController.ATTRIBUTES index,
    int32 resist,
    function (uint) internal view returns (uint) random_
  ) internal view returns (bool) {
    int32 chance = _getChance(attackerInfo, attackerMA.aType, index, resist);
    if (chance == 0) {
      return false;
    }
    if (chance >= RESISTANCE_DENOMINATOR) {
      return true;
    }
    return random_(RESISTANCE_DENOMINATOR.toUint()) < chance.toUint();
  }

  /// @notice set fResult.fighterB.statuses (for isA = true) or fResult.fighterA.statuses (for isA = false)
  /// @param random_ Either _pseudoRandom or pseudo-random for ut
  function setStatuses(
    IFightCalculator.FightInfoInternal memory fResult,
    bool isA,
    function (uint) internal view returns (uint) random_
  ) internal view {
    // setStatuses is called twice one by one: first time for A, second time for B
    // if stun is set for A, setStatuses is skipped for B completely
    if (!skipTurn(fResult, isA)) {
      IFightCalculator.FighterInfo memory attackerInfo = isA ? fResult.fighterA.info : fResult.fighterB.info;
      IFightCalculator.FighterInfo memory defenderInfo = isA ? fResult.fighterB.info : fResult.fighterA.info;

      IItemController.AttackInfo memory attackerMA = isA ? fResult.fighterA.magicAttack : fResult.fighterB.magicAttack;

      IFightCalculator.Statuses memory statuses = isA ? fResult.fighterB.statuses : fResult.fighterA.statuses;

      int32 resist = _getAttrValue(defenderInfo.fighterAttributes, IStatController.ATTRIBUTES.RESIST_TO_STATUSES);

      statuses.stun = statusChance(attackerInfo, attackerMA, IStatController.ATTRIBUTES.STUN, resist, random_);
      statuses.burn = statusChance(
        attackerInfo,
        attackerMA,
        IStatController.ATTRIBUTES.BURN,
        _getAttrValue(defenderInfo.fighterAttributes, IStatController.ATTRIBUTES.FIRE_RESISTANCE),
        random_
      );
      statuses.freeze = statusChance(
        attackerInfo,
        attackerMA,
        IStatController.ATTRIBUTES.FREEZE,
        _getAttrValue(defenderInfo.fighterAttributes, IStatController.ATTRIBUTES.COLD_RESISTANCE),
        random_
      );
      statuses.confuse = statusChance(attackerInfo, attackerMA, IStatController.ATTRIBUTES.CONFUSE, resist, random_);
      statuses.curse = statusChance(attackerInfo, attackerMA, IStatController.ATTRIBUTES.CURSE, resist, random_);
      statuses.poison = statusChance(attackerInfo, attackerMA, IStatController.ATTRIBUTES.POISON, resist, random_);
    }
  }

  function magicDamageCalculation(
    IFightCalculator.FighterInfo memory attackerInfo,
    IFightCalculator.FighterInfo memory defenderInfo,
    IItemController.AttackInfo memory magicAttack,
    int32 defenderHealth,
    function (uint) internal view returns (uint) random_
  ) internal view returns (AttackResult memory attackResult) {
    // generate damage
    int32 damage = getMagicDamage(
      attackerInfo,
      magicAttack,
      CalcLib.pseudoRandomInRangeFlex(magicAttack.min.toUint(), magicAttack.max.toUint(), random_)
    );
    damage = increaseMagicDmgByFactor(damage, attackerInfo, magicAttack.aType);
    damage = increaseRaceDmg(damage, attackerInfo, defenderInfo.race);
    bool critical = isCriticalHit(attackerInfo, random_(RESISTANCE_DENOMINATOR.toUint()));
    damage = critical ? damage * 2 : damage;

    // decrease damage
    damage = decreaseRaceDmg(damage, defenderInfo, attackerInfo.race);
    damage = decreaseDmgByDmgReduction(damage, defenderInfo);

    if (magicAttack.aType == IItemController.AttackType.FIRE) {
      damage -= _calcDmgInline(damage, defenderInfo, IStatController.ATTRIBUTES.FIRE_RESISTANCE);
    } else if (magicAttack.aType == IItemController.AttackType.COLD) {
      damage -= _calcDmgInline(damage, defenderInfo, IStatController.ATTRIBUTES.COLD_RESISTANCE);
    } else if (magicAttack.aType == IItemController.AttackType.LIGHTNING) {
      damage -= _calcDmgInline(damage, defenderInfo, IStatController.ATTRIBUTES.LIGHTNING_RESISTANCE);
    }

    int32 defenderHealthResult = defenderHealth < damage ? int32(0) : defenderHealth - damage;
    damage = defenderHealth - defenderHealthResult;

    return AttackResult({
      defenderHealth: defenderHealthResult,
      damage: damage,
      lifeStolen: lifeStolenPerHit(damage, attackerInfo),
      reflectDamage: reflectMagicDmg(damage, defenderInfo) + reflectChaos(magicAttack, attackerInfo, random_(1e18)),
      critical: critical ? uint8(1) : uint8(0),
      missed: 0,
      blocked: 0
    });
  }

  function meleeDamageCalculation(
    IFightCalculator.FighterInfo memory attackerInfo,
    IFightCalculator.FighterInfo memory defenderInfo,
    int32 defenderHealth,
    function (uint) internal view returns (uint) random_
  ) internal view returns (AttackResult memory attackResult) {
    attackResult = (new AttackResult[](1))[0];

    // generate damage
    int32 damage = getDamage(attackerInfo.fighterAttributes, random_);
    damage = increaseMeleeDmgByFactor(damage, attackerInfo);
    damage = increaseRaceDmg(damage, attackerInfo, defenderInfo.race);
    attackResult.critical = isCriticalHit(attackerInfo, random_(RESISTANCE_DENOMINATOR.toUint())) ? uint8(1) : uint8(0);
    damage = attackResult.critical == 0 ? damage : damage * 2;

    // decrease damage
    damage = decreaseRaceDmg(damage, defenderInfo, attackerInfo.race);
    damage = decreaseDmgByDmgReduction(damage, defenderInfo);

    attackResult.missed = random_(1e18) > StatLib.chanceToHit(
      _getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.ATTACK_RATING).toUint(),
      _getAttrValue(defenderInfo.fighterAttributes, IStatController.ATTRIBUTES.DEFENSE).toUint(),
      attackerInfo.fighterStats.level,
      defenderInfo.fighterStats.level,
      _getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.AR_FACTOR).toUint()
    ) ? 1 : 0;

    attackResult.blocked = (random_(100) < _getAttrValue(defenderInfo.fighterAttributes, IStatController.ATTRIBUTES.BLOCK_RATING).toUint()) ? 1 : 0;

    if (attackResult.missed != 0 || attackResult.blocked != 0) {
      damage = 0;
    }

    int32 defenderHealthResult = defenderHealth <= damage ? int32(0) : defenderHealth - damage;
    damage = defenderHealth - defenderHealthResult;


    attackResult.defenderHealth = defenderHealthResult;
    attackResult.damage = damage;
    attackResult.lifeStolen = lifeStolenPerHit(damage, attackerInfo);
    attackResult.reflectDamage = reflectMeleeDmg(damage, defenderInfo);
  }

  function getDamage(
    int32[] memory attributes,
    function (uint) internal view returns (uint) random_
  ) internal view returns (int32) {
    return int32(int(CalcLib.pseudoRandomInRangeFlex(
      _getAttrValue(attributes, IStatController.ATTRIBUTES.DAMAGE_MIN).toUint(),
      _getAttrValue(attributes, IStatController.ATTRIBUTES.DAMAGE_MAX).toUint(),
      random_
    )));
  }

  //endregion ------------------------ Internal logic

  //region ------------------------ Pure utils

  /// @notice Modify values in {targetAttributes} and {casterAttributes} according to {statuses}
  function reduceAttributesByStatuses(
    int32[] memory targetAttributes,
    IFightCalculator.Statuses memory statuses,
    int32[] memory casterAttributes
  ) internal pure {

    if (statuses.burn) {
      targetAttributes[uint(IStatController.ATTRIBUTES.DEFENSE)] -= (targetAttributes[uint(IStatController.ATTRIBUTES.DEFENSE)] / 3);
      targetAttributes[uint(IStatController.ATTRIBUTES.COLD_RESISTANCE)] += 50;
      casterAttributes[uint(IStatController.ATTRIBUTES.CRITICAL_HIT)] += 10;
      casterAttributes[uint(IStatController.ATTRIBUTES.DESTROY_ITEMS)] += 20;
    }
    if (statuses.freeze) {
      targetAttributes[uint(IStatController.ATTRIBUTES.DAMAGE_MIN)] /= 2;
      targetAttributes[uint(IStatController.ATTRIBUTES.DAMAGE_MAX)] /= 2;
      targetAttributes[uint(IStatController.ATTRIBUTES.ATTACK_RATING)] -= targetAttributes[uint(IStatController.ATTRIBUTES.ATTACK_RATING)] / 3;
      targetAttributes[uint(IStatController.ATTRIBUTES.BLOCK_RATING)] /= 2;
      targetAttributes[uint(IStatController.ATTRIBUTES.FIRE_RESISTANCE)] += 50;
    }
    if (statuses.confuse) {
      targetAttributes[uint(IStatController.ATTRIBUTES.ATTACK_RATING)] /= 2;
    }
    if (statuses.curse) {
      targetAttributes[uint(IStatController.ATTRIBUTES.FIRE_RESISTANCE)] /= 2;
      targetAttributes[uint(IStatController.ATTRIBUTES.COLD_RESISTANCE)] /= 2;
      targetAttributes[uint(IStatController.ATTRIBUTES.LIGHTNING_RESISTANCE)] /= 2;
    }
    if (statuses.stun) {
      casterAttributes[uint(IStatController.ATTRIBUTES.CRITICAL_HIT)] += 10;
    }
    if (statuses.poison) {
      targetAttributes[uint(IStatController.ATTRIBUTES.ATTACK_RATING)] /= 2;
    }

  }

  /// @notice Calculate new damage value depending on {defenderRace} and value of corresponded DMG_AGAINST_XXX attribute
  /// @param defenderRace See IStatController.Race
  /// @return Updated damage value
  function increaseRaceDmg(int32 dmg, IFightCalculator.FighterInfo memory attackerInfo, uint defenderRace)
  internal pure returns (int32) {
    if (defenderRace == uint(IStatController.Race.HUMAN)) {
      return dmg + _getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.DMG_AGAINST_HUMAN) * dmg / RESISTANCE_DENOMINATOR;
    } else if (defenderRace == uint(IStatController.Race.UNDEAD)) {
      return dmg + _getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.DMG_AGAINST_UNDEAD) * dmg / RESISTANCE_DENOMINATOR;
    } else if (defenderRace == uint(IStatController.Race.DAEMON)) {
      return dmg + _getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.DMG_AGAINST_DAEMON) * dmg / RESISTANCE_DENOMINATOR;
    } else if (defenderRace == uint(IStatController.Race.BEAST)) {
      return dmg + _getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.DMG_AGAINST_BEAST) * dmg / RESISTANCE_DENOMINATOR;
    } else {
      return dmg;
    }
  }

  /// @notice Decrease damage depending on {attackerRace}
  function decreaseRaceDmg(int32 dmg, IFightCalculator.FighterInfo memory defenderInfo, uint attackerRace) internal pure returns (int32) {
    if (attackerRace == uint(IStatController.Race.HUMAN)) {
      return dmg - _calcDmgInline(dmg, defenderInfo, IStatController.ATTRIBUTES.DEF_AGAINST_HUMAN);
    } else if (attackerRace == uint(IStatController.Race.UNDEAD)) {
      return dmg - _calcDmgInline(dmg, defenderInfo, IStatController.ATTRIBUTES.DEF_AGAINST_UNDEAD);
    } else if (attackerRace == uint(IStatController.Race.DAEMON)) {
      return dmg - _calcDmgInline(dmg, defenderInfo, IStatController.ATTRIBUTES.DEF_AGAINST_DAEMON);
    } else if (attackerRace == uint(IStatController.Race.BEAST)) {
      return dmg - _calcDmgInline(dmg, defenderInfo, IStatController.ATTRIBUTES.DEF_AGAINST_BEAST);
    } else {
      return dmg;
    }
  }

  /// @notice Calculate damage after Melee-attack
  function increaseMeleeDmgByFactor(int32 dmg, IFightCalculator.FighterInfo memory attackerInfo) internal pure returns (int32){
    return dmg + _getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.MELEE_DMG_FACTOR) * dmg / RESISTANCE_DENOMINATOR;
  }

  /// @notice Calculate damage after Magic-attack
  function increaseMagicDmgByFactor(int32 dmg, IFightCalculator.FighterInfo memory attackerInfo, IItemController.AttackType aType) internal pure returns (int32) {
    if (aType == IItemController.AttackType.FIRE) {
      return dmg + dmg * _getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.FIRE_DMG_FACTOR) / RESISTANCE_DENOMINATOR;
    } else if (aType == IItemController.AttackType.COLD) {
      return dmg + dmg * _getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.COLD_DMG_FACTOR) / RESISTANCE_DENOMINATOR;
    } else if (aType == IItemController.AttackType.LIGHTNING) {
      return dmg + dmg * _getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.LIGHTNING_DMG_FACTOR) / RESISTANCE_DENOMINATOR;
    } else {
      return dmg;
    }
  }

  /// @notice Reduce damage depending on value of Damage Reduction attribute
  function decreaseDmgByDmgReduction(int32 dmg, IFightCalculator.FighterInfo memory defenderInfo) internal pure returns (int32) {
    return dmg - _calcDmgInline(dmg, defenderInfo, IStatController.ATTRIBUTES.DAMAGE_REDUCTION);
  }

  /// @notice Calculate poison damage < {health}
  function poisonDmg(int32 health, IFightCalculator.Statuses memory statuses) internal pure returns (int32) {
    // poison should not kill
    if (statuses.poison && health.toUint() > 1) {
      // at least 1 dmg
      return int32(int(Math.max(health.toUint() / 10, 1)));
    }
    return 0;
  }

  /// @notice Reduce health of the fighters according to attacks results, calc damagePoison, damage and damageReflect.
  function reduceHp(
    AttackResult memory firstAttack,
    AttackResult memory secondAttack,
    IFightCalculator.Fighter memory firstFighter,
    IFightCalculator.Fighter memory secondFighter
  ) internal pure {
    secondFighter.health = firstAttack.defenderHealth;
    firstFighter.damage = firstAttack.damage;

    // hit only if second fighter survived
    if (secondFighter.health != 0) {
      firstFighter.health = secondAttack.defenderHealth;
      secondFighter.damage = secondAttack.damage;

      // reflect damage from second to first
      secondFighter.damageReflect = (CalcLib.minI32(firstAttack.reflectDamage, firstFighter.health));
      firstFighter.health -= secondFighter.damageReflect;

      // reflect damage from first to second
      firstFighter.damageReflect = (CalcLib.minI32(secondAttack.reflectDamage, secondFighter.health));
      secondFighter.health -= firstFighter.damageReflect;
    }

    // poison second firstly (he got damage and statuses early)
    firstFighter.damagePoison = poisonDmg(secondFighter.health, secondFighter.statuses);
    secondFighter.health -= firstFighter.damagePoison;

    // poison first fighter
    secondFighter.damagePoison = poisonDmg(firstFighter.health, firstFighter.statuses);
    firstFighter.health -= secondFighter.damagePoison;
  }

  /// @notice Calculate life-stolen-per-hit value for the given {damage} value
  function lifeStolenPerHit(int32 dmg, IFightCalculator.FighterInfo memory attackerInfo) internal pure returns (int32) {
    return dmg * _getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.LIFE_STOLEN_PER_HIT) / RESISTANCE_DENOMINATOR;
  }

  /// @notice Increase {fighter.health} on the value of life-stolen-per-hit (only if the health > 0)
  function stealLife(IFightCalculator.Fighter memory fighter, AttackResult memory attackResult) internal pure {
    if (fighter.health != 0) {
      int32 newHealth = fighter.health + attackResult.lifeStolen;
      int32 maxHealth = _getAttrValue(fighter.info.fighterAttributes, IStatController.ATTRIBUTES.LIFE);
      fighter.health = (CalcLib.minI32(newHealth, maxHealth));
    }
  }

  function skipTurn(IFightCalculator.FightInfoInternal memory fResult, bool isA) internal pure returns (bool) {
    return isA ? fResult.fighterA.statuses.stun : fResult.fighterB.statuses.stun;
  }

  /// @notice Detect which hero is faster and makes the hit first. Magic is faster melee.
  /// Otherwise first hit is made by the fighter with higher attack rating (A is selected if the ratings are equal)
  function calcFirstHit(IFightCalculator.FightInfoInternal memory fInfo) internal pure returns (bool aFirst){
    if (fInfo.fighterA.info.attackType == IFightCalculator.AttackType.MAGIC) {
      if (fInfo.fighterB.info.attackType == IFightCalculator.AttackType.MAGIC) {
        // if both fighters use magic we check attack rating
        aFirst = isAttackerFaster(fInfo.fighterA.info, fInfo.fighterB.info);
      } else {
        // otherwise, magic always faster than melee
        aFirst = true;
      }
    } else {
      if (fInfo.fighterB.info.attackType == IFightCalculator.AttackType.MAGIC) {
        // if fighter use magic he will be faster
        aFirst = false;
      } else {
        // otherwise, check attack rating
        aFirst = isAttackerFaster(fInfo.fighterA.info, fInfo.fighterB.info);
      }
    }
  }

  function isAttackerFaster(
    IFightCalculator.FighterInfo memory fighterAInfo,
    IFightCalculator.FighterInfo memory fighterBInfo
  ) internal pure returns (bool) {
    return _getAttrValue(fighterAInfo.fighterAttributes, IStatController.ATTRIBUTES.ATTACK_RATING)
      >= _getAttrValue(fighterBInfo.fighterAttributes, IStatController.ATTRIBUTES.ATTACK_RATING);
  }

  function reflectMeleeDmg(int32 dmg, IFightCalculator.FighterInfo memory defenderInfo) internal pure returns (int32) {
    return dmg * _getAttrValue(defenderInfo.fighterAttributes, IStatController.ATTRIBUTES.REFLECT_DAMAGE_MELEE) / RESISTANCE_DENOMINATOR;
  }

  function reflectMagicDmg(int32 dmg, IFightCalculator.FighterInfo memory defenderInfo) internal pure returns (int32) {
    return dmg * _getAttrValue(defenderInfo.fighterAttributes, IStatController.ATTRIBUTES.REFLECT_DAMAGE_MAGIC) / RESISTANCE_DENOMINATOR;
  }

  function _getChance(
    IFightCalculator.FighterInfo memory attackerInfo,
    IItemController.AttackType aType,
    IStatController.ATTRIBUTES index,
    int32 resist
  ) internal pure returns (int32 chance) {
    int32 chanceBase = attackerInfo.fighterAttributes[uint(index)];

    if (attackerInfo.attackType == IFightCalculator.AttackType.MAGIC) {
      if (index == IStatController.ATTRIBUTES.BURN && aType == IItemController.AttackType.FIRE) {
        chanceBase += int32(20);
      }
      if (index == IStatController.ATTRIBUTES.FREEZE && aType == IItemController.AttackType.COLD) {
        chanceBase += int32(20);
      }
      if (index == IStatController.ATTRIBUTES.CONFUSE && aType == IItemController.AttackType.LIGHTNING) {
        chanceBase += int32(20);
      }
    }

    chance = _getAdjustedAttributeValue(chanceBase, index);

    return chance - chance * (CalcLib.minI32(resist, _MAX_RESIST)) / RESISTANCE_DENOMINATOR;
  }

  /// @param randomValue Result of call _pseudoRandom, value in the range [0...RESISTANCE_DENOMINATOR)
  function isCriticalHit(
    IFightCalculator.FighterInfo memory attackerInfo,
    uint randomValue
  ) internal pure returns (bool) {
    return randomValue < _getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.CRITICAL_HIT).toUint();
  }

  /// @param randomValue Result of call CalcLib.pseudoRandom(1e18)
  function reflectChaos(
    IItemController.AttackInfo memory magicAttack,
    IFightCalculator.FighterInfo memory attackerInfo,
    uint randomValue
  ) internal pure returns (int32) {
    return (magicAttack.aType == IItemController.AttackType.CHAOS && randomValue > 5e17)
      ? int32(attackerInfo.fighterStats.life) / int32(2)
      : int32(0);
  }

  function _calcDmgInline(int32 dmg, IFightCalculator.FighterInfo memory info, IStatController.ATTRIBUTES index) internal pure returns (int32) {
    return dmg * (CalcLib.minI32(_getAttrValue(info.fighterAttributes, index), _MAX_RESIST)) / RESISTANCE_DENOMINATOR;
  }

  function getMagicDamage(
    IFightCalculator.FighterInfo memory attackerInfo,
    IItemController.AttackInfo memory mAttack,
    uint randomValue_
  ) internal pure returns (int32) {

    int32 attributeFactorResult = (_getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.STRENGTH) * mAttack.attributeFactors.strength / 100);
    attributeFactorResult += (_getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.DEXTERITY) * mAttack.attributeFactors.dexterity / 100);
    attributeFactorResult += (_getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.VITALITY) * mAttack.attributeFactors.vitality / 100);
    attributeFactorResult += (_getAttrValue(attackerInfo.fighterAttributes, IStatController.ATTRIBUTES.ENERGY) * mAttack.attributeFactors.energy / 100);

    return int32(int(randomValue_)) + attributeFactorResult;
  }
  //endregion ------------------------ Pure utils

  //region ------------------------ SIP-002

  /// @notice SIP-002: Implement smooth increase that approaches to y0 but never reaches that value
  /// @dev https://discord.com/channels/1134537718039318608/1265261881652674631
  /// @param y0 is desired capacity, 90 for resists/defs, 100 for critical hit and statuses
  /// @param x current value, base attribute. Assume x >= 0
  /// @param k is the factor of how fast the value will reach 90 capacity, k=100 by default
  /// @return new attribute value that is used in calculations, decimals 18
  function getReducedValue(uint y0, uint x, uint k) internal pure returns (uint) {
    // 2^n = exp(ln(2^n)) = exp(n * ln2)
    int t = FixedPointMathLib.expWad(-int(x) * LN2 / int(k));
    return t < 0
      ? 0 // some mistake happens (???)
      : y0 * (1e18 - uint(t));
  }

  /// @notice Apply {getReducedValue} to the given attribute, change value in place
  function _getAdjustedValue(int32 attributeValue, uint y0, uint k) internal pure returns (int32) {
    return attributeValue <= 0
      ? int32(0) // negative values => 0
      : int32(int(getReducedValue(y0, uint(int(attributeValue)), k) / 1e18));
  }

  /// @notice Return adjusted attribute value. Adjust selected attributes using y=z(1−2^(−x/k)) formula
  /// Value in array {attributes} is NOT changed.
  function _getAttrValue(int32[] memory attributes, IStatController.ATTRIBUTES attrId) internal pure returns (int32) {
    return _getAdjustedAttributeValue(attributes[uint(attrId)], attrId);
  }

  function _getAdjustedAttributeValue(int32 value, IStatController.ATTRIBUTES attrId) internal pure returns (int32) {
    if (
      attrId == IStatController.ATTRIBUTES.BLOCK_RATING
      || attrId == IStatController.ATTRIBUTES.FIRE_RESISTANCE
      || attrId == IStatController.ATTRIBUTES.COLD_RESISTANCE
      || attrId == IStatController.ATTRIBUTES.LIGHTNING_RESISTANCE
      || attrId == IStatController.ATTRIBUTES.DEF_AGAINST_HUMAN
      || attrId == IStatController.ATTRIBUTES.DEF_AGAINST_UNDEAD
      || attrId == IStatController.ATTRIBUTES.DEF_AGAINST_DAEMON
      || attrId == IStatController.ATTRIBUTES.DEF_AGAINST_BEAST
      || attrId == IStatController.ATTRIBUTES.DAMAGE_REDUCTION
      || attrId == IStatController.ATTRIBUTES.RESIST_TO_STATUSES
    ) {
      // use CAPACITY_RESISTS_DEFS, K_FACTOR
      return _getAdjustedValue(value, CAPACITY_RESISTS_DEFS, K_FACTOR);
    } else if (
      attrId == IStatController.ATTRIBUTES.CRITICAL_HIT
      || attrId == IStatController.ATTRIBUTES.STUN
      || attrId == IStatController.ATTRIBUTES.BURN
      || attrId == IStatController.ATTRIBUTES.FREEZE
      || attrId == IStatController.ATTRIBUTES.CONFUSE
      || attrId == IStatController.ATTRIBUTES.CURSE
      || attrId == IStatController.ATTRIBUTES.POISON
    ) {
      // use CAPACITY_CRITICAL_HIT_STATUSES, K_FACTOR
      return _getAdjustedValue(value, CAPACITY_CRITICAL_HIT_STATUSES, K_FACTOR);
    } else {
      return value;
    }
  }

  //endregion ------------------------ SIP-002

}
