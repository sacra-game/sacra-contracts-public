// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "./IStatController.sol";
import "./IGOC.sol";
import "../openzeppelin/EnumerableSet.sol";

interface IItemController {

  enum GlobalParam {
    UNKNOWN_0,

    /// @notice Address of ItemControllerHelper
    ITEM_CONTROLLER_HELPER_ADDRESS_1
  }

  /// @custom:storage-location erc7201:item.controller.main
  struct MainState {

    ////////////////// GENERATE //////////////////

    EnumerableSet.AddressSet items;

    /// @dev itemAdr => itemMetaType8 + itemLvl8 + itemType8 + baseDurability16 + defaultRarity8 + minAttr8 + maxAttr8 + manaCost32 + req(packed core 128)
    mapping(address => bytes32) itemMeta;

    /// @dev itemAdr => packed tokenAdr160+ amount96
    mapping(address => bytes32) augmentInfo;

    // --- common attr ---

    /// @dev itemAdr => id8 + min(int32) + max(int32) + chance32
    mapping(address => bytes32[]) generateInfoAttributes;

    // --- consumable ---

    /// @dev itemAdr => ids+values (toBytes32ArrayWithIds)
    mapping(address => bytes32[]) _itemConsumableAttributes;

    /// @dev itemAdr => IStatController.ChangeableStats packed int32[]
    mapping(address => bytes32) itemConsumableStats;

    // --- buff ---

    /// @dev itemAdr => id8 + min(int32) + max(int32) + chance32
    mapping(address => bytes32[]) generateInfoCasterAttributes;

    /// @dev itemAdr => id8 + minDmg(int32) + maxDmg(int32) + chance32
    mapping(address => bytes32[]) generateInfoTargetAttributes;

    // --- attack ---

    /// @dev itemAdr => packed AttackInfo: attackType8 + min32 + max32 + factors(packed core 128)
    mapping(address => bytes32) generateInfoAttack;

    ////////////////// ITEMS INFO //////////////////

    /// @dev itemAdr+id => itemRarity8 + augmentationLevel8 + itemDurability16
    mapping(bytes32 => bytes32) itemInfo;

    /// @dev itemAdr+id => heroAdr+id
    mapping(bytes32 => bytes32) equippedOn;

    // --- common attr ---

    /// @dev itemAdr+Id => ids+values (toBytes32ArrayWithIds)
    mapping(bytes32 => bytes32[]) _itemAttributes;

    // --- consumable ---

    // consumable stats unchangeable, get them by address

    // --- buff ---

    /// @dev itemAdr+Id => ids+values (toBytes32ArrayWithIds)
    mapping(bytes32 => bytes32[]) _itemCasterAttributes;

    /// @dev itemAdr+Id => ids+values (toBytes32ArrayWithIds)
    mapping(bytes32 => bytes32[]) _itemTargetAttributes;

    // --- attack ---

    /// @dev itemAdr+Id => packed AttackInfo: attackType8 + min32 + max32 + factors(packed core 128)
    mapping(bytes32 => bytes32) _itemAttackInfo;

    ////////////////// Additional generate info //////////////////

    /// @notice (itemAdr) => Bitmask of ConsumableActionBits
    mapping(address => uint) _consumableActionMask;


    /// --------------------------------- SIP-003: Item fragility
    /// @notice itemAdr + id => item fragility counter that displays the chance of an unsuccessful repair
    /// @dev [0...100_000], decimals 3
    mapping(bytes32 packedItem => uint fragility) itemFragility;

    /// @notice Universal mapping to store various addresses and numbers (params of the contract)
    mapping (GlobalParam param => uint value) globalParam;

    /// @notice Item address => packedMetadata
    /// {packedMetaData} is encoded using abi.encode/abi.decode
    /// Read first byte, detect meta data type by the byte value, apply proper decoder from PackingLib
    mapping(address item => bytes packedMetaData) packedItemMetaData;

    /// --------------------------------- SCR-1263: Reverse-augmentation
    /// @notice Item attributes values before first augmentation.
    /// @dev SCR-1263: The values are required in augmentation if protective item is used and the augmentation is failed.
    mapping(bytes32 packedItem => ResetAugmentationData) _resetAugmentation;
  }

  struct RegisterItemParams {
    ItemMeta itemMeta;
    address augmentToken;
    uint augmentAmount;
    ItemGenerateInfo commonAttributes;

