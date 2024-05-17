// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "../lib/StatLib.sol";
import "../lib/CalcLib.sol";

contract StatReader {
  using CalcLib for int32;

  function chanceToHit(
    int32 attackersAttackRating,
    int32 defendersDefenceRating,
    int32 attackersLevel,
    int32 defendersLevel,
    int32 arFactor
  ) external pure returns (uint) {
    return StatLib.chanceToHit(
      attackersAttackRating.toUint(),
      defendersDefenceRating.toUint(),
      attackersLevel.toUint(),
      defendersLevel.toUint(),
      arFactor.toUint()
    );
  }

  function levelExperience(uint32 level) external pure returns (uint) {
    return StatLib.levelExperience(level);
  }

  function minDamage(int32 strength, uint heroClass) external pure returns (int32) {
    return StatLib.minDamage(strength, heroClass);
  }

  function experienceToLvl(uint exp, uint startFromLevel) external pure returns (uint) {
    return StatLib.experienceToLvl(exp, startFromLevel);
  }

  function startHeroAttributes(uint heroClass) external pure returns (
    IStatController.CoreAttributes memory,
    StatLib.BaseMultiplier memory,
    StatLib.LevelUp memory
  ) {
    StatLib.InitialHero memory h = StatLib.initialHero(heroClass);
    return (h.core, h.multiplier, h.levelUp);
  }

  function baseLifeChances(uint heroClass) external pure returns(int32) {
    return StatLib.initialHero(heroClass).baseLifeChances;
  }
}
