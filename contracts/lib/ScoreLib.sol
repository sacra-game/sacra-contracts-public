// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../openzeppelin/Math.sol";
import "../interfaces/IStatController.sol";
import "./CalcLib.sol";

library ScoreLib {
  using CalcLib for int32;

  // core
  uint public constant STRENGTH = 100;
  uint public constant DEXTERITY = 100;
  uint public constant VITALITY = 100;
  uint public constant ENERGY = 100;

  // attributes
  uint public constant MELEE_DAMAGE = 10;
  uint public constant ATTACK_RATING = 3;
  uint public constant DEFENCE = 10;
  uint public constant BLOCK_RATING = 500;
  uint public constant LIFE = 10;
  uint public constant MANA = 10;

  uint public constant LIFE_CHANCES = 10_000;
  uint public constant MAGIC_FIND = 300;
  uint public constant CRITICAL_HIT = 150;
  uint public constant DMG_FACTOR = 200;

  uint public constant AR_FACTOR = 200;
  uint public constant LIFE_STOLEN_PER_HIT = 1000;
  uint public constant MANA_AFTER_KILL = 1000;
  uint public constant DAMAGE_REDUCTION = 500;
  uint public constant REFLECT_DAMAGE = 250;
  uint public constant RESIST_TO_STATUSES = 70;

  // resistance
  uint public constant ELEMENT_RESIST = 100;

  // race specific attributes
  uint public constant RACE_SPECIFIC = 20;

  // statuses
  uint public constant STATUSES = 100;

  // items
  uint public constant DURABILITY_SCORE = 1;

  // hero
  uint public constant HERO_LEVEL_SCORE = 1000;

  function attributesScore(int32[] memory attributes) internal pure returns (uint) {
    uint result;
    {
      result += (attributes[uint(IStatController.ATTRIBUTES.STRENGTH)]).toUint() * STRENGTH
        + (attributes[uint(IStatController.ATTRIBUTES.DEXTERITY)]).toUint() * DEXTERITY
        + (attributes[uint(IStatController.ATTRIBUTES.VITALITY)]).toUint() * VITALITY
        + (attributes[uint(IStatController.ATTRIBUTES.ENERGY)]).toUint() * ENERGY
        + (attributes[uint(IStatController.ATTRIBUTES.ATTACK_RATING)]).toUint() * ATTACK_RATING
        + (attributes[uint(IStatController.ATTRIBUTES.DEFENSE)]).toUint() * DEFENCE
        + (attributes[uint(IStatController.ATTRIBUTES.BLOCK_RATING)]).toUint() * BLOCK_RATING
        + Math.average(attributes[uint(IStatController.ATTRIBUTES.DAMAGE_MIN)].toUint(), attributes[uint(IStatController.ATTRIBUTES.DAMAGE_MAX)].toUint()) * MELEE_DAMAGE
      ;
    }
    {
      result +=
        (attributes[uint(IStatController.ATTRIBUTES.LIFE)]).toUint() * LIFE
        + (attributes[uint(IStatController.ATTRIBUTES.MANA)]).toUint() * MANA
        + (attributes[uint(IStatController.ATTRIBUTES.FIRE_RESISTANCE)]).toUint() * ELEMENT_RESIST
        + (attributes[uint(IStatController.ATTRIBUTES.COLD_RESISTANCE)]).toUint() * ELEMENT_RESIST
        + (attributes[uint(IStatController.ATTRIBUTES.LIGHTNING_RESISTANCE)]).toUint() * ELEMENT_RESIST;
    }
    {
      result +=
        (attributes[uint(IStatController.ATTRIBUTES.DMG_AGAINST_HUMAN)]).toUint() * RACE_SPECIFIC
        + (attributes[uint(IStatController.ATTRIBUTES.DMG_AGAINST_UNDEAD)]).toUint() * RACE_SPECIFIC
        + (attributes[uint(IStatController.ATTRIBUTES.DMG_AGAINST_DAEMON)]).toUint() * RACE_SPECIFIC
        + (attributes[uint(IStatController.ATTRIBUTES.DMG_AGAINST_BEAST)]).toUint() * RACE_SPECIFIC
        + (attributes[uint(IStatController.ATTRIBUTES.DEF_AGAINST_HUMAN)]).toUint() * RACE_SPECIFIC
        + (attributes[uint(IStatController.ATTRIBUTES.DEF_AGAINST_UNDEAD)]).toUint() * RACE_SPECIFIC
        + (attributes[uint(IStatController.ATTRIBUTES.DEF_AGAINST_DAEMON)]).toUint() * RACE_SPECIFIC
        + (attributes[uint(IStatController.ATTRIBUTES.DEF_AGAINST_BEAST)]).toUint() * RACE_SPECIFIC;
    }
    {
      result +=
        (attributes[uint(IStatController.ATTRIBUTES.STUN)]).toUint() * STATUSES
        + (attributes[uint(IStatController.ATTRIBUTES.BURN)]).toUint() * STATUSES
        + (attributes[uint(IStatController.ATTRIBUTES.FREEZE)]).toUint() * STATUSES
        + (attributes[uint(IStatController.ATTRIBUTES.CONFUSE)]).toUint() * STATUSES
        + (attributes[uint(IStatController.ATTRIBUTES.CURSE)]).toUint() * STATUSES
        + (attributes[uint(IStatController.ATTRIBUTES.POISON)]).toUint() * STATUSES;
    }
    {
      result +=
        (attributes[uint(IStatController.ATTRIBUTES.LIFE_CHANCES)]).toUint() * LIFE_CHANCES
        + (attributes[uint(IStatController.ATTRIBUTES.MAGIC_FIND)]).toUint() * MAGIC_FIND
        + (attributes[uint(IStatController.ATTRIBUTES.CRITICAL_HIT)]).toUint() * CRITICAL_HIT
        + (attributes[uint(IStatController.ATTRIBUTES.MELEE_DMG_FACTOR)]).toUint() * DMG_FACTOR
        + (attributes[uint(IStatController.ATTRIBUTES.FIRE_DMG_FACTOR)]).toUint() * DMG_FACTOR
        + (attributes[uint(IStatController.ATTRIBUTES.COLD_DMG_FACTOR)]).toUint() * DMG_FACTOR
        + (attributes[uint(IStatController.ATTRIBUTES.LIGHTNING_DMG_FACTOR)]).toUint() * DMG_FACTOR;
    }
    {
      result +=
        (attributes[uint(IStatController.ATTRIBUTES.AR_FACTOR)]).toUint() * AR_FACTOR
        + (attributes[uint(IStatController.ATTRIBUTES.LIFE_STOLEN_PER_HIT)]).toUint() * LIFE_STOLEN_PER_HIT
        + (attributes[uint(IStatController.ATTRIBUTES.MANA_AFTER_KILL)]).toUint() * MANA_AFTER_KILL
        + (attributes[uint(IStatController.ATTRIBUTES.DAMAGE_REDUCTION)]).toUint() * DAMAGE_REDUCTION
        + (attributes[uint(IStatController.ATTRIBUTES.REFLECT_DAMAGE_MELEE)]).toUint() * REFLECT_DAMAGE
        + (attributes[uint(IStatController.ATTRIBUTES.REFLECT_DAMAGE_MAGIC)]).toUint() * REFLECT_DAMAGE
        + (attributes[uint(IStatController.ATTRIBUTES.RESIST_TO_STATUSES)]).toUint() * RESIST_TO_STATUSES;
    }
    return result;
  }

  function itemScore(int32[] memory attributes, uint16 baseDurability) internal pure returns (uint) {
    return attributesScore(attributes) + baseDurability * DURABILITY_SCORE;
  }

  function heroScore(int32[] memory attributes, uint level) internal pure returns (uint) {
    return attributesScore(attributes) + level * HERO_LEVEL_SCORE;
  }

}
