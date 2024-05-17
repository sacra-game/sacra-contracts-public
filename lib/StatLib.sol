// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IStatController.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IAppErrors.sol";
import "../openzeppelin/Math.sol";
import "./CalcLib.sol";
import "./PackingLib.sol";

library StatLib {
  using PackingLib for bytes32[];
  using PackingLib for bytes32;
  using PackingLib for uint32[];
  using PackingLib for int32[];
  using CalcLib for int32;

  //region --------------------------- Constants

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant STAT_LIB_VERSION = "1.0.0";
  uint32 public constant MAX_LEVEL = 99;

  uint public constant BASE_EXPERIENCE = 100_000;
  uint public constant BIOME_LEVEL_STEP = 5;
  uint internal constant _MAX_AMPLIFIER = 1e18;
  uint private constant _PRECISION = 1e18;

  /// @dev Assume MAX_BIOME * BIOME_LEVEL_STEP < MAX_LEVEL + 1, see dungeonTreasuryReward
  uint public constant MAX_POSSIBLE_BIOME = 19;
  //endregion --------------------------- Constants

  //region --------------------------- Data types

  struct BaseMultiplier {
    uint minDamage;
    uint maxDamage;
    uint attackRating;
    uint defense;
    uint blockRating;
    uint life;
    uint mana;
  }

  struct LevelUp {
    uint life;
    uint mana;
  }

  struct InitialHero {
    IStatController.CoreAttributes core;
    BaseMultiplier multiplier;
    LevelUp levelUp;
    int32 baseLifeChances;
  }

  enum HeroClasses {
    UNKNOWN,
    THRALL,
    SAVAGE,
    MAGE,
    ASSASSIN,
    GHOST,
    HAMMERGINA,
    END_SLOT
  }
  //endregion --------------------------- Data types

  //region --------------------------- BASE

  // --- HERO 1 (Slave) ---

  function initialHero1() internal pure returns (InitialHero memory) {
    return InitialHero({
      core: IStatController.CoreAttributes({
      strength: 15,
      dexterity: 15,
      vitality: 30,
      energy: 10
    }),

      multiplier: BaseMultiplier({
      minDamage: 0.1e18,
      maxDamage: 0.2e18,
      attackRating: 2e18,
      defense: 2e18,
      blockRating: 0.1e18,
      life: 1.5e18,
      mana: 0.5e18
    }),

      levelUp: LevelUp({
      life: 2e18,
      mana: 1e18
    }),

      baseLifeChances: 5
    });
  }

  // --- HERO 2 (Spata) ---

  function initialHero2() internal pure returns (InitialHero memory) {
    return InitialHero({
      core: IStatController.CoreAttributes({
      strength: 30,
      dexterity: 5,
      vitality: 25,
      energy: 10
    }),

      multiplier: BaseMultiplier({
      minDamage: 0.15e18,
      maxDamage: 0.25e18,
      attackRating: 2e18,
      defense: 1e18,
      blockRating: 0.08e18,
      life: 1.3e18,
      mana: 0.5e18
    }),

      levelUp: LevelUp({
      life: 1.8e18,
      mana: 1e18
    }),

      baseLifeChances: 5
    });
  }

  // --- HERO 3 (Decidia) ---

  function initialHero3() internal pure returns (InitialHero memory) {
    return InitialHero({
      core: IStatController.CoreAttributes({
      strength: 10,
      dexterity: 15,
      vitality: 20,
      energy: 25
    }),

      multiplier: BaseMultiplier({
      minDamage: 0.1e18,
      maxDamage: 0.2e18,
      attackRating: 2e18,
      defense: 1e18,
      blockRating: 0.1e18,
      life: 1e18,
      mana: 2e18
    }),

      levelUp: LevelUp({
      life: 1.3e18,
      mana: 2e18
    }),

      baseLifeChances: 5
    });
  }

  // --- HERO 4 (Innatus) ---

  function initialHero4() internal pure returns (InitialHero memory) {
    return InitialHero({
      core: IStatController.CoreAttributes({
      strength: 15,
      dexterity: 25,
      vitality: 15,
      energy: 15
    }),

      multiplier: BaseMultiplier({
      minDamage: 0.1e18,
      maxDamage: 0.2e18,
      attackRating: 4e18,
      defense: 3e18,
      blockRating: 0.2e18,
      life: 1.2e18,
      mana: 1e18
    }),

      levelUp: LevelUp({
      life: 1.7e18,
      mana: 1.5e18
    }),

      baseLifeChances: 5
    });
  }

  // --- HERO 5 (F2P) ---

  function initialHero5() internal pure returns (InitialHero memory) {
    return InitialHero({
      core: IStatController.CoreAttributes({
      strength: 20,
      dexterity: 20,
      vitality: 20,
      energy: 10
    }),

      multiplier: BaseMultiplier({
      minDamage: 0.15e18,
      maxDamage: 0.25e18,
      attackRating: 3e18,
      defense: 2.5e18,
      blockRating: 0.15e18,
      life: 1.5e18,
      mana: 1.5e18
    }),

      levelUp: LevelUp({
      life: 1.5e18,
      mana: 1.5e18
    }),

      baseLifeChances: 1
    });
  }

  // --- HERO 6 (F2P) HAMMERGINA ---

  function initialHero6() internal pure returns (InitialHero memory) {
    return InitialHero({
      core: IStatController.CoreAttributes({
      strength: 50,
      dexterity: 30,
      vitality: 50,
      energy: 15
    }),

      multiplier: BaseMultiplier({
      minDamage: 0.2e18,
      maxDamage: 0.3e18,
      attackRating: 5e18,
      defense: 3e18,
      blockRating: 0.15e18,
      life: 2e18,
      mana: 2e18
    }),

      levelUp: LevelUp({
      life: 1.7e18,
      mana: 1.5e18
    }),

      baseLifeChances: 1
    });
  }

  // ------

  function initialHero(uint heroClass) internal pure returns (InitialHero memory) {
    if (heroClass == 1) {
      return initialHero1();
    } else if (heroClass == 2) {
      return initialHero2();
    } else if (heroClass == 3) {
      return initialHero3();
    } else if (heroClass == 4) {
      return initialHero4();
    } else if (heroClass == 5) {
      return initialHero5();
    } else if (heroClass == 6) {
      return initialHero6();
    } else {
      revert IAppErrors.UnknownHeroClass(heroClass);
    }
  }
  //endregion --------------------------- BASE

  //region --------------------------- CALCULATIONS

  function minDamage(int32 strength, uint heroClass) internal pure returns (int32) {
    return int32(int(strength.toUint() * initialHero(heroClass).multiplier.minDamage / _PRECISION));
  }

  function maxDamage(int32 strength, uint heroClass) internal pure returns (int32){
    return int32(int(strength.toUint() * initialHero(heroClass).multiplier.maxDamage / _PRECISION));
  }

  function attackRating(int32 dexterity, uint heroClass) internal pure returns (int32){
    return int32(int(dexterity.toUint() * initialHero(heroClass).multiplier.attackRating / _PRECISION));
  }

  function defense(int32 dexterity, uint heroClass) internal pure returns (int32){
    return int32(int(dexterity.toUint() * initialHero(heroClass).multiplier.defense / _PRECISION));
  }

  function blockRating(int32 dexterity, uint heroClass) internal pure returns (int32){
    return int32(int(Math.min((dexterity.toUint() * initialHero(heroClass).multiplier.blockRating / _PRECISION), 75)));
  }

  function life(int32 vitality, uint heroClass, uint32 level) internal pure returns (int32){
    return int32(int(
      (vitality.toUint() * initialHero(heroClass).multiplier.life / _PRECISION)
      + (uint(level) * initialHero(heroClass).levelUp.life / _PRECISION)
    ));
  }

  function mana(int32 energy, uint heroClass, uint32 level) internal pure returns (int32){
    return int32(int(
      (energy.toUint() * initialHero(heroClass).multiplier.mana / _PRECISION)
      + (uint(level) * initialHero(heroClass).levelUp.mana / _PRECISION)
    ));
  }

  function lifeChances(uint heroClass, uint32 /*level*/) internal pure returns (int32){
    return initialHero(heroClass).baseLifeChances;
  }

  function levelExperience(uint32 level) internal pure returns (uint32) {
    if (level == 0 || level >= MAX_LEVEL) {
      return 0;
    }
    return uint32(uint(level) * BASE_EXPERIENCE * (67e17 - CalcLib.log2((uint(MAX_LEVEL - level + 2)) * 1e18)) / 1e18);
  }

  function chanceToHit(
    uint attackersAttackRating,
    uint defendersDefenceRating,
    uint attackersLevel,
    uint defendersLevel,
    uint arFactor
  ) internal pure returns (uint) {
    attackersAttackRating += attackersAttackRating * arFactor / 100;
    uint x = Math.max(attackersAttackRating, 1);
    uint y = Math.max(attackersAttackRating + defendersDefenceRating, 1);
    uint z = attackersLevel;
    uint k = defendersLevel / 2;
    uint xy = x * 1e18 / y;
    uint zk = z * 1e18 / (attackersLevel + k);
    uint base = 2 * xy * zk / 1e18;
    return Math.max(Math.min(base, 0.95e18), 0.2e18);
  }

  function experienceToLvl(uint experience, uint startFromLevel) internal pure returns (uint level) {
    level = startFromLevel;
    for (; level < MAX_LEVEL;) {
      if (levelExperience(uint32(level)) >= experience) {
        break;
      }
      unchecked{++level;}
    }
  }

  function expPerMonster(uint32 monsterExp, uint monsterRarity, uint32 heroExp, uint32 heroCurrentLvl, uint monsterBiome) internal pure returns (uint32) {
    uint heroLvl = experienceToLvl(uint(heroExp), uint(heroCurrentLvl));
    uint heroBiome = heroLvl / StatLib.BIOME_LEVEL_STEP + 1;
    uint base = uint(monsterExp) + uint(monsterExp) * monsterRarity / _MAX_AMPLIFIER;

    // reduce exp if hero not in his biome
    if (heroBiome > monsterBiome) {
      base = base / (2 ** (heroBiome - monsterBiome));
    }
    return uint32(base);
  }

  /// @notice Allow to calculate delta param for {mintDropChance}
  function mintDropChanceDelta(uint experience, uint startFromLevel, uint monsterBiome) internal pure returns (uint) {
    uint heroBiome = StatLib.experienceToLvl(experience, startFromLevel) / StatLib.BIOME_LEVEL_STEP + 1;
    return heroBiome > monsterBiome ? 2**(heroBiome - monsterBiome) : 0;
  }

  /// @param delta 2 ** (heroBiome - monsterBiome) or zero if heroBiome < monsterBiome, see {mintDropChanceDelta}
  function mintDropChance(uint baseChance, uint monsterRarity, uint delta) internal pure returns (uint) {
    uint chance = baseChance + baseChance * monsterRarity / _MAX_AMPLIFIER;

    // reduce chance if hero not in his biome
    return delta == 0
      ? chance
      : chance / delta;
  }

  function initAttributes(
    bytes32[] storage attributes,
    uint heroClass,
    uint32 level,
    IStatController.CoreAttributes memory base
  ) internal returns (uint32[] memory result) {

    attributes.setInt32(uint(IStatController.ATTRIBUTES.STRENGTH), base.strength);
    attributes.setInt32(uint(IStatController.ATTRIBUTES.DEXTERITY), base.dexterity);
    attributes.setInt32(uint(IStatController.ATTRIBUTES.VITALITY), base.vitality);
    attributes.setInt32(uint(IStatController.ATTRIBUTES.ENERGY), base.energy);

    attributes.setInt32(uint(IStatController.ATTRIBUTES.DAMAGE_MIN), minDamage(base.strength, heroClass));
    attributes.setInt32(uint(IStatController.ATTRIBUTES.DAMAGE_MAX), maxDamage(base.strength, heroClass));
    attributes.setInt32(uint(IStatController.ATTRIBUTES.ATTACK_RATING), attackRating(base.dexterity, heroClass));
    attributes.setInt32(uint(IStatController.ATTRIBUTES.DEFENSE), defense(base.dexterity, heroClass));
    attributes.setInt32(uint(IStatController.ATTRIBUTES.BLOCK_RATING), blockRating(base.dexterity, heroClass));
    attributes.setInt32(uint(IStatController.ATTRIBUTES.LIFE), life(base.vitality, heroClass, level));
    attributes.setInt32(uint(IStatController.ATTRIBUTES.MANA), mana(base.energy, heroClass, level));
    attributes.setInt32(uint(IStatController.ATTRIBUTES.LIFE_CHANCES), lifeChances(heroClass, level));

    result = new uint32[](3);
    result[0] = uint32(life(base.vitality, heroClass, level).toUint());
    result[1] = uint32(mana(base.energy, heroClass, level).toUint());
    result[2] = uint32(lifeChances(heroClass, uint32(level)).toUint());
  }

  function updateCoreDependAttributesInMemory(
    int32[] memory attributes,
    int32[] memory bonus,
    uint heroClass,
    uint32 level
  ) internal pure returns (int32[] memory) {
    int32 strength = attributes[uint(IStatController.ATTRIBUTES.STRENGTH)];
    int32 dexterity = attributes[uint(IStatController.ATTRIBUTES.DEXTERITY)];
    int32 vitality = attributes[uint(IStatController.ATTRIBUTES.VITALITY)];
    int32 energy = attributes[uint(IStatController.ATTRIBUTES.ENERGY)];

    attributes[uint(IStatController.ATTRIBUTES.DAMAGE_MIN)] = minDamage(strength, heroClass) + bonus[uint(IStatController.ATTRIBUTES.DAMAGE_MIN)];
    attributes[uint(IStatController.ATTRIBUTES.DAMAGE_MAX)] = maxDamage(strength, heroClass) + bonus[uint(IStatController.ATTRIBUTES.DAMAGE_MAX)];
    attributes[uint(IStatController.ATTRIBUTES.ATTACK_RATING)] = attackRating(dexterity, heroClass) + bonus[uint(IStatController.ATTRIBUTES.ATTACK_RATING)];
    attributes[uint(IStatController.ATTRIBUTES.DEFENSE)] = defense(dexterity, heroClass) + bonus[uint(IStatController.ATTRIBUTES.DEFENSE)];
    attributes[uint(IStatController.ATTRIBUTES.BLOCK_RATING)] = blockRating(dexterity, heroClass) + bonus[uint(IStatController.ATTRIBUTES.BLOCK_RATING)];
    attributes[uint(IStatController.ATTRIBUTES.LIFE)] = life(vitality, heroClass, level) + bonus[uint(IStatController.ATTRIBUTES.LIFE)];
    attributes[uint(IStatController.ATTRIBUTES.MANA)] = mana(energy, heroClass, level) + bonus[uint(IStatController.ATTRIBUTES.MANA)];
    return attributes;
  }

  function updateCoreDependAttributes(
    IController controller,
    bytes32[] storage attributes,
    bytes32[] storage bonusMain,
    bytes32[] storage bonusExtra,
    IStatController.ChangeableStats memory _heroStats,
    uint index,
    address heroToken,
    int32 base
  ) internal {
    uint heroClass = IHeroController(controller.heroController()).heroClass(heroToken);
    if (index == uint(IStatController.ATTRIBUTES.STRENGTH)) {

      attributes.setInt32(uint(IStatController.ATTRIBUTES.DAMAGE_MIN),
        StatLib.minDamage(base, heroClass)
        + bonusMain.getInt32(uint(IStatController.ATTRIBUTES.DAMAGE_MIN))
        + bonusExtra.getInt32(uint(IStatController.ATTRIBUTES.DAMAGE_MIN))
      );
      attributes.setInt32(uint(IStatController.ATTRIBUTES.DAMAGE_MAX),
        StatLib.maxDamage(base, heroClass)
        + bonusMain.getInt32(uint(IStatController.ATTRIBUTES.DAMAGE_MAX))
        + bonusExtra.getInt32(uint(IStatController.ATTRIBUTES.DAMAGE_MAX))
      );
    } else if (index == uint(IStatController.ATTRIBUTES.DEXTERITY)) {

      attributes.setInt32(uint(IStatController.ATTRIBUTES.ATTACK_RATING),
        StatLib.attackRating(base, heroClass)
        + bonusMain.getInt32(uint(IStatController.ATTRIBUTES.ATTACK_RATING))
        + bonusExtra.getInt32(uint(IStatController.ATTRIBUTES.ATTACK_RATING))
      );

      attributes.setInt32(uint(IStatController.ATTRIBUTES.DEFENSE),
        StatLib.defense(base, heroClass)
        + bonusMain.getInt32(uint(IStatController.ATTRIBUTES.DEFENSE))
        + bonusExtra.getInt32(uint(IStatController.ATTRIBUTES.DEFENSE))
      );

      attributes.setInt32(uint(IStatController.ATTRIBUTES.BLOCK_RATING),
        StatLib.blockRating(base, heroClass)
        + bonusMain.getInt32(uint(IStatController.ATTRIBUTES.BLOCK_RATING))
        + bonusExtra.getInt32(uint(IStatController.ATTRIBUTES.BLOCK_RATING))
      );
    } else if (index == uint(IStatController.ATTRIBUTES.VITALITY)) {

      attributes.setInt32(uint(IStatController.ATTRIBUTES.LIFE),
        StatLib.life(base, heroClass, _heroStats.level)
        + bonusMain.getInt32(uint(IStatController.ATTRIBUTES.LIFE))
        + bonusExtra.getInt32(uint(IStatController.ATTRIBUTES.LIFE))
      );
    } else if (index == uint(IStatController.ATTRIBUTES.ENERGY)) {

      attributes.setInt32(uint(IStatController.ATTRIBUTES.MANA),
        StatLib.mana(base, heroClass, _heroStats.level)
        + bonusMain.getInt32(uint(IStatController.ATTRIBUTES.MANA))
        + bonusExtra.getInt32(uint(IStatController.ATTRIBUTES.MANA))
      );
    }
  }

  function attributesAdd(int32[] memory base, int32[] memory add) internal pure returns (int32[] memory) {
    unchecked{
      for (uint i; i < base.length; ++i) {
        base[i] += add[i];
      }
    }
    return base;
  }

// Currently this function is not used
//  function attributesRemove(int32[] memory base, int32[] memory remove) internal pure returns (int32[] memory) {
//    unchecked{
//      for (uint i; i < base.length; ++i) {
//        base[i] = CalcLib.minusWithMinFloorI32(base[i], remove[i]);
//      }
//    }
//    return base;
//  }

  function packChangeableStats(IStatController.ChangeableStats memory stats) internal pure returns (bytes32) {
    uint32[] memory cData = new uint32[](5);
    cData[0] = stats.level;
    cData[1] = stats.experience;
    cData[2] = stats.life;
    cData[3] = stats.mana;
    cData[4] = stats.lifeChances;

    return cData.packUint32Array();
  }

  function unpackChangeableStats(bytes32 data) internal pure returns (IStatController.ChangeableStats memory result) {
    uint32[] memory cData = data.unpackUint32Array();
    return IStatController.ChangeableStats({
      level: cData[0],
      experience: cData[1],
      life: cData[2],
      mana: cData[3],
      lifeChances: cData[4]
    });
  }

  function bytesToFullAttributesArray(bytes32[] memory attributes) internal pure returns (int32[] memory result) {
    (int32[] memory values, uint8[] memory ids) = attributes.toInt32ArrayWithIds();
    return valuesToFullAttributesArray(values, ids);
  }

  function valuesToFullAttributesArray(int32[] memory values, uint8[] memory ids) internal pure returns (int32[] memory result) {
    result = new int32[](uint(IStatController.ATTRIBUTES.END_SLOT));
    for (uint i; i < values.length; ++i) {
      int32 value = values[i];
      if (value != 0) {
        result[ids[i]] = value;
      }
    }
  }
  //endregion --------------------------- CALCULATIONS

}
