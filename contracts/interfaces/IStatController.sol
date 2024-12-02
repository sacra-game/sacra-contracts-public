// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;
import "../openzeppelin/EnumerableSet.sol";
import "../openzeppelin/EnumerableMap.sol";

interface IStatController {

  /// @custom:storage-location erc7201:stat.controller.main
  struct MainState {
    mapping(bytes32 => bytes32[]) heroTotalAttributes;
    /// @dev heroAdr+heroId => int32 packed strength, dexterity, vitality, energy
    mapping(bytes32 => bytes32) _heroCore;
    mapping(bytes32 => bytes32[]) heroBonusAttributes;
    mapping(bytes32 => bytes32[]) heroTemporallyAttributes;
    /// @dev heroAdr+heroId => uint32 packed level, experience, life, mana, lifeChances
    mapping(bytes32 => bytes32) heroStats;
    /// @dev heroAdr+heroId+itemSlot => itemAdr + itemId
    mapping(bytes32 => bytes32) heroSlots;
    /// @dev heroAdr+heroId => busy slots uint8[] packed
    mapping(bytes32 => bytes32) heroBusySlots;
    mapping(bytes32 => EnumerableSet.AddressSet) usedConsumables;
    /// @dev heroCustomDataV2 is used instead
    mapping(bytes32 => mapping(bytes32 => uint)) _deprecated_heroCustomData;
    mapping(bytes32 => uint) globalCustomData;

    /// @notice packNftIdWithValue(hero, heroId, ngLevel) => hero custom data map
    /// @dev initially it was packedHero => hero custom data map
    mapping(bytes32 => EnumerableMap.Bytes32ToUintMap) heroCustomDataV2;
  }


  enum ATTRIBUTES {
    // core
    STRENGTH, // 0
    DEXTERITY, // 1
    VITALITY, // 2
    ENERGY, // 3
    // attributes
    DAMAGE_MIN, // 4
    DAMAGE_MAX, // 5
    ATTACK_RATING, // 6
    DEFENSE, // 7
    BLOCK_RATING, // 8
    LIFE, // 9
    MANA, // 10
    // resistance
    FIRE_RESISTANCE, // 11
    COLD_RESISTANCE, // 12
    LIGHTNING_RESISTANCE, // 13
    // dmg against
    DMG_AGAINST_HUMAN, // 14
    DMG_AGAINST_UNDEAD, // 15
    DMG_AGAINST_DAEMON, // 16
    DMG_AGAINST_BEAST, // 17

    // defence against
    DEF_AGAINST_HUMAN, // 18
    DEF_AGAINST_UNDEAD, // 19
    DEF_AGAINST_DAEMON, // 20
    DEF_AGAINST_BEAST, // 21

    // --- unique, not augmentable
    // hero will not die until have positive chances
    LIFE_CHANCES, // 22
    // increase chance to get an item
    MAGIC_FIND, // 23
    // decrease chance to get an item
    DESTROY_ITEMS, // 24
    // percent of chance x2 dmg
    CRITICAL_HIT, // 25
    // dmg factors
    MELEE_DMG_FACTOR, // 26
    FIRE_DMG_FACTOR, // 27
    COLD_DMG_FACTOR, // 28
    LIGHTNING_DMG_FACTOR, // 29
    // increase attack rating on given percent
    AR_FACTOR, // 30
    // percent of damage will be converted to HP
    LIFE_STOLEN_PER_HIT, // 31
    // amount of mana restored after each battle
    MANA_AFTER_KILL, // 32
    // reduce all damage on percent after all other reductions
    DAMAGE_REDUCTION, // 33

    // -- statuses
    // chance to stun an enemy, stunned enemy skip next hit
    STUN, // 34
    // chance burn an enemy, burned enemy will loss 50% of defence
    BURN, // 35
    // chance freeze an enemy, frozen enemy will loss 50% of MELEE damage
    FREEZE, // 36
    // chance to reduce enemy's attack rating on 50%
    CONFUSE, // 37
    // chance curse an enemy, cursed enemy will loss 50% of resistance
    CURSE, // 38
    // percent of dmg return to attacker
    REFLECT_DAMAGE_MELEE, // 39
    REFLECT_DAMAGE_MAGIC, // 40
    // chance to poison enemy, poisoned enemy will loss 10% of the current health
    POISON, // 41
    // reduce chance get any of uniq statuses
    RESIST_TO_STATUSES, // 42

