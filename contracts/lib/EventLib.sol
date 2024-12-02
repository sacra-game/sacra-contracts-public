// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./CalcLib.sol";
import "./PackingLib.sol";
import "./ItemLib.sol";
import "./StoryLib.sol";
import "../interfaces/IStatController.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IGOC.sol";
import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";

library EventLib {
  using CalcLib for int32;
  using PackingLib for bytes32;
  using PackingLib for bytes32[];
  using PackingLib for uint16;
  using PackingLib for uint8;
  using PackingLib for address;
  using PackingLib for uint32[];
  using PackingLib for uint32;
  using PackingLib for uint64;
  using PackingLib for int32[];
  using PackingLib for int32;

  //region ------------------------ Main logic

  function action(IGOC.ActionContext calldata ctx, IGOC.EventInfo storage info) external returns (
    IGOC.ActionResult memory
  ) {
    (bool accept) = abi.decode(ctx.data, (bool));
    return accept
      ? _eventAcceptResult(ctx, info)
      : _noActionResult();
  }

  /// @notice Save data from {regInfo} to {info}
  function eventRegInfoToInfo(IGOC.EventRegInfo calldata regInfo, IGOC.EventInfo storage info) external {
    info.goodChance = regInfo.goodChance;
    info.goodAttributes = regInfo.goodAttributes.values.toBytes32ArrayWithIds(regInfo.goodAttributes.ids);
    info.badAttributes = regInfo.badAttributes.values.toBytes32ArrayWithIds(regInfo.badAttributes.ids);
    info.statsChange = regInfo.experience.packStatsChange(
      regInfo.heal,
      regInfo.manaRegen,
      regInfo.lifeChancesRecovered,
      regInfo.damage,
      regInfo.manaConsumed
    );

    bytes32[] memory mintItems = new bytes32[](regInfo.mintItems.length);

    for (uint i; i < mintItems.length; ++i) {
      mintItems[i] = regInfo.mintItems[i].packItemMintInfo(regInfo.mintItemsChances[i]);
    }
    info.mintItems = mintItems;
  }
  //endregion ------------------------ Main logic

  //region ------------------------ Internal logic
  function _eventAcceptResult(IGOC.ActionContext calldata ctx, IGOC.EventInfo storage info) internal returns (
    IGOC.ActionResult memory result
  ) {
    IStatController sc = IStatController(ctx.controller.statController());

    IStatController.ActionInternalInfo memory gen = _generate(ctx, info, sc);

    if (gen.posAttributes.length != 0) {
      sc.changeBonusAttributes(IStatController.ChangeAttributesInfo({
        heroToken: ctx.heroToken,
        heroTokenId: ctx.heroTokenId,
        changeAttributes: gen.posAttributes,
        add: true,
        temporally: true
      }));
    }

    if (gen.negAttributes.length != 0) {
      sc.changeBonusAttributes(IStatController.ChangeAttributesInfo({
        heroToken: ctx.heroToken,
        heroTokenId: ctx.heroTokenId,
        changeAttributes: gen.negAttributes,
        add: true,
        temporally: true
      }));
    }

    // refreshed stats
    IStatController.ChangeableStats memory stats = sc.heroStats(ctx.heroToken, ctx.heroTokenId);

    result.completed = true;
    result.experience = gen.experience;
    result.heal = gen.heal;
    result.manaRegen = gen.manaRegen;
    result.lifeChancesRecovered = gen.lifeChancesRecovered;
    result.damage = gen.damage;
    result.manaConsumed = CalcLib.minI32(gen.manaConsumed, int32(stats.mana));
    result.mintItems = gen.mintedItems;

    if (stats.life <= gen.damage.toUint()) {
      result.kill = true;
    }

    emit IApplicationEvents.EventResult(ctx.dungeonId, ctx.heroToken, ctx.heroTokenId, ctx.stageId, gen, ctx.iteration);
    return result;
  }

  /// @notice Generate empty result structure, only "completed" is true
  function _noActionResult() internal pure returns (IGOC.ActionResult memory result) {
    result.completed = true;
    return result;
  }

  /// @notice Generate either positive or negative attributes, mint single item in any case
  function _generate(IGOC.ActionContext calldata ctx, IGOC.EventInfo storage info, IStatController sc) internal returns (
    IStatController.ActionInternalInfo memory result
  ) {
    uint32 goodChance = info.goodChance;
    if (goodChance > CalcLib.MAX_CHANCE) revert IAppErrors.TooHighChance(goodChance);

    IOracle oracle = IOracle(ctx.controller.oracle());

    uint random = goodChance == CalcLib.MAX_CHANCE ? CalcLib.MAX_CHANCE : oracle.getRandomNumber(CalcLib.MAX_CHANCE, 0);
    if (random <= goodChance) {
      result.posAttributes = StoryLib._generateAttributes(info.goodAttributes);
      (result.experience,
        result.heal,
        result.manaRegen,
        result.lifeChancesRecovered,,) = info.statsChange.unpackStatsChange();
    } else {
      result.negAttributes = StoryLib._generateAttributes(info.badAttributes);
      (,,,, result.damage, result.manaConsumed) = info.statsChange.unpackStatsChange();
    }

    // always mint possible items even if bad result
    result.mintedItems = _mintRandomItem(ctx, info, oracle, sc, CalcLib.nextPrng);

    return result;
  }

  /// @notice Mint single random item
  /// @param nextPrng_ CalcLib.nextPrng, param is required by unit tests
  function _mintRandomItem(
    IGOC.ActionContext calldata ctx,
    IGOC.EventInfo storage info,
    IOracle oracle,
    IStatController sc,
    function (LibPRNG.PRNG memory, uint) internal view returns (uint) nextPrng_
  ) internal returns (address[] memory minted) {
    bytes32[] memory mintItemsPacked = info.mintItems;
    if (mintItemsPacked.length == 0) {
      return minted;
    }

    IStatController.ChangeableStats memory stats = sc.heroStats(ctx.heroToken, ctx.heroTokenId);

    address[] memory mintItems = new address[](mintItemsPacked.length);
    uint32[] memory mintItemsChances = new uint32[](mintItemsPacked.length);

    for (uint i = 0; i < mintItemsPacked.length; i++) {
      (mintItems[i], mintItemsChances[i]) = mintItemsPacked[i].unpackItemMintInfo();
    }

    return ItemLib._mintRandomItems(
      ItemLib.MintItemInfo({
        mintItems: mintItems,
        mintItemsChances: mintItemsChances,
        amplifier: 0,
        seed: 0,
        oracle: oracle,
        magicFind: 0,
        destroyItems: 0,
        maxItems: 1, // MINT ONLY 1 ITEM!
        mintDropChanceDelta: StatLib.mintDropChanceDelta(stats.experience, uint8(stats.level), ctx.biome),
        mintDropChanceNgLevelMultiplier: 1e18
      }),
      nextPrng_
    );
  }
  //endregion ------------------------ Internal logic
}
