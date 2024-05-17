// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./CalcLib.sol";
import "./StatLib.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IItemController.sol";
import "../interfaces/IItem.sol";
import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../openzeppelin/Math.sol";
import "../solady/LibPRNG.sol";

library ItemLib {
  using CalcLib for int32;
  using PackingLib for address;
  using PackingLib for bytes32;
  using PackingLib for bytes32[];
  using PackingLib for uint32[];
  using PackingLib for int32[];

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
    /// @notice Total sum of all {random} values for random attributes generated in {_prepareAttributes}
    uint randomSum;
    /// @notice Total sum of all chances of the random attributes generated in {_prepareAttributes}
    uint chancesSum;
    /// @notice Total number of random attributes that can be generated
    uint totalRandomAttrsPossible;
  }

  struct MintItemInfo {
    uint8 biome;
    uint8 heroCurrentLvl;
    uint8 maxItems;
    IOracle oracle;
    address[] mintItems;
    int32 magicFind;
    int32 destroyItems;
    uint32[] mintItemsChances;
    uint32 heroExp;
    uint amplifier;
    uint seed;
  }
  //endregion ------------------------ Data types

  //region ------------------------ Main logic

  /// @notice Mint new item, setup attributes, make extra setup if necessary (setup attack item, buff item)
  /// @param sender Dungeon Factory only is allowed
  /// @param item Item to be minted
  /// @param recipient The item is minted for the given recipient
  /// @return itemId Id of the newly minted item
  function mintNewItem(
    IItemController.MainState storage s,
    IController controller,
    address sender,
    address item,
    address recipient
  ) external returns (uint itemId) {
    if (controller.dungeonFactory() != sender) revert IAppErrors.ErrorNotDungeonFactory(sender);

    itemId = IItem(item).mintFor(recipient);

    IItemController.MintInfo memory info;

    (
      info.meta,
      info.attributesIds,
      info.attributesValues,
      info.itemRarity
    ) = _setupNewAttributes(s, item, itemId, CalcLib.pseudoRandom);

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

  //endregion ------------------------ Main logic

  //region ------------------------ Internal logic
  /// @param nextPrng_ CalcLib.nextPrng, param is required by unit tests
  function _mintRandomItems(
    MintItemInfo memory info,
    function (LibPRNG.PRNG memory, uint) internal view returns (uint) nextPrng_
  ) internal returns (address[] memory) {
    unchecked {
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
      uint delta = StatLib.mintDropChanceDelta(info.heroExp, info.heroCurrentLvl, info.biome);
      uint di = Math.min(uint(int(info.destroyItems)), 100);

      for (uint i; i < len; ++i) {
        if (info.mintItemsChances[indices[i]] > CalcLib.MAX_CHANCE) {
          revert IAppErrors.TooHighChance(info.mintItemsChances[indices[i]]);
        }
        uint chance = StatLib.mintDropChance(info.mintItemsChances[indices[i]], info.amplifier, delta);
        chance += chance * uint(int(info.magicFind)) / 100;
        chance -= chance * di / 100;

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
  }

  function _setupNewAttributes(
    IItemController.MainState storage s,
    address item,
    uint itemId,
    function (uint) internal view returns (uint) random_
  ) internal returns (
    IItemController.ItemMeta memory meta,
    uint8[] memory ids,
    int32[] memory values,
    IItemController.ItemRarity itemRarity
  ){
    meta = unpackedItemMeta(s.itemMeta[item]);
    (ids, values, itemRarity) = _generateAttributes(unpackItemGenerateInfo(s.generateInfoAttributes[item]), meta, random_);

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

      // Fisher–Yates shuffle
      _shuffleInfo(info, random_);

      // initialize ctx by initial values
      // generate all mandatory attributes, try to generate not more than {meta.maxRandomAttributes} random attributes
      _prepareAttributes(info, meta.maxRandomAttributes, ctx, random_);

      // generate missing random attributes if it's necessary, ctx.counter is incremented
      _generateMissingRandomAttributes(info, meta.minRandomAttributes, ctx, random_);

      itemRarity = meta.defaultRarity == 0
        ? _calculateRarity(ctx.randomSum, ctx.chancesSum, ctx.randomAttrCounter, meta.maxRandomAttributes)
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
        (int32 attr,) = _generateAttribute(info.mins[idx], info.maxs[idx], CalcLib.MAX_CHANCE, random_);
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
        (int32 attr, uint random) = _generateAttribute(info.mins[i], info.maxs[i], info.chances[i], random_);
//          console.log("GEN id: %s, value: %s%s", _info.ids[i], attr >= 0 ? '' : '-', attr >= 0 ? uint(int(attr)) : uint(int(- attr)));

        // count only random attributes for calc rarity
        if (attr != 0) {

          if (
            info.chances[i] < CalcLib.MAX_CHANCE
            // && random != 0 // commented: random = 0 can produce crash in _generateMissingRandomAttributes
          ) {
            ctx.randomAttrCounter++;
            ctx.randomSum += random;
            ctx.chancesSum += info.chances[i];
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
  /// @param chance Chance in the range [0...MAX_CHANCE], MAX_CHANCE=1e9 means "mandatory" element.
  /// @param random_ Pass CalcLib.pseudoRandom here, param is required for unit tests
  /// @return attr Either 0 or min <= attr <= max
  /// @return rnd Random value in the range [0...MAX_CHANCE]; It's always 0 for mandatory elements
  function _generateAttribute(
    int32 min,
    int32 max,
    uint32 chance,
    function (uint) internal view returns (uint) random_
  ) internal view returns (
    int32 attr,
    uint rnd
  ) {
    if (chance > CalcLib.MAX_CHANCE) revert IAppErrors.TooHighChance(chance);

    uint diff = uint(CalcLib.absDiff(min, max));

    if (chance < CalcLib.MAX_CHANCE) {
      uint32 random = CalcLib.pseudoRandomUint32Flex(CalcLib.MAX_CHANCE, random_);
      if (random < chance) {
        uint r = uint(CalcLib.MAX_CHANCE - random * (CalcLib.MAX_CHANCE / chance));
        int32 k = int32(int(r * diff / uint(CalcLib.MAX_CHANCE)));
        return (min + k, random);
      }
    } else { // chance == CalcLib.MAX_CHANCE => mandatory element
      if (diff == 0) {
        return (min, 0);
      } else {
        uint r = uint(CalcLib.pseudoRandomUint32Flex(CalcLib.MAX_CHANCE, random_));
        int32 k = int32(int(r % (diff + 1)));

        // return zero random - no need to calc rarity for mandatory elements
        return (min + k, 0);
      }
    }

    return (0, 0);
  }

  /// @notice Calculate item rarity
  /// @param randomSum Total sum random values of all random attributes in ItemGenerateInfo, [0...MAX_CHANCE/attrCounter]
  /// @param chancesSum Total sum of all random chances in ItemGenerateInfo
  /// @param attrCounter Count of random attributes in ItemGenerateInfo
  /// @param maxAttr Index of max allowed random attribute (all attributes with higher indices are not random)
  /// @return item rarity
  function _calculateRarity(uint randomSum, uint chancesSum, uint attrCounter, uint maxAttr) internal pure returns (
    IItemController.ItemRarity
  ) {
    if (attrCounter == 0) {
      return IItemController.ItemRarity.NORMAL;
    }

    uint random = randomSum / attrCounter;
    uint averageChance = chancesSum / attrCounter;

    if (random > CalcLib.MAX_CHANCE) revert IAppErrors.TooHighRandom(random);

    if (random < averageChance / 4 && attrCounter == maxAttr) {
      return IItemController.ItemRarity.RARE;
    } else if (random < averageChance * 3 / 4) {
      return attrCounter > 2
        ? IItemController.ItemRarity.RARE
        : IItemController.ItemRarity.MAGIC;
    } else {
      return attrCounter > 1
        ? IItemController.ItemRarity.MAGIC
        : IItemController.ItemRarity.NORMAL;
    }
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
