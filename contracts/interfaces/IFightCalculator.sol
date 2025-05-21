// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "./IStatController.sol";
import "./IItemController.sol";

interface IFightCalculator {

  enum AttackType {
    UNKNOWN, // 0
    MELEE, // 1
    MAGIC, // 2
    SLOT_3,
    SLOT_4,
    SLOT_5,
    SLOT_6,
    SLOT_7,
    SLOT_8,
    SLOT_9,
    SLOT_10
  }

  /// @notice Attacker info: suitable both for hero and monsters
  struct AttackInfo {
    /// @notice Type of the attack
    /// by default, if attack token presents, it's magic attack and not-magic otherwise
    /// but this logic can become more complicated after introducing new attack types
    AttackType attackType;
    /// @notice NFT selected by hero for attack, it should be equip on.
    /// If attacker is a monster, this is a special case (stub NFT with zero ID is used)
    address attackToken;
    uint attackTokenId;
    address[] skillTokens;
    uint[] skillTokenIds;
  }

  struct FighterInfo {
    int32[] fighterAttributes;
    IStatController.ChangeableStats fighterStats;
    AttackType attackType;
    address attackToken;
    uint attackTokenId;
    uint race;
  }

  struct Statuses {
    bool stun;
    bool burn;
    bool freeze;
    bool confuse;
    bool curse;
    bool poison;
    bool gotCriticalHit;
    bool missed;
    bool hitBlocked;
  }

  struct FightResult {
    int32 healthA;
    int32 healthB;
    int32 manaConsumedA;
    int32 manaConsumedB;
  }

  struct FightCall {
    FighterInfo fighterA;
    FighterInfo fighterB;
    uint64 dungeonId;
    uint32 objectId;
    address heroAdr;
    uint heroId;
    uint8 stageId;
    uint iteration;
    uint8 turn;
  }

  /// @notice Additional info passed to fight
  struct FightCallAdd {
    address msgSender;

    /// @notice Unique ID of the pvp-fight, 0 for not pvp fights
    uint48 fightId;
  }

  struct SkillSlots {
    bool slot1;
    bool slot2;
    bool slot3;
  }

  //region ------------------------ FightLib-internal (FightInfoInternal is required by IApplicationEvents..)
  struct FightInfoInternal {
    Fighter fighterA;
    Fighter fighterB;
  }

  struct Fighter {
    IFightCalculator.FighterInfo info;
    IItemController.AttackInfo magicAttack;
    int32 health;
    int32 manaConsumed;
    int32 damage;
    int32 damagePoison;
    int32 damageReflect;
    IFightCalculator.Statuses statuses;
  }
  //endregion ------------------------ FightLib-internal

  function fight(FightCall memory callData) external returns (FightResult memory);
}