    IGOC.AttributeGenerateInfo consumableAttributes;
    IStatController.ChangeableStats consumableStats;

    ItemGenerateInfo casterAttributes;
    ItemGenerateInfo targetAttributes;

    AttackInfo genAttackInfo;
    /// @notice Bit mask of ConsumableActionBits
    uint consumableActionMask;
  }

  /// @notice Possible actions that can be triggered by using the consumable item
  enum ConsumableActionBits {
    CLEAR_TEMPORARY_ATTRIBUTES_0
    // other items are used instead this mask
  }

  struct ItemGenerateInfo {
    /// @notice Attribute ids
    uint8[] ids;
    /// @notice Min value of the attribute, != 0
    int32[] mins;
    /// @notice Max value of the attribute, != 0
    int32[] maxs;
    /// @notice Chance of the selection [0..MAX_CHANCES]
    uint32[] chances;
  }

  struct ItemMeta {
    uint8 itemMetaType;
    // Level in range 1-99. Reducing durability in low level dungeons. lvl/5+1 = biome
    uint8 itemLevel;
    IItemController.ItemType itemType;
    uint16 baseDurability;
    uint8 defaultRarity;
    uint32 manaCost;

    // it doesn't include positions with 100% chance
    uint8 minRandomAttributes;
    uint8 maxRandomAttributes;

    IStatController.CoreAttributes requirements;
  }

  // Deprecated. Todo - remove
  enum FeeType {
    UNKNOWN,
    REPAIR,
    AUGMENT,
    STORY,

    END_SLOT
  }

  enum ItemRarity {
    UNKNOWN, // 0
    NORMAL, // 1
    MAGIC, // 2
    RARE, // 3
    SET, // 4
    UNIQUE, // 5

    END_SLOT
  }

  enum ItemType {
    NO_SLOT, // 0
    HEAD, // 1
    BODY, // 2
    GLOVES, // 3
    BELT, // 4
    AMULET, // 5
    RING, // 6
    OFF_HAND, // 7
    BOOTS, // 8
    ONE_HAND, // 9
    TWO_HAND, // 10
    SKILL, // 11
    OTHER, // 12

    END_SLOT
  }

  enum ItemMetaType {
    UNKNOWN, // 0
    COMMON, // 1
    ATTACK, // 2
    BUFF, // 3
    CONSUMABLE, // 4

    END_SLOT
  }

  enum AttackType {
    UNKNOWN, // 0
    FIRE, // 1
    COLD, // 2
    LIGHTNING, // 3
    CHAOS, // 4

    END_SLOT
  }

  struct AttackInfo {
    AttackType aType;
    int32 min;
    int32 max;
    // if not zero - activate attribute factor for the attribute
    IStatController.CoreAttributes attributeFactors;
  }

  struct ItemInfo {
    ItemRarity rarity;
    uint8 augmentationLevel;
    uint16 durability;
  }

  /// @dev The struct is used in events, so it's moved here from the lib
  struct MintInfo {
    IItemController.ItemMeta meta;
    uint8[] attributesIds;
    int32[] attributesValues;
    IItemController.ItemRarity itemRarity;

    IItemController.AttackInfo attackInfo;

    uint8[] casterIds;
    int32[] casterValues;
    uint8[] targetIds;
    int32[] targetValues;
  }

  /// @dev The struct is used in events, so it's moved here from the lib
  struct AugmentInfo {
    uint8[] attributesIds;
    int32[] attributesValues;
    IItemController.AttackInfo attackInfo;
    uint8[] casterIds;
    int32[] casterValues;
    uint8[] targetIds;
    int32[] targetValues;
  }

  ///region ------------------------ Item type "Other"
  /// @notice Possible kinds of "Other" items
  /// Each "Other" item has each own structure for metadata, see OtherItemXXX
  enum OtherSubtypeKind {
    UNKNOWN_0,
    /// @notice Item to reduce fragility, see SCB-1014. Metadata is {OtherItemReduceFragility}
    REDUCE_FRAGILITY_1,

    /// @notice This item allows asking guild reinforcement to the guild member
    USE_GUILD_REINFORCEMENT_2,

    /// @notice Exit from dungeon (shelter of level 3 is required)
    EXIT_FROM_DUNGEON_3,

    /// @notice OTHER_5 Rest in the shelter: restore of hp & mp, clear temporally attributes, clear used consumables (shelter of level 3 is required)
    /// @dev It's OTHER_5 in deploy script, but internally it has subtype 4, see gen_others.ts
    REST_IN_SHELTER_4,

