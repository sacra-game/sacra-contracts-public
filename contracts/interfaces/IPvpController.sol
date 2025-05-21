// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../openzeppelin/EnumerableSet.sol";
import "../openzeppelin/EnumerableMap.sol";
import "./IFightCalculator.sol";

interface IPvpController {
  enum PvpParams {
    NONE_0,
    /// @notice Hero can be pvp-staked if his level is greater of equal to the given min level
    MIN_HERO_LEVEL_1,

    /// @notice Address of IGuildStakingAdapter, can be not initialized
    GUILD_STAKING_ADAPTER_2,

    /// @notice Unique ID of the pvp-fight (each pvp-fight consists from multiple turns)
    FIGHT_COUNTER_3

    // max 255 params because enum is uint8 by default
  }

  /// @custom:storage-location erc7201:pvp.controller.main
  struct MainState {
    /// @notice Mapping to store various params of PvpController
    mapping(PvpParams param => uint value) pvpParam;

    /// @notice Current states of biomes
    mapping(uint8 biome => BiomeData) biomeState;

    /// @notice Biomes owned by the guilds
    mapping(uint guildId => uint8 biome) ownedBiome;

    mapping(uint epochWeek => EpochData) epochData;
  }

  struct EpochData {
    /// @notice Current state of the user in the current epoch
    mapping (address user => PvpUserState) pvpUserState;

    /// @notice biome data for the given epoch
    mapping(uint8 biome => EpochBiomeData) epochBiomeData;

    /// @notice All prepared pvp-fights for the given user
    /// Index of currently active fight is stored in {pvpUserState.activeFightIndex1}
    mapping (address user => PvpFightData[]) fightData;

    /// @notice All currently registered packed-heroes
    EnumerableSet.UintSet stakedHeroes;

    /// @notice Weekly request of the guild to dominate at the given biome starting from the next week
    mapping(uint guildId => uint8 biome) targetBiome;

    /// @notice All guilds pretend for the given biome
    mapping(uint8 biome => EnumerableSet.UintSet guildIds) biomeGuilds;
  }

  /// @notice Current state of the user. Possible states: user has or hasn't staked a hero in pvp.
  /// Each user is able to stake pvp-heroes multiple times per epoch
  /// but the user is able to stake only 1 pvp-hero at any moment.
  /// @dev Implementation assumes that the struct occupies single slot, the struct is read as a whole
  struct PvpUserState {
    /// @notice Domination biome at the moment of staking
    /// @dev not 0 if the user has pvp-staked hero
    uint8 biome;

    /// @notice 1-based index of currently active fight in {fightData} (the fight is either prepared or in-progress).
    /// 0 - there is no active fight
    uint32 activeFightIndex1;

    /// @notice How many times the user has staked heroes for PVP
    /// @dev Max possible value is limited by MAX_NUMBER_STAKES_FOR_USER_PER_EPOCH
    uint32 numHeroesStaked;

    /// @notice User's guild at the moment of staking
    /// 0 if user has no hero staked in pvp currently
    uint64 guildId;

    /// @notice Total number of pvp-fights performed since the last call of addPvpHero.
    /// @dev All pvp-fights are won here because looser is auto removed.
    uint8 countFights;

    /// @notice Max number of pvp-fights allowed by the user per single call of addPvpHero, 0 - no limits
    uint8 maxFights;

    /// @notice Unique id of the current pvp-fight (the fight with activeFightIndex1)
    uint48 fightId;
  }

  struct BiomeData {
    /// @notice Biome owner - the guild that dominates in the biome at the given epoch. He has a right to get a tax
    /// @dev Assume here that uint64 is enough to store any guildId. It allows us to store whole struct in a single slot
    uint64 guildBiomeOwnerId;

    /// @notice Current epoch (last epoch for which pvp-battle was made)
    /// 0 if epoch was never started
    uint32 startedEpochWeek;

    /// @notice Number of consecutive epochs during which {guildBiomeOwnerId} wasn't changed
    uint16 dominationCounter;
  }

  struct EpochBiomeData {
    /// @notice List of guilds asked for domination in the biome => total points scored by the guilds in the given epoch
    /// @dev guildId => count points
    EnumerableMap.UintToUintMap guildPoints;

    /// @notice All users free for pvp-fight
    /// User is added here on registration and removed as soon as the fight for the user is initialized.
    mapping(uint guildId => EnumerableSet.AddressSet) freeUsers;

    /// @notice All users (from the {guilds}) provided heroes for pvp
    /// @dev guildId => (user address => packedHero (hero + heroId))
    mapping(uint guildId => EnumerableMap.AddressToUintMap) registeredHeroes;

    /// @notice The skills and attack type selected in advance
    mapping(bytes32 packedHero => bytes) pvpStrategy;
  }

  enum PvpFightStatus {
    /// @notice No fight, the hero doesn't have selected opponent
    NOT_INITIALIZED_0,

    /// @notice The hero has opponent, the fight is not started
    PREPARED_1,

    /// @notice The fight is started but not completed
    FIGHTING_2,

    /// @notice The fight is completed, the hero is the winner
    WINNER_3,

    /// @notice The fight is completed, the hero is the looser
    LOSER_4
  }

  /// @notice Current state of the fight
  /// @dev Implementation assumes that the struct occupies single slot, the struct is read as a whole
  /// @dev We don't store biome and guildId here. This info is stored in user state and can be lost after fight ending.
  struct PvpFightData {
    /// @notice address of user whose hero is the fight opponent
    address fightOpponent;

    /// @notice Current status of PVP-fight
    PvpFightStatus fightStatus;

    /// @notice Current value of the health (only when fightStatus is FIGHTING_2)
    uint32 health;

    /// @notice Current value of the mana (only when fightStatus is FIGHTING_2)
    uint32 mana;

    /// @notice Number of moves made (only when fightStatus is FIGHTING_2)
    uint8 countTurns;
  }

  /// @dev Implementation assumes that the struct occupies single slot, the struct is read as a whole
  struct PvpFightResults {
    bool completed;
    uint8 totalCountFights;
    uint32 healthHero;
    uint32 healthOpponent;
    uint32 manaConsumedHero;
    uint32 manaConsumedOpponent;
  }

  /// @notice Strategy how to use attack info
  enum PvpBehaviourStrategyKinds {
    /// @notice Use all skills, use magic attack if it's available
    /// @dev {PvpStrategyDefault} is used as data in {addPvpHero}
    DEFAULT_STRATEGY_0

    // new strategies are able to use different structures to store data passed to {addPvpHero}
  }

  /// @notice The data provided by user at the staking with {DEFAULT_STRATEGY_0}
  struct PvpStrategyDefault {
    /// @notice Should be equal to DEFAULT_STRATEGY_0
    uint behaviourStrategyKind;
    IFightCalculator.AttackInfo attackInfo;
  }

  struct HeroData {
    address hero;
    uint heroId;
    bytes pvpStrategy;
  }

  /// ------------------------------------------------------------------------------------------------------------------
  /// ------------------------------------------------------------------------------------------------------------------
  /// ------------------------------------------------------------------------------------------------------------------

  /// @notice Update epoch if necessary and return actual biome owner and tax
  /// @return guildId Owner of the biome
  /// @return taxPercent Tax percent , [0...100_000], decimals 3
  function refreshBiomeTax(uint8 biome) external returns (uint guildId, uint taxPercent);

  function isHeroStakedCurrently(address hero, uint heroId) external view returns (bool staked);
  function onGuildDeletion(uint guildId) external;
}