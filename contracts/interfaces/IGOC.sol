// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "../openzeppelin/EnumerableSet.sol";
import "./IController.sol";

interface IGOC {

  enum ObjectType {
    UNKNOWN, // 0
    EVENT, // 1
    MONSTER, // 2
    STORY, // 3
    END_SLOT
  }

  enum ObjectSubType {
    UNKNOWN_0, // 0
    ENEMY_NPC_1, // 1
    ENEMY_NPC_SUPER_RARE_2, // 2
    BOSS_3, // 3
    SHRINE_4, // 4
    CHEST_5, // 5
    STORY_6, // 6
    STORY_UNIQUE_7, // 7
    SHRINE_UNIQUE_8, // 8
    CHEST_UNIQUE_9, // 9
    ENEMY_NPC_UNIQUE_10, // 10
    STORY_ON_ROAD_11, // 11
    STORY_UNDERGROUND_12, // 12
    STORY_NIGHT_CAMP_13, // 13
    STORY_MOUNTAIN_14, // 14
    STORY_WATER_15, // 15
    STORY_CASTLE_16, // 16
    STORY_HELL_17, // 17
    STORY_SPACE_18, // 18
    STORY_WOOD_19, // 19
    STORY_CATACOMBS_20, // 20
    STORY_BAD_HOUSE_21, // 21
    STORY_GOOD_TOWN_22, // 22
    STORY_BAD_TOWN_23, // 23
    STORY_BANDIT_CAMP_24, // 24
    STORY_BEAST_LAIR_25, // 25
    STORY_PRISON_26, // 26
    STORY_SWAMP_27, // 27
    STORY_INSIDE_28, // 28
    STORY_OUTSIDE_29, // 29
    STORY_INSIDE_RARE_30,
    STORY_OUTSIDE_RARE_31,
    ENEMY_NPC_INSIDE_32,
    ENEMY_NPC_INSIDE_RARE_33,
    ENEMY_NPC_OUTSIDE_34,
    ENEMY_NPC_OUTSIDE_RARE_35,
    END_SLOT
  }

  /// @custom:storage-location erc7201:game.object.controller.main
  struct MainState {

    /// @dev objId = biome(00) type(00) id(0000) => biome(uint8) + objType(uint8)
    /// Id is id of the event, story or monster.
    mapping(uint32 => bytes32) objectMeta;

    /// @dev biome(uint8) + objType(uint8) => set of object id
    mapping(bytes32 => EnumerableSet.UintSet) objectIds;

    /// @dev heroAdr180 + heroId64 + cType8 + biome8 => set of already played objects. Should be cleared periodically
    mapping(bytes32 => EnumerableSet.UintSet) playedObjects;

    /// @dev HeroAdr(160) + heroId(uint64) + objId(uint32) => iteration count. It needs for properly emit events for every new entrance.
    mapping(bytes32 => uint) iterations;

    /// @dev objId(uint32) => EventInfo
    mapping(uint32 => EventInfo) eventInfos;

    /// @dev objId(uint32) => storyId
    mapping(uint32 => uint16) storyIds;

    /// @dev objId(uint32) => MonsterInfo
    mapping(uint32 => MonsterInfo) monsterInfos;

    /// @dev hero+id => last fight action timestamp
    mapping(bytes32 => uint) lastHeroFightTs;

    /// @dev delay for user actions in fight (suppose to prevent bot actions)
    uint fightDelay;
  }

  struct ActionResult {
    bool kill;
    bool completed;
    address heroToken;
    address[] mintItems;
    int32 heal;
    int32 manaRegen;
    int32 lifeChancesRecovered;
    int32 damage;
    int32 manaConsumed;
    uint32 objectId;
    uint32 experience;
    uint heroTokenId;
    uint iteration;
    uint32[] rewriteNextObject;
  }

  struct EventInfo {
    /// @dev chance to use good or bad attributes/stats
    uint32 goodChance;

    /// @dev toBytes32ArrayWithIds
    bytes32[] goodAttributes;
    bytes32[] badAttributes;

    /// @dev experience(uint32) + heal(int32) + manaRegen(int32) + lifeChancesRecovered(int32) + damage(int32) + manaConsume(int32) packStatsChange
    bytes32 statsChange;

    /// @dev item+chance packItemMintInfo
    bytes32[] mintItems;
  }

  struct MonsterInfo {
    /// @dev toBytes32ArrayWithIds
    bytes32[] attributes;
    /// @dev level(uint8) + race(uint8) + experience(uint32) + maxDropItems(uint8) packMonsterStats
    bytes32 stats;
    /// @dev attackToken(160) + attackTokenId(uint64) + attackType(uint8) packAttackInfo
    bytes32 attackInfo;

    /// @dev item+chance packItemMintInfo
    bytes32[] mintItems;

    /// @dev heroAdr(160) + heroId(uint64) => iteration => GeneratedMonster packed
    mapping(bytes32 => mapping(uint => bytes32)) _generatedMonsters;
  }

  struct MultiplierInfo {
    uint8 biome;
    uint totalSupply;
  }

  struct GeneratedMonster {
    bool generated;
    uint8 turnCounter;
    int32 hp;
    uint32 amplifier;
  }

  struct MonsterGenInfo {
    uint16 monsterId;
    uint8 biome;
    ObjectSubType subType;

    uint8[] attributeIds;
    int32[] attributeValues;

    uint8 level;
    uint8 race;
    uint32 experience;
    uint8 maxDropItems;

    address attackToken;
    uint64 attackTokenId;
    uint8 attackType;

    address[] mintItems;
    uint32[] mintItemsChances;
  }

  struct ActionContext {
    address sender;
    address heroToken;
    IController controller;
    uint8 biome;
    uint8 objectSubType;
    uint8 stageId;
    uint32 objectId;
    uint64 dungeonId;
    uint heroTokenId;
    uint salt;
    uint iteration;
    bytes data;
  }

  struct EventRegInfo {
    uint8 biome;
    uint16 eventId;
    ObjectSubType subType;

    uint32 goodChance;

    AttributeGenerateInfo goodAttributes;
    AttributeGenerateInfo badAttributes;

    uint32 experience;
    int32 heal;
    int32 manaRegen;
    int32 lifeChancesRecovered;
    int32 damage;
    int32 manaConsumed;

    address[] mintItems;
    uint32[] mintItemsChances;
  }

  struct AttributeGenerateInfo {
    uint8[] ids;
    int32[] values;
  }

  //////////////////////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////////////

  /// @dev represent object registration if non zero values
  function getObjectMeta(uint32 objectId) external view returns (uint8 biome, uint8 objectSubType);

  function isBattleObject(uint32 objectId) external view returns (bool);

  function getRandomObject(
    uint8[] memory cTypes,
    uint32[] memory chances,
    uint8 biomeLevel,
    address heroToken,
    uint heroTokenId
  ) external returns (uint32 objectId);

  function open(address heroToken, uint heroTokenId, uint32 objectId) external returns (uint iteration);

  function action(
    address sender,
    uint64 dungeonId,
    uint32 objectId,
    address heroToken,
    uint heroTokenId,
    uint8 stageId,
    bytes memory data
  ) external returns (ActionResult memory);

}
