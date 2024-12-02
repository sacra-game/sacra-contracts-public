// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;
import "../interfaces/IAppErrors.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IItemController.sol";
import "./ItemLib.sol";
import "./PackingLib.sol";

/// @notice Implement all variants of other-items
library OtherItemLib {
  //region ------------------------ Restrictions
  function onlyNotEquippedItem(IItemController.MainState storage s, address item, uint itemId) internal view {
    if (s.equippedOn[PackingLib.packNftId(item, itemId)] != bytes32(0)) revert IAppErrors.ItemEquipped(item, itemId);
  }

  function onlyOwner(address token, uint tokenId, address sender) internal view {
    if (IERC721(token).ownerOf(tokenId) != sender) revert IAppErrors.ErrorNotOwner(token, tokenId);
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
  /// @param expectedKind Not 0 means that we expects that the {otherItem} should have such subtype kind. Can be 0.
  function useOtherItem(
    IItemController.MainState storage s,
    IController controller,
    address msgSender,
    address otherItem,
    uint otherItemId,
    bytes memory data,
    IItemController.OtherSubtypeKind expectedKind
  ) external {
    // get kind of the other-item
    IItemController.ItemMeta memory meta = ItemLib.unpackedItemMeta(s.itemMeta[otherItem]);
    if (meta.itemType != IItemController.ItemType.OTHER) revert IAppErrors.NotOther();
    bytes memory packedMetaData = s.packedItemMetaData[otherItem];
    IItemController.OtherSubtypeKind kind = PackingLib.getOtherItemTypeKind(packedMetaData);

    // ensure that the other item has expected kind
    if (expectedKind != IItemController.OtherSubtypeKind.UNKNOWN_0) {
      if (kind != expectedKind) revert IAppErrors.UnexpectedOtherItem(otherItem);
    }

    // make action assigned to the other-item
    if (kind == IItemController.OtherSubtypeKind.REDUCE_FRAGILITY_1) {
      (address item, uint itemId) = abi.decode(data, (address, uint));
      _repairFragility(s, msgSender, item, itemId, otherItem, otherItemId, packedMetaData);
    } else if (kind == IItemController.OtherSubtypeKind.USE_GUILD_REINFORCEMENT_2) {
      (address heroToken, uint heroTokenId, address helper, uint helperId) = abi.decode(data, (address, uint, address, uint));
      _askGuildReinforcement(controller, msgSender, otherItem, otherItemId, heroToken, heroTokenId, helper, helperId);
    } else {
      revert IAppErrors.UnexpectedOtherItem(otherItem);
    }
  }
  //endregion ------------------------ Main logic

  //region ------------------------ Other items logic

  /// @notice Call guild reinforcement
  /// @param item An other-item with subtype "USE_GUILD_REINFORCEMENT_2"
  /// @param msgSender Owner of the {heroTokenId}
  /// @param heroToken Hero which asks helper
  /// @param helper The hero staked in the guild reinforcement which help is being asked
  function _askGuildReinforcement(
    IController controller,
    address msgSender,
    address item,
    uint itemId,
    address heroToken,
    uint heroTokenId,
    address helper,
    uint helperId
  ) internal {
    onlyOwner(heroToken, heroTokenId, msgSender);
    IHeroController hc = IHeroController(controller.heroController());
    hc.askGuildReinforcement(heroToken, heroTokenId, helper, helperId);

    emit IApplicationEvents.OtherItemGuildReinforcement(item, itemId, heroToken, heroTokenId, helper, helperId);
  }

  /// @notice Reduce fragility of the {item} on the value taken from the metadata of the {consumedItem}.
  /// Destroy the consumed item.
  /// New fragility = initial fragility - value from metadata.
  /// @param consumedItem Item of type "Other" subtype "REDUCE_FRAGILITY_1"
  function _repairFragility(
    IItemController.MainState storage s,
    address msgSender,
    address item,
    uint itemId,
    address consumedItem,
    uint consumedItemId,
    bytes memory packedMetaData
  ) internal {
    onlyOwner(item, itemId, msgSender);

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

  //endregion ------------------------ Other items logic
}