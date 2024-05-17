// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";
import "../interfaces/IItemController.sol";
import "./../lib/ItemStatsLib.sol";
import "./../lib/ScoreLib.sol";
import "./../lib/StatLib.sol";

contract ItemController is Controllable, ERC2771Context, IItemController {
  using EnumerableSet for EnumerableSet.AddressSet;
  using PackingLib for address;

  //region ------------------------ CONSTANTS

  /// @notice Version of the contract
  string public constant VERSION = "1.0.1";
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
    return ItemStatsLib.equippedOn(item, itemId);
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
  //endregion ------------------------ VIEWS

  //region ------------------------ GOV ACTIONS

  /// @dev It's possible to reduce size of the contract on 1kb by replacing calldata=>memory (+2k gas)
  function registerItem(address item, RegisterItemParams calldata info) external {
    ItemStatsLib.registerItem(IController(controller()), _msgSender(), item, info);
  }

  function removeItem(address item) external {
    ItemStatsLib.removeItem(IController(controller()), _msgSender(), item);
  }
  //endregion ------------------------ GOV ACTIONS

  //region ------------------------ DUNGEON ACTIONS

  function mint(address item, address recipient) external override returns (uint itemId) {
    return ItemStatsLib.mintNewItem(IController(controller()), msg.sender, item, recipient);
  }

  function reduceDurability(address hero, uint heroId, uint8 biome) external override {
    return ItemStatsLib.reduceEquippedItemsDurability(IController(controller()), _msgSender(), hero, heroId, biome);
  }

  /// @dev Some stories can destroy items
  function destroy(address item, uint itemId) external override {
    ItemStatsLib.destroy(IController(controller()), _msgSender(), item, itemId);
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
    ItemStatsLib.takeOffDirectly(
      IController(controller()),
      item,
      itemId,
      hero,
      heroId,
      itemSlot,
      destination,
      broken
    );
  }
  //endregion ------------------------ DUNGEON ACTIONS

  //region ------------------------ EOA ACTIONS
  // an item must not be equipped

  function equip(
    address heroToken,
    uint heroTokenId,
    address[] calldata items,
    uint[] calldata tokenIds,
    uint8[] calldata itemSlots
  ) external {
    ItemStatsLib.equipMany(
      _isNotSmartContract(),
      IController(controller()),
      _msgSender(),
      heroToken,
      heroTokenId,
      items,
      tokenIds,
      itemSlots
    );
  }

  function takeOff(
    address heroToken,
    uint heroTokenId,
    address[] calldata items,
    uint[] calldata tokenIds,
    uint8[] calldata itemSlots
  ) external {
    ItemStatsLib.takeOffMany(
      _isNotSmartContract(),
      IController(controller()),
      _msgSender(),
      heroToken,
      heroTokenId,
      items,
      tokenIds,
      itemSlots
    );
  }

  /// @dev Repair durability.
  function repairDurability(address item, uint itemId, uint consumedItemId) external {
    ItemStatsLib.repairDurability(
      _isNotSmartContract(),
      IController(controller()),
      _msgSender(),
      item,
      itemId,
      consumedItemId
    );
  }

  function augment(address item, uint itemId, uint consumedItemId) external {
    ItemStatsLib.augment(
      _isNotSmartContract(),
      IController(controller()),
      _msgSender(),
      item,
      itemId,
      consumedItemId
    );
  }

  function use(address item, uint tokenId, address heroToken, uint heroTokenId) external {
    ItemStatsLib.use(
      _isNotSmartContract(),
      IController(controller()),
      _msgSender(),
      item,
      tokenId,
      heroToken,
      heroTokenId
    );
  }
  //endregion ------------------------ EOA ACTIONS

}
