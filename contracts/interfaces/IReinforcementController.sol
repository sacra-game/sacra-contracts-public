// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "./IStatController.sol";
import "../openzeppelin/EnumerableMap.sol";

/// @notice Terms
/// Reinforcement v1: helper is selected randomly in askHero, fixed part of rewards (tokens and NFT) is sent to the helper.
/// Guild reinforcement: helper is selected from guild heroes. Rewards are sent to guild bank.
/// Reinforcement v2: helper is selected manually in askHeroV2, helper receives fixed amount.
interface IReinforcementController {

  enum ConfigParams {
    /// @notice Packed MinMaxBoardV2
    V2_MIN_MAX_BOARD_0
  }

  /// @custom:storage-location erc7201:reinforcement.controller.main
  struct MainState {

    // ------------------------ Reinforcement v1

    /// @dev minLvl8 + minLifeChances8
    bytes32 config;
    /// @dev hero token + hero id => heroInfo(biome8 + score128 + fee8 + stakeTs64)
    mapping(bytes32 => bytes32) _stakedHeroes;
    /// @dev biome => helperAdr+id
    mapping(uint => EnumerableSet.Bytes32Set) _internalIdsByBiomes;
    /// @dev biome => score  // The field is deprecated and not updated any more
    mapping(uint => uint) maxScore;
    /// @dev heroAdr+id => itemAdr+id
    mapping(bytes32 => bytes32[]) _heroNftRewards;
    /// @dev heroAdr+id => tokenAdr and amount map
    mapping(bytes32 => EnumerableMap.AddressToUintMap) _heroTokenRewards;


    // ------------------------ Guild reinforcement

    /// @notice All staked guild heroes for the given guild
    /// @dev helper (hero token + hero id) => guild
    mapping(bytes32 packedHero => uint guildId) stakedGuildHeroes;

    /// @notice All guild heroes that are currently in use by guild reinforcement
    /// It's allowed to withdraw a hero before reinforcement releasing,
    /// so it's possible to have !0 in {guildBusyHelpers} and 0 in {stakedGuildHeroes} simultaneously.
    /// @dev helper (hero token + hero id) => guildId (guild at the moment of askGuildReinforcement)
    mapping(bytes32 packedHero => uint guildId) busyGuildHelpers;

    /// @notice All (free and busy) staked guild heroes per guild.
    /// guild => (packed helper => guild where the helper is busy currently)
    /// @dev There is a chance that guilds are different here
    /// i.e. hero can be:
    /// 1) added to G1 2) staked in G1 3) asked for help 4) withdrawn 5) G1=>G2 6) staked in G2
    /// In such case guildHelpers[G2][hero] = G1, guildHelpers[G1][hero] = 0
    /// After releasing guildHelpers[G2][hero] = 0
    mapping(uint guildId => EnumerableMap.Bytes32ToUintMap) guildHelpers;

    /// @notice Moment of withdrawing the hero from staking. Next staking is possible in 1 day since withdrawing
    mapping(bytes32 packedHero => uint lastWithdrawTimestamp) lastGuildHeroWithdrawTs;


    // ------------------------ Reinforcement v2
    /// @notice Map to store various config params
    mapping(ConfigParams paramId => uint) configParams;

    mapping(bytes32 packedHero => HeroInfoV2) stakedHeroesV2;

    /// @notice biome => set of packedHero. All staked heroes (they can be busy of free currently)
    mapping(uint biome => EnumerableSet.Bytes32Set) heroesByBiomeV2;

    mapping(uint biome => LastWindowsV2) stat24hV2;
  }


  /// @notice Deprecated. Reinforcement v1
  struct HeroInfo {
    uint8 biome;
    uint score; // stored in 128 but easy to use 256
    /// @notice To helper ratio
    uint8 fee;
    uint64 stakeTs;
  }

  struct HeroInfoV2 {
    uint8 biome;
    uint64 stakeTs;
    /// @notice Amount of game token that is paid to the helper at the moment of the call {askHeroV2}
    uint128 rewardAmount;
  }

  /// @notice Statistic of askHeroV2 calls per last 24 hours at the moment of the last call
  struct LastWindowsV2 {
    /// @notice 24 hours are divided on 8 intervals, each interval is 3 hour
    /// Current basket has index {basketIndex}
    /// {baskets[current basket]} contains "old" value.
    /// New value for the current basket is collected in {basketValue}.
    /// The value for the current basket is calculated as weighted average of old and new values.
    /// New value replaces the old value at the moment of changing current basket index.
    uint24[8] baskets;
    /// @notice New value (hits counter) for current basket
    uint24 basketValue;
    /// @notice Abs. index of the current basket (abs. hour / 3)
    uint48 basketIndex;
  }

  /// @dev 1 slot
  struct ConfigReinforcementV2 {
    /// @notice if Number-of-askHeroV2-calls is below given value then burn fee has min value
    uint32 minNumberHits;
    /// @notice if Number-of-askHeroV2-calls is above given value then burn fee has max value
    uint32 maxNumberHits;
    /// @notice Lowest fee = amountForDungeon / given value, i.e. 100 => amountForDungeon/100 as lower fee
    uint32 lowDivider;
    /// @notice Highest fee = amountForDungeon / given value, i.e. 2 => amountForDungeon/2 as highest fee
    uint32 highDivider;
    /// @notice Limit for min level of the staked hero
    /// In practice we need following limitation: (stats.level < 5 || (stats.level - 5) / 5 < biome)
    /// so, levelLimit should be equal 5
    /// In tests we need to be able to disable such limitation, so levelLimit = 0 allow to disable that constraint
    uint8 levelLimit;
  }

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  function toHelperRatio(address heroToken, uint heroId) external view returns (uint);

  function isStaked(address heroToken, uint heroId) external view returns (bool);

  function registerTokenReward(address heroToken, uint heroId, address token, uint amount) external;

  function registerNftReward(address heroToken, uint heroId, address token, uint tokenId) external;

  function askHeroV2(address hero, uint heroId, address helper, uint helperId) external returns (int32[] memory attributes);

  function askGuildHero(address hero, uint heroId, address helper, uint helperId) external returns (int32[] memory attributes);

  /// @notice Return the guild in which the hero is currently asked for guild reinforcement
  function busyGuildHelperOf(address heroToken, uint heroId) external view returns (uint guildId);

  function releaseGuildHero(address helperHeroToken, uint helperHeroTokenId) external;
}