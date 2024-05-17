// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../openzeppelin/Math.sol";
import "../openzeppelin/EnumerableSet.sol";
import "../interfaces/IItemController.sol";
import "../interfaces/IStatController.sol";
import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../lib/StatLib.sol";

/// @notice Implementation of StatController
library StatControllerLib {
  using StatLib for uint;
  using StatLib for uint[];
  using StatLib for uint32;
  using StatLib for int32;
  using StatLib for int32;
  using CalcLib for uint;
  using CalcLib for int;
  using CalcLib for int32;
  using EnumerableSet for EnumerableSet.AddressSet;
  using PackingLib for bytes32[];
  using PackingLib for bytes32;
  using PackingLib for int32;
  using PackingLib for uint32;

  //region ------------------------ Constants
  /// @dev keccak256(abi.encode(uint256(keccak256("stat.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant MAIN_STORAGE_LOCATION = 0xca9e8235a410bd2656fc43f888ab589425034944963c2881072ee821e700e600;

  int32 public constant LEVEL_UP_SUM = 5;
  bytes32 public constant KARMA_HASH = bytes32("KARMA");
  bytes32 public constant HERO_CLASS_HASH = bytes32("HERO_CLASS");
  //endregion ------------------------ Constants

  //region ------------------------ RESTRICTIONS

  function onlyRegisteredContract(IController controller_) internal view {
    address sender = msg.sender;
    if (
      controller_.heroController() != sender
      && controller_.itemController() != sender
      && controller_.dungeonFactory() != sender
      && controller_.storyController() != sender
      && controller_.gameObjectController() != sender
    ) revert IAppErrors.ErrorForbidden(sender);
  }

  function onlyItemController(IController controller_) internal view {
    if (controller_.itemController() != msg.sender) revert IAppErrors.ErrorNotItemController(msg.sender);
  }

  function onlyHeroController(IController controller_) internal view {
    if (controller_.heroController() != msg.sender) revert IAppErrors.ErrorNotHeroController(msg.sender);
  }
  //endregion ------------------------ RESTRICTIONS

  //region ------------------------ VIEWS
  function _S() internal pure returns (IStatController.MainState storage s) {
    assembly {
      s.slot := MAIN_STORAGE_LOCATION
    }
    return s;
  }

  function heroAttributes(IStatController.MainState storage s, address token, uint tokenId) internal view returns (int32[] memory) {
    return PackingLib.toInt32Array(s.heroTotalAttributes[PackingLib.packNftId(token, tokenId)], uint(IStatController.ATTRIBUTES.END_SLOT));
  }

  function heroBonusAttributes(IStatController.MainState storage s, address token, uint tokenId) internal view returns (int32[] memory) {
    return PackingLib.toInt32Array(s.heroBonusAttributes[PackingLib.packNftId(token, tokenId)], uint(IStatController.ATTRIBUTES.END_SLOT));
  }

  function heroTemporallyAttributes(IStatController.MainState storage s, address token, uint tokenId) internal view returns (int32[] memory) {
    return PackingLib.toInt32Array(s.heroTemporallyAttributes[PackingLib.packNftId(token, tokenId)], uint(IStatController.ATTRIBUTES.END_SLOT));
  }


  function heroAttributesLength(address /*token*/, uint /*tokenId*/) internal pure returns (uint) {
    return uint(IStatController.ATTRIBUTES.END_SLOT);
  }

  function heroAttribute(IStatController.MainState storage s, address token, uint tokenId, uint index) internal view returns (int32) {
    return PackingLib.getInt32(s.heroTotalAttributes[PackingLib.packNftId(token, tokenId)], index);
  }

  function heroBaseAttributes(IStatController.MainState storage s, address token, uint tokenId) internal view returns (
    IStatController.CoreAttributes memory core
  ) {
    int32[] memory data = PackingLib.unpackInt32Array(s._heroCore[PackingLib.packNftId(token, tokenId)]);
    core = IStatController.CoreAttributes({
      strength: int32(data[0]),
      dexterity: int32(data[1]),
      vitality: int32(data[2]),
      energy: int32(data[3])
    });
  }

  function heroCustomData(IStatController.MainState storage s, address token, uint tokenId, bytes32 index) internal view returns (uint) {
    return s.heroCustomData[PackingLib.packNftId(token, tokenId)][index];
  }

  function globalCustomData(IStatController.MainState storage s, bytes32 index) internal view returns (uint) {
    return s.globalCustomData[index];
  }

  function heroStats(IStatController.MainState storage s, address token, uint tokenId) internal view returns (
    IStatController.ChangeableStats memory result
  ) {
    uint32[] memory data = PackingLib.unpackUint32Array(s.heroStats[PackingLib.packNftId(token, tokenId)]);
    result = IStatController.ChangeableStats({
      level: uint32(data[0]),
      experience: uint32(data[1]),
      life: uint32(data[2]),
      mana: uint32(data[3]),
      lifeChances: uint32(data[4])
    });
  }

  function heroItemSlot(IStatController.MainState storage s, address heroToken, uint64 heroTokenId, uint8 itemSlot) internal view returns (
    bytes32 nftPacked
  ) {
    return s.heroSlots[PackingLib.packMapObject(heroToken, heroTokenId, itemSlot)];
  }

  /// @return Return list of indices of the busy item slots for the given hero
  function heroItemSlots(IStatController.MainState storage s, address heroToken, uint heroTokenId) internal view returns (
    uint8[] memory
  ) {
    uint8[] memory slots = PackingLib.unpackUint8Array(s.heroBusySlots[PackingLib.packNftId(heroToken, heroTokenId)]);

    uint8[] memory busySlotsNumbers = new uint8[](slots.length);
    uint counter;

    for (uint8 i; i < uint8(slots.length); ++i) {
      if (slots[i] != 0) {
        busySlotsNumbers[counter] = i;
        counter++;
      }
    }

    uint8[] memory result = new uint8[](counter);

    for (uint i; i < counter; ++i) {
      result[i] = busySlotsNumbers[i];
    }

    return result;
  }

  function isHeroAlive(IStatController.MainState storage s, address heroToken, uint heroTokenId) internal view returns (bool) {
    return heroStats(s, heroToken, heroTokenId).lifeChances != 0;
  }

  function isConsumableUsed(IStatController.MainState storage s, address heroToken, uint heroTokenId, address item) internal view returns (bool) {
    return s.usedConsumables[PackingLib.packNftId(heroToken, heroTokenId)].contains(item);
  }

  /// @notice Calculate totalAttributes + all attributes of the items specified in {info}
  function buffHero(
    IStatController.MainState storage s,
    IController c,
    IStatController.BuffInfo memory info
  ) internal view returns (
    int32[] memory dest,
    int32 manaSum
  ) {
    uint length = info.buffTokens.length;
    if (length == 0) {
      return (heroAttributes(s, info.heroToken, info.heroTokenId), 0);
    }

    IItemController ic = IItemController(c.itemController());

    int32[] memory buffAttributes = new int32[](uint(IStatController.ATTRIBUTES.END_SLOT));
    address[] memory usedTokens = new address[](length);

    for (uint i; i < length; ++i) {

      // we should ignore the same skills
      bool used;
      for(uint j; j < i; ++j) {
        if (usedTokens[j] == info.buffTokens[i]) {
          used = true;
          break;
        }
      }
      if(used) {
        continue;
      }


      manaSum += int32(ic.itemMeta(info.buffTokens[i]).manaCost);
      (int32[] memory values, uint8[] memory ids) = ic.casterAttributes(info.buffTokens[i], info.buffTokenIds[i]);
      StatLib.attributesAdd(buffAttributes, StatLib.valuesToFullAttributesArray(values, ids));
      usedTokens[i] = info.buffTokens[i];
    }

    int32[] memory totalAttributes = StatLib.attributesAdd(heroAttributes(s, info.heroToken, info.heroTokenId), buffAttributes);

    StatLib.attributesAdd(buffAttributes, heroBonusAttributes(s, info.heroToken, info.heroTokenId));
    StatLib.attributesAdd(buffAttributes, heroTemporallyAttributes(s, info.heroToken, info.heroTokenId));

    return (
      StatLib.updateCoreDependAttributesInMemory(
        totalAttributes,
        buffAttributes,
        IHeroController(c.heroController()).heroClass(info.heroToken),
        info.heroLevel
      ),
      manaSum
    );
  }

  //endregion ------------------------ VIEWS

  //region ------------------------ PURE

  function isItemTypeEligibleToItemSlot(uint itemType, uint itemSlot) internal pure returns (bool) {
    // Consumable items not eligible
    if (itemType == 0 || itemSlot == 0) {
      return false;
    }
    // items with type before 5 mapped 1 to 1
    if (itemType <= uint(IItemController.ItemType.AMULET)) {
      return itemSlot == itemType;
    }
    if (itemType == uint(IItemController.ItemType.RING)) {
      return itemSlot == uint(IStatController.ItemSlots.RIGHT_RING)
        || itemSlot == uint(IStatController.ItemSlots.LEFT_RING);
    }
    if (itemType == uint(IItemController.ItemType.BOOTS)) {
      return itemSlot == uint(IStatController.ItemSlots.BOOTS);
    }
    if (itemType == uint(IItemController.ItemType.ONE_HAND)) {
      return itemSlot == uint(IStatController.ItemSlots.RIGHT_HAND);
    }
    if (itemType == uint(IItemController.ItemType.OFF_HAND)) {
      return itemSlot == uint(IStatController.ItemSlots.LEFT_HAND);
    }
    if (itemType == uint(IItemController.ItemType.TWO_HAND)) {
      return itemSlot == uint(IStatController.ItemSlots.TWO_HAND);
    }
    if (itemType == uint(IItemController.ItemType.SKILL)) {
      return itemSlot == uint(IStatController.ItemSlots.SKILL_1)
      || itemSlot == uint(IStatController.ItemSlots.SKILL_2)
        || itemSlot == uint(IStatController.ItemSlots.SKILL_3);
    }
    // unknown types
    return false;
  }

  /// @notice How much experience is required to go from the {level} to the next level
  function levelUpExperienceRequired(uint32 level) internal pure returns (uint) {
    if (level == 0 || level >= StatLib.MAX_LEVEL) return 0;
    return level == uint32(1)
      ? StatLib.levelExperience(level)
      : StatLib.levelExperience(level) - StatLib.levelExperience(level - uint32(1));
  }

  //endregion ------------------------ PURE

  //region ------------------------ ACTIONS

  /// @notice Initialize new hero, set up custom data, core data, changeable stats by default value
  /// @param heroClass [1..6], see StatLib.initHeroXXX
  function initNewHero(
    IStatController.MainState storage s,
    IController c,
    address heroToken,
    uint heroTokenId,
    uint heroClass
  ) internal {
    StatControllerLib.onlyHeroController(c);

    bytes32 heroPackedId = PackingLib.packNftId(heroToken, heroTokenId);
    _initNewHeroCore(s, heroPackedId, heroClass);

    bytes32[] storage totalAttributes = s.heroTotalAttributes[heroPackedId];
    uint32[] memory baseStats = StatLib.initAttributes(totalAttributes, heroClass, 1, heroClass.initialHero().core);

    _initChangeableStats(s, heroPackedId, baseStats);
    emit IApplicationEvents.NewHeroInited(heroToken, heroTokenId, IStatController.ChangeableStats({
      level: 1,
      experience: 0,
      life: baseStats[0],
      mana: baseStats[1],
      lifeChances: baseStats[2]
    }));

    // --- init predefined custom hero data

    mapping(bytes32 => uint) storage customData = s.heroCustomData[heroPackedId];

    // set initial karma
    customData[KARMA_HASH] = 1000;
    emit IApplicationEvents.HeroCustomDataChanged(heroToken, heroTokenId, KARMA_HASH, 1000);

    // set hero class as parameter for stories
    customData[HERO_CLASS_HASH] = heroClass;
    emit IApplicationEvents.HeroCustomDataChanged(heroToken, heroTokenId, HERO_CLASS_HASH, heroClass);
  }

  function _initNewHeroCore(IStatController.MainState storage s, bytes32 heroPackedId, uint heroClass) internal {
    IStatController.CoreAttributes memory initialCore = heroClass.initialHero().core;
    int32[] memory arr = new int32[](4);

    arr[0] = int32(initialCore.strength);
    arr[1] = int32(initialCore.dexterity);
    arr[2] = int32(initialCore.vitality);
    arr[3] = int32(initialCore.energy);

    s._heroCore[heroPackedId] = PackingLib.packInt32Array(arr);
  }

  function _initChangeableStats(IStatController.MainState storage s, bytes32 heroPackedId, uint32[] memory baseStats) internal {
    _changeChangeableStats(s, heroPackedId, 1, 0, baseStats[0], baseStats[1], baseStats[2]);
  }

  function _changeChangeableStats(
    IStatController.MainState storage s,
    bytes32 heroPackedId,
    uint32 level,
    uint32 experience,
    uint32 life,
    uint32 mana,
    uint32 lifeChances
  ) internal {
    if(lifeChances != 0 && life == 0) {
      life = 1;
    }
    uint32[] memory data = new uint32[](5);
    data[0] = level;
    data[1] = experience;
    data[2] = life;
    data[3] = mana;
    data[4] = lifeChances;

    s.heroStats[heroPackedId] = PackingLib.packUint32Array(data);
  }

  /// @notice Add/remove the item to/from the hero
  function changeHeroItemSlot(
    IStatController.MainState storage s,
    IController controller,
    address heroToken,
    uint64 heroTokenId,
    uint itemType,
    uint8 itemSlot,
    address itemToken,
    uint itemTokenId,
    bool equip
  ) internal {
    StatControllerLib.onlyItemController(controller);
    if (!StatControllerLib.isItemTypeEligibleToItemSlot(itemType, itemSlot)) revert IAppErrors.ErrorItemNotEligibleForTheSlot(itemType, itemSlot);

    // if we are going to take an item by two hands, we need both hands free.
    // if we are going to use only one hand, we shouldn't keep anything by two hands
    if (itemSlot == uint(IStatController.ItemSlots.TWO_HAND)) {
      if (heroItemSlot(s, heroToken, heroTokenId, uint8(IStatController.ItemSlots.RIGHT_HAND)) != bytes32(0)
        || heroItemSlot(s, heroToken, heroTokenId, uint8(IStatController.ItemSlots.LEFT_HAND)) != bytes32(0)) {
        revert IAppErrors.ErrorItemSlotBusyHand(itemSlot);
      }
    }
    if (itemSlot == uint(IStatController.ItemSlots.RIGHT_HAND) || itemSlot == uint(IStatController.ItemSlots.LEFT_HAND)) {
      if (heroItemSlot(s, heroToken, heroTokenId, uint8(IStatController.ItemSlots.TWO_HAND)) != bytes32(0)) {
        revert IAppErrors.ErrorItemSlotBusyHand(itemSlot);
      }
    }

    bytes32 heroPackedId = PackingLib.packNftId(heroToken, heroTokenId);
    (address equippedItem, uint equippedItemId) = PackingLib.unpackNftId(heroItemSlot(s, heroToken, heroTokenId, itemSlot));
    if (equip) {
      if (equippedItem != address(0)) revert IAppErrors.ErrorItemSlotBusy();

      s.heroSlots[PackingLib.packMapObject(heroToken, uint64(heroTokenId), itemSlot)] = PackingLib.packNftId(itemToken, itemTokenId);
      s.heroBusySlots[heroPackedId] = PackingLib.changeUnit8ArrayWithCheck(s.heroBusySlots[heroPackedId], itemSlot, 1, 0);
    } else {
      if (equippedItem != itemToken || equippedItemId != itemTokenId) revert IAppErrors.ErrorItemNotInSlot();

      delete s.heroSlots[PackingLib.packMapObject(heroToken, uint64(heroTokenId), itemSlot)];
      s.heroBusySlots[heroPackedId] = PackingLib.changeUnit8ArrayWithCheck(s.heroBusySlots[heroPackedId], itemSlot, 0, 1);
    }

    emit IApplicationEvents.HeroItemSlotChanged(heroToken, heroTokenId, itemType, itemSlot, itemToken, itemTokenId, equip, msg.sender);
  }

  /// @notice Increase or decrease stats (life, mana, lifeChances). Experience can be increased only.
  function changeCurrentStats(
    IStatController.MainState storage s,
    IController c,
    address heroToken,
    uint heroTokenId,
    IStatController.ChangeableStats memory change,
    bool increase
  ) internal {
    StatControllerLib.onlyRegisteredContract(c);

    bytes32 heroPackedId = PackingLib.packNftId(heroToken, heroTokenId);
    IStatController.ChangeableStats memory currentStats = heroStats(s, heroToken, heroTokenId);

    uint32 life = currentStats.life;
    uint32 mana = currentStats.mana;
    uint32 lifeChances = currentStats.lifeChances;

    if (increase) {
      bytes32[] storage attrs = s.heroTotalAttributes[heroPackedId];
      int32 maxLife = attrs.getInt32(uint(IStatController.ATTRIBUTES.LIFE));
      int32 maxMana = attrs.getInt32(uint(IStatController.ATTRIBUTES.MANA));
      int32 maxLC = attrs.getInt32(uint(IStatController.ATTRIBUTES.LIFE_CHANCES));

      currentStats.experience += change.experience;
      life = uint32(Math.min(maxLife.toUint(), uint(life + change.life)));
      mana = uint32(Math.min(maxMana.toUint(), uint(mana + change.mana)));
      lifeChances = uint32(Math.min(maxLC.toUint(), uint(lifeChances + change.lifeChances)));
    } else {
      if (change.experience != 0) revert IAppErrors.ErrorExperienceMustNotDecrease();
      life = life > change.life ? life - change.life : 0;
      lifeChances = lifeChances > change.lifeChances ? lifeChances - change.lifeChances : 0;
      mana = mana > change.mana ? mana - change.mana : 0;
    }

    _changeChangeableStats(s, heroPackedId, currentStats.level, currentStats.experience, life, mana, lifeChances);
    emit IApplicationEvents.CurrentStatsChanged(heroToken, heroTokenId, change, increase, msg.sender);
  }

  /// @notice Mark consumable {item} as used
  function registerConsumableUsage(
    IStatController.MainState storage s,
    IController c,
    address heroToken,
    uint heroTokenId,
    address item
  ) internal {
    StatControllerLib.onlyRegisteredContract(c);

    if (!s.usedConsumables[PackingLib.packNftId(heroToken, heroTokenId)].add(item)) revert IAppErrors.ErrorConsumableItemIsUsed(item);
    emit IApplicationEvents.ConsumableUsed(heroToken, heroTokenId, item);
  }

  /// @notice Clear all consumable items of the given hero
  function clearUsedConsumables(
    IStatController.MainState storage s,
    IController c,
    address heroToken,
    uint heroTokenId
  ) internal {
    StatControllerLib.onlyRegisteredContract(c);

    EnumerableSet.AddressSet storage items = s.usedConsumables[PackingLib.packNftId(heroToken, heroTokenId)];

    uint length = items.length();

    for (uint i; i < length; ++i) {
      // we are removing the first element, so it's safe to use in cycle
      address item = items.at(0);
      if (!items.remove(item)) revert IAppErrors.ErrorCannotRemoveItemFromMap();
      emit IApplicationEvents.RemoveConsumableUsage(heroToken, heroTokenId, item);
    }
  }

  /// @notice Increase or decrease values of the given attributes, any attributes are allowed.
  /// @dev If a core attribute is changed than depended attributes are recalculated
  function changeBonusAttributes(
    IStatController.MainState storage s,
    IController c,
    IStatController.ChangeAttributesInfo memory info
  ) internal {
    StatControllerLib.onlyRegisteredContract(c);
    bytes32 heroPackedId = PackingLib.packNftId(info.heroToken, info.heroTokenId);

    IStatController.ChangeableStats memory stats = heroStats(s, info.heroToken, info.heroTokenId);
    bytes32[] storage totalAttributes = s.heroTotalAttributes[heroPackedId];
    (bytes32[] storage bonusMain, bytes32[] storage bonusExtra) = info.temporally
      ? (s.heroTemporallyAttributes[heroPackedId], s.heroBonusAttributes[heroPackedId])
      : (s.heroBonusAttributes[heroPackedId], s.heroTemporallyAttributes[heroPackedId]);

    int32[] memory cachedTotalAttrChanged = new int32[](info.changeAttributes.length);
    for (uint i; i < info.changeAttributes.length; ++i) {
      int32 change = info.changeAttributes[i];
      if (change != 0) {
        int32 newTotalValue;

        if (info.add) {
          bonusMain.changeInt32(i, change);
          newTotalValue = totalAttributes.getInt32(i) + change;
        } else {
          bonusMain.changeInt32(i, - change);
          newTotalValue = totalAttributes.getInt32(i) - change;
        }

        // todo in some cases value stored here to totalAttributes will be overwritten below by updateCoreDependAttributes
        // it happens if core attribute is changed AND it's depend attribute is change too
        // values of the depend attribute will be overwritten by updateCoreDependAttributes
        // fix it together with PACKED WRITING
        totalAttributes.setInt32(i, newTotalValue);
        cachedTotalAttrChanged[i] = newTotalValue;
      }
    }

    _updateCoreDependAttributes(c, totalAttributes, bonusMain, bonusExtra, stats, info.heroToken, cachedTotalAttrChanged, info.changeAttributes);
    _compareStatsWithAttributes(s, heroPackedId, totalAttributes, stats);

    emit IApplicationEvents.BonusAttributesChanged(info.heroToken, info.heroTokenId, info.add, info.temporally, msg.sender);
  }

  /// @dev Make sure we don't have life/mana more than total attributes after decreasing
  function _compareStatsWithAttributes(
    IStatController.MainState storage s,
    bytes32 heroPackedId,
    bytes32[] storage totalAttributes,
    IStatController.ChangeableStats memory curStats
  ) internal {
    uint life = totalAttributes.getInt32(uint(IStatController.ATTRIBUTES.LIFE)).toUint();
    uint mana = totalAttributes.getInt32(uint(IStatController.ATTRIBUTES.MANA)).toUint();
    bool changed;
    if (life < curStats.life) {
      curStats.life = uint32(Math.min(life, curStats.life));
      changed = true;
    }
    if (mana < curStats.mana) {
      curStats.mana = uint32(Math.min(mana, curStats.mana));
      changed = true;
    }
    if (changed) {
      _changeChangeableStats(s,
        heroPackedId,
        curStats.level,
        curStats.experience,
        curStats.life,
        curStats.mana,
        curStats.lifeChances
      );
    }
  }

  function clearTemporallyAttributes(
    IStatController.MainState storage s,
    IController c,
    address heroToken,
    uint heroTokenId
  ) internal {
    StatControllerLib.onlyRegisteredContract(c);
    bytes32 heroPackedId = PackingLib.packNftId(heroToken, heroTokenId);

    bytes32[] memory tmpBonuses = s.heroTemporallyAttributes[heroPackedId];

    IStatController.ChangeableStats memory stats = heroStats(s, heroToken, heroTokenId);
    bytes32[] storage bonus = s.heroBonusAttributes[heroPackedId];
    bytes32[] storage totalAttributes = s.heroTotalAttributes[heroPackedId];

    int32[] memory baseValues = new int32[](uint(IStatController.ATTRIBUTES.END_SLOT));
    int32[] memory tmpBonusesUnpacked = new int32[](uint(IStatController.ATTRIBUTES.END_SLOT));
    for (uint i; i < uint(IStatController.ATTRIBUTES.END_SLOT); ++i) {
      int32 value = tmpBonuses.getInt32Memory(i);
      if (value != int32(0)) {
        (baseValues[i],) = totalAttributes.changeInt32(i, - int32(uint32(value)));
        tmpBonusesUnpacked[i] = value;
      }
    }

    delete s.heroTemporallyAttributes[heroPackedId];

    bytes32[] storage tmpBonusesStorage = s.heroTemporallyAttributes[heroPackedId];

    _updateCoreDependAttributes(c, totalAttributes, bonus, tmpBonusesStorage, stats, heroToken, baseValues, tmpBonusesUnpacked);
    _compareStatsWithAttributes(s, heroPackedId, totalAttributes, stats);

    emit IApplicationEvents.TemporallyAttributesCleared(heroToken, heroTokenId, msg.sender);
  }

  /// @dev Update depend-values for all changed attributes
  function _updateCoreDependAttributes(
    IController c,
    bytes32[] storage totalAttributes,
    bytes32[] storage bonusMain,
    bytes32[] storage bonusExtra,
    IStatController.ChangeableStats memory stats,
    address heroToken,
    int32[] memory baseValues,
    int32[] memory changed
  ) internal {
    // handle core depend attributes in the second loop, totalAttributes should be updated together
    uint len = changed.length;
    for (uint i; i < len; ++i) {
      // depend-values should be recalculated if corresponded core value is changed (even if it's equal to 0 now)
      if (changed[i] != 0) {
        StatLib.updateCoreDependAttributes(c, totalAttributes, bonusMain, bonusExtra, stats, i, heroToken, baseValues[i]);
      }
    }
  }

  function levelUp(
    IStatController.MainState storage s,
    IController c,
    address heroToken,
    uint heroTokenId,
    uint heroClass,
    IStatController.CoreAttributes memory change
  ) internal returns (uint newLvl) {
    StatControllerLib.onlyHeroController(c);

    bytes32 heroPackedId = PackingLib.packNftId(heroToken, heroTokenId);
    if (change.strength + change.dexterity + change.vitality + change.energy != LEVEL_UP_SUM) revert IAppErrors.ErrorWrongLevelUpSum();

    IStatController.ChangeableStats memory currentStats = heroStats(s, heroToken, heroTokenId);

    if (currentStats.level >= StatLib.MAX_LEVEL) revert IAppErrors.ErrorMaxLevel();
    if (currentStats.level.levelExperience() > currentStats.experience) revert IAppErrors.ErrorNotEnoughExperience();
    currentStats.level++;

    {
      int32[] memory data = PackingLib.unpackInt32Array(s._heroCore[heroPackedId]);

      data[0] += change.strength;
      data[1] += change.dexterity;
      data[2] += change.vitality;
      data[3] += change.energy;

      s._heroCore[heroPackedId] = PackingLib.packInt32Array(data);
    }

    bytes32[] storage totalAttributes = s.heroTotalAttributes[heroPackedId];
    {
      bytes32[] storage bonus = s.heroBonusAttributes[heroPackedId];
      bytes32[] storage bonusTmp = s.heroTemporallyAttributes[heroPackedId];

      // update
      _addCoreToTotal(
        c,
        totalAttributes,
        bonus,
        bonusTmp,
        currentStats,
        heroToken,
        change.strength,
        uint(IStatController.ATTRIBUTES.STRENGTH)
      );
      _addCoreToTotal(
        c,
        totalAttributes,
        bonus,
        bonusTmp,
        currentStats,
        heroToken,
        change.dexterity,
        uint(IStatController.ATTRIBUTES.DEXTERITY)
      );
      _addCoreToTotal(
        c,
        totalAttributes,
        bonus,
        bonusTmp,
        currentStats,
        heroToken,
        change.vitality,
        uint(IStatController.ATTRIBUTES.VITALITY)
      );
      _addCoreToTotal(
        c,
        totalAttributes,
        bonus,
        bonusTmp,
        currentStats,
        heroToken,
        change.energy,
        uint(IStatController.ATTRIBUTES.ENERGY)
      );
    }

    // setup new level and restore life/mana
    currentStats.life = uint32(totalAttributes.getInt32(uint(IStatController.ATTRIBUTES.LIFE)).toUint());
    currentStats.mana = uint32(totalAttributes.getInt32(uint(IStatController.ATTRIBUTES.MANA)).toUint());

    _changeChangeableStats(
      s,
      heroPackedId,
      currentStats.level,
      currentStats.experience,
      currentStats.life,
      currentStats.mana,
      currentStats.lifeChances
    );

    emit IApplicationEvents.LevelUp(heroToken, heroTokenId, heroClass, change);

    return currentStats.level;
  }

  function _addCoreToTotal(
    IController c,
    bytes32[] storage totalAttributes,
    bytes32[] storage bonus,
    bytes32[] storage bonusTmp,
    IStatController.ChangeableStats memory stats,
    address heroToken,
    int32 changeValue,
    uint attrIndex
  ) internal {
    if (changeValue != 0) {
      (int32 newValue,) = totalAttributes.changeInt32(attrIndex, int32(uint32(changeValue)));
      StatLib.updateCoreDependAttributes(c, totalAttributes, bonus, bonusTmp, stats, attrIndex, heroToken, newValue);
    }
  }

  function setHeroCustomData(
    IStatController.MainState storage s,
    IController c,
    address token,
    uint tokenId,
    bytes32 index,
    uint value
  ) internal {
    StatControllerLib.onlyRegisteredContract(c);

    if (index == KARMA_HASH && value == 0) {
      revert IAppErrors.ErrorZeroKarmaNotAllowed();
    }

    s.heroCustomData[PackingLib.packNftId(token, tokenId)][index] = value;

    emit IApplicationEvents.HeroCustomDataChanged(token, tokenId, index, value);
  }

  function setGlobalCustomData(
    IStatController.MainState storage s,
    IController c,
    bytes32 index,
    uint value
  ) internal {
    StatControllerLib.onlyRegisteredContract(c);

    s.globalCustomData[index] = value;

    emit IApplicationEvents.GlobalCustomDataChanged(index, value);
  }
  //endregion ------------------------ ACTIONS
}
