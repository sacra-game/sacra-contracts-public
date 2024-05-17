// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "./IStatController.sol";
import "../openzeppelin/EnumerableMap.sol";

interface IReinforcementController {

  /// @custom:storage-location erc7201:reinforcement.controller.main
  struct MainState {

    /// @dev minLvl8 + minLifeChances8
    bytes32 config;

    /// @dev hero token + hero id => heroInfo(biome8 + score128 + fee8 + stakeTs64)
    mapping(bytes32 => bytes32) _stakedHeroes;
    /// @dev biome => helperAdr+id
    mapping(uint => EnumerableSet.Bytes32Set) _internalIdsByBiomes;
    /// @dev biome => score
    mapping(uint => uint) maxScore;
    /// @dev heroAdr+id => itemAdr+id
    mapping(bytes32 => bytes32[]) _heroNftRewards;
    /// @dev heroAdr+id => tokenAdr and amount map
    mapping(bytes32 => EnumerableMap.AddressToUintMap) _heroTokenRewards;

  }

  struct HeroInfo {
    uint8 biome;
    uint score; // stored in 128 but easy to use 256
    /// @notice To helper ratio
    uint8 fee;
    uint64 stakeTs;
  }

  function toHelperRatio(address heroToken, uint heroId) external view returns (uint);

  function isStaked(address heroToken, uint heroId) external view returns (bool);

  function askHero(uint biome) external returns (address heroToken, uint heroId, int32[] memory attributes);

  function registerTokenReward(address heroToken, uint heroId, address token, uint amount) external;

  function registerNftReward(address heroToken, uint heroId, address token, uint tokenId) external;

}
