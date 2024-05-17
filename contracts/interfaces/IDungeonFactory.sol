// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "../openzeppelin/EnumerableSet.sol";
import "../openzeppelin/EnumerableMap.sol";

interface IDungeonFactory {

  /// @custom:storage-location erc7201:dungeon.factory.main
  struct MainState {
    /// @dev biome => dungeonLaunchedId
    mapping(uint => EnumerableSet.UintSet) freeDungeons;
    /// @dev hero + heroId + biome (packMapObject) -> completed
    mapping(bytes32 => bool) bossCompleted;
    /// @dev hero + heroId + dungNum (packDungeonKey) -> completed
    mapping(bytes32 => bool) specificDungeonCompleted;
    /// @notice Max biome completed by the hero
    /// @dev hero + heroId (nftPacked) -> max biome completed
    mapping(bytes32 => uint8) maxBiomeCompleted;
    /// @notice which dungeon the hero is currently in
    /// @dev hero+id => current DungeonId
    mapping(bytes32 => uint64) heroCurrentDungeon;

    // ---

    /// @notice Specific dungeon for the given pair of hero level + hero class
    ///         ALl specific dungeons are listed also in allSpecificDungeons
    /// @dev packUint8Array(specReqBiome, specReqHeroClass) => dungNum
    mapping(bytes32 => uint16) dungeonSpecific;
    /// @dev contains all specific dungNum for easy management
    EnumerableSet.UintSet allSpecificDungeons;
    /// @dev biome => dungNum
    mapping(uint8 => EnumerableSet.UintSet) dungeonsLogicByBiome;

    // ---

    /// @dev max available biome. auto-increment with new dung deploy
    uint8 maxBiome;

    /// @notice Address of treasure token => min hero level required
    /// @dev manual threshold for treasury
    mapping(address => uint) minLevelForTreasury;

    /// @notice Contains arrays for SKILL_1, SKILL_2, SKILL_3 with 0 or 1
    /// i.e. [0, 1, 0] means that durability of SKILL_2 should be reduced
    /// @dev hero + heroId => uint8[] array where idx = slotNum
    mapping(bytes32 => bytes32) skillSlotsForDurabilityReduction;

    /// @notice Counter of dungeons, it's incremented on launch of a new dungeon
    uint64 dungeonCounter;

    /// @dev dungNum = init attributes
    mapping(uint16 => DungeonAttributes) dungeonAttributes;
    /// @dev dungeonId => status
    mapping(uint64 => DungeonStatus) dungeonStatuses;
  }

  struct ObjectGenerateInfo {
    /// @notice List of chamber types for each unique object
    /// @dev uint8 types, packed using PackingLib.packUint8Array
    bytes32[] objTypesByStages;
    /// @notice List of chances for each chamber type
    /// @dev uint64 chances
    uint32[][] objChancesByStages;
  }

  struct DungeonGenerateInfo {
    /// @notice List of chamber types for each unique object
    uint8[][] objTypesByStages;
    /// @notice List of chances for each chamber type
    uint32[][] objChancesByStages;

    uint32[] uniqObjects;

    uint8 minLevel;
    uint8 maxLevel;

    bytes32[] requiredCustomDataIndex;
    uint64[] requiredCustomDataMinValue;
    uint64[] requiredCustomDataMaxValue;
    bool[] requiredCustomDataIsHero;
  }

  /// @notice Attributes of the given dungeon logic
  struct DungeonAttributes {
    /// @notice Total number of stages that should be passed to complete the dungeon
    uint8 stages;
    uint8 biome;

    /// @notice Default list of objects that should be passed in the dungeon
    uint32[] uniqObjects;

    /// @dev min+max (packUint8Array)
    bytes32 minMaxLevel;

    bytes32[] requiredCustomDataIndex;
    /// @notice Packed DungeonGenerateInfo.requiredCustomData: MinValue, MaxValue, IsHero
    /// @dev min+max+isHero(packStoryCustomDataRequirements)
    bytes32[] requiredCustomDataValue;

    ObjectGenerateInfo info;
  }

  /// @notice Current status of the given dungeon
  struct DungeonStatus {
    uint64 dungeonId;
    /// @notice Dungeon logic id
    uint16 dungNum;

    /// @notice True if the dungeon is completed by the hero
    bool isCompleted;

    /// @notice Hero in the dungeon or 0
    address heroToken;
    uint heroTokenId;
    /// @notice Current object that should be passed by the hero. 0 - new object is not opened
    uint32 currentObject;
    /// @notice Current stage in the dungeon that should be passed by the hero.
    uint8 currentStage;

    EnumerableMap.AddressToUintMap treasuryTokens;
    /// @notice All items that were minted on result of made actions
    bytes32[] treasuryItems;

    /// @notice Total number of stages that should be passed to complete the dungeon
    /// This value can be bigger than length of uniqObjects
    uint8 stages;
    /// @notice List of objects to be passed in the stage. The list can be dynamically changed during passing the stages
    uint32[] uniqObjects;
  }

  ////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////

  function launchForNewHero(address heroToken, uint heroTokenId, address owner) external returns (uint64 dungeonId);

  function maxBiomeCompleted(address heroToken, uint heroTokenId) external view returns (uint8);

  function currentDungeon(address heroToken, uint heroTokenId) external view returns (uint64);

  function skillSlotsForDurabilityReduction(address heroToken, uint heroTokenId) external view returns (uint8[] memory result);

  function setBossCompleted(uint32 objectId, address heroToken, uint heroTokenId, uint8 heroBiome) external;

}
