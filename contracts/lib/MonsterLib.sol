// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IGOC.sol";
import "./CalcLib.sol";
import "./PackingLib.sol";
import "./StatLib.sol";
import "./ItemLib.sol";
import "./StringLib.sol";
import "./FightLib.sol";
import "./RewardsPoolLib.sol";
import "../interfaces/IController.sol";
import "../interfaces/IStatController.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IFightCalculator.sol";
import "../interfaces/IDungeonFactory.sol";
import "../interfaces/IItemController.sol";
import "../interfaces/IERC20.sol";

library MonsterLib {
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

  /// @notice Max value for monster rarity and monster/dungeon multiplier
  uint32 internal constant _MAX_AMPLIFIER = 1e9;
  uint private constant _TOTAL_SUPPLY_BASE = 10_000_000e18;

  /// @notice Base monster multiplier for NG+. Multiplier = base multiplier * hero ng_level
  uint internal constant _MONSTER_MULTIPLIER_NGP_BASE = uint(_MAX_AMPLIFIER);

  //region ------------------------ Data types
  struct AdrContext {
    address sender;
    address heroToken;
    IController controller;
    IOracle oracle;
    IStatController statController;
    IItemController itemController;
    uint heroTokenId;
  }

  struct FightInternalInfo {
    int32 manaConsumed;
    int32 damage;
    int32 heroLifeRegen;
    int32 heroHp;
    int32 monsterHp;
    uint32 monsterRarity;
    IFightCalculator.FighterInfo heroFightInfo;
    IFightCalculator.FighterInfo monsterFightInfo;
  }
  //endregion ------------------------ Data types

  //region ------------------------ Main logic

  /// @param heroNgLevel Pass type(uint8).max for !NG+
  function initialGeneration(
    IGOC.MonsterInfo storage mInfo,
    address heroToken,
    uint heroTokenId,
    uint iteration,
    uint8 heroNgLevel
  ) internal {
    return _initialGeneration(mInfo, heroToken, heroTokenId, iteration, _pseudoRandom, heroNgLevel);
  }

  /// @notice Fight, post fight, generate fight results
  /// @return result Fields objectId, heroToken, heroTokenId, iteration remain uninitialized here.
  /// Caller is responsible to set that values.
  /// @dev weird, but memory ctx is more efficient here than calldata ctx
  function action(IGOC.ActionContext memory ctx, IGOC.MonsterInfo storage mInfo) external returns (
    IGOC.ActionResult memory result,
    uint8 turn
  ) {
    return _action(ctx, mInfo, _pseudoRandom, FightLib.fight);
  }

  //endregion ------------------------ Main logic

  //region ------------------------ Internal calculations
  function _action(
    IGOC.ActionContext memory ctx,
    IGOC.MonsterInfo storage mInfo,
    function (uint) internal view returns (uint) random_,
    function(
      IItemController,
      IFightCalculator.FightCall memory,
      address,
      function (uint) internal view returns (uint)
    ) internal returns (IFightCalculator.FightResult memory) fight_
  ) internal returns (
    IGOC.ActionResult memory result,
    uint8 turn
  ) {
    AdrContext memory adrCtx = _context(ctx);
    IGOC.GeneratedMonster memory gen = unpackGeneratedMonster(mInfo._generatedMonsters[ctx.heroToken.packNftId(ctx.heroTokenId)][ctx.iteration]);
    turn = gen.turnCounter;

    (FightInternalInfo memory fInfo, IGOC.MonsterGenInfo memory genInfo) = _fight(ctx, mInfo, gen, adrCtx, random_, fight_);
    result = _postFight(mInfo, ctx, adrCtx, fInfo, genInfo, gen);
  }

  /// @dev This function was extracted from {action()} to simplify unit testing
  /// @param gen These values CAN BE modified in place in some cases.
  /// @return result Fields objectId, heroToken, heroTokenId, iteration remain uninitialized here.
  /// Caller is responsible to set that values.
  function _postFight(
    IGOC.MonsterInfo storage mInfo,
    IGOC.ActionContext memory ctx,
    AdrContext memory adrCtx,
    FightInternalInfo memory fInfo,
    IGOC.MonsterGenInfo memory genInfo,
    IGOC.GeneratedMonster memory gen
  ) internal returns (
    IGOC.ActionResult memory result
  ) {
    bytes32 heroPackedId = ctx.heroToken.packNftId(ctx.heroTokenId);
    if (gen.turnCounter > 100) {
      // instant kill hero if too long battle
      fInfo.heroHp = 0;
    }

    bool isMonsterDead = fInfo.monsterHp == 0;
    bool isHeroDead = fInfo.heroHp == 0;

    if (isMonsterDead) {
      _bossDefeated(adrCtx, ctx);
    }

    if (isMonsterDead || isHeroDead) {
      if (gen.generated) {
        delete mInfo._generatedMonsters[heroPackedId][ctx.iteration];
      }
      // assume that if the hero is dead clearUsedConsumables will be called in _objectAction
      if (isMonsterDead) {
        adrCtx.statController.clearUsedConsumables(ctx.heroToken, ctx.heroTokenId);
      }
    } else {
      if (gen.generated) {
        gen.hp = fInfo.monsterHp;
        gen.turnCounter = gen.turnCounter + 1;
      } else {
        // new instance of gen is created
        gen = IGOC.GeneratedMonster({
          generated: true,
          amplifier: fInfo.monsterRarity,
          hp: fInfo.monsterHp,
          turnCounter: 1
        });
      }

      mInfo._generatedMonsters[heroPackedId][ctx.iteration] = packGeneratedMonster(gen);
    }

    if (isMonsterDead) {
      bytes32 index = _getMonsterCounterIndex(ctx.objectId);
      uint curValue = adrCtx.statController.heroCustomData(ctx.heroToken, ctx.heroTokenId, index);
      adrCtx.statController.setHeroCustomData(ctx.heroToken, ctx.heroTokenId, index, curValue + 1);
    }

    // --- generate result
    result.kill = isHeroDead;
    result.experience = isMonsterDead
      ? StatLib.expPerMonster(
        fInfo.monsterFightInfo.fighterStats.experience,
        fInfo.monsterRarity,
        fInfo.heroFightInfo.fighterStats.experience,
        fInfo.heroFightInfo.fighterStats.level,
        ctx.biome
      )
      : 0;

    result.heal = fInfo.heroLifeRegen;
    result.manaRegen = isMonsterDead ? fInfo.heroFightInfo.fighterAttributes[uint(IStatController.ATTRIBUTES.MANA_AFTER_KILL)] : int32(0);
    // result.lifeChancesRecovered = 0; // zero by default
    result.damage = fInfo.damage;
    result.manaConsumed = fInfo.manaConsumed;
    result.mintItems = isMonsterDead
      ? _mintRandomItems(fInfo, ctx, genInfo, CalcLib.nextPrng)
      : new address[](0);
    result.completed = isMonsterDead || isHeroDead;

    return result;
  }

  /// @notice Generate new {GeneratedMonster} and put it to {mInfo._generatedMonsters}
  /// @param random_ Pass _pseudoRandom here, param is required for unit tests, range [0...MAX_AMPLIFIER]
  /// @param heroNgLevel Assume type(uint8).max for !NG+
  function _initialGeneration(
    IGOC.MonsterInfo storage mInfo,
    address heroToken,
    uint heroTokenId,
    uint iteration,
    function (uint) internal view returns (uint) random_,
    uint8 heroNgLevel
  ) internal {
    IGOC.GeneratedMonster memory gen = IGOC.GeneratedMonster({
      generated: true,
      amplifier: uint32(random_(_MAX_AMPLIFIER)),
      hp: 0,
      turnCounter: 0
    });

    IGOC.MonsterGenInfo memory info = unpackMonsterInfo(mInfo);

    (int32[] memory attributes,) = generateMonsterAttributes(
      info.attributeIds,
      info.attributeValues,
      gen.amplifier,
      monsterMultiplier(heroNgLevel),
      info.experience
    );
    gen.hp = attributes[uint(IStatController.ATTRIBUTES.LIFE)];

    mInfo._generatedMonsters[heroToken.packNftId(heroTokenId)][iteration] = packGeneratedMonster(gen);
  }

  function _bossDefeated(AdrContext memory adrCtx, IGOC.ActionContext memory ctx) internal {
    if (ctx.objectSubType == uint8(IGOC.ObjectSubType.BOSS_3)) {
      IDungeonFactory(adrCtx.controller.dungeonFactory()).setBossCompleted(ctx.objectId, ctx.heroToken, ctx.heroTokenId, ctx.biome);
    }
  }

  function _collectHeroFighterInfo(
    IFightCalculator.AttackInfo memory attackInfo,
    AdrContext memory adrContext
  ) internal view returns (
    IFightCalculator.FighterInfo memory fInfo,
    int32 manaConsumed
  ) {
    IStatController.ChangeableStats memory heroStats = adrContext.statController.heroStats(adrContext.heroToken, adrContext.heroTokenId);

    (int32[] memory heroAttributes, int32 _manaConsumed) = _buffAndGetHeroAttributes(heroStats.level, attackInfo, adrContext);

    manaConsumed = _manaConsumed;

    if (attackInfo.attackType == IFightCalculator.AttackType.MAGIC) {
      manaConsumed += int32(adrContext.itemController.itemMeta(attackInfo.attackToken).manaCost);
    }

    fInfo = IFightCalculator.FighterInfo({
      fighterAttributes: heroAttributes,
      fighterStats: heroStats,
      attackType: attackInfo.attackType,
      attackToken: attackInfo.attackToken,
      attackTokenId: attackInfo.attackTokenId,
      race: uint(IStatController.Race.HUMAN)
    });
  }

  function _buffAndGetHeroAttributes(
    uint level,
    IFightCalculator.AttackInfo memory attackInfo,
    AdrContext memory context
  ) internal view returns (
    int32[] memory heroAttributes,
    int32 manaConsumed
  ) {
    return context.statController.buffHero(IStatController.BuffInfo({
      heroToken: context.heroToken,
      heroTokenId: context.heroTokenId,
      heroLevel: uint32(level),
      buffTokens: attackInfo.skillTokens,
      buffTokenIds: attackInfo.skillTokenIds
    }));
  }

  /// @notice Get skill tokens, ensure that they are equipped on, add skill-tokens target attributes to hero attributes
  /// @param attributes Hero attributes. These values are incremented in place
  // @param heroAttackInfo Checked attack info. Assume that all skill tokens belong either to the hero or to the helper.
  function _debuff(
    int32[] memory attributes,
    IFightCalculator.AttackInfo memory heroAttackInfo,
    AdrContext memory context
  ) internal view {
    uint length = heroAttackInfo.skillTokens.length;
    for (uint i; i < length; ++i) {
      (int32[] memory values, uint8[] memory ids) = context.itemController.targetAttributes(
        heroAttackInfo.skillTokens[i],
        heroAttackInfo.skillTokenIds[i]
      );

      StatLib.attributesAdd(attributes, StatLib.valuesToFullAttributesArray(values, ids));
    }
  }

  /// @param random_ Pass _pseudoRandom here, param is required for unit tests, range [0...MAX_AMPLIFIER]
  function _collectMonsterFighterInfo(
    IGOC.MultiplierInfo memory multiplierInfo,
    IGOC.MonsterInfo storage mInfo,
    IGOC.GeneratedMonster memory gen,
    IFightCalculator.AttackInfo memory heroAttackInfo,
    uint heroLevel,
    AdrContext memory adrCtx,
    function (uint) internal view returns (uint) random_
  ) internal view returns (
    IFightCalculator.FighterInfo memory fighterInfo,
    uint32 rarity,
    IGOC.MonsterGenInfo memory genInfo
  ) {
    IFightCalculator.AttackInfo memory attackInfo;

    rarity = gen.generated ? gen.amplifier : uint32(random_(_MAX_AMPLIFIER));
    (
      fighterInfo.fighterAttributes,
      fighterInfo.fighterStats.level,
      fighterInfo.fighterStats.experience,
      attackInfo,
      genInfo
    ) = _generateMonsterInfo(
      mInfo,
      rarity,
      monsterMultiplier(multiplierInfo.heroNgLevel),
      heroLevel,
      multiplierInfo.biome,
      random_
    );

    _debuff(fighterInfo.fighterAttributes, heroAttackInfo, adrCtx);

    fighterInfo.fighterStats.life = gen.generated
      ? uint32(gen.hp)
      : fighterInfo.fighterStats.life = uint32(CalcLib.max32(fighterInfo.fighterAttributes[uint(IStatController.ATTRIBUTES.LIFE)], int32(1)));

    fighterInfo.fighterStats.mana = uint32(fighterInfo.fighterAttributes[uint(IStatController.ATTRIBUTES.MANA)]);

    fighterInfo.attackType = attackInfo.attackType;
    fighterInfo.attackToken = attackInfo.attackToken;
    fighterInfo.attackTokenId = attackInfo.attackTokenId;
    fighterInfo.race = genInfo.race;

    return (fighterInfo, rarity, genInfo);
  }

  /// @param random_ Pass _pseudoRandom here, param is required to simplify unit testing
  /// @param fight_ Pass FightLib.fight here, param is required to simplify unit testing
  function _fight(
    IGOC.ActionContext memory ctx,
    IGOC.MonsterInfo storage mInfo,
    IGOC.GeneratedMonster memory gen,
    AdrContext memory adrCtx,
    function (uint) internal view returns (uint) random_,
    function(
      IItemController,
      IFightCalculator.FightCall memory,
      address,
      function (uint) internal view returns (uint)
    ) internal returns (IFightCalculator.FightResult memory) fight_
  ) internal returns (
    FightInternalInfo memory fInfo,
    IGOC.MonsterGenInfo memory info
  ) {
    IFightCalculator.FighterInfo memory heroFightInfo;
    IFightCalculator.FighterInfo memory monsterFightInfo;

    {
      IFightCalculator.AttackInfo memory heroAttackInfo = decodeAndCheckAttackInfo(
        adrCtx.itemController,
        IHeroController(IController(adrCtx.controller).heroController()),
        ctx.data,
        adrCtx.heroToken,
        adrCtx.heroTokenId
      );

      // use fInfo.manaConsumed and fInfo.monsterRarity to story values temporally to avoid creation of additional vars
      (heroFightInfo, fInfo.manaConsumed) = _collectHeroFighterInfo(heroAttackInfo, adrCtx);
      (monsterFightInfo, fInfo.monsterRarity, info) = _collectMonsterFighterInfo(
        IGOC.MultiplierInfo({
          biome: ctx.biome,
          heroNgLevel: ctx.heroNgLevel
        }),
        mInfo,
        gen,
        heroAttackInfo,
        heroFightInfo.fighterStats.level,
        adrCtx,
        random_
      );
    }

    // >>> FIGHT!
    IFightCalculator.FightResult memory fightResult = fight_(
      adrCtx.itemController,
      IFightCalculator.FightCall({
        fighterA: heroFightInfo,
        fighterB: monsterFightInfo,
        dungeonId: ctx.dungeonId,
        objectId: ctx.objectId,
        heroAdr: adrCtx.heroToken,
        heroId: adrCtx.heroTokenId,
        stageId: ctx.stageId,
        iteration: ctx.iteration,
        turn: gen.turnCounter
      }),
      ctx.sender,
      random_
    );

    fInfo = FightInternalInfo({
      manaConsumed: fInfo.manaConsumed + fightResult.manaConsumedA,
      monsterRarity: fInfo.monsterRarity,
      damage: _calcDmg(int32(heroFightInfo.fighterStats.life), fightResult.healthA),
      heroFightInfo: heroFightInfo,
      monsterFightInfo: monsterFightInfo,
      heroLifeRegen: fightResult.healthA > int32(heroFightInfo.fighterStats.life) ? fightResult.healthA - int32(heroFightInfo.fighterStats.life) : int32(0),
      heroHp: fightResult.healthA,
      monsterHp: fightResult.healthB
    });
  }

  /// @param random_ Pass _pseudoRandom here, param is required for unit tests, range [0...1e18]
  /// @return attributes Attributes amplified on amplifier and dungeonMultiplier
  /// @return level Result level in the range: [mInfo.level .. heroLevel]
  /// @return experience Experience amplified on amplifier and dungeonMultiplier
  /// @return attackInfo Attack info. For magic hero attack type monster will have melee in half hits (randomly)
  /// @return info Unpacked data from {mInfo}, some fields can be uninitialized, see comments to unpackMonsterInfo (!)
  function _generateMonsterInfo(
    IGOC.MonsterInfo storage mInfo,
    uint32 amplifier,
    uint dungeonMultiplier,
    uint heroLevel,
    uint biome,
    function (uint) internal view returns (uint) random_
  ) internal view returns (
    int32[] memory attributes,
    uint32 level,
    uint32 experience,
    IFightCalculator.AttackInfo memory attackInfo,
    IGOC.MonsterGenInfo memory info
  ) {
    info = unpackMonsterInfo(mInfo);

    level = uint32(info.level);
    if (level < heroLevel + 1) {
      level = uint32(Math.min(level + ((heroLevel - level) * 10 / 15), biome * 5));
    }

    if (info.attackType == uint8(IFightCalculator.AttackType.MAGIC)) {
      // sometimes use melee (25% chance)
      uint rnd = random_(1e18);
      if (rnd > 0.75e18) {
        attackInfo.attackType = IFightCalculator.AttackType.MELEE;
      } else {
        attackInfo.attackType = IFightCalculator.AttackType.MAGIC;
        attackInfo.attackToken = info.attackToken;
        attackInfo.attackTokenId = info.attackTokenId;
      }
    } else {
      attackInfo.attackType = IFightCalculator.AttackType(info.attackType);
    }

    (attributes, experience) = generateMonsterAttributes(
      info.attributeIds,
      info.attributeValues,
      amplifier,
      dungeonMultiplier,
      info.experience
    );

    return (attributes, level, experience, attackInfo, info);
  }

  function _mintRandomItems(
    FightInternalInfo memory fInfo,
    IGOC.ActionContext memory ctx,
    IGOC.MonsterGenInfo memory genInfo,
    function (LibPRNG.PRNG memory, uint) internal view returns (uint) nextPrng_
  ) internal returns (
    address[] memory
  ) {
    return ItemLib._mintRandomItems(
      ItemLib.MintItemInfo({
        mintItems: genInfo.mintItems,
        mintItemsChances: genInfo.mintItemsChances,
        amplifier: fInfo.monsterRarity,
        seed: 0,
        oracle: IOracle(ctx.controller.oracle()),
        magicFind: fInfo.heroFightInfo.fighterAttributes[uint(IStatController.ATTRIBUTES.MAGIC_FIND)],
        destroyItems: fInfo.heroFightInfo.fighterAttributes[uint(IStatController.ATTRIBUTES.DESTROY_ITEMS)],
        maxItems: genInfo.maxDropItems,
        mintDropChanceDelta: ctx.objectSubType == uint8(IGOC.ObjectSubType.BOSS_3) ? 0 : // do not reduce drop for bosses at all
        StatLib.mintDropChanceDelta(
          fInfo.heroFightInfo.fighterStats.experience,
          uint8(fInfo.heroFightInfo.fighterStats.level),
          ctx.biome
        ),
        mintDropChanceNgLevelMultiplier: _getMintDropChanceNgLevelMultiplier(ctx)
      }),
      nextPrng_
    );
  }

  /// @return drop chance multiplier, decimals 1e18; result value is guaranteed to be <= 1e18
  function _getMintDropChanceNgLevelMultiplier(IGOC.ActionContext memory ctx) internal view returns (uint) {
    return Math.min(1e18, RewardsPoolLib.dropChancePercent(
      IDungeonFactory(ctx.controller.dungeonFactory()).maxAvailableBiome(),
      IHeroController(ctx.controller.heroController()).maxOpenedNgLevel(),
      ctx.heroNgLevel
    ));
  }

  //endregion ------------------------ Internal calculations

  //region ------------------------ Utils

  function _context(IGOC.ActionContext memory ctx) internal view returns (AdrContext memory context) {
    context = AdrContext({
      sender: ctx.sender,
      heroToken: ctx.heroToken,
      heroTokenId: ctx.heroTokenId,
      controller: ctx.controller,
      oracle: IOracle(ctx.controller.oracle()),
      statController: IStatController(ctx.controller.statController()),
      itemController: IItemController(ctx.controller.itemController())
    });
  }

  function unpackGeneratedMonster(bytes32 gen) internal pure returns (IGOC.GeneratedMonster memory result) {
    (bool generated, uint32 amplifier, int32 hp, uint8 turnCounter) = gen.unpackGeneratedMonster();
    result = IGOC.GeneratedMonster({
      generated: generated,
      amplifier: amplifier,
      hp: hp,
      turnCounter: turnCounter
    });
  }

  function packGeneratedMonster(IGOC.GeneratedMonster memory gen) internal pure returns (bytes32) {
    return PackingLib.packGeneratedMonster(gen.generated, gen.amplifier, gen.hp, gen.turnCounter);
  }

  function packMonsterInfo(IGOC.MonsterGenInfo memory mInfo, IGOC.MonsterInfo storage info) internal {
    info.attributes = mInfo.attributeValues.toBytes32ArrayWithIds(mInfo.attributeIds);
    info.stats = PackingLib.packMonsterStats(mInfo.level, mInfo.race, mInfo.experience, mInfo.maxDropItems);
    info.attackInfo = PackingLib.packAttackInfo(mInfo.attackToken, mInfo.attackTokenId, mInfo.attackType);

    uint len = mInfo.mintItems.length;
    bytes32[] memory mintItems = new bytes32[](len);

    for (uint i; i < len; ++i) {
      mintItems[i] = mInfo.mintItems[i].packItemMintInfo(mInfo.mintItemsChances[i]);
    }

    info.mintItems = mintItems;
  }

  /// @return Attention: Following fields are not initialized: biome, subType, monsterId
  function unpackMonsterInfo(IGOC.MonsterInfo storage mInfo) internal view returns (IGOC.MonsterGenInfo memory) {
    IGOC.MonsterGenInfo memory result;
    (result.attributeValues, result.attributeIds) = mInfo.attributes.toInt32ArrayWithIds();
    (result.level, result.race, result.experience, result.maxDropItems) = mInfo.stats.unpackMonsterStats();
    (result.attackToken, result.attackTokenId, result.attackType) = mInfo.attackInfo.unpackAttackInfo();

    uint len = mInfo.mintItems.length;
    result.mintItems = new address[](len);
    result.mintItemsChances = new uint32[](len);

    for (uint i = 0; i < len; i++) {
      (result.mintItems[i], result.mintItemsChances[i]) = mInfo.mintItems[i].unpackItemMintInfo();
    }

    // Attention: result.biome, result.subType, result.monsterId are not initialized
    return result;
  }

  /// @notice Decode attack info. Ensure that attack token belongs to the hero.
  /// Ensure that skill tokens belong to the hero OR to the current helper (SIP-001)
  function decodeAndCheckAttackInfo(
    IItemController ic,
    IHeroController heroController,
    bytes memory data,
    address heroToken,
    uint heroId
  ) internal view returns (IFightCalculator.AttackInfo memory) {
    (IFightCalculator.AttackInfo memory attackInfo) = abi.decode(data, (IFightCalculator.AttackInfo));

    if (uint(attackInfo.attackType) == 0) revert IAppErrors.UnknownAttackType(uint(attackInfo.attackType));

    if (attackInfo.attackToken != address(0)) {
      (address h, uint hId) = ic.equippedOn(attackInfo.attackToken, attackInfo.attackTokenId);
      if (heroToken != h || hId != heroId) revert IAppErrors.NotYourAttackItem();
    }

    (address helperHeroToken, uint helperHeroId) = heroController.heroReinforcementHelp(heroToken, heroId);
    for (uint i; i < attackInfo.skillTokens.length; ++i) {
      (address h, uint hId) = ic.equippedOn(attackInfo.skillTokens[i], attackInfo.skillTokenIds[i]);
      if (
        (heroToken != h || hId != heroId)
        && ((helperHeroToken == address(0)) || (helperHeroToken != h || helperHeroId != hId))
      ) revert IAppErrors.NotYourBuffItem();
    }

    return attackInfo;
  }

  /// @dev Monsters power is increased on 100% with each increment of hero NG_LEVEL
  function monsterMultiplier(uint8 heroNgLevel) internal pure returns (uint) {
    return _MONSTER_MULTIPLIER_NGP_BASE * uint(heroNgLevel);
  }

  function amplifyMonsterAttribute(int32 value, uint32 amplifier, uint dungeonMultiplier) internal pure returns (int32) {
    if (value == 0) {
      return 0;
    }

    int destValue = int(value)
      + (int(value) * int(uint(amplifier)) / int(uint(_MAX_AMPLIFIER)))
      + (int(value) * int(dungeonMultiplier) / int(uint(_MAX_AMPLIFIER)));
    if (destValue > type(int32).max || destValue < type(int32).min) revert IAppErrors.IntValueOutOfRange(destValue);

    return int32(destValue);
  }

  /// @dev A wrapper around {CalcLib.pseudoRandom} to pass it as param (to be able to implement unit tests}
  function _pseudoRandom(uint max) internal view returns (uint) {
    return CalcLib.pseudoRandom(max);
  }

  /// @notice Amplify values of the attributes and of the experience
  ///         using randomly generated {amplifier} and {dungeonMultiplier}.
  ///         Attributes = amplify(ids, values), experience = amplify(baseExperience)
  function generateMonsterAttributes(
    uint8[] memory ids,
    int32[] memory values,
    uint32 amplifier,
    uint dungeonMultiplier,
    uint32 baseExperience
  ) internal pure returns (
    int32[] memory attributes,
    uint32 experience
  ) {
    // reduce random
    amplifier = amplifier / 4;

    attributes = new int32[](uint(IStatController.ATTRIBUTES.END_SLOT));
    for (uint i; i < ids.length; ++i) {
      attributes[ids[i]] = amplifyMonsterAttribute(values[i], amplifier, dungeonMultiplier);
    }
    experience = uint32(amplifyMonsterAttribute(int32(baseExperience), amplifier, 0));
  }

  function _calcDmg(int32 heroLifeBefore, int32 heroLifeAfter) internal pure returns (int32 damage) {
    return heroLifeAfter == 0
      ? heroLifeBefore
      : heroLifeBefore - CalcLib.minI32(heroLifeAfter, heroLifeBefore);
  }

  function _getMonsterCounterIndex(uint32 objectId) internal pure returns (bytes32) {
    return bytes32(abi.encodePacked("MONSTER_", StringLib._toString(uint(objectId))));
  }
  //endregion ------------------------ Utils


}
