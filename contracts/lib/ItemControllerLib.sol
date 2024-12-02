// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IController.sol";
import "../interfaces/IStatController.sol";
import "./ItemStatsLib.sol";

/// @dev This library allows to avoid dependencies between other ItemController-related libs
library ItemControllerLib {
  using EnumerableSet for EnumerableSet.AddressSet;
  using CalcLib for int32;
  using PackingLib for address;
  using PackingLib for bytes32;
  using PackingLib for bytes32[];
  using PackingLib for uint32[];
  using PackingLib for int32[];

  //region ------------------------ Restrictions
  function onlyDeployer(IController c, address sender) internal view {
    if (!c.isDeployer(sender)) revert IAppErrors.ErrorNotDeployer(sender);
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Actions
  /// @notice Use consumable item to temporally increase bonus attributes and destroy the item
  /// @dev This is internal function, it's embedded to ItemController contract
  /// It calls two external functions - ItemStatsLib.use and ItemLib.applyActionMasks
  /// As result, ItemController depends on two libraries, but both libraries don't depend on each other.
  function use(
    bool isEoa,
    IController controller,
    address msgSender,
    address item,
    uint itemId,
    address heroToken,
    uint heroTokenId
  ) internal {
    IStatController statController = IStatController(controller.statController());
    uint actionMask = ItemStatsLib.use(isEoa, controller, statController, msgSender, item, itemId, heroToken, heroTokenId);
    if (actionMask != 0) {
      ItemLib.applyActionMasks(actionMask, statController, controller, msgSender, heroToken, heroTokenId);
    }
  }

  /// @notice Reduce fragility of the {item} on the value taken from the metadata of the {consumedItem}.
  /// Destroy the consumed item.
  /// New fragility = initial fragility - value from metadata.
  /// @param consumedItem Item of type "Other" subtype "REDUCE_FRAGILITY_1"
  function repairFragility(
    bool isEoa,
    IController controller,
    address msgSender,
    address item,
    uint itemId,
    address consumedItem,
    uint consumedItemId
  ) internal {
    useOtherItem(isEoa, controller, msgSender, consumedItem, consumedItemId, abi.encode(item, itemId), IItemController.OtherSubtypeKind.REDUCE_FRAGILITY_1);
  }

  /// @notice Apply given other item
  /// @param data Data required by other item, encoded by abi.encode
  /// Format of the data depends on the other-item-subkind
  /// @param expectedKind Not 0 means that we expects that the {otherItem} should have such subtype kind. Can be 0.
  function useOtherItem(
    bool isEoa,
    IController controller,
    address msgSender,
    address item,
    uint itemId,
    bytes memory data,
    IItemController.OtherSubtypeKind expectedKind
  ) internal {
    ItemStatsLib._checkPauseEoaOwner(isEoa, controller, msgSender, item, itemId);
    OtherItemLib.useOtherItem(ItemStatsLib._S(), controller, msgSender, item, itemId, data, expectedKind);
    ItemStatsLib._destroy(item, itemId);
  }
  //endregion ------------------------ Actions

  //region ------------------------ Deployer actions
  function registerItem(
    IItemController.MainState storage s,  
    IController controller,
    address msgSender,
    address item,
    IItemController.RegisterItemParams calldata info
  ) internal {
    onlyDeployer(controller, msgSender);

    if (info.itemMeta.itemMetaType == 0) revert IAppErrors.ZeroItemMetaType();
    if (info.itemMeta.itemType == IItemController.ItemType.OTHER) revert IAppErrors.WrongWayToRegisterItem();
    _registerItemMeta(s, info.itemMeta, item);

    s.augmentInfo[item] = PackingLib.packAddressWithAmount(info.augmentToken, info.augmentAmount);

    _setAttributesWithCheck(item, info.commonAttributes, s.generateInfoAttributes);

    if (info.itemMeta.itemMetaType == uint8(IItemController.ItemMetaType.CONSUMABLE)) {
      s._itemConsumableAttributes[item] = info.consumableAttributes.values.toBytes32ArrayWithIds(info.consumableAttributes.ids);

      s.itemConsumableStats[item] = StatLib.packChangeableStats(info.consumableStats);
    }

    if (info.itemMeta.itemMetaType == uint8(IItemController.ItemMetaType.BUFF)) {
      _setAttributesWithCheck(item, info.casterAttributes, s.generateInfoCasterAttributes);

      _setAttributesWithCheck(item, info.targetAttributes, s.generateInfoTargetAttributes);
    }

    if (info.itemMeta.itemMetaType == uint8(IItemController.ItemMetaType.ATTACK)) {
      s.generateInfoAttack[item] = ItemLib.packItemAttackInfo(info.genAttackInfo);

      // need to set default attack info for zero id, it will be used in monsters attacks
      s._itemAttackInfo[item.packNftId(0)] = ItemLib.packItemAttackInfo(info.genAttackInfo);
    }

    s._consumableActionMask[item] = info.consumableActionMask;

    emit IApplicationEvents.ItemRegistered(item, info);
  }

  function registerOtherItem(
    IItemController.MainState storage s, 
    IController controller,
    address msgSender,
    address item,
    IItemController.ItemMeta memory meta_,
    bytes memory packedItemMetaData_
  ) internal {
    onlyDeployer(controller, msgSender);

    if (meta_.itemType != IItemController.ItemType.OTHER) revert IAppErrors.WrongWayToRegisterItem();
    if (meta_.itemMetaType != 0) revert IAppErrors.NotZeroOtherItemMetaType();
    _registerItemMeta(s, meta_, item);

    // Let's ensure that packed meta data has known kind at least.
    // Following code will revert if extracted kind won't fit to OtherSubtypeKind.
    PackingLib.getOtherItemTypeKind(packedItemMetaData_);

    s.packedItemMetaData[item] = packedItemMetaData_;

    emit IApplicationEvents.OtherItemRegistered(item, meta_, packedItemMetaData_);
  }

  function _registerItemMeta(IItemController.MainState storage s, IItemController.ItemMeta memory meta, address item) internal {
    if (meta.itemLevel == 0) revert IAppErrors.ZeroLevel();

    if (!s.items.add(item)) {
      IItemController.ItemMeta memory existMeta = ItemLib.unpackedItemMeta(s.itemMeta[item]);
      // we should not change types for existed items
      if (existMeta.itemType != meta.itemType) revert IAppErrors.ItemTypeChanged();
      if (existMeta.itemMetaType != meta.itemMetaType) revert IAppErrors.ItemMetaTypeChanged();
    }

    s.itemMeta[item] = ItemLib.packItemMeta(meta);
  }

  /// @notice  Ensure: min != 0, max != 0 and both min and min should have same sign
  /// Value of attribute cannot be equal to 0 because toBytes32ArrayWithIds cannot store zero values.
  function _setAttributesWithCheck(
    address item,
    IItemController.ItemGenerateInfo memory data,
    mapping(address => bytes32[]) storage dest
  ) internal {
    for (uint i; i < data.ids.length; ++i) {
      if (
        data.mins[i] == 0
        || data.maxs[i] == 0
        || data.mins[i] > data.maxs[i]
        || (data.mins[i] < 0 && data.maxs[i] > 0)
      ) revert IAppErrors.IncorrectMinMaxAttributeRange(data.mins[i], data.maxs[i]);
    }

    dest[item] = ItemLib.packItemGenerateInfo(data);
  }

  function removeItem(IItemController.MainState storage s, IController controller, address msgSender, address item) internal {
    onlyDeployer(controller, msgSender);

    IItemController.ItemMeta memory meta = ItemLib.unpackedItemMeta(s.itemMeta[item]);

    if (! s.items.contains(item)) {
      // don't allow to remove not-exist items to avoid registration of broken item-address in the events below
      revert IAppErrors.NotExist();
    }

    s.items.remove(item);
    delete s.itemMeta[item];

    if (meta.itemType == IItemController.ItemType.OTHER) {
      delete s.packedItemMetaData[item];

      emit IApplicationEvents.OtherItemRemoved(item);
    } else {
      delete s.augmentInfo[item];
      delete s.generateInfoAttributes[item];
      delete s._itemConsumableAttributes[item];
      delete s.itemConsumableStats[item];
      delete s.generateInfoCasterAttributes[item];
      delete s.generateInfoTargetAttributes[item];
      delete s.generateInfoAttack[item];
      delete s._itemAttackInfo[item.packNftId(0)];
      delete s._consumableActionMask[item];

      emit IApplicationEvents.ItemRemoved(item);
    }
  }
  //endregion ------------------------ Deployer actions  
}