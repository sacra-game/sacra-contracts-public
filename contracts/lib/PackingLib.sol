// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IItemController.sol";
import "../interfaces/IStatController.sol";
import "../interfaces/IAppErrors.sol";

library PackingLib {

  //////////////////////////
  // ---- PACKING LOGIC ----
  //////////////////////////

  //region ------------------------------------ COMMON

  function packNftId(address token, uint id) internal pure returns (bytes32 serialized) {
    if (id > uint(type(uint64).max)) revert IAppErrors.TooHighValue(id);
    serialized = bytes32(uint(uint160(token)));
    serialized |= bytes32(uint(uint64(id))) << 160;
  }

  function unpackNftId(bytes32 data) internal pure returns (address token, uint id) {
    token = address(uint160(uint(data)));
    id = uint(data) >> 160;
  }

  function packAddressWithAmount(address token, uint amount) internal pure returns (bytes32 data) {
    if (amount > uint(type(uint96).max)) revert IAppErrors.TooHighValue(amount);
    data = bytes32(uint(uint160(token)));
    data |= bytes32(uint(uint96(amount))) << 160;
  }

  function unpackAddressWithAmount(bytes32 data) internal pure returns (address token, uint amount) {
    token = address(uint160(uint(data)));
    amount = uint(data) >> 160;
  }

  function packItemMintInfo(address item, uint32 chance) internal pure returns (bytes32 data) {
    data = bytes32(uint(uint160(item)));
    data |= bytes32(uint(chance)) << 160;
  }

  function unpackItemMintInfo(bytes32 data) internal pure returns (address item, uint32 chance) {
    item = address(uint160(uint(data)));
    chance = uint32(uint(data) >> 160);
  }

  /// @param customDataIndex We assume, that two lowest bytes of this string are always zero
  /// So, the string looks like following: 0xXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX0000
  /// Last 2 bytes will be used to encode {value}
  function packCustomDataChange(bytes32 customDataIndex, int16 value) internal pure returns (bytes32 data) {
    if (uint(customDataIndex) != (uint(customDataIndex) >> 16) << 16) revert IAppErrors.IncompatibleInputString();
    data = bytes32(uint(customDataIndex));
    data |= bytes32(uint(uint16(value)));
  }

  function unpackCustomDataChange(bytes32 data) internal pure returns (bytes32 customDataIndex, int16 value) {
    customDataIndex = bytes32((uint(data) >> 16) << 16);
    value = int16(int(uint(uint16(uint(data)))));
  }

  /// @dev min(uint64) + max(uint64) + isHeroData/isMandatory(uint8)
  function packCustomDataRequirements(uint64 min, uint64 max, bool key) internal pure returns (bytes32 data) {
    data = bytes32(uint(min));
    data |= bytes32(uint(max)) << 64;
    data |= bytes32(uint(key ? uint8(1) : uint8(0))) << (64 + 64);
  }

  function unpackCustomDataRequirements(bytes32 data) internal pure returns (uint64 min, uint64 max, bool key) {
    min = uint64(uint(data));
    max = uint64(uint(data) >> 64);
    key = uint8(uint(data) >> (64 + 64)) == uint8(1);
  }

  function packStatsChange(
    uint32 experience,
    int32 heal,
    int32 manaRegen,
    int32 lifeChancesRecovered,
    int32 damage,
    int32 manaConsumed
  ) internal pure returns (bytes32 data) {
    data = bytes32(uint(experience));
    data |= bytes32(uint(uint32(heal))) << 32;
    data |= bytes32(uint(uint32(manaRegen))) << (32 + 32);
    data |= bytes32(uint(uint32(lifeChancesRecovered))) << (32 + 32 + 32);
    data |= bytes32(uint(uint32(damage))) << (32 + 32 + 32 + 32);
    data |= bytes32(uint(uint32(manaConsumed))) << (32 + 32 + 32 + 32 + 32);
  }

  function unpackStatsChange(bytes32 data) internal pure returns (
    uint32 experience,
    int32 heal,
    int32 manaRegen,
    int32 lifeChancesRecovered,
    int32 damage,
    int32 manaConsumed
  ) {
    experience = uint32(uint(data));
    heal = int32(int(uint(data) >> 32));
    manaRegen = int32(int(uint(data) >> (32 + 32)));
    lifeChancesRecovered = int32(int(uint(data) >> (32 + 32 + 32)));
    damage = int32(int(uint(data) >> (32 + 32 + 32 + 32)));
    manaConsumed = int32(int(uint(data) >> (32 + 32 + 32 + 32 + 32)));
  }

  function packNftIdWithValue(address token, uint id, uint32 value) internal pure returns (bytes32 serialized) {
    if (id > uint(type(uint64).max)) revert IAppErrors.TooHighValue(id);
    serialized = bytes32(uint(uint160(token)));
    serialized |= bytes32(uint(uint64(id))) << 160;
    serialized |= bytes32(uint(value)) << 160 + 64;
  }

  function unpackNftIdWithValue(bytes32 data) internal pure returns (address token, uint id, uint32 value) {
    token = address(uint160(uint(data)));
    id = uint64(uint(data) >> 160);
    value = uint32(uint(data) >> 160 + 64);
  }
  //endregion ------------------------------------ COMMON

  //region ------------------------------------ WORLD/BATTLEFIELD MAP

  function packMapObject(address objectAddress, uint64 objectId, uint8 objectType) internal pure returns (bytes32 packedData) {
    packedData = bytes32(bytes20(objectAddress));
    packedData |= bytes32(uint(objectId) << 32);
    packedData |= bytes32(uint(objectType) << 24);
  }

  function unpackMapObject(bytes32 packedData) internal pure returns (address objectAddress, uint64 objectId, uint8 objectType) {
    objectAddress = address(bytes20(packedData));
    objectId = uint64(uint(packedData) >> 32);
    objectType = uint8(uint(packedData) >> 24);
  }

  function packCoordinate(uint128 x, uint128 y) internal pure returns (bytes32 packedData) {
    packedData = bytes32(uint(x));
    packedData |= bytes32(uint(y) << 128);
  }

  function unpackCoordinate(bytes32 packedData) internal pure returns (uint128 x, uint128 y) {
    x = uint128(uint(packedData));
    y = uint128(uint(packedData) >> 128);
  }

  /// @param x Assume x <= max uint64
  /// @param y Assume y <= max uint64
  function packBattlefieldId(uint8 biomeMapFieldId, uint8 territoryNumber, uint128 x, uint128 y) internal pure returns (bytes32 packedData) {
    // 256 => 128 + 128;
    // 1) 128 is used for biomeMapFieldId, territoryNumber and probably other fields in the future
    // 2) 128 is used to store x, y as uint64, uint64

    // we will use uint64 for coordinates assuming it is more than enough for biome map
    packedData = bytes32(uint(biomeMapFieldId));
    packedData |= bytes32(uint(territoryNumber) << (8));
    packedData |= bytes32(uint(uint64(x)) << 128);
    packedData |= bytes32(uint(uint64(y)) << (64 + 128));
  }

  function unpackBattlefieldId(bytes32 packedData) internal pure returns (uint8 biomeMapFieldId, uint8 territoryNumber, uint128 x, uint128 y) {
    biomeMapFieldId = uint8(uint(packedData));
    territoryNumber = uint8(uint(packedData) >> (8));
    x = uint128(uint64(uint(packedData) >> (128)));
    y = uint128(uint64(uint(packedData) >> (64 + 128)));
  }
  //endregion ------------------------------------ WORLD/BATTLEFIELD MAP

  //region ------------------------------------ REINFORCEMENT

  function packReinforcementHeroInfo(uint8 biome, uint128 score, uint8 fee, uint64 stakeTs) internal pure returns (bytes32 packedData) {
    packedData = bytes32(uint(biome));
    packedData |= bytes32(uint(score) << 8);
    packedData |= bytes32(uint(fee) << (8 + 128));
    packedData |= bytes32(uint(stakeTs) << (8 + 128 + 8));
  }

  function unpackReinforcementHeroInfo(bytes32 packedData) internal pure returns (uint8 biome, uint128 score, uint8 fee, uint64 stakeTs) {
    biome = uint8(uint(packedData));
    score = uint128(uint(packedData) >> 8);
    fee = uint8(uint(packedData) >> (8 + 128));
    stakeTs = uint64(uint(packedData) >> (8 + 128 + 8));
  }

  function packConfigReinforcementV2(uint32 min, uint32 max, uint32 lowDivider, uint32 highDivider, uint8 levelLimit) internal pure returns (bytes32 packedData) {
    packedData = bytes32(uint(min));
    packedData |= bytes32(uint(max) << 32);
    packedData |= bytes32(uint(lowDivider) << 64);
    packedData |= bytes32(uint(highDivider) << 96);
    packedData |= bytes32(uint(levelLimit) << 128);
  }

  function unpackConfigReinforcementV2(bytes32 packedData) internal pure returns (uint32 min, uint32 max, uint32 lowDivider, uint32 highDivider, uint8 levelLimit) {
    min = uint32(uint(packedData));
    max = uint32(uint(packedData) >> 32);
    lowDivider = uint32(uint(packedData) >> 64);
    highDivider = uint32(uint(packedData) >> 96);
    levelLimit = uint8(uint(packedData) >> 128);
  }
  //endregion ------------------------------------ REINFORCEMENT

  //region ------------------------------------ DUNGEON

  function packDungeonKey(address heroAdr, uint80 heroId, uint16 dungLogicNum) internal pure returns (bytes32 data) {
    data = bytes32(uint(uint160(heroAdr)));
    data |= bytes32(uint(heroId)) << 160;
    data |= bytes32(uint(dungLogicNum)) << (160 + 80);
  }

  function unpackDungeonKey(bytes32 data) internal pure returns (address heroAdr, uint80 heroId, uint16 dungLogicNum) {
    heroAdr = address(uint160(uint(data)));
    heroId = uint80(uint(data) >> 160);
    dungLogicNum = uint16(uint(data) >> (160 + 80));
  }

  // --- GAME OBJECTS ---

  function packIterationKey(address heroAdr, uint64 heroId, uint32 objId) internal pure returns (bytes32 data) {
    data = bytes32(uint(uint160(heroAdr)));
    data |= bytes32(uint(heroId)) << 160;
    data |= bytes32(uint(objId)) << (160 + 64);
  }

  function unpackIterationKey(bytes32 data) internal pure returns (address heroAdr, uint64 heroId, uint32 objId) {
    heroAdr = address(uint160(uint(data)));
    heroId = uint64(uint(data) >> 160);
    objId = uint32(uint(data) >> (160 + 64));
  }

  function packMonsterStats(
    uint8 level,
    uint8 race,
    uint32 experience,
    uint8 maxDropItems
  ) internal pure returns (bytes32 data) {
    data = bytes32(uint(level));
    data |= bytes32(uint(race)) << 8;
    data |= bytes32(uint(experience)) << (8 + 8);
    data |= bytes32(uint(maxDropItems)) << (8 + 8 + 32);
  }

  function unpackMonsterStats(bytes32 data) internal pure returns (
    uint8 level,
    uint8 race,
    uint32 experience,
    uint8 maxDropItems
  ) {
    level = uint8(uint(data));
    race = uint8(uint(data) >> 8);
    experience = uint32(uint(data) >> (8 + 8));
    maxDropItems = uint8(uint(data) >> (8 + 8 + 32));
  }

  function packAttackInfo(
    address attackToken,
    uint64 attackTokenId,
    uint8 attackType
  ) internal pure returns (bytes32 data) {
    data = bytes32(uint(uint160(attackToken)));
    data |= bytes32(uint(attackTokenId)) << 160;
    data |= bytes32(uint(attackType)) << (160 + 64);
  }

  function unpackAttackInfo(bytes32 data) internal pure returns (
    address attackToken,
    uint64 attackTokenId,
    uint8 attackType
  ) {
    attackToken = address(uint160(uint(data)));
    attackTokenId = uint64(uint(data) >> 160);
    attackType = uint8(uint(data) >> (160 + 64));
  }

  function packPlayedObjKey(address heroAdr, uint64 heroId, uint8 oType, uint8 biome) internal pure returns (bytes32 data) {
    data = bytes32(uint(uint160(heroAdr)));
    data |= bytes32(uint(heroId)) << 160;
    data |= bytes32(uint(oType)) << (160 + 64);
    data |= bytes32(uint(biome)) << (160 + 64 + 8);
  }

  function unpackPlayedObjKey(bytes32 data) internal pure returns (address heroAdr, uint64 heroId, uint8 oType, uint8 biome) {
    heroAdr = address(uint160(uint(data)));
    heroId = uint64(uint(data) >> 160);
    oType = uint8(uint(data) >> (160 + 64));
    biome = uint8(uint(data) >> (160 + 64 + 8));
  }

  function packGeneratedMonster(bool generated, uint32 amplifier, int32 hp, uint8 turnCounter) internal pure returns (bytes32 data) {
    data = bytes32(uint(uint8(generated ? 1 : 0)));
    data |= bytes32(uint(amplifier)) << 8;
    data |= bytes32(uint(uint32(hp))) << (8 + 32);
    data |= bytes32(uint(turnCounter)) << (8 + 32 + 32);
  }

  function unpackGeneratedMonster(bytes32 data) internal pure returns (bool generated, uint32 amplifier, int32 hp, uint8 turnCounter) {
    generated = uint8(uint(data)) == uint8(1);
    amplifier = uint32(uint(data) >> 8);
    hp = int32(int(uint(data) >> (8 + 32)));
    turnCounter = uint8(uint(data) >> (8 + 32 + 32));
  }
  //endregion ------------------------------------ DUNGEON

  //region ------------------------------------ ITEMS

  /// @notice itemMetaType8 + itemLvl8 + itemType8 + baseDurability16 + defaultRarity8 + minAttr8 + maxAttr8 + manaCost32 + req(packed core 128)
  /// @param itemType This is ItemType enum
  function packItemMeta(
    uint8 itemMetaType,
    uint8 itemLvl,
    uint8 itemType,
    uint16 baseDurability,
    uint8 defaultRarity,
    uint8 minAttr,
    uint8 maxAttr,
    uint32 manaCost,
    IStatController.CoreAttributes memory req
  ) internal pure returns (bytes32 data) {
    data = bytes32(uint(itemMetaType));
    data |= bytes32(uint(itemLvl)) << 8;
    data |= bytes32(uint(itemType)) << (8 + 8);
    data |= bytes32(uint(baseDurability)) << (8 + 8 + 8);
    data |= bytes32(uint(defaultRarity)) << (8 + 8 + 8 + 16);
    data |= bytes32(uint(minAttr)) << (8 + 8 + 8 + 16 + 8);
    data |= bytes32(uint(maxAttr)) << (8 + 8 + 8 + 16 + 8 + 8);
    data |= bytes32(uint(manaCost)) << (8 + 8 + 8 + 16 + 8 + 8 + 8);
    data |= bytes32(uint(int(req.strength))) << (8 + 8 + 8 + 16 + 8 + 8 + 8 + 32);
    data |= bytes32(uint(int(req.dexterity))) << (8 + 8 + 8 + 16 + 8 + 8 + 8 + 32 + 32);
    data |= bytes32(uint(int(req.vitality))) << (8 + 8 + 8 + 16 + 8 + 8 + 8 + 32 + 32 + 32);
    data |= bytes32(uint(int(req.energy))) << (8 + 8 + 8 + 16 + 8 + 8 + 8 + 32 + 32 + 32 + 32);
  }

  function unpackItemMeta(bytes32 data) internal pure returns (IItemController.ItemMeta memory) {
    IItemController.ItemMeta memory result;

    result.itemMetaType = uint8(uint(data));
    result.itemLevel = uint8(uint(data) >> 8);
    result.itemType = IItemController.ItemType(uint8(uint(data) >> (8 + 8)));
    result.baseDurability = uint16(uint(data) >> (8 + 8 + 8));
    result.defaultRarity = uint8(uint(data) >> (8 + 8 + 8 + 16));
    result.minRandomAttributes = uint8(uint(data) >> (8 + 8 + 8 + 16 + 8));
    result.maxRandomAttributes = uint8(uint(data) >> (8 + 8 + 8 + 16 + 8 + 8));
    result.manaCost = uint32(uint(data) >> (8 + 8 + 8 + 16 + 8 + 8 + 8));
    result.requirements.strength = int32(int(uint(data) >> (8 + 8 + 8 + 16 + 8 + 8 + 8 + 32)));
    result.requirements.dexterity = int32(int(uint(data) >> (8 + 8 + 8 + 16 + 8 + 8 + 8 + 32 + 32)));
    result.requirements.vitality = int32(int(uint(data) >> (8 + 8 + 8 + 16 + 8 + 8 + 8 + 32 + 32 + 32)));
    result.requirements.energy = int32(int(uint(data) >> (8 + 8 + 8 + 16 + 8 + 8 + 8 + 32 + 32 + 32 + 32)));

    return result;
  }

  function packItemGenerateInfo(uint8 id, int32 min, int32 max, uint32 chance) internal pure returns (bytes32 data) {
    data = bytes32(uint(id));
    data |= bytes32(uint(uint32(min))) << 8;
    data |= bytes32(uint(uint32(max))) << (8 + 32);
    data |= bytes32(uint(chance)) << (8 + 32 + 32);
  }

  function unpackItemGenerateInfo(bytes32 data) internal pure returns (uint8 id, int32 min, int32 max, uint32 chance) {
    id = uint8(uint(data));
    min = int32(int(uint(data) >> 8));
    max = int32(int(uint(data) >> (8 + 32)));
    chance = uint32(uint(data) >> (8 + 32 + 32));
  }

  function packItemAttackInfo(
    uint8 attackType,
    int32 min,
    int32 max,
    int32 factorStr,
    int32 factorDex,
    int32 factorVit,
    int32 factorEng
  ) internal pure returns (bytes32 data) {
    data = bytes32(uint(attackType));
    data |= bytes32(uint(uint32(min))) << 8;
    data |= bytes32(uint(uint32(max))) << (8 + 32);
    data |= bytes32(uint(int(factorStr))) << (8 + 32 + 32);
    data |= bytes32(uint(int(factorDex))) << (8 + 32 + 32 + 32);
    data |= bytes32(uint(int(factorVit))) << (8 + 32 + 32 + 32 + 32);
    data |= bytes32(uint(int(factorEng))) << (8 + 32 + 32 + 32 + 32 + 32);
  }

  function unpackItemAttackInfo(bytes32 data) internal pure returns (
    uint8 attackType,
    int32 min,
    int32 max,
    int32 factorStr,
    int32 factorDex,
    int32 factorVit,
    int32 factorEng
  ) {
    attackType = uint8(uint(data));
    min = int32(int(uint(data) >> 8));
    max = int32(int(uint(data) >> (8 + 32)));
    factorStr = int32(int(uint(data) >> (8 + 32 + 32)));
    factorDex = int32(int(uint(data) >> (8 + 32 + 32 + 32)));
    factorVit = int32(int(uint(data) >> (8 + 32 + 32 + 32 + 32)));
    factorEng = int32(int(uint(data) >> (8 + 32 + 32 + 32 + 32 + 32)));
  }

  function packItemInfo(uint8 rarity, uint8 augmentationLevel, uint16 durability) internal pure returns (bytes32 data) {
    data = bytes32(uint(rarity));
    data |= bytes32(uint(augmentationLevel)) << 8;
    data |= bytes32(uint(durability)) << (8 + 8);
  }

  function unpackItemInfo(bytes32 data) internal pure returns (uint8 rarity, uint8 augmentationLevel, uint16 durability) {
    rarity = uint8(uint(data));
    augmentationLevel = uint8(uint(data) >> 8);
    durability = uint16(uint(data) >> (8 + 8));
  }

  function packItemBoxItemInfo(bool withdrawn, uint64 timestamp) internal pure returns (bytes32 data) {
    data = bytes32(uint(uint8(withdrawn ? 1 : 0)));
    data |= bytes32(uint(timestamp)) << 8;
  }

  function unpackItemBoxItemInfo(bytes32 data) internal pure returns (bool withdrawn, uint64 timestamp) {
    withdrawn = uint8(uint(data)) != 0;
    timestamp = uint64(uint(data) >> 8);
  }
  //endregion ------------------------------------ ITEMS

  //region ------------------------------------ STORIES

  function packStoryPageId(uint16 storyId, uint16 pageId, uint8 heroClass) internal pure returns (bytes32 data) {
    data = bytes32(uint(storyId));
    data |= bytes32(uint(pageId)) << 16;
    data |= bytes32(uint(heroClass)) << (16 + 16);
  }

  function unpackStoryPageId(bytes32 data) internal pure returns (uint16 storyId, uint16 pageId, uint8 heroClass) {
    storyId = uint16(uint(data));
    pageId = uint16(uint(data) >> 16);
    heroClass = uint8(uint(data) >> (16 + 16));
  }

  function packStoryAnswerId(uint16 storyId, uint16 pageId, uint8 heroClass, uint16 answerId) internal pure returns (bytes32 data) {
    data = bytes32(uint(storyId));
    data |= bytes32(uint(pageId)) << 16;
    data |= bytes32(uint(heroClass)) << (16 + 16);
    data |= bytes32(uint(answerId)) << (16 + 16 + 8);
  }

  function unpackStoryAnswerId(bytes32 data) internal pure returns (uint16 storyId, uint16 pageId, uint8 heroClass, uint16 answerId) {
    storyId = uint16(uint(data));
    pageId = uint16(uint(data) >> 16);
    heroClass = uint8(uint(data) >> (16 + 16));
    answerId = uint16(uint(data) >> (16 + 16 + 8));
  }

  function packStoryNextPagesId(uint16 storyId, uint16 pageId, uint8 heroClass, uint16 answerId, uint8 resultId) internal pure returns (bytes32 data) {
    data = bytes32(uint(storyId));
    data |= bytes32(uint(pageId)) << 16;
    data |= bytes32(uint(heroClass)) << (16 + 16);
    data |= bytes32(uint(answerId)) << (16 + 16 + 8);
    data |= bytes32(uint(resultId)) << (16 + 16 + 8 + 16);
  }

  function unpackStoryNextPagesId(bytes32 data) internal pure returns (uint16 storyId, uint16 pageId, uint8 heroClass, uint16 answerId, uint8 resultId) {
    storyId = uint16(uint(data));
    pageId = uint16(uint(data) >> 16);
    heroClass = uint8(uint(data) >> (16 + 16));
    answerId = uint16(uint(data) >> (16 + 16 + 8));
    resultId = uint8(uint(data) >> (16 + 16 + 8 + 16));
  }

  function packStoryAttributeRequirement(uint8 attributeIndex, int32 value, bool isCore) internal pure returns (bytes32 data) {
    data = bytes32(uint(attributeIndex));
    data |= bytes32(uint(uint32(value))) << 8;
    data |= bytes32(uint(isCore ? uint8(1) : uint8(0))) << (8 + 32);
  }

  function unpackStoryAttributeRequirement(bytes32 data) internal pure returns (uint8 attributeIndex, int32 value, bool isCore) {
    attributeIndex = uint8(uint(data));
    value = int32(int(uint(data) >> 8));
    isCore = uint8(uint(data) >> (8 + 32)) == uint8(1);
  }

  function packStoryItemRequirement(address item, bool requireItemBurn, bool requireItemEquipped) internal pure returns (bytes32 data) {
    data = bytes32(uint(uint160(item)));
    data |= bytes32(uint(requireItemBurn ? uint8(1) : uint8(0))) << 160;
    data |= bytes32(uint(requireItemEquipped ? uint8(1) : uint8(0))) << (160 + 8);
  }

  function unpackStoryItemRequirement(bytes32 data) internal pure returns (address item, bool requireItemBurn, bool requireItemEquipped) {
    item = address(uint160(uint(data)));
    requireItemBurn = uint8(uint(data) >> 160) == uint8(1);
    requireItemEquipped = uint8(uint(data) >> (160 + 8)) == uint8(1);
  }

  /// @dev max amount is 309,485,009 for token with 18 decimals
  function packStoryTokenRequirement(address token, uint88 amount, bool requireTransfer) internal pure returns (bytes32 data) {
    data = bytes32(uint(uint160(token)));
    data |= bytes32(uint(amount)) << 160;
    data |= bytes32(uint(requireTransfer ? uint8(1) : uint8(0))) << (160 + 88);
  }

  function unpackStoryTokenRequirement(bytes32 data) internal pure returns (address token, uint88 amount, bool requireTransfer) {
    token = address(uint160(uint(data)));
    amount = uint88(uint(data) >> 160);
    requireTransfer = uint8(uint(data) >> (160 + 88)) == uint8(1);
  }

  function packStoryCustomDataResult(uint16 storyId, uint16 pageId, uint8 heroClass, uint16 answerId, uint8 customDataResultId) internal pure returns (bytes32 data) {
    data = bytes32(uint(storyId));
    data |= bytes32(uint(pageId)) << 16;
    data |= bytes32(uint(heroClass)) << (16 + 16);
    data |= bytes32(uint(answerId)) << (16 + 16 + 8);
    data |= bytes32(uint(customDataResultId)) << (16 + 16 + 8 + 16);
  }

  function unpackStoryCustomDataResult(bytes32 data) internal pure returns (uint16 storyId, uint16 pageId, uint8 heroClass, uint16 answerId, uint8 customDataResultId) {
    storyId = uint16(uint(data));
    pageId = uint16(uint(data) >> 16);
    heroClass = uint8(uint(data) >> (16 + 16));
    answerId = uint16(uint(data) >> (16 + 16 + 8));
    customDataResultId = uint8(uint(data) >> (16 + 16 + 8 + 16));
  }

  function packStoryHeroState(uint16 pageId, uint40 heroLastActionTS) internal pure returns (bytes32 data) {
    data = bytes32(uint(pageId));
    data |= bytes32(uint(heroLastActionTS)) << 16;
  }

  function unpackStoryHeroState(bytes32 data) internal pure returns (uint16 pageId, uint40 heroLastActionTS) {
    pageId = uint16(uint(data));
    heroLastActionTS = uint40(uint(data) >> 16);
  }

  function packStoryHeroStateId(address heroAdr, uint80 heroId, uint16 storyId) internal pure returns (bytes32 data) {
    data = bytes32(uint(uint160(heroAdr)));
    data |= bytes32(uint(heroId)) << 160;
    data |= bytes32(uint(storyId)) << (160 + 80);
  }

  function unpackStoryHeroStateId(bytes32 data) internal pure returns (address heroAdr, uint80 heroId, uint16 storyId) {
    heroAdr = address(uint160(uint(data)));
    heroId = uint80(uint(data) >> 160);
    storyId = uint16(uint(data) >> (160 + 80));
  }

  function packStorySimpleRequirement(uint32 randomRequirement, uint32 delayRequirement, bool isFinalAnswer) internal pure returns (bytes32 data) {
    data = bytes32(uint(randomRequirement));
    data |= bytes32(uint(delayRequirement)) << 32;
    data |= bytes32(uint(isFinalAnswer ? uint8(1) : uint8(0))) << (32 + 32);
  }

  function unpackStorySimpleRequirement(bytes32 data) internal pure returns (uint32 randomRequirement, uint32 delayRequirement, bool isFinalAnswer) {
    randomRequirement = uint32(uint(data));
    delayRequirement = uint32(uint(data) >> 32);
    isFinalAnswer = uint8(uint(data) >> (32 + 32)) == uint8(1);
  }

  function packBreakInfo(uint8 slot, uint64 chance, bool stopIfBroken) internal pure returns (bytes32 data) {
    data = bytes32(uint(slot));
    data |= bytes32(uint(chance)) << 8;
    data |= bytes32(uint(stopIfBroken ? uint8(1) : uint8(0))) << (8 + 64);
  }

  function unpackBreakInfo(bytes32 data) internal pure returns (uint8 slot, uint64 chance, bool stopIfBurned) {
    slot = uint8(uint(data));
    chance = uint64(uint(data) >> 8);
    stopIfBurned = uint8(uint(data) >> (8 + 64)) == uint8(1);
  }
  //endregion ------------------------------------ STORIES

  //region ------------------------------------ Hero controller
  function packTierHero(uint8 tier, address hero) internal pure returns (bytes32 packedTierHero) {
    packedTierHero = bytes32(uint(tier));
    packedTierHero |= bytes32(uint(uint160(hero)) << 8);
  }

  function unpackTierHero(bytes32 packedTierHero) internal pure returns (uint8 tier, address hero) {
    tier = uint8(uint(packedTierHero));
    hero = address(uint160(uint(packedTierHero) >> 8));
  }

  //endregion ------------------------------------ Hero controller

  ////////////////////////////////////////////////////////////////////////////////////
  // ---- ARRAYS LOGIC ----
  ////////////////////////////////////////////////////////////////////////////////////

  //region ------------------------------------ SIMPLE ARRAYS


  function packUint8Array(uint8[] memory data) internal pure returns (bytes32) {
    uint len = data.length;
    if (len > 32) revert IAppErrors.OutOfBounds(len, 32);
    bytes32 result;
    for (uint i = 0; i < len; i++) {
      result |= bytes32(uint(data[i])) << (i * 8);
    }
    return result;
  }

  /// @notice Simple faster version of {packUint8Array} for small number of items
  ///         It allows to exclude dynamic array creation.
  function packUint8Array3(uint8 a, uint8 b, uint8 c) internal pure returns (bytes32) {
    bytes32 result = bytes32(uint(a));
    result |= bytes32(uint(b)) << (1 * 8);
    result |= bytes32(uint(c)) << (2 * 8);
    return result;
  }


  function unpackUint8Array(bytes32 data) internal pure returns (uint8[] memory) {
    uint8[] memory result = new uint8[](32);
    for (uint i = 0; i < 32; i++) {
      result[i] = uint8(uint(data) >> (i * 8));
    }
    return result;
  }

  /// @notice Simple faster version of {unpackUint8Array} for small number of items
  ///         It allows to exclude only first 3 values
  function unpackUint8Array3(bytes32 data) internal pure returns (uint8 a, uint8 b, uint8 c) {
    a = uint8(uint(data));
    b = uint8(uint(data) >> (1 * 8));
    c = uint8(uint(data) >> (2 * 8));
  }

  function changeUnit8ArrayWithCheck(bytes32 data, uint index, uint8 value, uint8 expectedPrevValue) internal pure returns (bytes32 newData) {
    uint8[] memory arr = unpackUint8Array(data);
    if (arr[index] != expectedPrevValue) revert IAppErrors.UnexpectedValue(uint(expectedPrevValue), uint(arr[index]));
    arr[index] = value;
    return packUint8Array(arr);
  }

  function packInt32Array(int32[] memory data) internal pure returns (bytes32) {
    uint len = data.length;
    if (len > 8) revert IAppErrors.OutOfBounds(len, 8);
    bytes32 result;
    for (uint i; i < len; i++) {
      result |= bytes32(uint(uint32(data[i]))) << (i * 32);
    }
    return result;
  }

  function unpackInt32Array(bytes32 data) internal pure returns (int32[] memory) {
    int32[] memory result = new int32[](8);
    for (uint i = 0; i < 8; i++) {
      result[i] = int32(int(uint(data) >> (i * 32)));
    }
    return result;
  }

  function packUint32Array(uint32[] memory data) internal pure returns (bytes32) {
    uint len = data.length;
    if (len > 8) revert IAppErrors.OutOfBounds(len, 8);
    bytes32 result;
    for (uint i = 0; i < len; i++) {
      result |= bytes32(uint(data[i])) << (i * 32);
    }
    return result;
  }

  function unpackUint32Array(bytes32 data) internal pure returns (uint32[] memory) {
    uint32[] memory result = new uint32[](8);
    for (uint i = 0; i < 8; i++) {
      result[i] = uint32(uint(data) >> (i * 32));
    }
    return result;
  }
  //endregion ------------------------------------ SIMPLE ARRAYS

  //region ------------------------------------ COMPLEX ARRAYS

  // We should represent arrays without concrete size.
  // For this reason we must not revert IAppErrors.on out of bounds but return zero value instead.

  // we need it for properly unpack packed arrays with ids
//  function getInt32AsInt24(bytes32[] memory arr, uint idx) internal pure returns (int32) {
//    if (idx / 8 >= arr.length) {
//      return int32(0);
//    }
//    return int32(int24(int(uint(arr[idx / 8]) >> ((idx % 8) * 32))));
//  }

  // we need it for properly unpack packed arrays with ids
//  function getUnit8From32Step(bytes32[] memory arr, uint idx) internal pure returns (uint8) {
//    if (idx / 8 >= arr.length) {
//      return uint8(0);
//    }
//    return uint8(uint(arr[idx / 8]) >> ((idx % 8) * 32 + 24));
//  }

  function getInt32Memory(bytes32[] memory arr, uint idx) internal pure returns (int32) {
    if (idx / 8 >= arr.length) {
      return int32(0);
    }
    return int32(int(uint(arr[idx / 8]) >> ((idx % 8) * 32)));
  }

  function getInt32(bytes32[] storage arr, uint idx) internal view returns (int32) {
    // additional gas usage, but we should not revert IAppErrors.on out of bounds
    if (idx / 8 >= arr.length) {
      return int32(0);
    }
    return int32(int(uint(arr[idx / 8]) >> ((idx % 8) * 32)));
  }

  function setInt32(bytes32[] storage arr, uint idx, int32 value) internal {
    uint pos = idx / 8;
    uint shift = (idx % 8) * 32;

    uint curLength = arr.length;
    if (pos >= curLength) {
      arr.push(0);
      for (uint i = curLength; i < pos; ++i) {
        arr.push(0);
      }
    }

    arr[pos] = bytes32(uint(arr[pos]) & ~(uint(0xffffffff) << shift) | (uint(uint32(value)) & 0xffffffff) << shift);
  }

  /// @notice Increment {idx}-th item on {value}
  function changeInt32(bytes32[] storage arr, uint idx, int32 value) internal returns (int32 newValue, int32 change) {
    int32 cur = int32(int(getInt32(arr, idx)));
    int newValueI = int(cur) + int(value);
    newValue = int32(newValueI);
    change = int32(newValueI - int(cur));

    setInt32(arr, idx, newValue);
  }

  function toInt32Array(bytes32[] memory arr, uint size) internal pure returns (int32[] memory) {
    int32[] memory result = new int32[](size);
    for (uint i = 0; i < arr.length; i++) {
      for (uint j; j < 8; ++j) {
        uint idx = i * 8 + j;
        if (idx >= size) break;
        result[idx] = getInt32Memory(arr, idx);
      }
    }
    return result;
  }

  /// @dev pack int32 array into bytes32 array
  function toBytes32Array(int32[] memory arr) internal pure returns (bytes32[] memory) {
    uint size = arr.length / 8 + 1;
    bytes32[] memory result = new bytes32[](size);
    for (uint i; i < size; ++i) {
      for (uint j; j < 8; ++j) {
        uint idx = i * 8 + j;
        if (idx >= arr.length) break;
        result[i] |= bytes32(uint(uint32(arr[idx]))) << (j * 32);
      }
    }
    return result;
  }

  /// @dev pack int32 array into bytes32 array using last 8bytes for ids
  ///      we can not use zero values coz will not able to properly unpack it later
  function toBytes32ArrayWithIds(int32[] memory arr, uint8[] memory ids) internal pure returns (bytes32[] memory) {
    if (arr.length != ids.length) revert IAppErrors.LengthsMismatch();

    uint size = arr.length / 8 + 1;
    bytes32[] memory result = new bytes32[](size);
    for (uint i; i < size; ++i) {
      for (uint j; j < 8; ++j) {
        uint idx = i * 8 + j;
        if (idx >= arr.length) break;

        if (arr[idx] > type(int24).max || arr[idx] < type(int24).min) revert IAppErrors.IntOutOfRange(int(arr[idx]));
        if (arr[idx] == 0) revert IAppErrors.ZeroValue();
        result[i] |= bytes32(uint(uint24(int24(arr[idx])))) << (j * 32);
        result[i] |= bytes32(uint(ids[idx])) << (j * 32 + 24);
      }
    }
    return result;
  }

  /// @dev we do not know exact size of array, assume zero values is not acceptable for this array
  function toInt32ArrayWithIds(bytes32[] memory arr) internal pure returns (int32[] memory values, uint8[] memory ids) {
    uint len = arr.length;
    uint size = len * 8;
    int32[] memory valuesTmp = new int32[](size);
    uint8[] memory idsTmp = new uint8[](size);
    uint counter;
    for (uint i = 0; i < len; i++) {
      for (uint j; j < 8; ++j) {
        uint idx = i * 8 + j;
        // if (idx >= size) break;  // it looks like a useless check
        valuesTmp[idx] = int32(int24(int(uint(arr[i]) >> (j * 32)))); // getInt32AsInt24(arr, idx);
        idsTmp[idx] = uint8(uint(arr[i]) >> (j * 32 + 24)); // getUnit8From32Step(arr, idx);
        if (valuesTmp[idx] == 0) {
          break;
        }
        counter++;
      }
    }

    values = new int32[](counter);
    ids = new uint8[](counter);
    for (uint i; i < counter; ++i) {
      values[i] = valuesTmp[i];
      ids[i] = idsTmp[i];
    }
  }
  //endregion ------------------------------------ COMPLEX ARRAYS

  //region ------------------------------------ Guilds
  /// @dev ShelterID is uint. But in the code we assume that this ID can be stored as uint64 (see auctions)
  /// @param biome 1, 2, 3...
  /// @param shelterLevel 1, 2 or 3.
  /// @param shelterIndex 0, 1, 2 ...
  function packShelterId(uint8 biome, uint8 shelterLevel, uint8 shelterIndex) internal pure returns (uint) {
    return uint(biome) | (uint(shelterLevel) << 8) | (uint(shelterIndex) << 16);
  }

  function unpackShelterId(uint shelterId) internal pure returns (uint8 biome, uint8 shelterLevel, uint8 shelterIndex) {
    return (uint8(shelterId), uint8(shelterId >> 8), uint8(shelterId >> 16));
  }
  //endregion ------------------------------------ Guilds

  //region ------------------------------------ Metadata of IItemController.OtherSubtypeKind

  function getOtherItemTypeKind(bytes memory packedData) internal pure returns (IItemController.OtherSubtypeKind) {
    bytes32 serialized;
    assembly {
      serialized := mload(add(packedData, 32))
    }
    uint8 kind = uint8(uint(serialized));
    if (kind == 0 || kind >= uint8(IItemController.OtherSubtypeKind.END_SLOT)) revert IAppErrors.IncorrectOtherItemTypeKind(kind);
    return IItemController.OtherSubtypeKind(kind);
  }

  function packOtherItemReduceFragility(uint value) internal pure returns (bytes memory packedData) {
    bytes32 serialized = bytes32(uint(uint8(IItemController.OtherSubtypeKind.REDUCE_FRAGILITY_1)));
    serialized |= bytes32(uint(uint248(value))) << 8;
    return bytes.concat(serialized);
  }

  function unpackOtherItemReduceFragility(bytes memory packedData) internal pure returns (uint) {
    bytes32 serialized;
    assembly {
      serialized := mload(add(packedData, 32))
    }
    uint8 kind = uint8(uint(serialized));
    if (kind != uint8(IItemController.OtherSubtypeKind.REDUCE_FRAGILITY_1)) revert IAppErrors.IncorrectOtherItemTypeKind(kind);
    uint value = uint248(uint(serialized) >> 8);
    return value;
  }
  //endregion ------------------------------------ Metadata of IItemController.OtherSubtypeKind

  //region ------------------------------------ Metadata of IPvpController.PvpAttackInfoDefaultStrategy
  function getPvpBehaviourStrategyKind(bytes memory encodedData) internal pure returns (uint) {
    bytes32 serialized;
    assembly {
      serialized := mload(add(encodedData, 64)) // first 32 bytes contain 0x20 and indicate array, we need to read second 32 bytes to get first uint in the struct
    }

    return uint(serialized);
  }
  //endregion ------------------------------------ Metadata of IPvpController.PvpAttackInfoDefaultStrategy

}
