// SPDX-License-Identifier: BUSL-1.1
/**
            ▒▓▒  ▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓███▓▓▒     ▒▒▒▒▓▓▓▒▓▓▓▓▓▓▓██▓
             ▒██▒▓▓▓▓█▓██████████████████▓  ▒▒▒▓███████████████▒
              ▒██▒▓█████████████████████▒ ▒▓██████████▓███████
               ▒███████████▓▒                   ▒███▓▓██████▓
                 █████████▒                     ▒▓▒▓███████▒
                  ███████▓      ▒▒▒▒▒▓▓█▓▒     ▓█▓████████
                   ▒▒▒▒▒   ▒▒▒▒▓▓▓█████▒      ▓█████████▓
                         ▒▓▓▓▒▓██████▓      ▒▓▓████████▒
                       ▒██▓▓▓███████▒      ▒▒▓███▓████
                        ▒███▓█████▒       ▒▒█████▓██▓
                          ██████▓   ▒▒▒▓██▓██▓█████▒
                           ▒▒▓▓▒   ▒██▓▒▓▓████████
                                  ▓█████▓███████▓
                                 ██▓▓██████████▒
                                ▒█████████████
                                 ███████████▓
      ▒▓▓▓▓▓▓▒▓                  ▒█████████▒                      ▒▓▓
    ▒▓█▒   ▒▒█▒▒                   ▓██████                       ▒▒▓▓▒
   ▒▒█▒       ▓▒                    ▒████                       ▒▓█▓█▓▒
   ▓▒██▓▒                             ██                       ▒▓█▓▓▓██▒
    ▓█▓▓▓▓▓█▓▓▓▒        ▒▒▒         ▒▒▒▓▓▓▓▒▓▒▒▓▒▓▓▓▓▓▓▓▓▒    ▒▓█▒ ▒▓▒▓█▓
     ▒▓█▓▓▓▓▓▓▓▓▓▓▒    ▒▒▒▓▒     ▒▒▒▓▓     ▓▓  ▓▓█▓   ▒▒▓▓   ▒▒█▒   ▒▓▒▓█▓
            ▒▒▓▓▓▒▓▒  ▒▓▓▓▒█▒   ▒▒▒█▒          ▒▒█▓▒▒▒▓▓▓▒   ▓██▓▓▓▓▓▓▓███▓
 ▒            ▒▓▓█▓  ▒▓▓▓▓█▓█▓  ▒█▓▓▒          ▓▓█▓▒▓█▓▒▒   ▓█▓        ▓███▓
▓▓▒         ▒▒▓▓█▓▒▒▓█▒   ▒▓██▓  ▓██▓▒     ▒█▓ ▓▓██   ▒▓▓▓▒▒▓█▓        ▒▓████▒
 ██▓▓▒▒▒▒▓▓███▓▒ ▒▓▓▓▓▒▒ ▒▓▓▓▓▓▓▓▒▒▒▓█▓▓▓▓█▓▓▒▒▓▓▓▓▓▒    ▒▓████▓▒     ▓▓███████▓▓▒
*/
pragma solidity 0.8.23;

import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";
import "../interfaces/IReinforcementController.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IDungeonFactory.sol";
import "../openzeppelin/ERC721Holder.sol";
import "../lib/PackingLib.sol";
import "../lib/ReinforcementControllerLib.sol";

