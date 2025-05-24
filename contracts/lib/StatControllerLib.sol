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
  using EnumerableMap for EnumerableMap.Bytes32ToUintMap;
  using PackingLib for bytes32[];
  using PackingLib for bytes32;
  using PackingLib for int32;
  using PackingLib for uint32;

  //region ------------------------ Constants
  /// @dev keccak256(abi.encode(uint256(keccak256("stat.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant MAIN_STORAGE_LOCATION = 0xca9e8235a410bd2656fc43f888ab589425034944963c2881072ee821e700e600;

  int32 public constant LEVEL_UP_SUM = 5;
  bytes32 public constant KARMA_HASH = bytes32("KARMA");
  uint internal constant DEFAULT_KARMA_VALUE = 1000;

  /// @notice Virtual data, value is not stored to hero custom data, heroClass is taken from heroController by the index
  bytes32 public constant HERO_CLASS_HASH = bytes32("HERO_CLASS");

  /// @notice Custom data of the hero. Value is incremented on every life-chance lost
  bytes32 public constant DEATH_COUNT_HASH = bytes32("DEATH_COUNT");

  /// @notice Custom data of the hero. Value is locate in Banfoot dungeon
  bytes32 public constant DUNGEON_BANFOOT = bytes32("DUNG_BF");

  /// @notice Custom data of the hero. Value is locate in Enfitilia dungeon
  bytes32 public constant DUNGEON_ENFITILIA = bytes32("DUNG_EN");

  /// @notice Custom data of the hero. Value is locate in Askra dungeon
  bytes32 public constant DUNGEON_ASKRA = bytes32("DUNG_AS");
  //endregion ------------------------ Constants

  //region ------------------------ RESTRICTIONS

  function onlyRegisteredContract(IController controller_) internal view returns (IHeroController) {
    // using of ControllerContextLib.ControllerContext increases size of the contract on 0.5 kb
    address sender = msg.sender;
    address heroController = controller_.heroController();
    if (
      heroController != sender
      && controller_.itemController() != sender
      && controller_.dungeonFactory() != sender
      && controller_.storyController() != sender
      && controller_.gameObjectController() != sender
      && controller_.pvpController() != sender
    ) revert IAppErrors.ErrorForbidden(sender);

    return IHeroController(heroController);
  }

  function onlyItemController(IController controller_) internal view {
    if (controller_.itemController() != msg.sender) revert IAppErrors.ErrorNotItemController(msg.sender);
  }

  function onlyHeroController(IController controller_) internal view returns (IHeroController) {
    address heroController = controller_.heroController();
    if (heroController != msg.sender) revert IAppErrors.ErrorNotHeroController(msg.sender);
    return IHeroController(heroController);
  }

  function onlyDeployer(IController controller) internal view {
    if (!controller.isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
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

  function heroCustomData(IHeroController hc, address hero, uint heroId, bytes32 index) internal view returns (uint) {
    return heroCustomDataOnNgLevel(hc, hero, heroId, index, hc.getHeroInfo(hero, heroId).ngLevel);
  }

  function heroCustomDataOnNgLevel(IHeroController hc, address hero, uint heroId, bytes32 index, uint8 ngLevel) internal view returns (uint) {
    if (index == HERO_CLASS_HASH) {
      return hc.heroClass(hero);
    } else {
      (, uint value) = _S().heroCustomDataV2[PackingLib.packNftIdWithValue(hero, heroId, ngLevel)].tryGet(index);

      if (index == KARMA_HASH && value == 0) {
        return DEFAULT_KARMA_VALUE;
      }

      return value;
    }
  }


  function getAllHeroCustomData(IHeroController hc, address hero, uint heroId) internal view returns (bytes32[] memory keys, uint[] memory values) {
    // Result doesn't include HERO_CLASS_HASH
    EnumerableMap.Bytes32ToUintMap storage map = _S().heroCustomDataV2[PackingLib.packNftIdWithValue(hero, heroId, hc.getHeroInfo(hero, heroId).ngLevel)];
    uint length = map.length();
    keys = new bytes32[](length);
    values = new uint[](length);
    for (uint i; i < length; ++i) {
      (keys[i], values[i]) = map.at(i);
    }
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
    IController controller,
    IStatController.BuffInfo calldata info
  ) external view returns (
    int32[] memory dest,
    int32 manaSum
  ) {
    uint length = info.buffTokens.length;
    if (length == 0) {
      return (heroAttributes(s, info.heroToken, info.heroTokenId), 0);
    }

    IItemController ic = IItemController(controller.itemController());

    int32[] memory buffAttributes = new int32[](uint(IStatController.ATTRIBUTES.END_SLOT));
    address[] memory usedTokens = new address[](length);

    for (uint i; i < length; ++i) {

      // we should ignore the same skills
      bool used;
      for (uint j; j < i; ++j) {
        if (usedTokens[j] == info.buffTokens[i]) {
          used = true;
          break;
        }
      }
      if (used) {
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
        IHeroController(controller.heroController()).heroClass(info.heroToken),
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

  /// @param heroClass Assume that heroController passes correct value of the heroClass for the given hero
  /// Also assume that the hero exists and alive
  function reborn(IController controller, address hero, uint heroId, uint heroClass) external {
    IStatController.MainState storage s = _S();
    bytes32 heroPackedId = PackingLib.packNftId(hero, heroId);

    IHeroController heroController = onlyHeroController(controller);
    if (_S().heroBusySlots[heroPackedId] != 0) revert IAppErrors.EquippedItemsExist();

    uint32 lifeChances = heroStats(s, hero, heroId).lifeChances;

    // -------------------------- clear
    delete s.heroTotalAttributes[heroPackedId];
    delete s.heroTemporallyAttributes[heroPackedId];
    delete s.heroBonusAttributes[heroPackedId];

    // -------------------------- init from zero
    uint32[] memory baseStats = _initCoreAndAttributes(s, heroPackedId, heroClass);
    _changeChangeableStats(
      s,
      heroPackedId,
      1, // level is set to 1
      0, // experience is set to 0
      baseStats[0], // life is restored
      baseStats[1], // mana is restored
      lifeChances// life chances are not changed
    );

    // custom data is NOT cleared on reborn, new custom data map is used on each new NG_LVL
    _prepareHeroCustomDataForNextNgLevel(heroController, hero, heroId);
  }

  function _prepareHeroCustomDataForNextNgLevel(IHeroController heroController, address hero, uint heroId) internal {
    // assume here, that statController.reborn is called AFTER incrementing of NG_LVL, current NG_LVL has "new" value
    uint8 newNgLevel = heroController.getHeroInfo(hero, heroId).ngLevel;
    if (newNgLevel == 0) revert IAppErrors.ZeroValueNotAllowed(); // edge case
    uint8 prevNgLevel = newNgLevel - 1;

    // copy value of DEATH_COUNT from current ng-level to next ng-level
    (bool exist, uint value) = _S().heroCustomDataV2[PackingLib.packNftIdWithValue(hero, heroId, prevNgLevel)].tryGet(DEATH_COUNT_HASH);
    if (exist && value != 0) {
      _S().heroCustomDataV2[PackingLib.packNftIdWithValue(hero, heroId, newNgLevel)].set(DEATH_COUNT_HASH, value);
      emit IApplicationEvents.HeroCustomDataChangedNg(hero, heroId, DEATH_COUNT_HASH, value, newNgLevel);
    }

    // leave KARMA equal to 0 on next ng-level, getter returns default karma in this case
    emit IApplicationEvents.HeroCustomDataChangedNg(hero, heroId, KARMA_HASH, DEFAULT_KARMA_VALUE, newNgLevel);
  }

  /// @notice Keep stories, monsters, DEATH_COUNT_HASH and HERO_CLASS_HASH; remove all other custom data
  function _removeAllHeroCustomData(IHeroController hc, address hero, uint heroId) internal {
    EnumerableMap.Bytes32ToUintMap storage data = _S().heroCustomDataV2[PackingLib.packNftIdWithValue(hero, heroId, hc.getHeroInfo(hero, heroId).ngLevel)];
    uint length = data.length();
    bytes32[] memory keysToRemove = new bytes32[](length);
    bytes32 monsterPrefix = bytes32(abi.encodePacked("MONSTER_")); // 8 bytes
    bytes32 storyPrefix = bytes32(abi.encodePacked("STORY_")); // 6 bytes

    for (uint i; i < length; ++i) {
      (bytes32 key,) = data.at(i);
      if (key == DEATH_COUNT_HASH || key == HERO_CLASS_HASH) continue;

      bool isNotMonster;
      bool isNotStory;
      for (uint j; j < 8; j++) {
        if (!isNotMonster && key[j] != monsterPrefix[j]) {
          isNotMonster = true;
        }
        if (!isNotStory && j < 6 && key[j] != storyPrefix[j]) {
          isNotStory = true;
        }
        if (isNotMonster && isNotStory) break;
      }

      if (isNotMonster && isNotStory) {
        keysToRemove[i] = key;
      }
    }

    for (uint i; i < length; ++i) {
      if (keysToRemove[i] != bytes32(0)) {
        data.remove(keysToRemove[i]);
      }
    }

    emit IApplicationEvents.HeroCustomDataCleared(hero, heroId);
  }

  /// @notice Initialize new hero, set up custom data, core data, changeable stats by default value
  /// @param heroClass [1..6], see StatLib.initHeroXXX
  function initNewHero(
    IStatController.MainState storage s,
    IController c,
    address heroToken,
    uint heroTokenId,
    uint heroClass
  ) external {
    IHeroController heroController = onlyHeroController(c);

    bytes32 heroPackedId = PackingLib.packNftId(heroToken, heroTokenId);
    uint32[] memory baseStats = _initCoreAndAttributes(s, heroPackedId, heroClass);

    _changeChangeableStats(s, heroPackedId, 1, 0, baseStats[0], baseStats[1], baseStats[2]);

    emit IApplicationEvents.NewHeroInited(heroToken, heroTokenId, IStatController.ChangeableStats({
      level: 1,
      experience: 0,
      life: baseStats[0],
      mana: baseStats[1],
      lifeChances: baseStats[2]
    }));

    // --- init predefined custom hero data
    _initNewHeroCustomData(s, heroController, heroToken, heroTokenId);
  }

  /// @dev Reset custom hero data if something went wrong
  function resetHeroCustomData(
    IStatController.MainState storage s,
    IController c,
    address heroToken,
    uint heroTokenId
  ) external {
    onlyDeployer(c);
    _removeAllHeroCustomData(IHeroController(c.heroController()), heroToken, heroTokenId);
    _initNewHeroCustomData(s, IHeroController(c.heroController()), heroToken, heroTokenId);
  }

  function _initNewHeroCustomData(IStatController.MainState storage s, IHeroController heroController, address hero, uint heroId) internal {
    uint8 ngLevel = heroController.getHeroInfo(hero, heroId).ngLevel;
    bytes32 heroPackedIdValue = PackingLib.packNftIdWithValue(hero, heroId, ngLevel);

    EnumerableMap.Bytes32ToUintMap storage customData = s.heroCustomDataV2[heroPackedIdValue];

    // set initial karma
    customData.set(KARMA_HASH, DEFAULT_KARMA_VALUE);
    emit IApplicationEvents.HeroCustomDataChangedNg(hero, heroId, KARMA_HASH, DEFAULT_KARMA_VALUE, ngLevel);

    // HERO_CLASS_HASH is not used as custom data anymore, getter takes value directly from heroController

    // set death count value
    // customData[DEATH_COUNT_HASH] is initialized by 0 by default
    emit IApplicationEvents.HeroCustomDataChangedNg(hero, heroId, DEATH_COUNT_HASH, 0, ngLevel);
  }

  function _initCoreAndAttributes(IStatController.MainState storage s, bytes32 heroPackedId, uint heroClass) internal returns (
    uint32[] memory baseStats
  ){
    _initNewHeroCore(s, heroPackedId, heroClass);
    bytes32[] storage totalAttributes = s.heroTotalAttributes[heroPackedId];
    return StatLib.initAttributes(totalAttributes, heroClass, 1, heroClass.initialHero().core);
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

  function _changeChangeableStats(
    IStatController.MainState storage s,
    bytes32 heroPackedId,
    uint32 level,
    uint32 experience,
    uint32 life,
    uint32 mana,
    uint32 lifeChances
  ) internal {
    if (lifeChances != 0 && life == 0) {
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
    onlyItemController(controller);
    if (!isItemTypeEligibleToItemSlot(itemType, itemSlot)) revert IAppErrors.ErrorItemNotEligibleForTheSlot(itemType, itemSlot);

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
    onlyRegisteredContract(c);

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

      // Assume that Life Chances can be increased only by 1 per use.
      // Some stories and events can allow users to increase life chance above max...
      // Such attempts should be forbidden on UI side, we just silently ignore them here, no revert
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
    onlyRegisteredContract(c);

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
    onlyRegisteredContract(c);

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
    IHeroController heroController = onlyRegisteredContract(c);
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

    _updateCoreDependAttributes(heroController.heroClass(info.heroToken), totalAttributes, bonusMain, bonusExtra, stats, cachedTotalAttrChanged, info.changeAttributes);
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
    IHeroController heroController = onlyRegisteredContract(c);
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

    _updateCoreDependAttributes(heroController.heroClass(heroToken), totalAttributes, bonus, tmpBonusesStorage, stats, baseValues, tmpBonusesUnpacked);
    _compareStatsWithAttributes(s, heroPackedId, totalAttributes, stats);

    emit IApplicationEvents.TemporallyAttributesCleared(heroToken, heroTokenId, msg.sender);
  }

  /// @dev Update depend-values for all changed attributes
  function _updateCoreDependAttributes(
    uint heroClass,
    bytes32[] storage totalAttributes,
    bytes32[] storage bonusMain,
    bytes32[] storage bonusExtra,
    IStatController.ChangeableStats memory stats,
    int32[] memory baseValues,
    int32[] memory changed
  ) internal {
    // handle core depend attributes in the second loop, totalAttributes should be updated together
    uint len = changed.length;
    for (uint i; i < len; ++i) {
      // depend-values should be recalculated if corresponded core value is changed (even if it's equal to 0 now)
      if (changed[i] != 0) {
        StatLib.updateCoreDependAttributes(totalAttributes, bonusMain, bonusExtra, stats, i, heroClass, baseValues[i]);
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
    onlyHeroController(c);

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
        heroClass,
        totalAttributes,
        bonus,
        bonusTmp,
        currentStats,
        change.strength,
        uint(IStatController.ATTRIBUTES.STRENGTH)
      );
      _addCoreToTotal(
        heroClass,
        totalAttributes,
        bonus,
        bonusTmp,
        currentStats,
        change.dexterity,
        uint(IStatController.ATTRIBUTES.DEXTERITY)
      );
      _addCoreToTotal(
        heroClass,
        totalAttributes,
        bonus,
        bonusTmp,
        currentStats,
        change.vitality,
        uint(IStatController.ATTRIBUTES.VITALITY)
      );
      _addCoreToTotal(
        heroClass,
        totalAttributes,
        bonus,
        bonusTmp,
        currentStats,
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

  /// @notice scb-1009: Update current values of Life and mana during reinforcement as following:
  /// Reinforcement increases max value of life/mana on DELTA, current value of life/mana is increased on DELTA too
  /// @param prevAttributes Hero attributes before reinforcement
  function restoreLifeAndMana(
    IStatController.MainState storage s,
    IController c,
    address heroToken,
    uint heroTokenId,
    int32[] memory prevAttributes
  ) external {
    onlyRegisteredContract(c);

    IStatController.ChangeableStats memory currentStats = heroStats(s, heroToken, heroTokenId);
    bytes32 heroPackedId = PackingLib.packNftId(heroToken, heroTokenId);

    // assume here that totalAttributes were already updated during reinforcement
    // and so max values of life and mana were increased on delta1 and delta2
    bytes32[] storage totalAttributes = s.heroTotalAttributes[heroPackedId];

    // now increase current values of life and mana on delta1 and delta2 too
    currentStats.life += _getPositiveDelta(totalAttributes.getInt32(uint(IStatController.ATTRIBUTES.LIFE)), prevAttributes[uint(IStatController.ATTRIBUTES.LIFE)]);
    currentStats.mana += _getPositiveDelta(totalAttributes.getInt32(uint(IStatController.ATTRIBUTES.MANA)), prevAttributes[uint(IStatController.ATTRIBUTES.MANA)]);

    _changeChangeableStats(
      s,
      heroPackedId,
      currentStats.level,
      currentStats.experience,
      currentStats.life,
      currentStats.mana,
      currentStats.lifeChances
    );
  }

  function _getPositiveDelta(int32 a, int32 b) internal pure returns (uint32) {
    return a < b
      ? 0
      : uint32(uint(int(a - b)));
  }

  function _addCoreToTotal(
    uint heroClass,
    bytes32[] storage totalAttributes,
    bytes32[] storage bonus,
    bytes32[] storage bonusTmp,
    IStatController.ChangeableStats memory stats,
    int32 changeValue,
    uint attrIndex
  ) internal {
    if (changeValue != 0) {
      (int32 newValue,) = totalAttributes.changeInt32(attrIndex, int32(uint32(changeValue)));
      StatLib.updateCoreDependAttributes(totalAttributes, bonus, bonusTmp, stats, attrIndex, heroClass, newValue);
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
    IHeroController heroController = onlyRegisteredContract(c);
    uint8 ngLevel = heroController.getHeroInfo(token, tokenId).ngLevel;

    if (index == KARMA_HASH && value == 0) {
      revert IAppErrors.ErrorZeroKarmaNotAllowed();
    }

    s.heroCustomDataV2[PackingLib.packNftIdWithValue(token, tokenId, ngLevel)].set(index, value);
    emit IApplicationEvents.HeroCustomDataChangedNg(token, tokenId, index, value, ngLevel);
  }

  function setGlobalCustomData(
    IStatController.MainState storage s,
    IController c,
    bytes32 index,
    uint value
  ) internal {
    onlyRegisteredContract(c);

    s.globalCustomData[index] = value;

    emit IApplicationEvents.GlobalCustomDataChanged(index, value);
  }
  //endregion ------------------------ ACTIONS
}
