// SPDX-License-Identifier: BUSL-1.1
/**
            ▒▓▒  ▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓███▓▓▒     ▒▒▒▒▓▓▓▒▓▓▓▓▓▓▓██▓
             ▒██▒▓▓▓▓█▓██████████████████▓  ▒▒▒▓███████████████▒
              ▒██▒▓█████████████████████▒ ▒▓██████████▓███████
               ▒███████████▓▒                   ▒███▓▓██████▓
                 █████████▒                     ▒▓▒▓███████▒
                  ███████▓      ▒▒▒▒▒▓▓█▓▒     ▓█▓████████
                   ▒▒▒▒▒   ▒▒▒▒▓▓▓█████▒      ▓█████████▓
                         ▒▓▓▓▒▓██████▓      ▒▓▓████████▒
                       ▒██▓▓▓███████▒      ▒▒▓███▓████
                        ▒███▓█████▒       ▒▒█████▓██▓
                          ██████▓   ▒▒▒▓██▓██▓█████▒
                           ▒▒▓▓▒   ▒██▓▒▓▓████████
                                  ▓█████▓███████▓
                                 ██▓▓██████████▒
                                ▒█████████████
                                 ███████████▓
      ▒▓▓▓▓▓▓▒▓                  ▒█████████▒                      ▒▓▓
    ▒▓█▒   ▒▒█▒▒                   ▓██████                       ▒▒▓▓▒
   ▒▒█▒       ▓▒                    ▒████                       ▒▓█▓█▓▒
   ▓▒██▓▒                             ██                       ▒▓█▓▓▓██▒
    ▓█▓▓▓▓▓█▓▓▓▒        ▒▒▒         ▒▒▒▓▓▓▓▒▓▒▒▓▒▓▓▓▓▓▓▓▓▒    ▒▓█▒ ▒▓▒▓█▓
     ▒▓█▓▓▓▓▓▓▓▓▓▓▒    ▒▒▒▓▒     ▒▒▒▓▓     ▓▓  ▓▓█▓   ▒▒▓▓   ▒▒█▒   ▒▓▒▓█▓
            ▒▒▓▓▓▒▓▒  ▒▓▓▓▒█▒   ▒▒▒█▒          ▒▒█▓▒▒▒▓▓▓▒   ▓██▓▓▓▓▓▓▓███▓
 ▒            ▒▓▓█▓  ▒▓▓▓▓█▓█▓  ▒█▓▓▒          ▓▓█▓▒▓█▓▒▒   ▓█▓        ▓███▓
▓▓▒         ▒▒▓▓█▓▒▒▓█▒   ▒▓██▓  ▓██▓▒     ▒█▓ ▓▓██   ▒▓▓▓▒▒▓█▓        ▒▓████▒
 ██▓▓▒▒▒▒▓▓███▓▒ ▒▓▓▓▓▒▒ ▒▓▓▓▓▓▓▓▒▒▒▓█▓▓▓▓█▓▓▒▒▓▓▓▓▓▒    ▒▓████▓▒     ▓▓███████▓▓▒
*/
pragma solidity 0.8.23;

import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";
import "../interfaces/IItemController.sol";
import "./../lib/ItemStatsLib.sol";
import "./../lib/ItemControllerLib.sol";
import "./../lib/ScoreLib.sol";
import "./../lib/StatLib.sol";

