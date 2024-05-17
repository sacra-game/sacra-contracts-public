// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;


import "./PackingLib.sol";
import "./ItemLib.sol";
import "./AppLib.sol";
import "./CalcLib.sol";
import "./ScoreLib.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IItemController.sol";
import "../interfaces/IReinforcementController.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IItem.sol";
import "../interfaces/IDungeonFactory.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IAppErrors.sol";

library ItemStatsLib {
  using EnumerableSet for EnumerableSet.AddressSet;
  using CalcLib for int32;
  using PackingLib for address;
  using PackingLib for bytes32;
  using PackingLib for bytes32[];
  using PackingLib for uint32[];
  using PackingLib for int32[];

  //region ------------------------ CONSTANTS

  uint private constant AUGMENT_CHANCE = 0.7e18;
  /// @dev should be 20%
  uint private constant AUGMENT_FACTOR = 5;
  uint private constant DURABILITY_REDUCTION = 3;
  uint private constant MAX_AUGMENTATION_LEVEL = 10;

  /// @dev keccak256(abi.encode(uint256(keccak256("item.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant MAIN_STORAGE_LOCATION = 0xe78a2879cd91c3f7b62ea14e72546fed47c40919bca4daada532a5fa05ac6700;

  //endregion ------------------------ CONSTANTS

  //region ------------------------ STRUCTS

  struct EquipLocalContext {
    IStatController statController;
    IDungeonFactory dungeonFactory;
    IHeroController hc;
    address payToken;
    address heroToken;
    uint heroTokenId;
//    IItemController.ItemMeta meta;
//    IItemController.ItemInfo itemInfo;
//    bytes32[] attributes;
  }

  struct ReduceDurabilityContext {
    /// @notice values 0 or 1 for SKILL_1, SKILL_2, SKILL_3
    uint8[] skillSlots;
    uint8[] busySlots;
    IStatController statController;
    address itemAdr;
    uint16 durability;
    uint itemId;
  }

  struct TakeOffContext {
    bool broken;
    IController controller;

    address msgSender;
    address heroToken;
    address destination;
    IHeroController heroController;
    IDungeonFactory dungeonFactory;
    IStatController statController;

    uint heroTokenId;
  }
  //endregion ------------------------ STRUCTS

  //region ------------------------ STORAGE
  function _S() internal pure returns (IItemController.MainState storage s) {
    assembly {
      s.slot := MAIN_STORAGE_LOCATION
    }
    return s;
  }
  //endregion ------------------------ STORAGE

  //region ------------------------ RESTRICTIONS

  function onlyDeployer(IController c, address sender) internal view {
    if (!c.isDeployer(sender)) revert IAppErrors.ErrorNotDeployer(sender);
  }

  function onlyOwner(address token, uint tokenId, address sender) internal view {
    if (IERC721(token).ownerOf(tokenId) != sender) revert IAppErrors.ErrorNotHeroOwner(token, sender);
  }

  function onlyEOA(bool isEoa) internal view {
    if (!isEoa) {
      revert IAppErrors.NotEOA(msg.sender);
    }
  }
  //endregion ------------------------ RESTRICTIONS

  //region ------------------------ REGISTER

  function registerItem(
    IController controller,
    address msgSender,
    address item,
    IItemController.RegisterItemParams calldata info
  ) internal {
    onlyDeployer(controller, msgSender);
    IItemController.MainState storage s = _S();

    if (info.itemMeta.itemMetaType == 0) revert IAppErrors.ZeroItemMetaType();
    if (info.itemMeta.itemLevel == 0) revert IAppErrors.ZeroLevel();

    if (!s.items.add(item)) {
      IItemController.ItemMeta memory existMeta = ItemLib.unpackedItemMeta(s.itemMeta[item]);
        // we should not change types for existed items
      if (existMeta.itemType != info.itemMeta.itemType) revert IAppErrors.ItemTypeChanged();
      if (existMeta.itemMetaType != info.itemMeta.itemMetaType) revert IAppErrors.ItemMetaTypeChanged();
    }

    s.itemMeta[item] = ItemLib.packItemMeta(info.itemMeta);

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

    emit IApplicationEvents.ItemRegistered(item, info);
  }

  /// @notice  Ensure: min != 0, max != 0 and both min and min should have same sign
  /// Value of attribute cannot be equal to 0 because toBytes32ArrayWithIds cannot store zero values.
  function _setAttributesWithCheck(
    address item,
    IItemController.ItemGenerateInfo memory data,
    mapping(address => bytes32[]) storage dest
  ) internal {
    for (uint i = 0; i < data.ids.length; ++i) {
      if (
        data.mins[i] == 0
        || data.maxs[i] == 0
        || data.mins[i] > data.maxs[i]
        || (data.mins[i] < 0 && data.maxs[i] > 0)
      ) revert IAppErrors.IncorrectMinMaxAttributeRange(data.mins[i], data.maxs[i]);
    }

    dest[item] = ItemLib.packItemGenerateInfo(data);
  }

  function removeItem(IController controller, address msgSender, address item) internal {
    IItemController.MainState storage s = _S();
    onlyDeployer(controller, msgSender);

    s.items.remove(item);

    delete s.itemMeta[item];
    delete s.augmentInfo[item];
    delete s.generateInfoAttributes[item];
    delete s._itemConsumableAttributes[item];
    delete s.itemConsumableStats[item];
    delete s.generateInfoCasterAttributes[item];
    delete s.generateInfoTargetAttributes[item];
    delete s.generateInfoAttack[item];
    delete s._itemAttackInfo[item.packNftId(0)];

    emit IApplicationEvents.ItemRemoved(item);
  }
  //endregion ------------------------ REGISTER

  //region ------------------------ EQUIP

  function isItemEquipped(IItemController.MainState storage s, address item, uint itemId) internal view returns (bool) {
    return s.equippedOn[item.packNftId(itemId)] != bytes32(0);
  }

  function equipMany(
    bool isEoa,
    IController controller,
    address msgSender,
    address heroToken,
    uint heroTokenId,
    address[] calldata items,
    uint[] calldata itemIds,
    uint8[] calldata itemSlots
  ) internal {
    onlyEOA(isEoa);
    IItemController.MainState storage s = _S();
    if (items.length != itemIds.length || items.length != itemSlots.length) revert IAppErrors.LengthsMismatch();

    EquipLocalContext memory ctx;
    ctx.statController = IStatController(controller.statController());
    ctx.dungeonFactory = IDungeonFactory(controller.dungeonFactory());
    ctx.hc = IHeroController(controller.heroController());
    (ctx.payToken,) = ctx.hc.payTokenInfo(heroToken);
    ctx.heroTokenId = heroTokenId;
    ctx.heroToken = heroToken;

    _checkHeroAndController(controller, ctx.hc, msgSender, heroToken, heroTokenId);
    if (ctx.dungeonFactory.currentDungeon(heroToken, heroTokenId) != 0) revert IAppErrors.EquipForbiddenInDungeon();

    if (ctx.payToken == address(0)) revert IAppErrors.ErrorEquipForbidden();

    for (uint i; i < items.length; ++i) {
      _equip(s, ctx, msgSender, items[i], itemIds[i], itemSlots[i]);
    }
  }

  /// @notice Equip the item, add bonus attributes, transfer the item from the sender to the hero token
  function _equip(
    IItemController.MainState storage s,
    EquipLocalContext memory c,
    address msgSender,
    address item,
    uint itemId,
    uint8 itemSlot
  ) internal {
    onlyOwner(item, itemId, msgSender);

    IItemController.ItemMeta memory meta = ItemLib.unpackedItemMeta(s.itemMeta[item]);
    IItemController.ItemInfo memory _itemInfo = ItemLib.unpackedItemInfo(s.itemInfo[item.packNftId(itemId)]);

    if (meta.itemMetaType == 0) revert IAppErrors.UnknownItem(item);
    if (isItemEquipped(s, item, itemId)) revert IAppErrors.ItemIsAlreadyEquipped(item);

    if (uint(meta.itemType) == 0) revert IAppErrors.Consumable(item);
    if (meta.baseDurability != 0 && _itemInfo.durability == 0) revert IAppErrors.Broken(item);
    _checkRequirements(c.statController, c.heroToken, c.heroTokenId, meta.requirements);

    c.statController.changeHeroItemSlot(
      c.heroToken,
      uint64(c.heroTokenId),
      uint(meta.itemType),
      itemSlot,
      item,
      itemId,
      true
    );

    bytes32[] memory attributes = s._itemAttributes[item.packNftId(itemId)];
    if (attributes.length != 0) {
      c.statController.changeBonusAttributes(IStatController.ChangeAttributesInfo({
        heroToken: c.heroToken,
        heroTokenId: c.heroTokenId,
        changeAttributes: StatLib.bytesToFullAttributesArray(attributes),
        add: true,
        temporally: false
      }));

      // some items can reduce hero life to zero, prevent this
      if (c.statController.heroStats(c.heroToken, c.heroTokenId).life == 0) revert IAppErrors.ZeroLife();
    }

    // transfer item to hero
    IItem(item).controlledTransfer(msgSender, c.heroToken, itemId);
    // need to equip after transfer for properly checks
    s.equippedOn[item.packNftId(itemId)] = c.heroToken.packNftId(c.heroTokenId);

    emit IApplicationEvents.Equipped(item, itemId, c.heroToken, c.heroTokenId, itemSlot);
  }

  function _checkRequirements(
    IStatController statController,
    address heroToken,
    uint heroTokenId,
    IStatController.CoreAttributes memory requirements
  ) internal view {
    IStatController.CoreAttributes memory attributes = statController.heroBaseAttributes(heroToken, heroTokenId);
    if (
      requirements.strength > attributes.strength
      || requirements.dexterity > attributes.dexterity
      || requirements.vitality > attributes.vitality
      || requirements.energy > attributes.energy
    ) revert IAppErrors.RequirementsToItemAttributes();
  }

  /// @notice Check requirements for the hero and for the controller state before equip/take off/use items
  function _checkHeroAndController(
    IController controller,
    IHeroController heroController,
    address msgSender,
    address heroToken,
    uint heroTokenId
  ) internal view {
    onlyOwner(heroToken, heroTokenId, msgSender);
    if (IReinforcementController(controller.reinforcementController()).isStaked(heroToken, heroTokenId)) revert IAppErrors.Staked(heroToken, heroTokenId);
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
    if (heroController.heroClass(heroToken) == 0) revert IAppErrors.ErrorHeroIsNotRegistered(heroToken);
  }
  //endregion ------------------------ EQUIP

  //region ------------------------ TAKE OFF

  function takeOffMany(
    bool isEoa,
    IController controller,
    address msgSender,
    address heroToken,
    uint heroTokenId,
    address[] calldata items,
    uint[] calldata tokenIds,
    uint8[] calldata itemSlots
  ) internal {
    onlyEOA(isEoa);

    TakeOffContext memory ctx = ItemStatsLib.TakeOffContext({
      controller: controller,
      msgSender: msgSender,
      heroToken: heroToken,
      heroTokenId: heroTokenId,
      destination: msgSender,
      broken: false,
      heroController: IHeroController(controller.heroController()),
      dungeonFactory: IDungeonFactory(controller.dungeonFactory()),
      statController: IStatController(controller.statController())
    });

    IItemController.MainState storage s = _S();
    uint len = items.length;
    if (len != tokenIds.length || len != itemSlots.length) revert IAppErrors.LengthsMismatch();

    for (uint i; i < len; ++i) {
      _takeOffWithChecks(s, ctx, items[i], tokenIds[i], itemSlots[i]);
    }
  }

  /// @dev Some stories can manipulate items
  function takeOffDirectly(
    IController controller,
    address item,
    uint itemId,
    address hero,
    uint heroId,
    uint8 itemSlot,
    address destination,
    bool broken
  ) internal {
    if (controller.storyController() != msg.sender && controller.heroController() != msg.sender) {
      revert IAppErrors.ErrorForbidden(msg.sender);
    }
    ItemStatsLib._takeOff(_S(), IStatController(controller.statController()), item, itemId, hero, heroId, itemSlot, destination, broken);
  }

  function _takeOffWithChecks(
    IItemController.MainState storage s,
    TakeOffContext memory ctx,
    address item,
    uint itemId,
    uint8 itemSlot
  ) internal {
    _checkHeroAndController(ctx.controller,
      ctx.heroController,
      ctx.msgSender,
      ctx.heroToken,
      ctx.heroTokenId
    );
    if (ctx.dungeonFactory.currentDungeon(ctx.heroToken, ctx.heroTokenId) != 0) revert IAppErrors.TakeOffForbiddenInDungeon();

    if (s.equippedOn[item.packNftId(itemId)] != ctx.heroToken.packNftId(ctx.heroTokenId)) revert IAppErrors.NotEquipped(item);

    _takeOff(s, ctx.statController, item, itemId, ctx.heroToken, ctx.heroTokenId, itemSlot, ctx.destination, ctx.broken);
  }

  /// @notice Take off the item, remove bonus attributes, transfer the item from the hero token to {destination}
  /// @param broken True if the item is broken. The durability of the broken item will be set to 0.
  function _takeOff(
    IItemController.MainState storage s,
    IStatController statController,
    address item,
    uint itemId,
    address heroToken,
    uint heroTokenId,
    uint8 itemSlot,
    address destination,
    bool broken
  ) internal {
    bytes32 packedItemId = item.packNftId(itemId);
    IItemController.ItemMeta memory meta = ItemLib.unpackedItemMeta(s.itemMeta[item]);
    IItemController.ItemInfo memory _itemInfo = ItemLib.unpackedItemInfo(s.itemInfo[packedItemId]);

    if (uint(meta.itemType) == 0) revert IAppErrors.Consumable(item);

    statController.changeHeroItemSlot(
      heroToken,
      uint64(heroTokenId),
      uint(meta.itemType),
      itemSlot,
      item,
      itemId,
      false
    );

    if (broken) {
      _itemInfo.durability = 0;
      s.itemInfo[packedItemId] = ItemLib.packItemInfo(_itemInfo);
    }

    bytes32[] memory attributes = s._itemAttributes[packedItemId];
    if (attributes.length != 0) {
      statController.changeBonusAttributes(IStatController.ChangeAttributesInfo({
        heroToken: heroToken,
        heroTokenId: heroTokenId,
        changeAttributes: StatLib.bytesToFullAttributesArray(attributes),
        add: false,
        temporally: false
      }));
    }

    // need to take off before transfer for properly checks
    s.equippedOn[packedItemId] = bytes32(0);
    IItem(item).controlledTransfer(heroToken, destination, itemId);

    emit IApplicationEvents.TakenOff(item, itemId, heroToken, heroTokenId, itemSlot, destination);
  }
  //endregion ------------------------ TAKE OFF

  //region ------------------------ AUGMENT and REPAIR

  /// @notice Initialization for augment() and repairDurability()
  /// Get {meta} and {info}, check some restrictions
  function _prepareToAugment(
    IItemController.MainState storage s,
    bool isEoa,
    IController controller,
    address msgSender,
    address item,
    uint itemId,
    uint consumedItemId
  ) internal view returns(
    IItemController.ItemMeta memory meta,
    IItemController.ItemInfo memory info
  ) {
    onlyEOA(isEoa);
    if (itemId == consumedItemId) revert IAppErrors.SameIdsNotAllowed();
    onlyOwner(item, itemId, msgSender);
    onlyOwner(item, consumedItemId, msgSender);

    meta = ItemLib.unpackedItemMeta(s.itemMeta[item]);
    info = ItemLib.unpackedItemInfo(s.itemInfo[item.packNftId(itemId)]);

    if (isItemEquipped(s, item, itemId) || isItemEquipped(s, item, consumedItemId)) revert IAppErrors.ItemEquipped();
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
  }

  /// @notice Destroy {consumed item} to repair durability of the {item}
  function repairDurability(
    bool isEoa,
    IController controller,
    address msgSender,
    address item,
    uint itemId,
    uint consumedItemId
  ) external {
    // restrictions are checked inside {_prepareToAugment}
    IItemController.MainState storage s = _S();
    (
      IItemController.ItemMeta memory meta,
      IItemController.ItemInfo memory _itemInfo
    ) = _prepareToAugment(s, isEoa, controller, msgSender, item, itemId, consumedItemId);

    if (meta.baseDurability == 0) revert IAppErrors.ZeroDurability();

    _destroy(item, consumedItemId);
    _sendFee(s, controller, item, msgSender, IItemController.FeeType.REPAIR);

    _itemInfo.durability = meta.baseDurability;
    s.itemInfo[item.packNftId(itemId)] = ItemLib.packItemInfo(_itemInfo);

    emit IApplicationEvents.ItemRepaired(item, itemId, consumedItemId, meta.baseDurability);
  }

  /// @notice Destroy {consumed item} to augment given {item}.
  /// There is a chance of 30% that the item will be destroyed instead of augmentation.
  function augment(
    bool isEoa,
    IController controller,
    address msgSender,
    address item,
    uint itemId,
    uint consumedItemId
  ) external {
    // restrictions are checked inside {_prepareToAugment}
    IItemController.MainState storage s = _S();
    (
      IItemController.ItemMeta memory meta,
      IItemController.ItemInfo memory _itemInfo
    ) = _prepareToAugment(s, isEoa, controller, msgSender, item, itemId, consumedItemId);

    if (meta.itemMetaType == uint8(IItemController.ItemMetaType.CONSUMABLE)) revert IAppErrors.Consumable(item);
    if (_itemInfo.augmentationLevel >= MAX_AUGMENTATION_LEVEL) revert IAppErrors.TooHighAgLevel(_itemInfo.augmentationLevel);

    _destroy(item, consumedItemId);

    address augToken = _sendFee(s, controller, item, msgSender, IItemController.FeeType.AUGMENT);
    // we check augToken for 0 AFTER sendFee to avoid second reading of augmentInfo
    if (augToken == address(0)) revert IAppErrors.ZeroAugmentation();

    if (IOracle(controller.oracle()).getRandomNumber(1e18, 0) < AUGMENT_CHANCE) {
      IItemController.AugmentInfo memory _augmentInfo;
      bytes32 packedItemId = item.packNftId(itemId);

      // augment base
      (_augmentInfo.attributesValues, _augmentInfo.attributesIds) = _augmentAttributes(s._itemAttributes[packedItemId], true);
      s._itemAttributes[packedItemId] = _augmentInfo.attributesValues.toBytes32ArrayWithIds(_augmentInfo.attributesIds);

      // additionally
      if (meta.itemMetaType == uint8(IItemController.ItemMetaType.ATTACK)) {
        _augmentInfo.attackInfo = ItemLib.unpackItemAttackInfo(s._itemAttackInfo[packedItemId]);
        _augmentInfo.attackInfo.min = _augmentAttribute(_augmentInfo.attackInfo.min);
        _augmentInfo.attackInfo.max = _augmentAttribute(_augmentInfo.attackInfo.max);
        s._itemAttackInfo[packedItemId] = ItemLib.packItemAttackInfo(_augmentInfo.attackInfo);
      } else if (meta.itemMetaType == uint8(IItemController.ItemMetaType.BUFF)) {
        // caster
        (_augmentInfo.casterValues, _augmentInfo.casterIds) = _augmentAttributes(s._itemCasterAttributes[packedItemId], true);
        s._itemCasterAttributes[packedItemId] = _augmentInfo.casterValues.toBytes32ArrayWithIds(_augmentInfo.casterIds);

        // target
        (_augmentInfo.targetValues, _augmentInfo.targetIds) = _augmentAttributes(s._itemTargetAttributes[packedItemId], false);
        s._itemTargetAttributes[packedItemId] = _augmentInfo.targetValues.toBytes32ArrayWithIds(_augmentInfo.targetIds);
      }

      // increase aug level
      _itemInfo.augmentationLevel = _itemInfo.augmentationLevel + 1;
      s.itemInfo[packedItemId] = ItemLib.packItemInfo(_itemInfo);

      emit IApplicationEvents.Augmented(item, itemId, consumedItemId, _itemInfo.augmentationLevel, _augmentInfo);
    } else {
      _destroy(item, itemId);
      emit IApplicationEvents.NotAugmented(item, itemId, consumedItemId, _itemInfo.augmentationLevel);
    }
  }

  /// @notice Modify either positive or negative values
  /// @param ignoreNegative True - leave unchanged all negative values, False - don't change all positive values
  function _augmentAttributes(bytes32[] memory packedAttr, bool ignoreNegative) internal pure returns (
    int32[] memory values,
    uint8[] memory ids
  ) {
    (values, ids) = packedAttr.toInt32ArrayWithIds();
    for (uint i; i < values.length; ++i) {
      // do not increase destroy item attribute
      if(uint(ids[i]) == uint(IStatController.ATTRIBUTES.DESTROY_ITEMS)) {
        continue;
      }
      if ((ignoreNegative && values[i] > 0) || (!ignoreNegative && values[i] < 0)) {
        values[i] = _augmentAttribute(values[i]);
      }
    }
  }

  /// @notice Increase/decrease positive/negative value on ceil(value/20) but at least on 1
  function _augmentAttribute(int32 value) internal pure returns (int32) {
    if (value == 0) {
      return 0;
    }
    // bonus must be not lower than 1
    if (value > 0) {
      return value + int32(int(Math.max(Math.ceilDiv(value.toUint(), AUGMENT_FACTOR), 1)));
    } else {
      return value - int32(int(Math.max(Math.ceilDiv((- value).toUint(), AUGMENT_FACTOR), 1)));
    }
  }
  //endregion ------------------------ AUGMENT and REPAIR

  //region ------------------------ NEW ITEM CREATION

  function mintNewItem(
    IController controller,
    address sender,
    address item,
    address recipient
  ) internal returns (uint itemId) {
    return ItemLib.mintNewItem(_S(), controller, sender, item, recipient);
  }
  //endregion ------------------------ NEW ITEM CREATION

  //region ------------------------ REDUCE DURABILITY

  /// @notice Reduce durability of all equipped items except items of SKILL-type.
  function reduceEquippedItemsDurability(
    IController controller,
    address msgSender,
    address hero,
    uint heroId,
    uint8 biome
  ) external {
    address dungeonFactory = controller.dungeonFactory();
    if (dungeonFactory != msgSender) revert IAppErrors.ErrorNotDungeonFactory(msgSender);
    IItemController.MainState storage s = _S();

    ReduceDurabilityContext memory ctx;
    ctx.skillSlots = IDungeonFactory(dungeonFactory).skillSlotsForDurabilityReduction(hero, heroId);
    ctx.statController = IStatController(controller.statController());
    ctx.busySlots = ctx.statController.heroItemSlots(hero, heroId);

    for (uint i; i < ctx.busySlots.length; ++i) {

      if (
        (ctx.busySlots[i] == uint8(IStatController.ItemSlots.SKILL_1) && ctx.skillSlots[0] == 0)
        || (ctx.busySlots[i] == uint8(IStatController.ItemSlots.SKILL_2) && ctx.skillSlots[1] == 0)
        || (ctx.busySlots[i] == uint8(IStatController.ItemSlots.SKILL_3) && ctx.skillSlots[2] == 0)
      ) {
        continue;
      }

      (ctx.itemAdr, ctx.itemId) = ctx.statController.heroItemSlot(hero, uint64(heroId), ctx.busySlots[i]).unpackNftId();
      ctx.durability = _reduceDurabilityForItem(s, ctx.itemAdr, ctx.itemId, biome);

      // if broken need to take off
      if (ctx.durability == 0) {
        _takeOff(
          s,
          ctx.statController,
          ctx.itemAdr,
          ctx.itemId,
          hero,
          heroId,
          ctx.busySlots[i],
          IERC721(hero).ownerOf(heroId),
          false
        );
      }

    }
  }

  /// @notice newDurability Calculate new durability for the {item}, update {itemInfo}
  function _reduceDurabilityForItem(
    IItemController.MainState storage s,
    address item,
    uint itemId,
    uint biome
  ) internal returns (uint16 newDurability) {
    IItemController.ItemMeta memory meta = ItemLib.unpackedItemMeta(s.itemMeta[item]);
    IItemController.ItemInfo memory _itemInfo = ItemLib.unpackedItemInfo(s.itemInfo[item.packNftId(itemId)]);

    newDurability = uint16(_calcReduceDurability(biome, _itemInfo.durability, meta.itemLevel, meta.itemType));

    _itemInfo.durability = newDurability;
    s.itemInfo[item.packNftId(itemId)] = ItemLib.packItemInfo(_itemInfo);

    emit IApplicationEvents.ReduceDurability(item, itemId, newDurability);
  }

  /// @return New (reduced) value for the current durability
  function _calcReduceDurability(
    uint biome,
    uint currentDurability,
    uint8 itemLevel,
    IItemController.ItemType itemType
  ) internal pure returns (uint) {
    uint value = DURABILITY_REDUCTION;

    if (itemType != IItemController.ItemType.SKILL) {
      uint itemBiomeLevel = uint(itemLevel) / StatLib.BIOME_LEVEL_STEP + 1;
      if (itemBiomeLevel < biome) {
        value = DURABILITY_REDUCTION * ((biome - itemBiomeLevel + 1) ** 2 / 2);
      }
    }

    return currentDurability > value
      ? currentDurability - value
      : 0;
  }
  //endregion ------------------------ REDUCE DURABILITY

  //region ------------------------ DESTROY

  function destroy(IController controller, address msgSender, address item, uint itemId) external {
    if (
      controller.gameObjectController() != msgSender
      && controller.storyController() != msgSender
      && IERC721(item).ownerOf(itemId) != msgSender
    ) {
      revert IAppErrors.ErrorForbidden(msgSender);
    }

    if (isItemEquipped(_S(), item, itemId)) revert IAppErrors.ItemEquipped();

    _destroy(item, itemId);
  }

  function _destroy(address item, uint itemId) internal {
    IItem(item).burn(itemId);
    emit IApplicationEvents.Destroyed(item, itemId);
  }
  //endregion ------------------------ DESTROY

  //region ------------------------ FEE

  /// @return augToken Return augToken to avoid repeat reading of augmentInfo inside augment()
  function _sendFee(
    IItemController.MainState storage s,
    IController controller,
    address item,
    address msgSender,
    IItemController.FeeType feeType
  ) internal returns (address augToken) {
    (address token, uint amount) = s.augmentInfo[item].unpackAddressWithAmount();
    if (token != address(0)) {
      address treasury = controller.treasury();
      IERC20(token).transferFrom(msgSender, address(this), amount);

      AppLib.approveIfNeeded(token, amount, treasury);
      ITreasury(treasury).sendFee(token, amount, feeType);
    }
    return token;
  }
  //endregion ------------------------ FEE

  //region ------------------------ USE

  /// @notice Use consumable item to temporally increase bonus attributes and destroy the item
  function use(
    bool isEoa,
    IController controller,
    address msgSender,
    address item,
    uint itemId,
    address heroToken,
    uint heroTokenId
  ) external {
    onlyEOA(isEoa);
    onlyOwner(item, itemId, msgSender);

    IItemController.MainState storage s = _S();

    IStatController statController = IStatController(controller.statController());
    IHeroController hc = IHeroController(controller.heroController());

    (address payToken,) = hc.payTokenInfo(heroToken);
    if (payToken == address(0)) revert IAppErrors.UseForbiddenZeroPayToken();

    _checkHeroAndController(controller, hc, msgSender, heroToken, heroTokenId);

    IItemController.ItemMeta memory meta = ItemLib.unpackedItemMeta(s.itemMeta[item]);
    if (uint8(meta.itemType) != 0) revert IAppErrors.NotConsumable(item);
    _checkRequirements(statController, heroToken, heroTokenId, meta.requirements);

    statController.registerConsumableUsage(heroToken, heroTokenId, item);

    statController.changeCurrentStats(heroToken, heroTokenId, StatLib.unpackChangeableStats(s.itemConsumableStats[item]), true);

    bytes32[] memory itemConsumableAttributes = s._itemConsumableAttributes[item];
    if (itemConsumableAttributes.length != 0) {
      int32[] memory attributes = StatLib.bytesToFullAttributesArray(itemConsumableAttributes);
      statController.changeBonusAttributes(IStatController.ChangeAttributesInfo({
        heroToken: heroToken,
        heroTokenId: heroTokenId,
        changeAttributes: attributes,
        add: true,
        temporally: true
      }));
    }

    _destroy(item, itemId);
    emit IApplicationEvents.Used(item, itemId, heroToken, heroTokenId);
  }
  //endregion ------------------------ USE

  //region ------------------------ VIEWS
  function itemByIndex(uint idx) internal view returns (address) {
    return _S().items.at(idx);
  }

  function itemsLength() internal view returns (uint) {
    return _S().items.length();
  }

  function itemMeta(address item) internal view returns (IItemController.ItemMeta memory meta) {
    return ItemLib.unpackedItemMeta(_S().itemMeta[item]);
  }

  function augmentInfo(address item) internal view returns (address token, uint amount) {
    return PackingLib.unpackAddressWithAmount(_S().augmentInfo[item]);
  }

  function genAttributeInfo(address item) internal view returns (IItemController.ItemGenerateInfo memory info) {
    return ItemLib.unpackItemGenerateInfo(_S().generateInfoAttributes[item]);
  }

  function genCasterAttributeInfo(address item) internal view returns (IItemController.ItemGenerateInfo memory info) {
    return ItemLib.unpackItemGenerateInfo(_S().generateInfoCasterAttributes[item]);
  }

  function genTargetAttributeInfo(address item) internal view returns (IItemController.ItemGenerateInfo memory info) {
    return ItemLib.unpackItemGenerateInfo(_S().generateInfoTargetAttributes[item]);
  }

  function genAttackInfo(address item) internal view returns (IItemController.AttackInfo memory info) {
    return ItemLib.unpackItemAttackInfo(_S().generateInfoAttack[item]);
  }

  function itemInfo(address item, uint itemId) internal view returns (IItemController.ItemInfo memory info) {
    return ItemLib.unpackedItemInfo(_S().itemInfo[PackingLib.packNftId(item, itemId)]);
  }

  function equippedOn(address item, uint itemId) internal view returns (address hero, uint heroId) {
    return PackingLib.unpackNftId(_S().equippedOn[item.packNftId(itemId)]);
  }

  function itemAttributes(address item, uint itemId) internal view returns (int32[] memory values, uint8[] memory ids) {
    return PackingLib.toInt32ArrayWithIds(_S()._itemAttributes[PackingLib.packNftId(item, itemId)]);
  }

  function consumableAttributes(address item) internal view returns (int32[] memory values, uint8[] memory ids) {
    return PackingLib.toInt32ArrayWithIds(_S()._itemConsumableAttributes[item]);
  }

  function consumableStats(address item) internal view returns (IStatController.ChangeableStats memory stats) {
    return StatLib.unpackChangeableStats(_S().itemConsumableStats[item]);
  }

  function casterAttributes(address item, uint itemId) internal view returns (int32[] memory values, uint8[] memory ids) {
    return PackingLib.toInt32ArrayWithIds(_S()._itemCasterAttributes[PackingLib.packNftId(item, itemId)]);
  }

  function targetAttributes(address item, uint itemId) internal view returns (int32[] memory values, uint8[] memory ids) {
    return PackingLib.toInt32ArrayWithIds(_S()._itemTargetAttributes[PackingLib.packNftId(item, itemId)]);
  }

  function itemAttackInfo(address item, uint itemId) internal view returns (IItemController.AttackInfo memory info) {
    return ItemLib.unpackItemAttackInfo(_S()._itemAttackInfo[PackingLib.packNftId(item, itemId)]);
  }

  function score(address item, uint itemId) external view returns (uint) {
    return ScoreLib.itemScore(
      StatLib.bytesToFullAttributesArray(_S()._itemAttributes[PackingLib.packNftId(item, itemId)]),
      ItemLib.unpackedItemMeta(_S().itemMeta[item]).baseDurability
    );
  }

  function isAllowedToTransfer(address item, uint itemId) internal view returns (bool) {
    return _S().equippedOn[item.packNftId(itemId)] == bytes32(0);
  }
  //endregion ------------------------ VIEWS

}