    END_SLOT // 46
  }

  // possible
  // HEAL_FACTOR

  struct CoreAttributes {
    int32 strength;
    int32 dexterity;
    int32 vitality;
    int32 energy;
  }

  struct ChangeableStats {
    uint32 level;
    uint32 experience;
    uint32 life;
    uint32 mana;
    uint32 lifeChances;
  }

  enum ItemSlots {
    UNKNOWN, // 0
    HEAD, // 1
    BODY, // 2
    GLOVES, // 3
    BELT, // 4
    AMULET, // 5
    BOOTS, // 6
    RIGHT_RING, // 7
    LEFT_RING, // 8
    RIGHT_HAND, // 9
    LEFT_HAND, // 10
    TWO_HAND, // 11
    SKILL_1, // 12
    SKILL_2, // 13
    SKILL_3, // 14
    END_SLOT // 15
  }

  struct NftItem {
    address token;
    uint tokenId;
  }

  enum Race {
    UNKNOWN, // 0
    HUMAN, // 1
    UNDEAD, // 2
    DAEMON, // 3
    BEAST, // 4
    END_SLOT // 5
  }

  struct ChangeAttributesInfo {
    address heroToken;
    uint heroTokenId;
    int32[] changeAttributes;
    bool add;
    bool temporally;
  }

  struct BuffInfo {
    address heroToken;
    uint heroTokenId;
    uint32 heroLevel;
    address[] buffTokens;
    uint[] buffTokenIds;
  }

  /// @dev This struct is used inside event, so it's moved here from lib
  struct ActionInternalInfo {
    int32[] posAttributes;
    int32[] negAttributes;

    uint32 experience;
    int32 heal;
    int32 manaRegen;
    int32 lifeChancesRecovered;
    int32 damage;
    int32 manaConsumed;

    address[] mintedItems;
  }

  function initNewHero(address token, uint tokenId, uint heroClass) external;

  function heroAttributes(address token, uint tokenId) external view returns (int32[] memory);

  function heroAttribute(address token, uint tokenId, uint index) external view returns (int32);

  function heroAttributesLength(address token, uint tokenId) external view returns (uint);

  function heroBaseAttributes(address token, uint tokenId) external view returns (CoreAttributes memory);

  function heroCustomData(address token, uint tokenId, bytes32 index) external view returns (uint);

  function globalCustomData(bytes32 index) external view returns (uint);

  function heroStats(address token, uint tokenId) external view returns (ChangeableStats memory);

  function heroItemSlot(address token, uint64 tokenId, uint8 itemSlot) external view returns (bytes32 nftPacked);

  function heroItemSlots(address heroToken, uint heroTokenId) external view returns (uint8[] memory);

  function isHeroAlive(address heroToken, uint heroTokenId) external view returns (bool);

  function levelUp(address token, uint tokenId, uint heroClass, CoreAttributes memory change) external returns (uint newLvl);

  function changeHeroItemSlot(
    address heroToken,
    uint64 heroTokenId,
    uint itemType,
    uint8 itemSlot,
    address itemToken,
    uint itemTokenId,
    bool equip
  ) external;

  function changeCurrentStats(
    address token,
    uint tokenId,
    ChangeableStats memory change,
    bool increase
  ) external;

  function changeBonusAttributes(ChangeAttributesInfo memory info) external;

  function registerConsumableUsage(address heroToken, uint heroTokenId, address item) external;

  function clearUsedConsumables(address heroToken, uint heroTokenId) external;

  function clearTemporallyAttributes(address heroToken, uint heroTokenId) external;

  function buffHero(BuffInfo memory info) external view returns (int32[] memory attributes, int32 manaConsumed);

  function setHeroCustomData(address token, uint tokenId, bytes32 index, uint value) external;

  function setGlobalCustomData(bytes32 index, uint value) external;

  /// @notice Restore life and mana during reinforcement
  /// @dev Life and mana will be increased on ((current life/mana attr value) - (prev life/mana attr value))
  /// @param prevAttributes Hero attributes before reinforcement
  function restoreLifeAndMana(address heroToken, uint heroTokenId, int32[] memory prevAttributes) external;

  function reborn(address heroToken, uint heroTokenId, uint heroClass) external;
}
