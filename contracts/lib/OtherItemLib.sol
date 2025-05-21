// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;
import "../interfaces/IAppErrors.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IItemController.sol";
import "./ItemLib.sol";
import "./PackingLib.sol";

/// @notice Implement all variants of other-items
library OtherItemLib {
  //region ------------------------ Data types
  struct UseOtherItemLocal {
    address hero;
    address helper;

    uint heroId;
    uint helperId;
    ItemLib.ItemWithId item;
  }
  //endregion ------------------------ Data types

  //region ------------------------ Restrictions
  function onlyNotEquippedItem(IItemController.MainState storage s, address item, uint itemId) internal view {
    if (s.equippedOn[PackingLib.packNftId(item, itemId)] != bytes32(0)) revert IAppErrors.ItemEquipped(item, itemId);
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Main logic
  /// @notice Apply given other item
  /// @param data Data required by other item, encoded by abi.encode
  /// Format of the data depends on the other-item-sub-kind
  /// REDUCE_FRAGILITY_1: (item, itemId)
  ///     item - the item which fragility should be reduced
  /// USE_GUILD_REINFORCEMENT_2: (hero, heroId, helper, helperId)
  ///     hero - the hero that asks the guild reinforcement
  ///     helper - the hero staked in guild reinforcement which help is desired
  /// EXIT_FROM_DUNGEON_3: (hero, heroId)
  ///     hero - the hero that is going to exit from the dungeon
  /// REST_IN_SHELTER_4: (hero, heroId)
  ///     hero - the hero that is going to have a rest in the shelter of the guild to which the hero's owner belongs
  /// @param expectedKind Not 0 means that we expects that the {otherItem} should have such subtype kind. Can be 0.
  function useOtherItem(
    IItemController.MainState storage s,
    IController controller_,
    address msgSender,
    ItemLib.ItemWithId memory otherItem,
    bytes memory data,
    IItemController.OtherSubtypeKind expectedKind
  ) external returns (bool inSandbox) {
    ControllerContextLib.ControllerContext memory cc = ControllerContextLib.init(controller_);
    // get kind of the other-item
    {
      IItemController.ItemMeta memory meta = ItemLib.unpackedItemMeta(s.itemMeta[otherItem.item]);
      if (meta.itemType != IItemController.ItemType.OTHER) revert IAppErrors.NotOther();
    }

    bytes memory packedMetaData = s.packedItemMetaData[otherItem.item];
    IItemController.OtherSubtypeKind kind = PackingLib.getOtherItemTypeKind(packedMetaData);

    // ensure that the other item has expected kind
    if (expectedKind != IItemController.OtherSubtypeKind.UNKNOWN_0) {
      if (kind != expectedKind) revert IAppErrors.UnexpectedOtherItem(otherItem.item);
    }

    UseOtherItemLocal memory v;

    // make action assigned to the other-item
    if (kind == IItemController.OtherSubtypeKind.REDUCE_FRAGILITY_1) {
      (v.item.item, v.item.itemId) = abi.decode(data, (address, uint));
      inSandbox = ItemLib._checkOwnerItems(cc, v.item, otherItem, msgSender, false)[1];
      _repairFragility(s, v.item.item, v.item.itemId, otherItem.item, otherItem.itemId, packedMetaData);
    } else if (kind == IItemController.OtherSubtypeKind.USE_GUILD_REINFORCEMENT_2) {
      (v.hero, v.heroId, v.helper, v.helperId) = abi.decode(data, (address, uint, address, uint));
      inSandbox = ItemLib.onlyItemOwner(cc, otherItem, v.hero, v.heroId, msgSender, ItemLib._getSandboxMode(cc, v.hero, v.heroId), [true, false]);
      _askGuildReinforcement(cc, otherItem.item, otherItem.itemId, v.hero, v.heroId, v.helper, v.helperId);
    } else if (kind == IItemController.OtherSubtypeKind.EXIT_FROM_DUNGEON_3) {
      (v.hero, v.heroId) = abi.decode(data, (address, uint));
      inSandbox = ItemLib.onlyItemOwner(cc, otherItem, v.hero, v.heroId, msgSender, ItemLib._getSandboxMode(cc, v.hero, v.heroId), [true, false]);
      _actionExitFromDungeon(cc, msgSender, v.hero, v.heroId);
    } else if (kind == IItemController.OtherSubtypeKind.REST_IN_SHELTER_4) {
      (v.hero, v.heroId) = abi.decode(data, (address, uint));
      inSandbox = ItemLib.onlyItemOwner(cc, otherItem, v.hero, v.heroId, msgSender, ItemLib._getSandboxMode(cc, v.hero, v.heroId), [true, false]);
      _actionRestInShelter(cc, msgSender, v.hero, v.heroId);
    } else {
      revert IAppErrors.UnexpectedOtherItem(otherItem.item);
    }

    return inSandbox;
  }
  //endregion ------------------------ Main logic

  //region ------------------------ Other items logic

  /// @notice Call guild reinforcement
  /// @param item An other-item with subtype "USE_GUILD_REINFORCEMENT_2"
  /// @param heroToken Hero which asks helper
  /// @param helper The hero staked in the guild reinforcement which help is being asked
  function _askGuildReinforcement(
    ControllerContextLib.ControllerContext memory cc,
    address item,
    uint itemId,
    address heroToken,
    uint heroTokenId,
    address helper,
    uint helperId
  ) internal {
    ControllerContextLib.heroController(cc).askGuildReinforcement(heroToken, heroTokenId, helper, helperId);
    emit IApplicationEvents.OtherItemGuildReinforcement(item, itemId, heroToken, heroTokenId, helper, helperId);
  }

  /// @notice Reduce fragility of the {item} on the value taken from the metadata of the {consumedItem}.
  /// Destroy the consumed item.
  /// New fragility = initial fragility - value from metadata.
  /// @param consumedItem Item of type "Other" subtype "REDUCE_FRAGILITY_1"
  function _repairFragility(
    IItemController.MainState storage s,
    address item,
    uint itemId,
    address consumedItem,
    uint consumedItemId,
    bytes memory packedMetaData
  ) internal {
    if (item == consumedItem) revert IAppErrors.OtherTypeItemNotRepairable();
    onlyNotEquippedItem(s, item, itemId);
    // assume here that item of "Other" type cannot be equipped, so no need to call onlyNotEquippedItem(consumedItemId)

    uint delta = PackingLib.unpackOtherItemReduceFragility(packedMetaData);

    bytes32 packedItem = PackingLib.packNftId(item, itemId);
    uint fragility = s.itemFragility[packedItem];
    if (fragility == 0) revert IAppErrors.ZeroFragility();

    s.itemFragility[packedItem] = fragility > delta
      ? fragility - delta
      : 0;

    emit IApplicationEvents.FragilityReduced(item, itemId, consumedItem, consumedItemId, fragility);
  }

  /// @notice Exit from the dungeon: same to the death without reducing life chance
  function _actionExitFromDungeon(ControllerContextLib.ControllerContext memory cc, address msgSender, address heroToken, uint heroTokenId) internal {
    ItemLib._onlyMemberOfGuildWithShelterMaxLevel(cc, msgSender);

    // exit from the dungeon ~ "soft kill"
    ControllerContextLib.dungeonFactory(cc).exitForcibly(heroToken, heroTokenId, msgSender);
    emit IApplicationEvents.ExitFromDungeon(heroToken, heroTokenId);
  }

  /// @notice Rest in the shelter of 3d level: restore of hp & mp, clear temporally attributes, clear used consumables
  function _actionRestInShelter(
    ControllerContextLib.ControllerContext memory cc,
    address msgSender,
    address heroToken,
    uint heroTokenId
  ) internal {
    ItemLib._onlyMemberOfGuildWithShelterMaxLevel(cc, msgSender);
    IStatController statController = ControllerContextLib.statController(cc);

    // restore life and mana to default values from the total attributes
    statController.restoreLifeAndMana(heroToken, heroTokenId, statController.heroAttributes(heroToken, heroTokenId));

    statController.clearTemporallyAttributes(heroToken, heroTokenId);
    statController.clearUsedConsumables(heroToken, heroTokenId);

    emit IApplicationEvents.RestInShelter(msgSender, heroToken, heroTokenId);
  }
  //endregion ------------------------ Other items logic
}