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
import "../interfaces/IRewardsPool.sol";
import "../interfaces/IApplicationEvents.sol";
import "../lib/RewardsPoolLib.sol";

contract RewardsPool is Initializable, Controllable, IRewardsPool {
  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant override VERSION = "1.0.1";

  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }

  function balanceOfToken(address token) external view override returns (uint) {
    return RewardsPoolLib.balanceOfToken(token);
  }

  function baseAmount(address token) external view returns (uint) {
    return RewardsPoolLib.baseAmount(token);
  }

  /// @param maxBiome Max available biome, see {IDungeonFactory.state.maxBiome}
  /// @param maxNgLevel Max opened NG_LEVEL, see {IHeroController.state.maxOpenedNgLevel}
  /// @param biome Current hero biome [0..19
  /// @param heroNgLevel Current hero NG_LVL [0..99]
  /// @return Reward percent, decimals 18
  function rewardPercent(uint maxBiome, uint maxNgLevel, uint biome, uint heroNgLevel) external pure returns (uint) {
    return RewardsPoolLib.rewardPercent(maxBiome, maxNgLevel, biome, heroNgLevel);
  }

  function lostProfitPercent(uint maxBiome, uint maxNgLevel, uint heroNgLevel) external pure returns (uint percent) {
    return RewardsPoolLib.lostProfitPercent(maxBiome, maxNgLevel, heroNgLevel);
  }

  function rewardAmount(address token, uint maxBiome, uint maxNgLevel, uint biome, uint heroNgLevel) external view returns (uint) {
    return RewardsPoolLib.rewardAmount(token, maxBiome, maxNgLevel, biome, heroNgLevel);
  }

  function setBaseAmount(address token, uint baseAmount_) external {
    RewardsPoolLib.setBaseAmount(IController(controller()), token, baseAmount_);
  }

  function withdraw(address token, uint amount, address receiver) external {
    RewardsPoolLib.withdraw(IController(controller()), token, amount, receiver);
  }

  /// @notice rewardAmount_ Amount calculated using {rewardAmount}
  function sendReward(address token, uint rewardAmount_, address receiver) external {
    RewardsPoolLib.sendReward(IController(controller()), token, rewardAmount_, receiver);
  }
}