contract ReinforcementController is Controllable, IReinforcementController, ERC721Holder, ERC2771Context {
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using PackingLib for bytes32;
  using PackingLib for address;
  using PackingLib for uint8[];

  //region ------------------------ CONSTANTS

  /// @notice Version of the contract
  string public constant override VERSION = "3.0.0";
  //endregion ------------------------ CONSTANTS

  //region ------------------------ INITIALIZER

  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ INITIALIZER

  //region ------------------------ VIEWS
  function toHelperRatio(address heroToken, uint heroId) external override view returns (uint) {
    return ReinforcementControllerLib.toHelperRatio(IController(controller()), heroToken, heroId);
  }

  function heroInfo(address heroToken, uint heroId) external view returns (HeroInfo memory) {
    return ReinforcementControllerLib.heroInfo(heroToken, heroId);
  }

  function heroInfoV2(address heroToken, uint heroId) external view returns (HeroInfoV2 memory) {
    return ReinforcementControllerLib.heroInfoV2(heroToken, heroId);
  }

  function isStaked(address heroToken, uint heroId) external view override returns (bool) {
    return ReinforcementControllerLib.isStaked(heroToken, heroId);
  }

  function isStakedV1(address heroToken, uint heroId) external view returns (bool) {
    return ReinforcementControllerLib.isStakedV1(heroToken, heroId);
  }

  function isStakedV2(address heroToken, uint heroId) external view returns (bool) {
    return ReinforcementControllerLib.isStakedV2(heroToken, heroId);
  }

  /// @return Return the guild in which the hero is staked for guild reinforcement
  function getStakedGuild(address heroToken, uint heroId) external view returns (uint) {
    return ReinforcementControllerLib.getStakedHelperGuild(heroToken, heroId);
  }

  function stakedGuildHelpersLength(uint guildId) external view returns (uint) {
    return ReinforcementControllerLib.stakedGuildHelpersLength(guildId);
  }

  /// @return hero Staked hero
  /// @return heroId ID of the staked hero
  /// @return busyInGuildId Id of the guild where the hero is being asked for help currently. 0 - free for being asked for the help
  function stakedGuildHelperByIndex(uint guildId, uint index) external view returns (address hero, uint heroId, uint busyInGuildId) {
    return ReinforcementControllerLib.stakedGuildHelperByIndex(guildId, index);
  }

  function earned(address heroToken, uint heroId) external view returns (
    address[] memory tokens,
    uint[] memory amounts,
    address[] memory nfts,
    uint[] memory ids
  ) {
    return ReinforcementControllerLib.earned(heroToken, heroId);
  }

  /// @notice Return the guild in which the hero is currently asked for guild reinforcement
  function busyGuildHelperOf(address heroToken, uint heroId) external view returns (uint guildId) {
    return ReinforcementControllerLib.busyGuildHelperOf(heroToken, heroId);
  }

  /// @notice Return moment of last withdrawing of the hero from guild reinforcement
  function lastGuildHeroWithdrawTs(address heroToken, uint heroId) external view returns (uint) {
    return ReinforcementControllerLib.lastGuildHeroWithdrawTs(heroToken, heroId);
  }

  function getConfigV2() external view returns (uint32 minNumberHits, uint32 maxNumberHits, uint32 lowDivider, uint32 highDivider, uint8 limitLevel) {
    return ReinforcementControllerLib.getConfigV2();
  }

  function getFeeAmount(uint hitsLast24h, uint8 biome, uint8 ngLevel) external view returns (uint feeAmount) {
    return ReinforcementControllerLib.getFeeAmount(IController(controller()).gameToken(), hitsLast24h, biome, ngLevel);
  }

  function getHitsNumberPerLast24Hours(uint8 biome) external view returns (uint hitsLast24h) {
    return ReinforcementControllerLib.getHitsNumberPerLast24Hours(biome, block.timestamp);
  }

  function getLastWindowsV2(uint8 biome) external view returns (IReinforcementController.LastWindowsV2 memory) {
    return ReinforcementControllerLib.getLastWindowsV2(biome);
  }

  function heroesByBiomeV2Length(uint8 biome) external view returns (uint) {
    return ReinforcementControllerLib.heroesByBiomeV2Length(biome);
  }

  function heroesByBiomeV2ByIndex(uint8 biome, uint index) external view returns (address helper, uint helperId) {
    return ReinforcementControllerLib.heroesByBiomeV2ByIndex(biome, index);
  }

  function heroesByBiomeV2(uint8 biome) external view returns (address[] memory helpers, uint[] memory helperIds) {
    return ReinforcementControllerLib.heroesByBiomeV2(biome);
  }
  //endregion ------------------------ VIEWS

  //region ------------------------ GOV ACTIONS
  function setConfigV2(IReinforcementController.ConfigReinforcementV2 memory config) external {
    ReinforcementControllerLib.setConfigV2(IController(controller()), config);
  }

  //endregion ------------------------ GOV ACTIONS

  //region ------------------------ Reinforcement V1
  function withdrawHero(address heroToken, uint heroId) external {
    ReinforcementControllerLib.withdrawHero(_isNotSmartContract(), IController(controller()), _msgSender(), heroToken, heroId);
  }
  //endregion ------------------------ Reinforcement V1

  //region ------------------------ Rewards for reinforcement of any kind
  /// @dev Only for dungeon. Assume the tokens already sent to this contract.
  function registerTokenReward(address heroToken, uint heroId, address token, uint amount, uint64 dungeonId) external override {
    ReinforcementControllerLib.registerTokenReward(IController(controller()), heroToken, heroId, token, amount, dungeonId);
  }

  /// @dev Only for dungeon. Assume the NFT already sent to this contract.
  function registerNftReward(address heroToken, uint heroId, address token, uint tokenId, uint64 dungeonId) external override {
    ReinforcementControllerLib.registerNftReward(IController(controller()), heroToken, heroId, token, tokenId, dungeonId);
  }

  function claimAll(address heroToken, uint heroId) external {
    ReinforcementControllerLib.claimAll(_isNotSmartContract(), IController(controller()), _msgSender(), heroToken, heroId);
  }

  /// @notice Claim {countNft} last NFT
  function claimNft(address heroToken, uint heroId, uint countNft) external {
    ReinforcementControllerLib.claimNft(_isNotSmartContract(), IController(controller()), _msgSender(), heroToken, heroId, countNft);
  }
  //endregion ------------------------ Rewards for reinforcement of any kind

  //region ------------------------ Guild reinforcement
  function stakeGuildHero(address heroToken, uint heroId) external {
    ReinforcementControllerLib.stakeGuildHero(_isNotSmartContract(), IController(controller()), _msgSender(), heroToken, heroId);
  }

  function withdrawGuildHero(address heroToken, uint heroId) external {
    ReinforcementControllerLib.withdrawGuildHero(_isNotSmartContract(), IController(controller()), _msgSender(), heroToken, heroId);
  }

  /// @notice user User which asks for guild reinforcement
  function askGuildHero(address hero, uint heroId, address helper, uint helperId) external returns (int32[] memory attributes) {
    return ReinforcementControllerLib.askGuildHero(IController(controller()), hero, heroId, helper, helperId);
  }

  function releaseGuildHero(address helperHeroToken, uint helperHeroTokenId) external {
    return ReinforcementControllerLib.releaseGuildHero(IController(controller()), helperHeroToken, helperHeroTokenId);
  }
  //endregion ------------------------ Guild reinforcement

  //region ------------------------ Reinforcement V2
  /// @notice Stake hero in reinforcement-v2
  /// @param rewardAmount Reward required by the helper for the help.
  function stakeHeroV2(address heroToken, uint heroId, uint rewardAmount) external {
    return ReinforcementControllerLib.stakeHeroV2(_isNotSmartContract(), IController(controller()), _msgSender(), heroToken, heroId, rewardAmount);
  }

  /// @notice Reverse operation for {stakeHeroV2}
  function withdrawHeroV2(address heroToken, uint heroId) external {
    return ReinforcementControllerLib.withdrawHeroV2(_isNotSmartContract(), IController(controller()), _msgSender(), heroToken, heroId);
  }

  /// @notice {hero} asks help of the {helper}
  /// Hero owner sends reward amount to the helper owner as the reward for the help.
  /// Hero owner sends fixed fee to controller using standard process-routine.
  /// Size of the fixed fee depends on total number of calls of {askHeroV2} for last 24 hours since the current moment.
  /// Durability of all equipped items of the helper are reduced.
  /// Assume, that hero owner approves rewardAmount + fixed fee to reinforcementController-contract
  /// - rewardAmount: amount required by the helper (see {heroInfoV2})
  /// - fixed fee: fee taken by controller (see {getFeeAmount})
  function askHeroV2(address hero, uint heroId, address helper, uint helperId) external returns (
    int32[] memory attributes
  ) {
    return ReinforcementControllerLib.askHeroV2(IController(controller()), hero, heroId, helper, helperId, block.timestamp);
  }
  //endregion ------------------------ Reinforcement V2
}
