// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IGuildController.sol";
import "../interfaces/IItem.sol";
import "../interfaces/IItemController.sol";
import "../interfaces/IItemControllerHelper.sol";
import "../interfaces/IOracle.sol";
import "../openzeppelin/Math.sol";
import "../solady/LibPRNG.sol";
import "./CalcLib.sol";
import "./ControllerContextLib.sol";
import "./ShelterLib.sol";
import "./StatLib.sol";

library ItemLib {
  using CalcLib for int32;
  using PackingLib for address;
  using PackingLib for bytes32;
  using PackingLib for bytes32[];
  using PackingLib for uint32[];
  using PackingLib for int32[];

  //region ------------------------ Constants
  /// @dev should be 20%
  uint private constant AUGMENT_FACTOR = 5;
  uint private constant AUGMENT_CHANCE = 0.7e18;
  uint private constant MAX_AUGMENTATION_LEVEL = 20;

  /// @dev keccak256(abi.encode(uint256(keccak256("item.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant MAIN_STORAGE_LOCATION = 0xe78a2879cd91c3f7b62ea14e72546fed47c40919bca4daada532a5fa05ac6700;
  //endregion ------------------------ Constants

  //region ------------------------ Data types
  struct GenerateAttributesContext {
    /// @notice True if max allowed amount of random attributes were reached inside {_prepareAttributes}
    bool stopGenerateRandom;
    /// @notice Flag - attribute was generated. The array matches to info.ids
    bool[] usedIndexes;
    /// @notice Ids of the generated attributes
    uint8[] ids;
    /// @notice Randomly selected values of the generated attributes
    int32[] values;
    /// @notice Counter of the stored values into {ids} and {values}
    uint counter;
    /// @notice Total number of random attributes that were generated inside {_prepareAttributes}
    uint randomAttrCounter;
    /// @notice Total sum of all {rarity} values for random attributes generated in {_prepareAttributes}
    uint raritySum;
    /// @notice Total number of random attributes that can be generated
    uint totalRandomAttrsPossible;
    /// @notice Magic find of the hero at the moment of item minting
    uint32 magicFind;
  }

  struct MintItemInfo {
    uint8 maxItems;
    int32 magicFind;
    int32 destroyItems;
    uint32[] mintItemsChances;
    IOracle oracle;
    address[] mintItems;
    uint amplifier;
    uint seed;
    /// @notice Penalty to reduce chance as chance/delta if the hero not in his biome
    /// @dev Use StatLib.mintDropChanceDelta
    uint mintDropChanceDelta;
  }

  struct ItemWithId {
    address item;
    uint itemId;
  }

  struct SenderInfo {
    address msgSender;
    bool isEoa;
  }

  //endregion ------------------------ Data types

  //region ------------------------ Restrictions
  function onlyDeployer(IController c, address sender) internal view {
    if (!c.isDeployer(sender)) revert IAppErrors.ErrorNotDeployer(sender);
  }

  function onlyEOA(bool isEoa) internal view {
    if (!isEoa) {
      revert IAppErrors.NotEOA(msg.sender);
    }
  }

  function onlyStoryController(IController c) internal view {
    if (msg.sender != c.storyController()) revert IAppErrors.ErrorNotStoryController();
  }

  function onlyNotEquippedItem(address item, uint itemId) internal view {
    if (_S().equippedOn[item.packNftId(itemId)] != bytes32(0)) revert IAppErrors.ItemEquipped(item, itemId);
  }

  function onlyNotConsumable(IItemController.ItemMeta memory meta, address item) internal pure {
    if (
      uint(meta.itemType) == 0
      || meta.itemMetaType == uint8(IItemController.ItemMetaType.CONSUMABLE) // todo probably first check is enough?
    ) revert IAppErrors.Consumable(item);
  }

  function checkPauseEoa(SenderInfo memory senderInfo, IController controller) internal view {
    onlyEOA(senderInfo.isEoa);
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
  }

  function onlyRegisteredControllers(ControllerContextLib.ControllerContext memory cc) internal view {
    if (
      msg.sender != address(ControllerContextLib.dungeonFactory(cc))
      && msg.sender != address(ControllerContextLib.reinforcementController(cc))
      && msg.sender != address(ControllerContextLib.pvpController(cc))
    ) revert IAppErrors.ErrorForbidden(msg.sender);
  }

  function checkRequirements(
    ControllerContextLib.ControllerContext memory cc,
    address hero,
    uint heroId,
    IStatController.CoreAttributes memory requirements
  ) internal view {
    IStatController.CoreAttributes memory attributes = ControllerContextLib.statController(cc).heroBaseAttributes(hero, heroId);
    if (
      requirements.strength > attributes.strength
      || requirements.dexterity > attributes.dexterity
      || requirements.vitality > attributes.vitality
      || requirements.energy > attributes.energy
    ) revert IAppErrors.RequirementsToItemAttributes();
  }

  /// @notice ensure that the user belongs to a guild, the guild has a shelter, the shelter has highest level 3
  function _onlyMemberOfGuildWithShelterMaxLevel(ControllerContextLib.ControllerContext memory cc, address msgSender) internal view {
    // ensure that signer belongs to a guild and the guild has a shelter of ANY level
    IGuildController gc = ControllerContextLib.guildController(cc);
    if (address(gc) == address(0)) revert IAppErrors.NotInitialized();

    uint guildId = gc.memberOf(msgSender);
    if (guildId == 0) revert IAppErrors.NotGuildMember();

    uint shelterId = gc.guildToShelter(guildId);
    if (shelterId == 0) revert IAppErrors.GuildHasNoShelter();

    // only highest level of shelters gives possibility to exit from dungeon
    (, uint8 shelterLevel,) = PackingLib.unpackShelterId(shelterId);
    if (shelterLevel != ShelterLib.MAX_SHELTER_LEVEL) revert IAppErrors.TooLowShelterLevel(shelterLevel, ShelterLib.MAX_SHELTER_LEVEL);
  }

  function onlyOwner(address token, uint tokenId, address sender) internal view {
    if (IERC721(token).ownerOf(tokenId) != sender) revert IAppErrors.ErrorNotOwner(token, tokenId);
  }

  /// @notice Ensure that the item belongs to the {sender} or the item is equipped on a hero that belongs to the given sender
  function onlyOwnerOrHero(address token, uint tokenId, address sender) internal view {
    address owner = IERC721(token).ownerOf(tokenId);
    if (owner != sender) {
      (address hero, uint heroId) = equippedOn(token, tokenId);
      if (hero == address(0) || IERC721(hero).ownerOf(heroId) != sender) {
        revert IAppErrors.ErrorNotOwnerOrHero(token, tokenId);
      }
    }
  }

  function onlyAliveHero(ControllerContextLib.ControllerContext memory cc, address hero, uint heroId) internal view {
    if (!ControllerContextLib.statController(cc).isHeroAlive(hero, heroId)) revert IAppErrors.ErrorHeroIsDead(hero, heroId);
  }

  /// @notice Hero belongs to the {sender} and
  /// 1) in sandbox mode: the item belongs to the same hero
  /// 2) in not sandbox mode: the item either belongs to the same sender
  /// or the item is sandbox item that belongs to the hero 2 (upgraded)
  /// and the hero 2 belongs to the same sender
  /// @param sandboxMode Sandbox mode of the given hero
  /// @param opts [checkIfHeroAlive, allowSandboxItemToBeEquipped]
  /// @return inSandbox True if the item is located in some sandbox (the hero or some other hero)
  function onlyItemOwner(
    ControllerContextLib.ControllerContext memory cc,
    ItemWithId memory itemData,
    address hero,
    uint heroId,
    address msgSender,
    IHeroController.SandboxMode sandboxMode,
    bool[2] memory opts
  ) internal view returns (bool inSandbox) {
    onlyOwner(hero, heroId, msgSender);

    if (opts[0]) { // checkIfHeroAlive
      ItemLib.onlyAliveHero(cc, hero, heroId);
    }

    bool checkSenderIsItemOwner;
    if (sandboxMode == IHeroController.SandboxMode.SANDBOX_MODE_1) {
      // the hero is in the sandbox mode, he can use only his own items from the sandbox
      inSandbox = _checkInSandbox(cc, itemData, hero, heroId);
      // not-upgraded hero has sandbox item outside of the sandbox .. it means the item is equipped on the hero
      if (!opts[1]) { // allowSandboxItemToBeEquipped
        // normally equipped items are not allowed
        if (!inSandbox) revert IAppErrors.SandboxItemAlreadyEquipped();
      }
    } else {
      // let's detect item owner
      (address hero2, uint heroId2) = ControllerContextLib.itemBoxController(cc).itemHero(itemData.item, itemData.itemId);
      if (hero2 == address(0)) {
        checkSenderIsItemOwner = true;
      } else if (hero2 == hero && heroId == heroId2) {
        inSandbox = _checkInSandbox(cc, itemData, hero, heroId);
      } else {
        IHeroController.SandboxMode sandboxMode2 = ItemLib._getSandboxMode(cc, hero2, heroId2);
        if (sandboxMode2 == IHeroController.SandboxMode.NORMAL_MODE_0) {
          checkSenderIsItemOwner = true;
        } else if (sandboxMode2 == IHeroController.SandboxMode.SANDBOX_MODE_1) {
          revert IAppErrors.SandboxModeNotAllowed();
        } else {
          inSandbox = _checkInSandbox(cc, itemData, hero2, heroId2);
          if (inSandbox) {
            onlyOwner(hero2, heroId2, msgSender);
          } else {
            checkSenderIsItemOwner = true;
          }
        }
      }

      if (checkSenderIsItemOwner) {
        onlyOwner(itemData.item, itemData.itemId, msgSender);
      }
    }

    return inSandbox;
  }

  function _checkInSandbox(
    ControllerContextLib.ControllerContext memory cc,
    ItemWithId memory itemData,
    address hero,
    uint heroId
  ) internal view returns (bool) {
    IItemBoxController.ItemState itemState = ControllerContextLib.itemBoxController(cc).itemState(hero, heroId, itemData.item, itemData.itemId);
    if (itemState == IItemBoxController.ItemState.NOT_REGISTERED_0) revert IAppErrors.SandboxItemNotRegistered();
    if (itemState == IItemBoxController.ItemState.NOT_AVAILABLE_1) revert IAppErrors.SandboxItemNotActive();
    return itemState == IItemBoxController.ItemState.INSIDE_2;
  }

  /// @notice Either both items belong to the {sender} or both sandbox-items belong to the same hero of the given {sender}
  /// @param allowEquippedItem {item} can be equipped (and so his owner is the hero, not the user)
  /// @return [item is in the sandbox, other item is in the sandbox]
  function _checkOwnerItems(
    ControllerContextLib.ControllerContext memory cc,
    ItemWithId memory item,
    ItemWithId memory otherItem,
    address sender,
    bool allowEquippedItem
  ) internal view returns (bool[2] memory) {
    (address hero1, uint heroId1, IHeroController.SandboxMode sandboxMode1, bool inSandbox1) = _checkSingleItem(cc, item, sender, allowEquippedItem);
    (address hero2, uint heroId2, IHeroController.SandboxMode sandboxMode2, bool inSandbox2) = _checkSingleItem(cc, otherItem, sender, false);

    if (sandboxMode1 == IHeroController.SandboxMode.SANDBOX_MODE_1 || sandboxMode2 == IHeroController.SandboxMode.SANDBOX_MODE_1) {
      if (hero1 != hero2 || heroId1 != heroId2) revert IAppErrors.SandboxDifferentHeroesNotAllowed();
    }

    return [inSandbox1, inSandbox2];
  }

  /// @dev a part of {_checkOwnerItems}
  /// @param allowEquippedItem {item} can be equipped (and so his owner is the hero, not the user)
  function _checkSingleItem(ControllerContextLib.ControllerContext memory cc, ItemWithId memory item, address sender, bool allowEquippedItem) internal view returns (
    address hero,
    uint heroId,
    IHeroController.SandboxMode sandboxMode,
    bool inSandbox
  ) {
    (hero, heroId) = ControllerContextLib.itemBoxController(cc).itemHero(item.item, item.itemId);

    sandboxMode = hero == address(0)
      ? IHeroController.SandboxMode.NORMAL_MODE_0
      : ItemLib._getSandboxMode(cc, hero, heroId);

    if (sandboxMode == IHeroController.SandboxMode.UPGRADED_TO_NORMAL_2 && IERC721(hero).ownerOf(heroId) != sender) {
      // SCR-1557: original hero was upgraded AND his item was sold to another user
      onlyOwner(item.item, item.itemId, sender);
    } else {
      inSandbox = hero != address(0) && onlyItemOwner(cc, item, hero, heroId, sender, sandboxMode, [true, allowEquippedItem]);

      if (hero == address(0)) {
        if (allowEquippedItem) {
          onlyOwnerOrHero(item.item, item.itemId, sender);
        } else {
          onlyOwner(item.item, item.itemId, sender);
        }
      } else {
        onlyOwner(hero, heroId, sender);
      }
    }

    return (hero, heroId, sandboxMode, inSandbox);
  }

  //endregion ------------------------ Restrictions

  //region ------------------------ STORAGE
  function _S() internal pure returns (IItemController.MainState storage s) {
    assembly {
      s.slot := MAIN_STORAGE_LOCATION
    }
    return s;
  }
  //endregion ------------------------ STORAGE

  //region ------------------------ View
  function equippedOn(address item, uint itemId) internal view returns (address hero, uint heroId) {
    return PackingLib.unpackNftId(_S().equippedOn[item.packNftId(itemId)]);
  }
  //endregion ------------------------ View

  //region ------------------------ Main logic

  /// @notice Mint new item, setup attributes, make extra setup if necessary (setup attack item, buff item)
  /// @param sender Dungeon Factory / User Controller / Guild Controller are allowed
  /// @param item Item to be minted
  /// @param recipient The item is minted for the given recipient
  /// @return itemId Id of the newly minted item
  function mintNewItem(
    IController controller,
    address sender,
    address item,
    address recipient,
    uint32 magicFind
  ) external returns (uint itemId) {
    IItemController.MainState storage s = _S();
    ControllerContextLib.ControllerContext memory ctx = ControllerContextLib.init(controller);

    address guildController = address(ControllerContextLib.guildController(ctx));
    address shelterController = guildController == address(0)
      ? address(0)
      : IGuildController(guildController).shelterController();

    if (
      address(ControllerContextLib.dungeonFactory(ctx)) != sender
      && address(ControllerContextLib.userController(ctx)) != sender
      && guildController != sender
      && shelterController != sender
      && address(ControllerContextLib.itemController(ctx)) != sender
      && address(ControllerContextLib.heroController(ctx)) != sender
    ) revert IAppErrors.MintNotAllowed();

    itemId = IItem(item).mintFor(recipient);

    IItemController.MintInfo memory info;

    (
      info.meta,
      info.attributesIds,
      info.attributesValues,
      info.itemRarity
    ) = _setupNewAttributes(s, item, itemId, magicFind, CalcLib.pseudoRandom);

    // setup extra info

    if (info.meta.itemMetaType == uint8(IItemController.ItemMetaType.ATTACK)) {
      info.attackInfo = unpackItemAttackInfo(_setupNewAttackItem(s, item, itemId));
    } else if (info.meta.itemMetaType == uint8(IItemController.ItemMetaType.BUFF)) {
      (
        info.casterIds,
        info.casterValues,
        info.targetIds,
        info.targetValues
      ) = _setupNewBuffItem(s, item, itemId, CalcLib.pseudoRandom);
    }
    // consumable stats unchangeable, get them by address

    emit IApplicationEvents.NewItemMinted(item, itemId, info);
  }

  /// @notice Mint random items, not more than {info.maxItems}
  function mintRandomItems(MintItemInfo memory info) internal returns (address[] memory) {
    return _mintRandomItems(info, CalcLib.nextPrng);
  }

  function applyActionMasks(
    uint actionMask,
    IStatController statController,
    address heroToken,
    uint heroTokenId
  ) external {
    if ((actionMask & (2 ** uint(IItemController.ConsumableActionBits.CLEAR_TEMPORARY_ATTRIBUTES_0))) != 0) {
      statController.clearTemporallyAttributes(heroToken, heroTokenId);
    }
  }

  function destroy(IController controller, address msgSender, address item, uint itemId) external {
    address owner = IERC721(item).ownerOf(itemId);
    address itemBox = controller.itemBoxController();
    bool sandbox = owner == itemBox;

    if (
      controller.gameObjectController() != msgSender
      && controller.storyController() != msgSender
    ) {
      if (sandbox) {
        (address hero, uint heroId) = IItemBoxController(itemBox).itemHero(item, itemId);
        address heroOwner = IERC721(hero).ownerOf(heroId);
        if (heroOwner != msgSender) revert IAppErrors.ErrorForbidden(msgSender);
      } else {
        if (owner != msgSender) revert IAppErrors.ErrorForbidden(msgSender);
      }
    }

    ItemLib.onlyNotEquippedItem(item, itemId);

    _destroy(ControllerContextLib.init(controller), item, itemId, sandbox);
  }

  /// @notice Destroy {consumed item} to augment given {item}.
  /// There is a chance of 30% that the item will be destroyed instead of augmentation.
  /// SCR-1263: Protective item allows to avoid item destruction in fail case - augmentation is reset instead.
  function augment(
    ItemLib.SenderInfo memory senderInfo,
    address controller_,
    address item,
    uint itemId,
    uint consumedItemId,
    IItemController.AugmentOptParams memory opt,
    IItemControllerHelper itemControllerHelper
  ) external {
    ControllerContextLib.ControllerContext memory cc = ControllerContextLib.init(IController(controller_));

    ( // restrictions are checked inside {_prepareToAugment}
      IItemController.ItemMeta memory meta,
      IItemController.ItemInfo memory _itemInfo,
      bool[2] memory inSandbox
    ) = _prepareToAugment(_S(), cc, senderInfo, item, itemId, consumedItemId, false);

    ItemLib.onlyNotConsumable(meta, item);
    if (_itemInfo.augmentationLevel >= MAX_AUGMENTATION_LEVEL) revert IAppErrors.TooHighAgLevel(_itemInfo.augmentationLevel);

    // ----------------- destroy consumable item
    ItemLib._destroy(cc, item, consumedItemId, inSandbox[1]);

    // do not send fee if protective item is used
    if (opt.protectiveItem == address(0)) { // ----------------- get augmentation fee
      address augToken = _sendFee(cc.controller, item, senderInfo.msgSender, 1);
      // we check augToken for 0 AFTER sendFee to avoid second reading of augmentInfo
      if (augToken == address(0)) revert IAppErrors.ZeroAugmentation();
    }

    // ----------------- check protective item if any
    bool protectiveInSandbox;
    if (opt.protectiveItem != address(0)) {
      // SCR-1263: If the item was augmented first time before introducing SCR-1263, _resetAugmentation is empty.
      // So, there is no way to use protective item.
      if (
        (_itemInfo.augmentationLevel != 0)
        && (0 == _S()._resetAugmentation[item.packNftId(itemId)].tsFirstAugmentation)
      ) revert IAppErrors.NoFirstAugmentationInfo();

      if (opt.protectiveItem != itemControllerHelper.getAugmentationProtectiveItem()) revert IAppErrors.NotAugmentationProtectiveItem(opt.protectiveItem);

      protectiveInSandbox = ItemLib._checkOwnerItems(cc, ItemLib.ItemWithId(item, itemId), ItemLib.ItemWithId(opt.protectiveItem, opt.protectiveItemId), senderInfo.msgSender, false)[1];
    }

    // ----------------- augmentation
    bytes32 packedItemId = item.packNftId(itemId);
    if (IOracle(ControllerContextLib.oracle(cc)).getRandomNumber(1e18, 0) < AUGMENT_CHANCE) {
      IItemController.AugmentInfo memory _augmentInfo = _applyAugmentation(_S(), packedItemId, meta, _itemInfo);
      emit IApplicationEvents.Augmented(item, itemId, consumedItemId, _itemInfo.augmentationLevel, _augmentInfo);
    } else {
      if (opt.protectiveItem != address(0)) {
        // protective item exists, so don't destroy base item but reduce its augmentation level to 0
        // and restore its attributes to original (stored before the first augmentation) values.
        if(_itemInfo.augmentationLevel != 0) {
          IItemController.AugmentInfo memory _augmentInfo = _resetAugmentation(_S(), packedItemId, meta, _itemInfo);
          emit IApplicationEvents.ResetAugmentation(item, itemId, consumedItemId, _augmentInfo);
        }
        // if augmentation level is zero we can perform it like nothing happened
      } else {
        ItemLib._destroy(cc, item, itemId, inSandbox[0]);
        emit IApplicationEvents.NotAugmented(item, itemId, consumedItemId, _itemInfo.augmentationLevel);
      }
    }

    // ----------------- destroy protective item
    if (opt.protectiveItem != address(0)) {
      ItemLib._destroy(cc, opt.protectiveItem, opt.protectiveItemId, protectiveInSandbox);
    }
  }
  //endregion ------------------------ Main logic

  //region ------------------------ Internal logic - augmentation
  /// @notice Decrease attribute values back to original values. Set augmentation level to 0
  function _resetAugmentation(
    IItemController.MainState storage s,
    bytes32 packedItemId,
    IItemController.ItemMeta memory meta,
    IItemController.ItemInfo memory _itemInfo
  ) internal returns (
    IItemController.AugmentInfo memory augmentInfo
  ) {
    // assume below that _itemInfo.augmentationLevel is not 0
    IItemController.ResetAugmentationData storage resetData = s._resetAugmentation[packedItemId];

    {
      bytes32[] memory data = resetData.itemAttributes;
      s._itemAttributes[packedItemId] = data;
      (augmentInfo.attributesValues, augmentInfo.attributesIds) = PackingLib.toInt32ArrayWithIds(data);
    }

    if (meta.itemMetaType == uint8(IItemController.ItemMetaType.ATTACK)) {
      bytes32 data = resetData.itemAttackInfo;
      s._itemAttackInfo[packedItemId] = data;
      augmentInfo.attackInfo = ItemLib.unpackItemAttackInfo(data);
    } else if (meta.itemMetaType == uint8(IItemController.ItemMetaType.BUFF)) {
      {
        bytes32[] memory data = resetData.itemCasterAttributes;
        s._itemCasterAttributes[packedItemId] = data;
        (augmentInfo.casterValues, augmentInfo.casterIds) = PackingLib.toInt32ArrayWithIds(data);
      }
      {
        bytes32[] memory data = resetData.itemTargetAttributes;
        s._itemTargetAttributes[packedItemId] = data;
        (augmentInfo.targetValues, augmentInfo.targetIds) = PackingLib.toInt32ArrayWithIds(data);
      }
    }

    // reset aug level
    _itemInfo.augmentationLevel = 0;
    s.itemInfo[packedItemId] = ItemLib.packItemInfo(_itemInfo);

    return augmentInfo;
  }

  /// @notice Successful augmentation - increase attribute values. Increase augmentation level.
  function _applyAugmentation(
    IItemController.MainState storage s,
    bytes32 packedItemId,
    IItemController.ItemMeta memory meta,
    IItemController.ItemInfo memory _itemInfo
  ) internal returns (
    IItemController.AugmentInfo memory augmentInfo
  ) {
    IItemController.ResetAugmentationData storage resetData = s._resetAugmentation[packedItemId];

    // SCR-1263: Save original attributes values before increasing to be able to restore them during augmentation reset.
    bool saveBeforeAugmentation = _itemInfo.augmentationLevel == 0 && resetData.tsFirstAugmentation == 0;

    { // augment base
      bytes32[] memory data = s._itemAttributes[packedItemId];
      (augmentInfo.attributesValues, augmentInfo.attributesIds) = _augmentAttributes(data, true);
      s._itemAttributes[packedItemId] = augmentInfo.attributesValues.toBytes32ArrayWithIds(augmentInfo.attributesIds);

      if (saveBeforeAugmentation) {
        resetData.tsFirstAugmentation = block.timestamp;
        resetData.itemAttributes = data;
      }
    }

    // additionally
    if (meta.itemMetaType == uint8(IItemController.ItemMetaType.ATTACK)) {
      bytes32 data = s._itemAttackInfo[packedItemId];
      augmentInfo.attackInfo = ItemLib.unpackItemAttackInfo(data);
      augmentInfo.attackInfo.min = _augmentAttribute(augmentInfo.attackInfo.min);
      augmentInfo.attackInfo.max = _augmentAttribute(augmentInfo.attackInfo.max);
      s._itemAttackInfo[packedItemId] = ItemLib.packItemAttackInfo(augmentInfo.attackInfo);
      if (saveBeforeAugmentation) {
        resetData.itemAttackInfo = data;
      }
    } else if (meta.itemMetaType == uint8(IItemController.ItemMetaType.BUFF)) {
      { // caster
        bytes32[] memory data = s._itemCasterAttributes[packedItemId];
        (augmentInfo.casterValues, augmentInfo.casterIds) = _augmentAttributes(data, true);
        s._itemCasterAttributes[packedItemId] = augmentInfo.casterValues.toBytes32ArrayWithIds(augmentInfo.casterIds);
        if (saveBeforeAugmentation) {
          resetData.itemCasterAttributes = data;
        }
      }

      { // target
        bytes32[] memory data = s._itemTargetAttributes[packedItemId];
        (augmentInfo.targetValues, augmentInfo.targetIds) = _augmentAttributes(data, false);
        s._itemTargetAttributes[packedItemId] = augmentInfo.targetValues.toBytes32ArrayWithIds(augmentInfo.targetIds);
        if (saveBeforeAugmentation) {
          resetData.itemTargetAttributes = data;
        }
      }
    }

    // increase aug level
    _itemInfo.augmentationLevel = _itemInfo.augmentationLevel + 1;
    s.itemInfo[packedItemId] = ItemLib.packItemInfo(_itemInfo);

    return augmentInfo;
  }

  /// @return augToken Return augToken to avoid repeat reading of augmentInfo inside augment()
  function _sendFee(
    IController controller,
    address item,
    address msgSender,
    uint divider
  ) internal returns (address augToken) {
    (address token, uint amount) = _S().augmentInfo[item].unpackAddressWithAmount();
    if (token != address(0)) {
      controller.process(token, amount / divider, msgSender);
    }
    return token;
  }


  /// @notice Initialization for augment() and repairDurability()
  /// Get {meta} and {info}, check some restrictions
  /// @return meta Metadata of the item
  /// @return info Unpacked item info
  /// @return inSandbox [item is in the sandbox, consumable item is in the sandbox]
  function _prepareToAugment(
    IItemController.MainState storage s_,
    ControllerContextLib.ControllerContext memory cc,
    ItemLib.SenderInfo memory senderInfo,
    address item,
    uint itemId,
    uint consumedItemId,
    bool allowEquippedItem
  ) internal view returns (
    IItemController.ItemMeta memory meta,
    IItemController.ItemInfo memory info,
    bool[2] memory inSandbox
  ) {
    ItemLib.checkPauseEoa(senderInfo, cc.controller);

    if (!allowEquippedItem) {
      ItemLib.onlyNotEquippedItem(item, itemId);
    }
    ItemLib.onlyNotEquippedItem(item, consumedItemId);

    inSandbox = ItemLib._checkOwnerItems(cc, ItemLib.ItemWithId(item, itemId), ItemLib.ItemWithId(item, consumedItemId), senderInfo.msgSender, allowEquippedItem);

    if (itemId == consumedItemId) revert IAppErrors.SameIdsNotAllowed();
    meta = ItemLib.unpackedItemMeta(s_.itemMeta[item]);
    info = ItemLib.unpackedItemInfo(s_.itemInfo[item.packNftId(itemId)]);

    return (meta, info, inSandbox);
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
  //endregion ------------------------ Internal logic - augmentation

  //region ------------------------ Internal logic
  function _destroy(ControllerContextLib.ControllerContext memory cc, address item, uint itemId, bool inSandbox) internal {
    if (inSandbox) {
      ControllerContextLib.itemBoxController(cc).destroyItem(item, itemId);
    } else {
      IItem(item).burn(itemId);
    }
    emit IApplicationEvents.Destroyed(item, itemId);
  }

  /// @param nextPrng_ CalcLib.nextPrng, param is required by unit tests
  function _mintRandomItems(
    MintItemInfo memory info,
    function (LibPRNG.PRNG memory, uint) internal view returns (uint) nextPrng_
  ) internal returns (address[] memory) {

    // if hero is not in his biome do not mint at all
    if (info.mintDropChanceDelta != 0) {
      return new address[](0);
    }

    uint len = info.mintItems.length;

    // Fisher–Yates shuffle
    LibPRNG.PRNG memory prng = LibPRNG.PRNG(info.oracle.getRandomNumber(CalcLib.MAX_CHANCE, info.seed));
    uint[] memory indices = new uint[](len);
    for (uint i = 1; i < len; ++i) {
      indices[i] = i;
    }
    LibPRNG.shuffle(prng, indices);

    address[] memory minted = new address[](len);
    uint mintedLength;
    uint di = Math.min(CalcLib.toUint(info.destroyItems), 100);

    for (uint i; i < len; ++i) {
      if (info.mintItemsChances[indices[i]] > CalcLib.MAX_CHANCE) {
        revert IAppErrors.TooHighChance(info.mintItemsChances[indices[i]]);
      }

      uint chance = _adjustChance(info.mintItemsChances[indices[i]], info, di);

      // need to call random in each loop coz each minted item should have dedicated chance
      uint rnd = nextPrng_(prng, CalcLib.MAX_CHANCE); // randomWithSeed_(CalcLib.MAX_CHANCE, rndSeed);

      if (chance != 0 && (chance >= CalcLib.MAX_CHANCE || rnd < chance)) {
        // There is no break here: the cycle is continued even if the number of the minted items reaches the max.
        // The reason: gas consumption of success operation must be great of equal of the gas consumption of fail op.
        if (mintedLength < info.maxItems) {
          minted[i] = info.mintItems[indices[i]];
          ++mintedLength;
        }
      }
    }

    address[] memory mintedAdjusted = new address[](mintedLength);
    uint j;
    for (uint i; i < len; ++i) {
      if (minted[i] != address(0)) {
        mintedAdjusted[j] = minted[i];
        ++j;
      }
    }

    return mintedAdjusted;
  }

  /// @notice Apply all corrections to the chance of item drop
  /// There are two params to increase chances: amplifier and magicFind
  /// There is single param to decrease chances: destroyItems
  /// @param di Assume that di <= 100
  function _adjustChance(uint32 itemChance, MintItemInfo memory info, uint di) internal pure returns (uint) {
    uint chance = uint(itemChance);
    chance += chance * info.amplifier / StatLib._MAX_AMPLIFIER;
    // now we use MF for increasing item quality instead of chance of drop
    // chance += chance * CalcLib.toUint(info.magicFind) / 100;
    chance -= chance * di / 100;
    return chance;
  }

  function _setupNewAttributes(
    IItemController.MainState storage s,
    address item,
    uint itemId,
    uint32 magicFind,
    function (uint) internal view returns (uint) random_
  ) internal returns (
    IItemController.ItemMeta memory meta,
    uint8[] memory ids,
    int32[] memory values,
    IItemController.ItemRarity itemRarity
  ){
    meta = unpackedItemMeta(s.itemMeta[item]);
    (ids, values, itemRarity) = _generateAttributes(unpackItemGenerateInfo(s.generateInfoAttributes[item]), meta, magicFind, random_);

    bytes32 packedItemId = item.packNftId(itemId);
    if (ids.length != 0) {
      s._itemAttributes[packedItemId] = values.toBytes32ArrayWithIds(ids);
    }

    s.itemInfo[packedItemId] = PackingLib.packItemInfo(uint8(itemRarity), 0, meta.baseDurability);
  }

  function _setupNewAttackItem(IItemController.MainState storage s, address item, uint itemId) internal returns (bytes32 attackInfo){
    // we just write data for attack item, no need to generate, it will be augmented later so need individual data for itemId
    attackInfo = s.generateInfoAttack[item];
    s._itemAttackInfo[item.packNftId(itemId)] = attackInfo;
  }

  function _setupNewBuffItem(
    IItemController.MainState storage s,
    address item,
    uint itemId,
    function (uint) internal view returns (uint) random_
  ) internal returns (
    uint8[] memory casterIds,
    int32[] memory casterValues,
    uint8[] memory targetIds,
    int32[] memory targetValues
  ){

    // CASTER
    (casterIds, casterValues) = _generateSimpleAttributes(
      unpackItemGenerateInfo(s.generateInfoCasterAttributes[item]),
      true,
      random_
    );

    if (casterIds.length != 0) {
      s._itemCasterAttributes[item.packNftId(itemId)] = casterValues.toBytes32ArrayWithIds(casterIds);
    }

    // TARGET
    (targetIds, targetValues) = _generateSimpleAttributes(
      unpackItemGenerateInfo(s.generateInfoTargetAttributes[item]),
      true,
      random_
    );

    if (targetIds.length != 0) {
      s._itemTargetAttributes[item.packNftId(itemId)] = targetValues.toBytes32ArrayWithIds(targetIds);
    }
  }

  /// @notice Generate all mandatory attributes and try to generate required number of random attributes.
  /// Generate at least {info.minRandomAttributes} of random attributes if it's possible
  /// but not more than {info.maxRandomAttributes}. Value of each attribute is generated randomly according its chances.
  /// @param meta Assume, that meta.min != 0, meta.max != 0 and both meta.min and meta.min should have same sign
  /// because results value cannot be 0
  /// @return ids Ids of the attributes, zero id is allowed
  /// @return values Randomly generated attributes values, min <= value <= max
  /// @return itemRarity Rarity of the item (Either meta.defaultRarity or calculated if there is no default rarity)
  function _generateAttributes(
    IItemController.ItemGenerateInfo memory info,
    IItemController.ItemMeta memory meta,
    uint32 magicFind,
    function (uint) internal view returns (uint) random_
  ) internal view returns (
    uint8[] memory ids,
    int32[] memory values,
    IItemController.ItemRarity itemRarity
  ) {
    GenerateAttributesContext memory ctx;

    uint len = info.ids.length;
    if (len != 0) {
      ctx.ids = new uint8[](len);
      ctx.values = new int32[](len);
      ctx.usedIndexes = new bool[](len);
      ctx.magicFind = magicFind;

      // Fisher–Yates shuffle
      _shuffleInfo(info, random_);

      // initialize ctx by initial values
      // generate all mandatory attributes, try to generate not more than {meta.maxRandomAttributes} random attributes
      _prepareAttributes(info, meta.maxRandomAttributes, ctx, random_);

      // generate missing random attributes if it's necessary, ctx.counter is incremented
      _generateMissingRandomAttributes(info, meta.minRandomAttributes, ctx, random_);

      itemRarity = meta.defaultRarity == 0
        ? _calculateRarity(ctx.raritySum, ctx.randomAttrCounter, meta.maxRandomAttributes)
        : IItemController.ItemRarity(meta.defaultRarity);
    } else {
      itemRarity = IItemController.ItemRarity.UNKNOWN;
    }

    (ids, values) = _fixLengthsIdsValues(ctx.ids, ctx.values, ctx.counter);
  }

  /// @notice Generate missing random attributes if necessary
  function _generateMissingRandomAttributes(
    IItemController.ItemGenerateInfo memory info,
    uint8 minRandomAttributes,
    GenerateAttributesContext memory ctx,
    function (uint) internal view returns (uint) random_
  ) internal view {
    uint attrToGen = Math.min(ctx.totalRandomAttrsPossible, minRandomAttributes);
    if (ctx.randomAttrCounter < attrToGen && ctx.totalRandomAttrsPossible > ctx.randomAttrCounter) {
      // it's necessary AND possible to generate more random attributes
      uint possibleRemainingAttrs = ctx.totalRandomAttrsPossible - ctx.randomAttrCounter;
      uint remainingAttrsToGen = attrToGen - ctx.randomAttrCounter;

      uint[] memory indicesToGen = new uint[](possibleRemainingAttrs);
      uint indicesToGenCounter;

      // enumerate all attributes, add all indices of not-generated attributes to {indexesToGen}
      for (uint i; i < info.ids.length; ++i) {
        // mandatory attrs should be already generated and no need to check
        if (!ctx.usedIndexes[i]) {
          indicesToGen[indicesToGenCounter] = i;
          indicesToGenCounter++;
        }
      }

      // Shuffle indices of not-generated attributes using Fisher–Yates shuffle
      if (possibleRemainingAttrs > 1) {
        for (uint i; i < possibleRemainingAttrs - 1; ++i) {
          uint randomIndex = CalcLib.pseudoRandomInRangeFlex(i, possibleRemainingAttrs - 1, random_);
          (indicesToGen[randomIndex], indicesToGen[i]) = (indicesToGen[i], indicesToGen[randomIndex]);
        }
      }
      // Generate necessary amount of attributes. Fist (shuffled) attributes are selected (MAX_CHANCE is used for each)
      for (uint i; i < remainingAttrsToGen; ++i) {
        uint idx = indicesToGen[i];
        (int32 attr,) = _generateAttribute(info.mins[idx], info.maxs[idx], CalcLib.MAX_CHANCE, ctx.magicFind, random_);
        ctx.ids[ctx.counter] = info.ids[idx];
        ctx.values[ctx.counter] = attr;
        ctx.counter++;
      }
    }
  }

  /// @notice Generate all mandatory attributes, generate not more than {meta.maxRandomAttributes} random attributes.
  /// Updates context:
  ///   {ctx.totalRandomAttrsPossible} - total number of possible random attributes
  ///   {ctx.randomAttrCounter} - total number of generated random attributes  <= {maxRandomAttributes}
  ///   {ctx.randomSum} = sum of random of all random attributes.
  ///   {ctx.chancesSum} = sum of chances of all random attributes.
  ///   {ctx.counter} = total number of generated attributes. Values of ctx.ids, ctx.values, ctx.usedIndexes are
  ///   initialized in the range [0...ctx.counter)
  /// @param ctx Empty struct but arrays ids, values and usedIndexes should be allocated for info.ids.length items
  function _prepareAttributes(
    IItemController.ItemGenerateInfo memory info,
    uint8 maxRandomAttributes,
    GenerateAttributesContext memory ctx,
    function (uint) internal view returns (uint) random_
  ) internal view {
    uint len = info.ids.length;
    for (uint i; i < len; ++i) {
      if (info.chances[i] != CalcLib.MAX_CHANCE) {
        ctx.totalRandomAttrsPossible++;
      }

      if (info.chances[i] >= CalcLib.MAX_CHANCE || !ctx.stopGenerateRandom) {
        (int32 attr, uint rarity) = _generateAttribute(info.mins[i], info.maxs[i], info.chances[i], ctx.magicFind, random_);

        // count only random attributes for calc rarity
        if (attr != 0) {

          if (
            info.chances[i] < CalcLib.MAX_CHANCE
            // && random != 0 // commented: random = 0 can produce crash in _generateMissingRandomAttributes
          ) {
            ctx.randomAttrCounter++;
            ctx.raritySum += rarity;
          }
          ctx.ids[ctx.counter] = info.ids[i];
          ctx.values[ctx.counter] = attr;
          ctx.counter++;
          ctx.usedIndexes[i] = true;
        }

        // it is a bit less fair random for attrs in the end of the list, however we assume it should be pretty rare case
        if (ctx.randomAttrCounter == maxRandomAttributes) {
          ctx.stopGenerateRandom = true;
        }
      }
    }
  }

  /// @notice Shuffle info arrays using Fisher–Yates shuffle algo
  function _shuffleInfo(
    IItemController.ItemGenerateInfo memory info,
    function (uint) internal view returns (uint) random_
  ) internal view {
    uint len = info.ids.length;
    if (len > 1) {
      for (uint i; i < len - 1; i++) {
        uint randomIndex = CalcLib.pseudoRandomInRangeFlex(i, len - 1, random_);

        (info.ids[randomIndex], info.ids[i]) = (info.ids[i], info.ids[randomIndex]);
        (info.mins[randomIndex], info.mins[i]) = (info.mins[i], info.mins[randomIndex]);
        (info.maxs[randomIndex], info.maxs[i]) = (info.maxs[i], info.maxs[randomIndex]);
        (info.chances[randomIndex], info.chances[i]) = (info.chances[i], info.chances[randomIndex]);
      }
    }
  }

  /// @notice Generate array [0,1,2.. N-1] and shuffle it using Fisher–Yates shuffle algo
  function _shuffleIndices(
    uint countItems,
    function (uint) internal view returns (uint) random_
  ) internal view returns (uint[] memory indices){
    indices = new uint[](countItems);
    for (uint i = 1; i < countItems; ++i) {
      indices[i] = i;
    }
    if (countItems > 1) {
      for (uint i; i < countItems - 1; i++) {
        uint randomIndex = CalcLib.pseudoRandomInRangeFlex(i, countItems - 1, random_);
        (indices[randomIndex], indices[i]) = (indices[i], indices[randomIndex]);
      }
    }
  }

  /// @notice Reduce lengths of {ids} and {values} to {count}
  function _fixLengthsIdsValues(uint8[] memory ids, int32[] memory values, uint count) internal pure returns (
    uint8[] memory idsOut,
    int32[] memory valuesOut
  ) {
    if (count == ids.length) {
      return (ids, values);
    }

    idsOut = new uint8[](count);
    valuesOut = new int32[](count);
    for (uint i; i < count; ++i) {
      idsOut[i] = ids[i];
      valuesOut[i] = values[i];
    }
    return (idsOut, valuesOut);
  }

  /// @param random_ Pass CalcLib.pseudoRandom here, param is required for unit tests. Max value is MAX_CHANCE
  function _generateSimpleAttributes(
    IItemController.ItemGenerateInfo memory info,
    bool maxChance,
    function (uint) internal view returns (uint) random_
  ) internal view returns (
    uint8[] memory ids,
    int32[] memory values
  ) {
    uint len = info.ids.length;
    ids = new uint8[](len);
    values = new int32[](len);

    uint n = 0;
    for (uint i; i < len; ++i) {
      (int32 attr,) = _generateAttribute(
        info.mins[i],
        info.maxs[i],
        maxChance ? CalcLib.MAX_CHANCE : info.chances[i],
        0,
        random_
      );
      if (attr != 0) {
        ids[n] = info.ids[i];
        values[n] = attr;
        ++n;
      }
    }

    return _fixLengthsIdsValues(ids, values, n);
  }

  //endregion ------------------------ Internal logic

  //region ------------------------ Internal utils
  /// @param baseChance Chance in the range [0...MAX_CHANCE], MAX_CHANCE=1e9 means "mandatory" element.
  /// @param random_ Pass CalcLib.pseudoRandom here, param is required for unit tests
  /// @return attr Either 0 or min <= attr <= max
  /// @return rarity Value in the range [0...MAX_CHANCE]; It's always 0 for mandatory elements
  function _generateAttribute(
    int32 min,
    int32 max,
    uint32 baseChance,
    uint32 magicFind,
    function (uint) internal view returns (uint) random_
  ) internal view returns (
    int32 attr,
    uint rarity
  ) {
    if (baseChance > CalcLib.MAX_CHANCE) revert IAppErrors.TooHighChance(baseChance);
    uint diff = uint(CalcLib.absDiff(min, max));
    uint32 bonus = _mfBonus(magicFind); // 0..MAX_CHANCE

    uint32 adjChance = baseChance + uint32(uint256(baseChance) * bonus / CalcLib.MAX_CHANCE);
    if (adjChance > CalcLib.MAX_CHANCE) adjChance = CalcLib.MAX_CHANCE;

    uint32 random = CalcLib.pseudoRandomUint32Flex(CalcLib.MAX_CHANCE, random_);

    if (random >= adjChance && adjChance < CalcLib.MAX_CHANCE) {
      return (0, 0);
    }

    // refresh for full random
    random = CalcLib.pseudoRandomUint32Flex(CalcLib.MAX_CHANCE, random_);

    uint scaled = uint(random) * (CalcLib.MAX_CHANCE - bonus) / CalcLib.MAX_CHANCE;

    uint boxSize = (adjChance / (diff + 1));
    if (boxSize == 0) {
      boxSize = 1;
    }
    uint box = scaled / boxSize; // 0 … diff (rounded down)
    if (box > diff) {
      box = diff;
    }
    int32 k = int32(int(diff - box));
    attr = min + k;

    if (diff == 0 || baseChance >= CalcLib.MAX_CHANCE) {
      // chance == CalcLib.MAX_CHANCE => mandatory element
      // return zero random - no need to calc rarity for mandatory elements
      rarity = 0;
    } else {
      rarity = uint32(uint(int(k)) * uint(CalcLib.MAX_CHANCE) / diff);
    }

    return (attr, rarity);
  }

  /// @dev 0 .. MAX_CHANCE
  function _mfBonus(uint32 mf) internal pure returns (uint32) {
    uint256 C = 300; // a normal average MF value on heroes
    return uint32(uint256(CalcLib.MAX_CHANCE) * mf / (mf + C));
  }

  /// @notice Calculate item rarity
  /// @param raritySum Total sum rarity values of all random attributes in ItemGenerateInfo, [0...MAX_CHANCE/attrCounter]
  /// @param attrCounter Count of random attributes in ItemGenerateInfo
  /// @param maxAttr Index of max allowed random attribute (all attributes with higher indices are not random)
  /// @return item rarity
  function _calculateRarity(uint raritySum, uint attrCounter, uint maxAttr) internal pure returns (
    IItemController.ItemRarity
  ) {
    if (attrCounter == 0) {
      return IItemController.ItemRarity.NORMAL;
    }

    uint averageRarity = raritySum / attrCounter;

    if (averageRarity > CalcLib.MAX_CHANCE) revert IAppErrors.TooHighRandom(averageRarity);

    if (averageRarity > (CalcLib.MAX_CHANCE - CalcLib.MAX_CHANCE / 10) && attrCounter == maxAttr) {
      return IItemController.ItemRarity.RARE;
    } else if (averageRarity > (CalcLib.MAX_CHANCE - CalcLib.MAX_CHANCE / 2)) {
      return IItemController.ItemRarity.MAGIC;
    } else {
      return IItemController.ItemRarity.NORMAL;
    }
  }

  function _getSandboxMode(ControllerContextLib.ControllerContext memory cc, address hero, uint heroId) internal view returns (
    IHeroController.SandboxMode sandboxMode
  ) {
    return IHeroController.SandboxMode(ControllerContextLib.heroController(cc).sandboxMode(hero, heroId));
  }
  //endregion ------------------------ Internal utils

  //region ------------------------ PACKING

  function packItemGenerateInfo(IItemController.ItemGenerateInfo memory info) internal pure returns (bytes32[] memory result) {
    uint len = info.ids.length;
    if (len != info.mins.length || len != info.maxs.length || len != info.chances.length) {
      revert IAppErrors.LengthsMismatch();
    }

    result = new bytes32[](len);

    for (uint i; i < len; ++i) {
      result[i] = PackingLib.packItemGenerateInfo(info.ids[i], info.mins[i], info.maxs[i], info.chances[i]);
    }
  }

  function unpackItemGenerateInfo(bytes32[] memory gen) internal pure returns (
    IItemController.ItemGenerateInfo memory
  ) {
    uint length = gen.length;

    uint8[] memory ids = new uint8[](length);
    int32[] memory mins = new int32[](length);
    int32[] memory maxs = new int32[](length);
    uint32[] memory chances = new uint32[](length);

    for (uint i; i < length; ++i) {
      (ids[i], mins[i], maxs[i], chances[i]) = gen[i].unpackItemGenerateInfo();
    }

    return IItemController.ItemGenerateInfo(ids, mins, maxs, chances);
  }

  function packItemMeta(IItemController.ItemMeta memory meta) internal pure returns (bytes32) {
    return PackingLib.packItemMeta(
      meta.itemMetaType,
      meta.itemLevel,
      uint8(meta.itemType),
      meta.baseDurability,
      meta.defaultRarity,
      meta.minRandomAttributes,
      meta.maxRandomAttributes,
      meta.manaCost,
      meta.requirements
    );
  }

  function unpackedItemMeta(bytes32 meta) internal pure returns (IItemController.ItemMeta memory result) {
    return meta.unpackItemMeta();
  }

  function packItemInfo(IItemController.ItemInfo memory info) internal pure returns (bytes32) {
    return PackingLib.packItemInfo(uint8(info.rarity), info.augmentationLevel, info.durability);
  }

  function unpackedItemInfo(bytes32 info) internal pure returns (IItemController.ItemInfo memory result) {
    uint8 rarity;
    (rarity, result.augmentationLevel, result.durability) = info.unpackItemInfo();

    result.rarity = IItemController.ItemRarity(rarity);
    return result;
  }

  function packItemAttackInfo(IItemController.AttackInfo memory info) internal pure returns (bytes32) {
    return PackingLib.packItemAttackInfo(
      uint8(info.aType),
      info.min,
      info.max,
      info.attributeFactors.strength,
      info.attributeFactors.dexterity,
      info.attributeFactors.vitality,
      info.attributeFactors.energy
    );
  }

  function unpackItemAttackInfo(bytes32 info) internal pure returns (IItemController.AttackInfo memory result) {
    IStatController.CoreAttributes memory fs;
    uint8 aType;
    (aType, result.min, result.max, fs.strength, fs.dexterity, fs.vitality, fs.energy) = info.unpackItemAttackInfo();

    result.aType = IItemController.AttackType(aType);
    result.attributeFactors = fs;

    return result;
  }
  //endregion ------------------------ PACKING
}
