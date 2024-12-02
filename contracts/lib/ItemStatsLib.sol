// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IDungeonFactory.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IGuildController.sol";
import "../interfaces/IItem.sol";
import "../interfaces/IItemController.sol";
import "../interfaces/IItemControllerHelper.sol";
import "../interfaces/IReinforcementController.sol";
import "../interfaces/ITreasury.sol";
import "./AppLib.sol";
import "./CalcLib.sol";
import "./ShelterLib.sol";
import "./ItemLib.sol";
import "./PackingLib.sol";
import "./ScoreLib.sol";
import "./OtherItemLib.sol";

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
  uint private constant MAX_AUGMENTATION_LEVEL = 20;

  /// @dev keccak256(abi.encode(uint256(keccak256("item.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant MAIN_STORAGE_LOCATION = 0xe78a2879cd91c3f7b62ea14e72546fed47c40919bca4daada532a5fa05ac6700;

  /// @notice SIP-003: Max value of item fragility that corresponds to 100%
  uint private constant MAX_FRAGILITY = 100_000;
  /// @notice SIP-003: Each successful repair has a chance of increasing the item's fragility by 1%.
  uint private constant FRAGILITY_SUCCESSFUL_REPAIR_PORTION = 1_000;
  /// @notice SIP-003: 10% chance of increasing the item's fragility on successful repair
  uint private constant FRAGILITY_SUCCESSFUL_REPAIR_CHANCE = 15;
  /// @notice SIP-003: The quest mechanic will break the item and increase its fragility by 1%.
  uint private constant FRAGILITY_BREAK_ITEM_PORTION = 1_000;

  //endregion ------------------------ CONSTANTS

  //region ------------------------ STRUCTS

  struct EquipLocalContext {
    IStatController statController;
    IDungeonFactory dungeonFactory;
    IHeroController hc;
    address payToken;
    address heroToken;
    /// @notice Lazy initialization of {equippedSlots}
    bool equippedSlotsLoaded;
    uint8[] equippedSlots;
    uint heroTokenId;
  }

  struct ReduceDurabilityContext {
    /// @notice values 0 or 1 for SKILL_1, SKILL_2, SKILL_3
    uint8[] skillSlots;
    uint8[] busySlots;
    IStatController statController;
    address dungeonFactory;
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

  //region ------------------------ Restrictions

  function onlyDeployer(IController c, address sender) internal view {
    if (!c.isDeployer(sender)) revert IAppErrors.ErrorNotDeployer(sender);
  }

  function onlyOwner(address token, uint tokenId, address sender) internal view {
    if (IERC721(token).ownerOf(tokenId) != sender) revert IAppErrors.ErrorNotOwner(token, tokenId);
  }

  function onlyEOA(bool isEoa) internal view {
    if (!isEoa) {
      revert IAppErrors.NotEOA(msg.sender);
    }
  }

  function onlyStoryController(IController c, address sender) internal view {
    if (sender != c.storyController()) revert IAppErrors.ErrorNotStoryController();
  }

  function onlyNotEquippedItem(address item, uint itemId) internal view {
    if (isItemEquipped(_S(), item, itemId)) revert IAppErrors.ItemEquipped(item, itemId);
  }

  function onlyNotConsumable(IItemController.ItemMeta memory meta, address item) internal pure {
    if (
      uint(meta.itemType) == 0
      || meta.itemMetaType == uint8(IItemController.ItemMetaType.CONSUMABLE) // todo probably first check is enough?
    ) revert IAppErrors.Consumable(item);
  }

  function _checkPauseEoaOwner(
    bool isEoa,
    IController controller,
    address msgSender,
    address item,
    uint itemId
  ) internal view {
    onlyEOA(isEoa);
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
    onlyOwner(item, itemId, msgSender);
  }

  function _onlyRegisteredControllers(IController controller) internal view returns (address dungeonFactory) {
    dungeonFactory = controller.dungeonFactory();
    if (
      msg.sender != dungeonFactory
      && msg.sender != controller.reinforcementController()
      // todo && msg.sender != controller.pvpController()
    ) revert IAppErrors.ErrorForbidden(msg.sender);
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Views
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

  function consumableActionMask(address item) internal view returns (uint) {
    return _S()._consumableActionMask[item];
  }

  /// @notice SIP-003: item fragility counter that displays the chance of an unsuccessful repair.
  /// @dev [0...100%], decimals 3, so the value is in the range [0...10_000]
  function itemFragility(address item, uint itemId) internal view returns (uint) {
    return _S().itemFragility[item.packNftId(itemId)];
  }

  /// @notice SCB-1014: packed metadata for the item of type "Other"
  /// Use {PackingLib.unpackOtherXXX} routines to unpack data.
  /// The proper routine depends on subtype kind, use {PackingLib.getOtherItemTypeKind} to extract it.
  function packedItemMetaData(address item) internal view returns (bytes memory) {
    return _S().packedItemMetaData[item];
  }

  function itemControllerHelper() internal view returns (address) {
    return address(uint160(_S().globalParam[IItemController.GlobalParam.ITEM_CONTROLLER_HELPER_ADDRESS_1]));
  }

  function isItemEquipped(IItemController.MainState storage s, address item, uint itemId) internal view returns (bool) {
    return s.equippedOn[item.packNftId(itemId)] != bytes32(0);
  }
  //endregion ------------------------ Views

  //region ------------------------ Deployer actions
  function setItemControllerHelper(IController controller, address helper_) internal {
    onlyDeployer(controller, msg.sender);
    if (itemControllerHelper() != address(0)) revert IAppErrors.AlreadyInitialized();

    _S().globalParam[IItemController.GlobalParam.ITEM_CONTROLLER_HELPER_ADDRESS_1] = uint(uint160(helper_));
    emit IApplicationEvents.ItemControllerHelper(helper_);
  }

  //endregion ------------------------ Deployer actions

  //region ------------------------ Controllers actions
  function mintNewItem(
    IController controller,
    address sender,
    address item,
    address recipient
  ) internal returns (uint itemId) {
    return ItemLib.mintNewItem(_S(), controller, sender, item, recipient);
  }

  /// @notice Reduce durability of all equipped items except not-used items of SKILL-type.
  /// Used skills are stored in skillSlotsForDurabilityReduction
  function reduceEquippedItemsDurability(
    IController controller,
    address hero,
    uint heroId,
    uint8 biome,
    bool reduceDurabilityAllSkills
  ) external {
    ReduceDurabilityContext memory ctx;
    ctx.dungeonFactory = _onlyRegisteredControllers(controller);

    IItemController.MainState storage s = _S();

    if (!reduceDurabilityAllSkills) {
      // reduce durability of skill-slots only if they are marked for slot-durability-reduction
      ctx.skillSlots = IDungeonFactory(ctx.dungeonFactory).skillSlotsForDurabilityReduction(hero, heroId);
    }
    ctx.statController = IStatController(controller.statController());
    ctx.busySlots = ctx.statController.heroItemSlots(hero, heroId);

    for (uint i; i < ctx.busySlots.length; ++i) {
      if (!reduceDurabilityAllSkills) {
        if (
          (ctx.busySlots[i] == uint8(IStatController.ItemSlots.SKILL_1) && ctx.skillSlots[0] == 0)
          || (ctx.busySlots[i] == uint8(IStatController.ItemSlots.SKILL_2) && ctx.skillSlots[1] == 0)
          || (ctx.busySlots[i] == uint8(IStatController.ItemSlots.SKILL_3) && ctx.skillSlots[2] == 0)
        ) {
          continue;
        }
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

  function destroy(IController controller, address msgSender, address item, uint itemId) external {
    if (
      controller.gameObjectController() != msgSender
      && controller.storyController() != msgSender
      && IERC721(item).ownerOf(itemId) != msgSender
    ) {
      revert IAppErrors.ErrorForbidden(msgSender);
    }

    onlyNotEquippedItem(item, itemId);

    _destroy(item, itemId);
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
  ) external {
    if (controller.storyController() != msg.sender && controller.heroController() != msg.sender) {
      revert IAppErrors.ErrorForbidden(msg.sender);
    }
    ItemStatsLib._takeOff(_S(), IStatController(controller.statController()), item, itemId, hero, heroId, itemSlot, destination, broken);
  }

  /// @notice SIP-003: The quest mechanic that previously burned the item will increase its fragility by 1%
  function incBrokenItemFragility(IController controller, address item, uint itemId) internal {
    onlyStoryController(controller, msg.sender);
    _addItemFragility(item, itemId, FRAGILITY_BREAK_ITEM_PORTION);
  }
  //endregion ------------------------ Controllers actions

  //region ------------------------ Eoa actions
  function equipMany(
    bool isEoa,
    IController controller,
    address msgSender,
    address heroToken,
    uint heroTokenId,
    address[] calldata items,
    uint[] calldata itemIds,
    uint8[] calldata itemSlots
  ) external {
    EquipLocalContext memory ctx;
    ctx.hc = IHeroController(controller.heroController());

    // only HeroController or EOA
    if (address(ctx.hc) != msgSender) {
      onlyEOA(isEoa);
    }

    IItemController.MainState storage s = _S();
    if (items.length != itemIds.length || items.length != itemSlots.length) revert IAppErrors.LengthsMismatch();

    ctx.statController = IStatController(controller.statController());
    ctx.dungeonFactory = IDungeonFactory(controller.dungeonFactory());
    (ctx.payToken,) = ctx.hc.payTokenInfo(heroToken);
    ctx.heroTokenId = heroTokenId;
    ctx.heroToken = heroToken;

    if (address(ctx.hc) != msgSender) {
      onlyOwner(heroToken, heroTokenId, msgSender);
    }
    _checkHeroAndController(controller, ctx.hc, heroToken, heroTokenId);
    if (ctx.dungeonFactory.currentDungeon(heroToken, heroTokenId) != 0) revert IAppErrors.EquipForbiddenInDungeon();

    if (ctx.payToken == address(0)) revert IAppErrors.ErrorEquipForbidden();

    for (uint i; i < items.length; ++i) {
      // SCB-1021: some slots require uniqueness of item tokens
      IStatController.ItemSlots slot = IStatController.ItemSlots(itemSlots[i]);
      if (slot == IStatController.ItemSlots.RIGHT_RING) {
        _checkItemIsUnique(ctx, items, i, [IStatController.ItemSlots.LEFT_RING, IStatController.ItemSlots.UNKNOWN]);
      } else if (slot == IStatController.ItemSlots.LEFT_RING) {
        _checkItemIsUnique(ctx, items, i, [IStatController.ItemSlots.RIGHT_RING, IStatController.ItemSlots.UNKNOWN]);
      } else if (slot == IStatController.ItemSlots.SKILL_1) {
        _checkItemIsUnique(ctx, items, i, [IStatController.ItemSlots.SKILL_2, IStatController.ItemSlots.SKILL_3]);
      } else if (slot == IStatController.ItemSlots.SKILL_2) {
        _checkItemIsUnique(ctx, items, i, [IStatController.ItemSlots.SKILL_1, IStatController.ItemSlots.SKILL_3]);
      } else if (slot == IStatController.ItemSlots.SKILL_3) {
        _checkItemIsUnique(ctx, items, i, [IStatController.ItemSlots.SKILL_1, IStatController.ItemSlots.SKILL_2]);
      }

      if (address(ctx.hc) != msgSender) {
        onlyOwner(items[i], itemIds[i], msgSender);
        _equip(s, ctx, msgSender, items[i], itemIds[i], itemSlots[i]);
      } else {
        _equip(s, ctx, IERC721(items[i]).ownerOf(itemIds[i]), items[i], itemIds[i], itemSlots[i]);
      }
    }
  }

  function takeOffMany(
    bool isEoa,
    IController controller,
    address msgSender,
    address heroToken,
    uint heroTokenId,
    address[] calldata items,
    uint[] calldata tokenIds,
    uint8[] calldata itemSlots
  ) external {
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

  /// @notice Destroy {consumed item} to repair durability of the {item}
  /// There is a chance ~ item fragility that the item won't be repaired.
  function repairDurability(
    bool isEoa,
    IController controller,
    address msgSender,
    address item,
    uint itemId,
    uint consumedItemId
  ) external {
    _repairDurability(isEoa, controller, msgSender, item, itemId, consumedItemId, CalcLib.pseudoRandom);
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
    ) = _prepareToAugment(isEoa, controller, msgSender, item, itemId, consumedItemId);

    onlyNotConsumable(meta, item);
    if (_itemInfo.augmentationLevel >= MAX_AUGMENTATION_LEVEL) revert IAppErrors.TooHighAgLevel(_itemInfo.augmentationLevel);

    _destroy(item, consumedItemId);

    address augToken = _sendFee(s, controller, item, msgSender);
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

  /// @notice Use consumable
  function use(
    bool isEoa,
    IController controller,
    IStatController statController,
    address msgSender,
    address item,
    uint itemId,
    address heroToken,
    uint heroTokenId
  ) external returns (uint actionMask) {
    onlyEOA(isEoa);
    onlyOwner(item, itemId, msgSender);

    IItemController.MainState storage s = _S();

    IHeroController hc = IHeroController(controller.heroController());

    (address payToken,) = hc.payTokenInfo(heroToken);
    if (payToken == address(0)) revert IAppErrors.UseForbiddenZeroPayToken();

    onlyOwner(heroToken, heroTokenId, msgSender);
    _checkHeroAndController(controller, hc, heroToken, heroTokenId);

    {
      IItemController.ItemMeta memory meta = ItemLib.unpackedItemMeta(s.itemMeta[item]);
      if (uint8(meta.itemType) != 0) revert IAppErrors.NotConsumable(item);
      _checkRequirements(statController, heroToken, heroTokenId, meta.requirements);

      IStatController.ChangeableStats memory change = StatLib.unpackChangeableStats(s.itemConsumableStats[item]);
      // allow to use multiple times items with experience/lc
      if(change.experience == 0 && change.lifeChances == 0) {
        statController.registerConsumableUsage(heroToken, heroTokenId, item);
      }
      statController.changeCurrentStats(heroToken, heroTokenId, change, true);
    }

    {
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
    }

    actionMask = s._consumableActionMask[item];

    _destroy(item, itemId);
    emit IApplicationEvents.Used(item, itemId, heroToken, heroTokenId);
  }

  function combineItems(
    bool isEoa,
    IController controller,
    address msgSender,
    uint configId,
    address[] memory items,
    uint[][] memory itemIds
  ) internal returns (uint itemId) {
    onlyEOA(isEoa);

    address helper = ItemStatsLib.itemControllerHelper();
    if (helper == address(0)) revert IAppErrors.NotInitialized();

    // validate that {items} and {itemIds} fit to the selected config
    address itemToMint = IItemControllerHelper(helper).prepareToCombine(msgSender, configId, items, itemIds);

    // destroy provided items
    uint lenItems = items.length;
    for (uint i; i < lenItems; ++i) {
      uint[] memory ids = itemIds[i];
      uint len = ids.length;
      for (uint j; j < len; ++j) {
        _destroy(items[i], ids[j]);
      }
    }

    // mint a new item in exchange of destroyed items
    itemId = ItemLib.mintNewItem(_S(), controller, address(this), itemToMint, msgSender);

    emit IApplicationEvents.CombineItems(msgSender, configId, items, itemIds, itemToMint, itemId);
  }

  //endregion ------------------------ Eoa actions

  //region ------------------------ Internal logic - equip and take off

  /// @notice Ensure that 1) {items} has no duplicates of items[index] 2) items[index] is not equipped at {slotsToCheck}
  function _checkItemIsUnique(
    EquipLocalContext memory ctx,
    address[] memory items,
    uint index,
    IStatController.ItemSlots[2] memory slotsToCheck
  ) internal view {
    if (!ctx.equippedSlotsLoaded) {
      ctx.equippedSlots = ctx.statController.heroItemSlots(ctx.heroToken, ctx.heroTokenId);
      ctx.equippedSlotsLoaded = true;
    }

    // there are no duplicates of the item in {items}
    // we don't check slots - assume that if item is being equipped it's equipped to the slot under consideration
    uint len = items.length;
    for (uint i; i < len; ++i) {
      if (i == index) continue;
      if (items[i] == items[index]) revert IAppErrors.DoubleItemUsageForbidden(index, items);
    }

    // ensure that the item is not yet equipped
    len = ctx.equippedSlots.length;
    for (uint i; i < len; ++i) {
      if (uint8(slotsToCheck[0]) == ctx.equippedSlots[i] || uint8(slotsToCheck[1]) == ctx.equippedSlots[i]) {
        (address item,) = PackingLib.unpackNftId(ctx.statController.heroItemSlot(ctx.heroToken, uint64(ctx.heroTokenId), ctx.equippedSlots[i]));
        if (item == items[index]) revert IAppErrors.ItemAlreadyUsedInSlot(item, uint8(ctx.equippedSlots[i]));
      }
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
    IItemController.ItemMeta memory meta = ItemLib.unpackedItemMeta(s.itemMeta[item]);
    IItemController.ItemInfo memory _itemInfo = ItemLib.unpackedItemInfo(s.itemInfo[item.packNftId(itemId)]);

    if (meta.itemMetaType == 0) revert IAppErrors.UnknownItem(item);
    onlyNotEquippedItem(item, itemId);
    onlyNotConsumable(meta, item);

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
  function _checkHeroAndController(IController controller, IHeroController heroController, address heroToken, uint heroTokenId) internal view {
    if (IReinforcementController(controller.reinforcementController()).isStaked(heroToken, heroTokenId)) revert IAppErrors.Staked(heroToken, heroTokenId);
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
    if (heroController.heroClass(heroToken) == 0) revert IAppErrors.ErrorHeroIsNotRegistered(heroToken);
  }

  function _takeOffWithChecks(
    IItemController.MainState storage s,
    TakeOffContext memory ctx,
    address item,
    uint itemId,
    uint8 itemSlot
  ) internal {
    onlyOwner(ctx.heroToken, ctx.heroTokenId, ctx.msgSender);
    _checkHeroAndController(ctx.controller,
      ctx.heroController,
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

    onlyNotConsumable(meta, item);

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
  //endregion ------------------------ Internal logic - equip and take off

  //region ------------------------ Internal logic - augment, repair

  /// @notice Initialization for augment() and repairDurability()
  /// Get {meta} and {info}, check some restrictions
  function _prepareToAugment(
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
    _checkPauseEoaOwner(isEoa, controller, msgSender, item, itemId);
    onlyOwner(item, consumedItemId, msgSender);

    if (itemId == consumedItemId) revert IAppErrors.SameIdsNotAllowed();
    meta = ItemLib.unpackedItemMeta(_S().itemMeta[item]);
    info = ItemLib.unpackedItemInfo(_S().itemInfo[item.packNftId(itemId)]);

    onlyNotEquippedItem(item, itemId);
    onlyNotEquippedItem(item, consumedItemId);
  }

  /// @notice Destroy {consumed item} to repair durability of the {item}
  /// There is a chance ~ item fragility that the item won't be repaired.
  /// @param random_ Pass _pseudoRandom here, param is required to simplify unit testing
  function _repairDurability(
    bool isEoa,
    IController controller,
    address msgSender,
    address item,
    uint itemId,
    uint consumedItemId,
    function (uint) internal view returns (uint) random_
  ) internal {
    // restrictions are checked inside {_prepareToAugment}
    IItemController.MainState storage s = _S();
    (
      IItemController.ItemMeta memory meta,
      IItemController.ItemInfo memory _itemInfo
    ) = _prepareToAugment(isEoa, controller, msgSender, item, itemId, consumedItemId);

    if (meta.baseDurability == 0) revert IAppErrors.ZeroDurability();

    _destroy(item, consumedItemId);
    _sendFee(s, controller, item, msgSender);

    // SIP-003: There is a chance of unsuccessful repair ~ to the item fragility
    uint fragility = itemFragility(item, itemId);
    bool success = fragility == 0 || random_(MAX_FRAGILITY - 1) > fragility;
    // Each successful repair has a 10% chance of increasing the item's fragility by 1%.
    bool incFragility = random_(100) < FRAGILITY_SUCCESSFUL_REPAIR_CHANCE;

    _itemInfo.durability = success
      ? meta.baseDurability // the item is repaired successfully
      : _itemInfo.durability;

    // try to hide gas difference between successful and failed cases
    _addItemFragility(item, itemId, success && incFragility ? FRAGILITY_SUCCESSFUL_REPAIR_PORTION : 0); // item fragility is increased

    s.itemInfo[item.packNftId(itemId)] = ItemLib.packItemInfo(_itemInfo);

    if (success) {
      emit IApplicationEvents.ItemRepaired(item, itemId, consumedItemId, meta.baseDurability);
    } else {
      emit IApplicationEvents.FailedToRepairItem(item, itemId, consumedItemId, _itemInfo.durability);
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
  //endregion ------------------------ Internal logic - augment, repair

  //region ------------------------ Internal logic - durability, destroy, fee, fragility

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

  function _destroy(address item, uint itemId) internal {
    IItem(item).burn(itemId);
    emit IApplicationEvents.Destroyed(item, itemId);
  }

  /// @return augToken Return augToken to avoid repeat reading of augmentInfo inside augment()
  function _sendFee(
    IItemController.MainState storage s,
    IController controller,
    address item,
    address msgSender
  ) internal returns (address augToken) {
    (address token, uint amount) = s.augmentInfo[item].unpackAddressWithAmount();
    if (token != address(0)) {
      controller.process(token, amount, msgSender);
    }
    return token;
  }

  function _addItemFragility(address item, uint itemId, uint portion) internal {
    uint fragility = _S().itemFragility[item.packNftId(itemId)];
    _S().itemFragility[item.packNftId(itemId)] = fragility + portion > MAX_FRAGILITY
      ? MAX_FRAGILITY
      : fragility + portion;
  }
  //endregion ------------------------ Internal logic - durability, destroy, fee, fragility
}