    /// @notice OTHER_4 Stub item that has no logic in contracts, but it has correct (not empty) packedMetaData
    /// @dev It's OTHER_4 in deploy script, but internally it has subtype 5, see gen_others.ts
    EMPTY_NO_LOGIC_5,

    END_SLOT
  }
  struct OtherItemReduceFragility {
    /// @notice "Other" item kind. It MUST BE first field in the struct.
    uint8 kind;

    /// @notice Value on which the fragility will be reduced.
    /// @dev [0...100%], decimals 3, so the value is in the range [0...10_000]
    uint248 value;
  }
  ///endregion ------------------------ Item type "Other"

  struct AugmentOptParams {
    /// @notice Optional protective item
    /// @dev SCR-1263: If the protective item specified
    /// than failed augmentation doesn't destroy main item but reduces its augmentation level to the zero instead.
    /// Protective item is configured in ItemControllerHelper.
    address protectiveItem;
    uint protectiveItemId;
  }

  struct ResetAugmentationData {
    /// @notice Moment of the first augmentation if any
    uint tsFirstAugmentation;

    /// @notice Values of the item attributes before the first augmentation
    /// @dev Use PackingLib.toInt32ArrayWithIds to decode attribute ids and values
    bytes32[] itemAttributes;

    /// @notice Values of the caster attributes before the first augmentation
    /// @dev Use PackingLib.toInt32ArrayWithIds to decode attribute ids and values
    bytes32[] itemCasterAttributes;

    /// @notice Values of the target attributes before the first augmentation
    /// @dev Use PackingLib.toInt32ArrayWithIds to decode attribute ids and values
    bytes32[] itemTargetAttributes;

    /// @notice packed AttackInfo: attackType8 + min32 + max32 + factors(packed core 128)
    bytes32 itemAttackInfo;
  }

  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  ////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  function itemMeta(address item) external view returns (ItemMeta memory meta);

  function augmentInfo(address item) external view returns (address token, uint amount);

  function genAttributeInfo(address item) external view returns (ItemGenerateInfo memory info);

  function genCasterAttributeInfo(address item) external view returns (ItemGenerateInfo memory info);

  function genTargetAttributeInfo(address item) external view returns (ItemGenerateInfo memory info);

  function genAttackInfo(address item) external view returns (AttackInfo memory info);

  function itemInfo(address item, uint itemId) external view returns (ItemInfo memory info);

  function equippedOn(address item, uint itemId) external view returns (address hero, uint heroId);

  function itemAttributes(address item, uint itemId) external view returns (int32[] memory values, uint8[] memory ids);

  function consumableAttributes(address item) external view returns (int32[] memory values, uint8[] memory ids);

  function consumableStats(address item) external view returns (IStatController.ChangeableStats memory stats);

  function casterAttributes(address item, uint itemId) external view returns (int32[] memory values, uint8[] memory ids);

  function targetAttributes(address item, uint itemId) external view returns (int32[] memory values, uint8[] memory ids);

  function itemAttackInfo(address item, uint itemId) external view returns (AttackInfo memory info);

  function score(address item, uint tokenId) external view returns (uint);

  function isAllowedToTransfer(address item, uint tokenId) external view returns (bool);

  // ---

  function mint(address item, address recipient, uint32 magicFind) external returns (uint itemId);

  function reduceDurability(address hero, uint heroId, uint8 biome, bool reduceDurabilityAllSkills) external;

  function destroy(address item, uint tokenId) external;

  function takeOffDirectly(
    address item,
    uint itemId,
    address hero,
    uint heroId,
    uint8 itemSlot,
    address destination,
    bool broken
  ) external;

  /// @notice SIP-003: item fragility counter that displays the chance of an unsuccessful repair.
  /// @dev [0...100%], decimals 3, so the value is in the range [0...10_000]
  function itemFragility(address item, uint itemId) external view returns (uint);

  /// @notice SIP-003: The quest mechanic that previously burned the item will increase its fragility by 1%
  function incBrokenItemFragility(address item, uint itemId) external;

  function equip(
    address hero,
    uint heroId,
    address[] calldata items,
    uint[] calldata itemIds,
    uint8[] calldata itemSlots
  ) external;

  function itemControllerHelper() external view returns (address);
}
