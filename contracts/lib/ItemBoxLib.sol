// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IERC721.sol";
import "../interfaces/IItem.sol";
import "../interfaces/IItemBoxController.sol";
import "../lib/PackingLib.sol";
import "../openzeppelin/EnumerableMap.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IApplicationEvents.sol";

library ItemBoxLib {
  using EnumerableMap for EnumerableMap.UintToUintMap;
  using EnumerableSet for EnumerableSet.AddressSet;

  //region ------------------------ Constants
  /// @dev keccak256(abi.encode(uint256(keccak256("ItemBox.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant ITEM_BOX_CONTROLLER_STORAGE_LOCATION = 0xf371ac52645de7a0c0ec059ab8ab924072822dd11454646ed103127e27edb600; // ItemBox.controller.main

  /// @notice Each item is available to grab only limited time interval since the moment of the minting
  uint internal constant ACTIVE_PERIOD_SINCE_MINTING_SEC = 1 days;
  //endregion ------------------------ Constants

  //region ------------------------ Data types
  struct WithdrawLocal {
    uint len;
    uint tsLimit;
    bool exist;
    uint packedItemBoxItemInfo;
  }

  //endregion ------------------------ Data types

  //region ------------------------ Storage

  function _S() internal pure returns (IItemBoxController.MainState storage s) {
    assembly {
      s.slot := ITEM_BOX_CONTROLLER_STORAGE_LOCATION
    }
    return s;
  }
  //endregion ------------------------ Storage

  //region ------------------------ Restrictions
  function _onlyDungeonFactory(IController controller) internal view {
    if (controller.dungeonFactory() != msg.sender) revert IAppErrors.ErrorNotDungeonFactory(msg.sender);
  }

  function _onlyItemController(IController controller, address msgSender_) internal view {
    if (controller.itemController() != msgSender_) revert IAppErrors.ErrorNotItemController(msgSender_);
  }

  function _onlyItemControllerOrDungeonFactory(IController controller, address msgSender_) internal view {
    if (
      controller.itemController() != msgSender_
      && controller.dungeonFactory() != msgSender_
    ) revert IAppErrors.ErrorNotAllowedSender();
  }

  function _onlyOwnerNotPaused(IController controller, address token, uint tokenId, address sender) internal view {
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
    if (IERC721(token).ownerOf(tokenId) != sender) revert IAppErrors.ErrorNotOwner(token, tokenId);
  }

  function _onlyNotEquipped(IItemController itemController, address item, uint itemId) internal view {
    (address hero,) = itemController.equippedOn(item, itemId);
    if (hero != address(0)) revert IAppErrors.ItemEquipped(item, itemId);
  }

  function _onlySandboxMode(IController controller, address hero, uint heroId) internal view {
    if (IHeroController(controller.heroController()).sandboxMode(hero, heroId) != uint8(IHeroController.SandboxMode.SANDBOX_MODE_1)) revert IAppErrors.SandboxModeRequired();
  }

  function _onlyHeroController(IController controller) internal view {
    if (controller.heroController() != msg.sender) revert IAppErrors.ErrorNotHeroController(msg.sender);
  }

  function _onlyActiveInside(address hero, uint heroId, address item, uint itemId) internal view {
    IItemBoxController.ItemState state = itemState(hero, heroId, item, itemId);
    if (state == IItemBoxController.ItemState.NOT_AVAILABLE_1) revert IAppErrors.SandboxItemNotActive();
    if (state == IItemBoxController.ItemState.OUTSIDE_3) revert IAppErrors.SandboxItemOutside();

    // the hero is detected by the item before this call, so it's not possible to get NOT_REGISTERED_0 here
    // let's keep this check for some edge cases
    if (state == IItemBoxController.ItemState.NOT_REGISTERED_0) revert IAppErrors.SandboxItemNotRegistered();
  }

  function _onlyActiveInside(uint packedItemBoxItemInfo, uint tsLimit) internal pure {
    IItemBoxController.ItemState state = _getItemState(packedItemBoxItemInfo, tsLimit);
    if (state == IItemBoxController.ItemState.NOT_AVAILABLE_1) revert IAppErrors.SandboxItemNotActive();
    if (state == IItemBoxController.ItemState.OUTSIDE_3) revert IAppErrors.SandboxItemOutside();

    // the hero is detected by the item before this call, so it's not possible to get NOT_REGISTERED_0 here
    // let's keep this check for some edge cases
    if (state == IItemBoxController.ItemState.NOT_REGISTERED_0) revert IAppErrors.SandboxItemNotRegistered();
  }

  function _onlyHeroAllowedToTransfer(IController controller, address hero, uint heroId, address item, uint itemId) internal view returns (address heroItemOwner, uint heroItemOwnerId) {
    (heroItemOwner, heroItemOwnerId) = PackingLib.unpackNftId(_S().heroes[PackingLib.packNftId(item, itemId)]);
    uint sandboxMode = IHeroController(controller.heroController()).sandboxMode(heroItemOwner, heroItemOwnerId);

    if (sandboxMode == uint8(IHeroController.SandboxMode.SANDBOX_MODE_1)) {
      // Both hero must be equal in the sandbox mode
      if (hero != heroItemOwner || heroId != heroItemOwnerId) revert IAppErrors.SandboxDifferentHeroesNotAllowed();
    } else if (sandboxMode == uint8(IHeroController.SandboxMode.UPGRADED_TO_NORMAL_2)) {
      // Ensure that the hero belongs to the same owner as the hero that is owner of the item
      if (IERC721(hero).ownerOf(heroId) != IERC721(heroItemOwner).ownerOf((heroItemOwnerId))) revert IAppErrors.ErrorNotOwner(item, itemId);
    } else {
      revert IAppErrors.SandboxModeRequired();
    }
  }

  function _onlyAliveHero(IController controller, address hero, uint heroId) internal view {
    if (!IStatController(controller.statController()).isHeroAlive(hero, heroId)) revert IAppErrors.ErrorHeroIsDead(hero, heroId);
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ View
  /// @notice Try to find first not-withdrawn and still active item, return 0 if there is no such item
  function firstActiveItemOfHeroByIndex(address hero, uint heroId, address item) internal view returns (uint itemId) {
    IItemBoxController.HeroData storage heroData = ItemBoxLib._S().heroData[PackingLib.packNftId(hero, heroId)];
    uint tsLimit = _getActiveLimitTs(heroData);

    EnumerableMap.UintToUintMap storage states = heroData.states[item];

    uint len = states.length();
    for (uint i = len; i > 0; i--) {
      (uint _itemId, uint packedItemInfo) = states.at(i - 1);
      (bool withdrawn, uint tsMinting) = PackingLib.unpackItemBoxItemInfo(bytes32(packedItemInfo));
      if (tsLimit >= tsMinting + ACTIVE_PERIOD_SINCE_MINTING_SEC) {
        // the item is not active, all following items are not active too because order of the items is never changed
        break;
      }
      if (!withdrawn) {
        itemId = _itemId;
        break;
      }
    }

    return itemId;
  }

  function getHeroRegisteredItems(address hero, uint heroId) internal view returns (address[] memory items) {
    EnumerableSet.AddressSet storage setItems = ItemBoxLib._S().heroData[PackingLib.packNftId(hero, heroId)].items;
    return setItems.values();
  }

  function getActiveItemIds(address hero, uint heroId, address item) internal view returns (
    uint[] memory itemIds,
    bool[] memory toWithdraw,
    uint[] memory timestamps
  ) {
    IItemBoxController.HeroData storage heroData = ItemBoxLib._S().heroData[PackingLib.packNftId(hero, heroId)];
    uint tsLimit = _getActiveLimitTs(heroData);

    EnumerableMap.UintToUintMap storage mapStates = heroData.states[item];
    uint len = mapStates.length();

    itemIds = new uint[](len);
    timestamps = new uint[](len);
    toWithdraw = new bool[](len);

    for (uint i; i < len; ++i) {
      uint packedItemInfo;
      (itemIds[i], packedItemInfo) = mapStates.at(i);

      // get: withdraw, timestamp of the minting
      (toWithdraw[i], timestamps[i]) = PackingLib.unpackItemBoxItemInfo(bytes32(packedItemInfo));

      // the item is active if it's not withdrawn and it was minted not long ago
      toWithdraw[i] = !toWithdraw[i] && tsLimit - ACTIVE_PERIOD_SINCE_MINTING_SEC < timestamps[i];
    }
  }

  function getItemInfo(address hero, uint heroId, address item, uint itemId) internal view returns (
    bool withdrawn,
    uint tsMinted
  ) {
    IItemBoxController.HeroData storage heroData = ItemBoxLib._S().heroData[PackingLib.packNftId(hero, heroId)];
    (bool exist, uint packedItemInfo) = heroData.states[item].tryGet(itemId);
    if (exist) {
      (withdrawn, tsMinted) = PackingLib.unpackItemBoxItemInfo(bytes32(packedItemInfo));
    }
    return (withdrawn, tsMinted);
  }

  function itemState(address hero, uint heroId, address item, uint itemId) internal view returns (
    IItemBoxController.ItemState
  ) {
    bytes32 packedHero = PackingLib.packNftId(hero, heroId);
    IItemBoxController.HeroData storage heroData = ItemBoxLib._S().heroData[packedHero];

    EnumerableMap.UintToUintMap storage mapStates = heroData.states[item];

    (bool exist, uint packedItemBoxItemInfo) = mapStates.tryGet(itemId);
    return exist
      ? _getItemState(packedItemBoxItemInfo, _getActiveLimitTs(heroData))
      : IItemBoxController.ItemState.NOT_REGISTERED_0;
  }

  function itemHero(address item, uint itemId) internal view returns (address hero, uint heroId) {
    (hero, heroId) = PackingLib.unpackNftId(_S().heroes[PackingLib.packNftId(item, itemId)]);
  }

  function upgradedAt(address hero, uint heroId) internal view returns (uint timestamp) {
    return _S().heroData[PackingLib.packNftId(hero, heroId)].tsUpgraded;
  }
  //endregion ------------------------ View

  //region ------------------------ Actions

  /// @notice Dungeon factory registers items minted for the hero in the dungeon.
  /// Assume, that the items are already on balance of the ItemBox
  function registerItems(IController controller, address hero, uint heroId, address[] memory items, uint[] memory itemIds, uint countValidItems) internal {
    _onlyDungeonFactory(controller);
    _onlySandboxMode(controller, hero, heroId);

    uint len = items.length;
    if (len != itemIds.length) revert IAppErrors.LengthsMismatch();
    if (len < countValidItems) revert IAppErrors.OutOfBounds(countValidItems, len);

    bytes32 packedHero = PackingLib.packNftId(hero, heroId);

    IItemBoxController.HeroData storage heroData = ItemBoxLib._S().heroData[packedHero];
    EnumerableSet.AddressSet storage setItems = heroData.items;

    for (uint i; i < countValidItems; ++i) {
      if (!setItems.contains(items[i])) {
        setItems.add(items[i]);
      }

      EnumerableMap.UintToUintMap storage mapStates = heroData.states[items[i]];
      if (mapStates.contains(itemIds[i])) revert IAppErrors.AlreadyRegistered();

      if (IERC721(items[i]).ownerOf(itemIds[i]) != address(this)) revert IAppErrors.ItemNotFound(items[i], itemIds[i]);

      mapStates.set(itemIds[i], uint(PackingLib.packItemBoxItemInfo(false, uint64(block.timestamp))));
      _S().heroes[PackingLib.packNftId(items[i], itemIds[i])] = packedHero;

      emit IApplicationEvents.RegisterSandboxItem(hero, heroId, items[i], itemIds[i], uint64(block.timestamp));
    }
  }

  /// @notice Transfer given items from ItemBox to the hero owner
  function withdrawActiveItems(
    IController controller,
    address msgSender_,
    address hero,
    uint heroId,
    address[] memory items,
    uint[] memory itemIds,
    address receiver
  ) internal {
    WithdrawLocal memory v;

    _onlyAliveHero(controller, hero, heroId);
    _onlyOwnerNotPaused(controller, hero, heroId, msgSender_);

    v.len = items.length;
    if (v.len != itemIds.length) revert IAppErrors.LengthsMismatch();

    if (IHeroController(controller.heroController()).sandboxMode(hero, heroId) != uint8(IHeroController.SandboxMode.UPGRADED_TO_NORMAL_2)) revert IAppErrors.SandboxUpgradeModeRequired();
    IItemController itemController = IItemController(controller.itemController());

    IItemBoxController.HeroData storage heroData = ItemBoxLib._S().heroData[PackingLib.packNftId(hero, heroId)];

    v.tsLimit = _getActiveLimitTs(heroData);
    for (uint i; i < v.len; ++i) {
      EnumerableMap.UintToUintMap storage mapStates = heroData.states[items[i]];

      (v.exist, v.packedItemBoxItemInfo) = mapStates.tryGet(itemIds[i]);
      if (! v.exist) revert IAppErrors.ErrorNotOwner(items[i], itemIds[i]);
      (bool withdrawn, uint64 timestamp) = PackingLib.unpackItemBoxItemInfo(bytes32(v.packedItemBoxItemInfo));
      if (withdrawn) revert IAppErrors.SandboxItemOutside();

      _onlyNotEquipped(itemController, items[i], itemIds[i]);
      _onlyActiveInside(v.packedItemBoxItemInfo, v.tsLimit);

      IERC721(items[i]).transferFrom(address(this), receiver, itemIds[i]);

      mapStates.set(itemIds[i], uint(PackingLib.packItemBoxItemInfo(true, timestamp)));
    }

    emit IApplicationEvents.WithdrawItemsFromSandbox(hero, heroId, items, itemIds);
  }

  function onERC721ReceivedLogic(
    IController controller,
    address operator,
    address /* from */,
    uint256 tokenId,
    bytes memory /* data */
  ) internal {
    _onlyItemControllerOrDungeonFactory(controller, operator);

    bytes32 packedItem = PackingLib.packNftId(msg.sender, tokenId);
    bytes32 packedHero = _S().heroes[packedItem];
    if (packedHero == 0) {
      // new item is registered for the hero, no actions are required
      // DungeonFactory will call {registerItems} next
      emit IApplicationEvents.NewItemSentToSandbox(msg.sender, tokenId);
    } else {
      // previously registered item is returned back to the ItemBox
      IItemBoxController.HeroData storage heroData = ItemBoxLib._S().heroData[packedHero];
      EnumerableMap.UintToUintMap storage mapStates = heroData.states[msg.sender];

      // keep minting timestamp unchanged, update only {withdrawn} value
      (, uint64 timestamp) = PackingLib.unpackItemBoxItemInfo(bytes32(mapStates.get(tokenId)));
      mapStates.set(tokenId, uint(PackingLib.packItemBoxItemInfo(false, timestamp)));

      (address hero, uint heroId) = PackingLib.unpackNftId(packedHero);
      emit IApplicationEvents.ItemReturnedToSandbox(hero, heroId, msg.sender, tokenId);
    }
  }

  /// @notice Register moment of upgrade. All items active at the moment of upgrade will remain active forever
  function registerSandboxUpgrade(IController controller, bytes32 packedHero) internal {
    _onlyHeroController(controller);

    IItemBoxController.HeroData storage heroData = ItemBoxLib._S().heroData[packedHero];
    heroData.tsUpgraded = block.timestamp;

    (address hero, uint heroId) = PackingLib.unpackNftId(packedHero);
    emit IApplicationEvents.RegisterSandboxUpgrade(hero, heroId, block.timestamp);
  }

  /// @notice Transfer the active {item} to the {hero}
  function transferToHero(IController controller, address hero, uint heroId, address item, uint itemId) internal {
    _onlyItemController(controller, msg.sender);

    // -------------- ensure that the item belongs to the hero, active, inside the box
    (address heroItemOwner, uint heroItemOwnerId) = _onlyHeroAllowedToTransfer(controller, hero, heroId, item, itemId);
    _onlyActiveInside(heroItemOwner, heroItemOwnerId, item, itemId);

    // -------------- move the item to the hero
    IItem(item).controlledTransfer(address(this), hero, itemId);

    // -------------- set the item as "withdrawn"
    IItemBoxController.HeroData storage heroData = ItemBoxLib._S().heroData[PackingLib.packNftId(heroItemOwner, heroItemOwnerId)];

    EnumerableMap.UintToUintMap storage mapState = heroData.states[item];
    (, uint64 timestamp) = PackingLib.unpackItemBoxItemInfo(bytes32(mapState.get(itemId)));
    mapState.set(itemId, uint(PackingLib.packItemBoxItemInfo(true, timestamp)));

    emit IApplicationEvents.TransferItemToHeroFromSandbox(hero, heroId, item, itemId);
  }

  function destroyItem(IController controller, address item, uint itemId) internal {
    _onlyItemController(controller, msg.sender);

    // -------------- ensure that the item is registered, active, inside in the box
    bytes32 packedItem = PackingLib.packNftId(item, itemId);
    bytes32 packedHero = _S().heroes[packedItem];
    IItemBoxController.HeroData storage heroData = _S().heroData[packedHero];
    EnumerableMap.UintToUintMap storage mapState = heroData.states[item];

    if (packedHero == 0) revert IAppErrors.ItemNotFound(item, itemId);

    (bool exist, uint packedItemBoxItemInfo) = mapState.tryGet(itemId);
    if (! exist) revert IAppErrors.ErrorNotOwner(item, itemId); // edge case because we detect hero by the item

    uint tsLimit = _getActiveLimitTs(heroData);
    _onlyActiveInside(packedItemBoxItemInfo, tsLimit);

    // -------------- mark the item as "withdrawn"
    (, uint64 timestamp) = PackingLib.unpackItemBoxItemInfo(bytes32(packedItemBoxItemInfo));
    mapState.set(itemId, uint(PackingLib.packItemBoxItemInfo(true, timestamp)));

    // -------------- burn the item
    IItem(item).burn(itemId);

    emit IApplicationEvents.DestroyItemInSandbox(item, itemId);
  }
  //endregion ------------------------ Actions

  //region ------------------------ Internal logic

  function _getItemState(uint packedItemBoxItemInfo, uint tsLimit) internal pure returns (
    IItemBoxController.ItemState
  ) {
    (bool withdrawn, uint64 tsMinting) = PackingLib.unpackItemBoxItemInfo(bytes32(packedItemBoxItemInfo));
    if (withdrawn) {
      return IItemBoxController.ItemState.OUTSIDE_3;
    } else {
      return tsLimit < tsMinting + ACTIVE_PERIOD_SINCE_MINTING_SEC
        ? IItemBoxController.ItemState.INSIDE_2
        : IItemBoxController.ItemState.NOT_AVAILABLE_1;
    }
  }

  function _getActiveLimitTs(IItemBoxController.HeroData storage heroData) internal view returns (uint timestamp) {
    timestamp = heroData.tsUpgraded;
    if (timestamp == 0) {
      timestamp = block.timestamp;
    }
  }
  //endregion ------------------------ Internal logic

}