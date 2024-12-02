// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IGameToken.sol";
import "../interfaces/IRewardsPool.sol";
import "../openzeppelin/Math.sol";
import "../proxy/Controllable.sol";

library RewardsPoolLib {
  /// @dev keccak256(abi.encode(uint256(keccak256("rewards.pool.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant REWARDS_POOL_STORAGE_LOCATION = 0x6ad655e44097c54b487e7c9215cc0bbf37bbe7fc2f8034e2ddf6749036fda500; // rewards.pool.main

  //region ------------------------ Storage

  function _S() internal pure returns (IRewardsPool.MainState storage s) {
    assembly {
      s.slot := REWARDS_POOL_STORAGE_LOCATION
    }
    return s;
  }
  //endregion ------------------------ Storage

  //region ------------------------ Restrictions
  function onlyHeroController(IController controller) internal view {
    if (controller.heroController() != msg.sender) revert IAppErrors.ErrorNotHeroController(msg.sender);
  }

  function _onlyDeployer(IController controller) internal view {
    if (!controller.isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }

  function _onlyGovernance(IController controller) internal view {
    if (controller.governance() != msg.sender) revert IAppErrors.NotGovernance(msg.sender);
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ View
  function balanceOfToken(address token) internal view returns (uint) {
    return IERC20(token).balanceOf(address(this));
  }

  function baseAmount(address token) internal view returns (uint) {
    return _S().baseAmounts[token];
  }

  /// @param maxBiome Max available biome, see {IDungeonFactory.state.maxBiome}
  /// @param maxNgLevel Max opened NG_LEVEL, see {IHeroController.state.maxOpenedNgLevel}
  /// @param biome Current hero biome [0..19
  /// @param heroNgLevel Current hero NG_LVL [0..99]
  /// @return Reward percent, decimals 18
  function rewardPercent(uint maxBiome, uint maxNgLevel, uint biome, uint heroNgLevel) internal pure returns (uint) {
    // biome_sum = max biome*(max biome+1)/2
    // biome_weight = biome / biome_sum
    // reward_percent = biome_weight * (1 + NG_LVL) / ng_sum
    return  1e18 * biome * (1 + heroNgLevel)
      / (maxBiome * (maxBiome + 1) / 2) // biome_sum
      / getNgSum(maxNgLevel);
  }

  /// @notice be definition  ng_sum  = (max_ng + 1) * (max_ng+2) / 2
  function getNgSum(uint maxNgLevel) internal pure returns (uint) {
    return ((maxNgLevel + 1) * (maxNgLevel + 2) / 2);
  }

  function rewardAmount(address token, uint maxBiome, uint maxNgLevel, uint biome, uint heroNgLevel) internal view returns (uint) {
    return baseAmount(token) * rewardPercent(maxBiome, maxNgLevel, biome, heroNgLevel) / 1e18;
  }

  /// @notice Calculate lost profit amount in percents in the case when hero is created on {heroNgLevel} > 0
  /// @param maxBiome Max available biome, see {IDungeonFactory.state.maxBiome}
  /// @param maxNgLevel Max opened NG_LEVEL, see {IHeroController.state.maxOpenedNgLevel}
  /// @param heroNgLevel NG_LVL [1..99] where the hero is created, assume heroNgLevel > 0
  /// @return Lost reward percent, decimals 18
  function lostProfitPercent(uint maxBiome, uint maxNgLevel, uint heroNgLevel) internal pure returns (uint) {
    uint percent;
    for (uint8 ngLevel = 0; ngLevel < heroNgLevel; ++ngLevel) {
      percent += totalProfitOnLevel(maxBiome, maxNgLevel, ngLevel);
    }
    return percent;
  }

  /// @notice SCR-1064: Calculate a percent to reduce drop chance of the monsters on various NG-levels.
  /// The percent is reverse to the percent of the rewards.
  /// @param maxBiome Max available biome, see {IDungeonFactory.state.maxBiome}
  /// @param maxNgLevel Max opened NG_LEVEL, see {IHeroController.state.maxOpenedNgLevel}
  /// @param heroNgLevel NG_LVL [1..99] where the hero is created, assume heroNgLevel > 0
  /// @return Drop chance percent, decimals 18
  function dropChancePercent(uint maxBiome, uint maxNgLevel, uint heroNgLevel) internal pure returns (uint) {
    if (heroNgLevel == 0) return 1e18; // NG0 is special case - drop is NOT reduced

    return heroNgLevel > maxNgLevel
      ? 0
      : totalProfitOnLevel(maxBiome, maxNgLevel, maxNgLevel - heroNgLevel + 1);
  }

  /// @notice Calculate total percent of rewards in all biomes on the given {ngLevel}
  function totalProfitOnLevel(uint maxBiome, uint maxNgLevel, uint ngLevel) internal pure returns (uint percent) {
    for (uint8 biome = 1; biome <= maxBiome; ++biome) {
      percent += rewardPercent(maxBiome, maxNgLevel, biome, ngLevel);
    }
    return percent;
  }
  //endregion ------------------------ View

  //region ------------------------ Gov actions
  function setBaseAmount(IController controller, address token, uint baseAmount_) internal {
    _onlyDeployer(controller);

    emit IApplicationEvents.BaseAmountChanged(_S().baseAmounts[token], baseAmount_);
    _S().baseAmounts[token] = baseAmount_;
  }

  function withdraw(IController controller, address token, uint amount, address receiver) internal {
    _onlyGovernance(controller);

    IERC20(token).transfer(receiver, amount);
  }
  //endregion ------------------------ Gov actions

  //region ------------------------ Logic
  /// @notice Send {amount} of the {token} to the {dungeon}
  /// @dev Assume here that all calculations and checks are made on dungeonFactory-side
  function sendReward(IController controller, address token, uint rewardAmount_, address receiver) internal {
    onlyHeroController(controller);

    uint balance = IERC20(token).balanceOf(address(this));
    if (balance >= rewardAmount_) {
      IERC20(token).transfer(receiver, rewardAmount_);
      emit IApplicationEvents.RewardSentToUser(receiver, token, rewardAmount_);
    } else {
      // there is not enough amount on reward pool balance
      // just register reward in events
      // assume that the reward should be paid to the receiver later manually
      emit IApplicationEvents.NotEnoughReward(receiver, token, rewardAmount_);
    }
  }

  //endregion ------------------------ Logic

}