contract ItemController is Controllable, ERC2771Context, IItemController {
  using EnumerableSet for EnumerableSet.AddressSet;
  using PackingLib for address;

  //region ------------------------ CONSTANTS

  /// @notice Version of the contract
  string public constant VERSION = "1.0.4";
  //endregion ------------------------ CONSTANTS

  //region ------------------------ INITIALIZER

  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ INITIALIZER

  //region ------------------------ VIEWS
  function itemByIndex(uint idx) external view returns (address) {
    return ItemStatsLib.itemByIndex(idx);
  }

  function itemsLength() external view returns (uint) {
    return ItemStatsLib.itemsLength();
  }

  function itemMeta(address item) external view override returns (ItemMeta memory meta) {
    return ItemStatsLib.itemMeta(item);
  }

  function augmentInfo(address item) external view override returns (address token, uint amount) {
    return ItemStatsLib.augmentInfo(item);
  }

  function genAttributeInfo(address item) external view override returns (ItemGenerateInfo memory info) {
    return ItemStatsLib.genAttributeInfo(item);
  }

  function genCasterAttributeInfo(address item) external view override returns (ItemGenerateInfo memory info) {
    return ItemStatsLib.genCasterAttributeInfo(item);
  }

  function genTargetAttributeInfo(address item) external view override returns (ItemGenerateInfo memory info) {
    return ItemStatsLib.genTargetAttributeInfo(item);
  }

  function genAttackInfo(address item) external view override returns (AttackInfo memory info) {
    return ItemStatsLib.genAttackInfo(item);
  }

  function itemInfo(address item, uint itemId) external view override returns (ItemInfo memory info) {
    return ItemStatsLib.itemInfo(item, itemId);
  }

  function equippedOn(address item, uint itemId) external view override returns (address hero, uint heroId) {
    return ItemLib.equippedOn(item, itemId);
  }

  function itemAttributes(address item, uint itemId) external view override returns (int32[] memory values, uint8[] memory ids) {
    return ItemStatsLib.itemAttributes(item, itemId);
  }

  function consumableAttributes(address item) external view override returns (int32[] memory values, uint8[] memory ids) {
    return ItemStatsLib.consumableAttributes(item);
  }

  function consumableStats(address item) external view override returns (IStatController.ChangeableStats memory stats) {
    return ItemStatsLib.consumableStats(item);
  }

  function casterAttributes(address item, uint itemId) external view override returns (int32[] memory values, uint8[] memory ids) {
    return ItemStatsLib.casterAttributes(item, itemId);
  }

  function targetAttributes(address item, uint itemId) external view override returns (int32[] memory values, uint8[] memory ids) {
    return ItemStatsLib.targetAttributes(item, itemId);
  }

  function itemAttackInfo(address item, uint itemId) external view override returns (AttackInfo memory info) {
    return ItemStatsLib.itemAttackInfo(item, itemId);
  }

  function score(address item, uint itemId) external view override returns (uint) {
    return ItemStatsLib.score(item, itemId);
  }

  function isAllowedToTransfer(address item, uint itemId) external view override returns (bool) {
    return ItemStatsLib.isAllowedToTransfer(item, itemId);
  }

  function consumableActionMask(address item) external view returns (uint) {
    return ItemStatsLib.consumableActionMask(item);
  }

  function packedItemMetaData(address item) external view returns (bytes memory) {
    return ItemStatsLib.packedItemMetaData(item);
  }

  function itemControllerHelper() external view returns (address) {
    return ItemStatsLib.itemControllerHelper();
  }

  /// @notice SIP-003: item fragility counter that displays the chance of an unsuccessful repair.
  /// @dev [0...100%], decimals 3, so the value is in the range [0...10_000]
  function itemFragility(address item, uint itemId) external view returns (uint) {
    return ItemStatsLib.itemFragility(item, itemId);
  }

  /// @notice SCR_1263: Timestamp of first augmentation moment.
  /// 0 - if either the item was not yet augmented OR it was augmented before implementation of SCR_1263.
  /// Augmentation cannot use protective item in second case.
  function tsFirstAugmentation(address item, uint itemId) external view returns (uint) {
    return ItemStatsLib.tsFirstAugmentation(item, itemId);
  }
  //endregion ------------------------ VIEWS

  //region ------------------------ GOV ACTIONS

  /// @dev It's possible to reduce size of the contract on 1kb by replacing calldata=>memory (+2k gas)
  function registerItem(address item, RegisterItemParams calldata info) external {
    ItemControllerLib.registerItem(ItemLib._S(), IController(controller()), _msgSender(), item, info);
  }

  function registerOtherItem(address item, IItemController.ItemMeta memory meta_, bytes memory packedItemMetaData_) external {
    ItemControllerLib.registerOtherItem(ItemLib._S(), IController(controller()), _msgSender(), item, meta_, packedItemMetaData_);
  }

  function removeItem(address item) external {
    ItemControllerLib.removeItem(ItemLib._S(), IController(controller()), _msgSender(), item);
  }

  function setItemControllerHelper(address helper) external {
    ItemStatsLib.setItemControllerHelper(IController(controller()), helper);
  }
  //endregion ------------------------ GOV ACTIONS

  //region ------------------------ Controllers actions

  function mint(address item, address recipient, uint32 magicFind) external override returns (uint itemId) {
    return ItemStatsLib.mintNewItem(IController(controller()), msg.sender, item, recipient, magicFind);
  }

  /// @notice Reduce durability of all equipped items except not-used items of SKILL-type
  function reduceDurability(address hero, uint heroId, uint8 biome, bool reduceDurabilityAllSkills) external override {
    return ItemStatsLib.reduceEquippedItemsDurability(_getCC(), hero, heroId, biome, reduceDurabilityAllSkills);
  }

  /// @dev Some stories can destroy items
  function destroy(address item, uint itemId) external override {
    ItemLib.destroy(IController(controller()), _msgSender(), item, itemId);
  }

  /// @dev Some stories can manipulate items
  function takeOffDirectly(
    address item,
    uint itemId,
    address hero,
    uint heroId,
    uint8 itemSlot,
    address destination,
    bool broken
  ) external override {
    ItemStatsLib.takeOffDirectly(_getCC(), item, itemId, hero, heroId, itemSlot, destination, broken);
  }

  /// @notice SIP-003: The quest mechanic that previously burned the item will increase its fragility by 1%
  function incBrokenItemFragility(address item, uint itemId) external {
    ItemStatsLib.incBrokenItemFragility(IController(controller()), item, itemId);
  }
  //endregion ------------------------ Controllers actions

  //region ------------------------ EOA ACTIONS
  // an item must not be equipped

  function equip(
    address hero,
    uint heroId,
    address[] calldata items,
    uint[] calldata itemIds,
    uint8[] calldata itemSlots
  ) external {
    ItemStatsLib.equipMany(_getSenderInfo(), _getCC(), hero, heroId, items, itemIds, itemSlots);
  }

  function takeOff(
    address hero,
    uint heroId,
    address[] calldata items,
    uint[] calldata tokenIds,
    uint8[] calldata itemSlots
  ) external {
    ItemStatsLib.takeOffMany(_getSenderInfo(), _getCC(), hero, heroId, items, tokenIds, itemSlots);
  }

  /// @dev Repair durability of the item with {itemId} by destroying {consumedItemId}
  function repairDurability(address item, uint itemId, uint consumedItemId) external {
    ItemStatsLib.repairDurability(_getSenderInfo(), _getCC(), item, itemId, consumedItemId);
  }

  /// @notice Reduce fragility of the {item} on the value taken from metadata of the {consumedItem}.
  /// Destroy the consumed item.
  /// New fragility = initial fragility - value from metadata.
  /// @dev If you have no space in this contract you can remove this function and use useOtherItem instead
  /// @param item Fragility of this item will be reduced. Initial fragility must be > 0
  /// @param consumedItem Item of type "Other" subtype "REDUCE_FRAGILITY_1"
  function repairFragility(address item, uint itemId, address consumedItem, uint consumedItemId) external {
    return ItemControllerLib.repairFragility(_getSenderInfo(), _getCC(), item, itemId, consumedItem, consumedItemId);
  }

  /// @param item Item to augment
  /// @param consumedItemId Item required to augmentation, it will be destroyed
  /// @param opt Optional parameters
  function augment(address item, uint itemId, uint consumedItemId, IItemController.AugmentOptParams memory opt) external {
    ItemLib.augment(
      _getSenderInfo(),
      controller(),
      item,
      itemId,
      consumedItemId,
      opt,
      IItemControllerHelper(ItemStatsLib.itemControllerHelper())
    );
  }

  /// @notice Use consumable
  function use(address item, uint itemId, address heroToken, uint heroTokenId) external {
    ItemControllerLib.use(
      _getSenderInfo(),
      _getCC(),
      ItemLib.ItemWithId({item: item, itemId: itemId}),
      heroToken,
      heroTokenId
    );
  }

  /// @notice Combine multiple {items} to single item according to the given union-config
  function combineItems(uint configId, address[] memory items, uint[][] memory itemIds) external returns (uint itemId) {
    return ItemStatsLib.combineItems(_getSenderInfo(), _getCC(), configId, items, itemIds);
  }

  /// @notice Apply given other item
  /// @param item Item of "Other" type
  /// @param data Data required by other item, encoded by abi.encode
  /// Format of the data depends on the other-item-subtype:
  /// REDUCE_FRAGILITY_1: (address item, uint itemId)
  ///     item - the item which fragility should be reduced
  /// USE_GUILD_REINFORCEMENT_2: (address hero, uint heroId, address helper, uint helperId)
  ///     hero - the hero that asks the guild reinforcement
  ///     helper - the hero staked in guild reinforcement which help is desired
  /// EXIT_FROM_DUNGEON_3: (address hero, uint heroId)
  ///     hero - the hero that is going to exit from the dungeon
  /// REST_IN_SHELTER_4: (address hero, uint heroId)
  ///     hero - the hero that is going to have a rest in the shelter of the guild to which the hero's owner belongs
  function useOtherItem(address item, uint itemId, bytes memory data) external {
    ItemControllerLib.useOtherItem(_getSenderInfo(), _getCC(), item, itemId, data, IItemController.OtherSubtypeKind.UNKNOWN_0);
  }
  //endregion ------------------------ EOA ACTIONS

  //region ------------------------ Utils
  function _getSenderInfo() internal view returns (ItemLib.SenderInfo memory) {
    return ItemLib.SenderInfo({msgSender: _msgSender(), isEoa: _isNotSmartContract()});
  }

  function _getCC() internal view returns (ControllerContextLib.ControllerContext memory cc) {
    return ControllerContextLib.init(IController(controller()));
  }
  //endregion ------------------------ Utils
}
