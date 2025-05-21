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

import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IPvpController.sol";
import "../lib/PvpControllerLib.sol";
import "../lib/PvpFightLib.sol";
import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";
import "../openzeppelin/ERC721Holder.sol";

contract PvpController is Initializable, Controllable, ERC2771Context, IPvpController, ERC721Holder {
  //region ------------------------ Constants

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant override VERSION = "1.0.0";
  //endregion ------------------------ Constants

  //region ------------------------ Initializer

  function init(address controller_) external initializer {
    __Controllable_init(controller_);

    PvpControllerLib._S().pvpParam[IPvpController.PvpParams.MIN_HERO_LEVEL_1] = PvpControllerLib.DEFAULT_MIN_HERO_LEVEL;
  }
  //endregion ------------------------ Initializer

  //region ------------------------ View
  function getBiomeOwner(uint8 biome) external view returns (uint guildId) {
    return PvpControllerLib.getBiomeOwner(biome);
  }

  function getStartedEpoch(uint8 biome) external view returns (uint32 epochWeek) {
    return PvpControllerLib.getStartedEpoch(biome);
  }

  function getDominationCounter(uint8 biome) external view returns (uint16 dominationCounter) {
    return PvpControllerLib.getDominationCounter(biome);
  }

  /// @notice List of guilds that send domination request for the biome
  function getBiomeGuilds(uint8 biome, uint32 week) external view returns (uint[] memory guildIds) {
    return PvpControllerLib.getBiomeGuilds(biome, week);
  }

  /// @return biome Biome where the guild is going to dominate in the given epoch
  function getDominationRequest(uint guildId, uint32 week) external view returns (uint8 biome) {
    return PvpControllerLib.getDominationRequest(guildId, week);
  }

  function getGuildPoints(uint8 biome, uint32 epochWeek, uint guildId) external view returns (uint) {
    return PvpControllerLib.getGuildPoints(biome, epochWeek, guildId);
  }

  function getFreeUsers(uint8 biome, uint32 epochWeek, uint guildId) external view returns (address[] memory) {
    return PvpControllerLib.getFreeUsers(biome, epochWeek, guildId);
  }

  function getPvpStrategy(uint8 biome, uint32 epochWeek, address hero, uint heroId) external view returns (bytes memory) {
    return PvpControllerLib.getPvpStrategy(biome, epochWeek, hero, heroId);
  }

  function getPvpStrategyKind(uint8 biome, uint32 epochWeek, address hero, uint heroId) external view returns (uint) {
    return PvpControllerLib.getPvpStrategyKind(biome, epochWeek, hero, heroId);
  }

  /// @notice Number of pvp-fights registered for the user in the given epoch
  function getFightDataLength(uint32 epochWeek, address user) external view returns (uint) {
    return PvpControllerLib.getFightDataLength(epochWeek, user);
  }

  function getFightDataByIndex(uint32 epochWeek, address user, uint index0) external view returns (IPvpController.PvpFightData memory) {
    return PvpControllerLib.getFightDataByIndex(epochWeek, user, index0);
  }

  /// @notice List of the users registered for pvp-fight in the given week and biome
  function registeredUsers(uint8 biome, uint32 epochWeek, uint guildId) external view returns (address[] memory) {
    return PvpControllerLib.registeredUsers(biome, epochWeek, guildId);
  }

  /// @notice Hero registered by the user for pvp-fight in the given week and biome
  function registeredHero(uint8 biome, uint32 epochWeek, uint guildId, address user) external view returns (address hero, uint heroId) {
    return PvpControllerLib.registeredHero(biome, epochWeek, guildId, user);
  }

  /// @notice Biome owned currently by the given guild
  function ownedBiome(uint guildId) external view returns (uint8 biome) {
    return PvpControllerLib.ownedBiome(guildId);
  }

  /// @notice Get week for the given timestamp. Assume that first day of the week is Monday
  function getCurrentEpochWeek(uint blockTimestamp) external pure returns (uint32) {
    return PvpControllerLib.getCurrentEpochWeek(blockTimestamp);
  }

  function currentWeek() external view returns (uint32) {
    return PvpControllerLib.getCurrentEpochWeek(block.timestamp);
  }

  /// @notice Get biome tax
  /// @return guildId Owner of the biome
  /// @return taxPercent Final tax percent, [0...100_000], decimals 3
  function getBiomeTax(uint8 biome) external view returns (uint guildId, uint taxPercent) {
    return PvpControllerLib.getBiomeTax(biome);
  }

  /// @notice Check if the user has a pvp-hero registered for pvp-fight in the given epoch
  function hasPvpHero(address user, uint guildId, uint32 week) external view returns (bool) {
    return PvpControllerLib.hasPvpHero(user, guildId, week);
  }

  /// @notice Check if the given hero is staked in pvp controller in the given epoch
  function isHeroStaked(address hero, uint heroId, uint32 epoch) external view returns (bool staked) {
    return PvpControllerLib.isHeroStaked(hero, heroId, epoch);
  }

  /// @notice Check if the given hero is staked in pvp controller in the current epoch
  function isHeroStakedCurrently(address hero, uint heroId) external view returns (bool staked) {
    return PvpControllerLib.isHeroStaked(hero, heroId, PvpControllerLib.getCurrentEpochWeek(block.timestamp));
  }

  function getUserState(uint32 week, address user) external view returns (IPvpController.PvpUserState memory userState) {
    return PvpControllerLib.getUserState(week, user);
  }

  /// @notice Get min hero level allowed for pvp-fight
  function getMinHeroLevel() external view returns (uint) {
    return PvpControllerLib.getMinHeroLevel();
  }

  function getCounterFightId() external view returns (uint48) {
    return PvpControllerLib.getCounterFightId();
  }

  function getGuildStakingAdapter() external view returns (address) {
    return PvpControllerLib.getGuildStakingAdapter();
  }

  //endregion ------------------------ View

  //region ------------------------ Deployer actions
  function setMinHeroLevel(uint level) external {
    PvpControllerLib.setMinHeroLevel(IController(controller()), level);
  }

  function setGuildStakingAdapter(address adapter_) external {
    PvpControllerLib.setGuildStakingAdapter(IController(controller()), adapter_);
  }
  //endregion ------------------------ Deployer actions

  //region ------------------------ Domination actions

  /// @notice Select new domination target once per epoch
  function selectBiomeForDomination(uint8 biome) external {
    return PvpControllerLib.selectBiomeForDomination(
      _msgSender(),
      IController(controller()),
      biome,
      block.timestamp,
      CalcLib.pseudoRandom
    );
  }

  /// @notice Withdraw hero from pvp for the current epoch
  function removePvpHero() external {
    PvpControllerLib.removePvpHero(_msgSender(), IController(controller()), block.timestamp);
  }

  /// @notice Stake hero for pvp for the current epoch.
  /// User is able to register a hero only once per epoch, the hero cannot be replaced, only removed.
  /// @param pvpStrategy abi.encode(PvpAttackInfoDefaultStrategy)
  function addPvpHero(address hero, uint heroId, bytes memory pvpStrategy, uint8 maxFights) external {
    PvpControllerLib.addPvpHero(
      _msgSender(),
      IController(controller()),
      hero,
      heroId,
      pvpStrategy,
      maxFights,
      block.timestamp,
      CalcLib.pseudoRandom
    );
  }

  /// @notice Change epoch if the current epoch is completed, update biome owner
  function updateEpoch(uint8 biome) external {
    PvpControllerLib.updateEpoch(biome, block.timestamp, CalcLib.pseudoRandom);
  }

  /// @notice Update epoch if necessary and return biome owner and biome tax
  /// @return guildId Owner of the biome
  /// @return taxPercent Tax percent [0...100_000], decimals 3
  function refreshBiomeTax(uint8 biome) external returns (uint guildId, uint taxPercent) {
    return PvpControllerLib.refreshBiomeTax(biome, block.timestamp, CalcLib.pseudoRandom);
  }

  function onGuildDeletion(uint guildId) external {
    PvpControllerLib.onGuildDeletion(IController(controller()), guildId);
  }
  //endregion ------------------------ Domination actions

  //region ------------------------ PvP actions
  function prepareFight() external {
    PvpFightLib.prepareFight(_msgSender(), IController(controller()), block.timestamp, CalcLib.pseudoRandom);
  }

  function startFight(uint8 maxCountTurns) external {
    PvpFightLib.startFight(_msgSender(), IController(controller()), block.timestamp, maxCountTurns);
  }
  //endregion ------------------------ PvP actions
}