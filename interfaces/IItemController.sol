// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "./IStatController.sol";
import "./IGOC.sol";
import "../openzeppelin/EnumerableSet.sol";

interface IItemController {

  /// @custom:storage-location erc7201:item.controlbler.main
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

  function mint(address item, address recipient) external returns (uint itemId);

  function reduceDurability(address hero, uint heroId, uint8 biome) external;

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
}
