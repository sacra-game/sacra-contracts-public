// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IHeroController {

  /// @custom:storage-location erc7201:hero.controller.main
  struct MainState {

    /// @dev A central place for all hero tokens
    address heroTokensVault;

    /// @dev heroAdr => packed tokenAdr160+ amount96
    mapping(address => bytes32) payToken;

    /// @dev heroAdr => heroCls8
    mapping(address => uint8) heroClass;

    // ---

    /// @dev hero+id => individual hero name
    mapping(bytes32 => string) heroName;

    /// @dev name => hero+id, needs for checking uniq names
    mapping(string => bytes32) nameToHero;

    // ---

    /// @dev hero+id => biome
    mapping(bytes32 => uint8) heroBiome;

    /// @dev hero+id => rein hero+id
    mapping(bytes32 => bytes32) reinforcementHero;

    /// @dev hero+id => rein packed attributes
    mapping(bytes32 => bytes32[]) reinforcementHeroAttributes;
  }

  function heroClass(address hero) external view returns (uint8);

  function heroBiome(address hero, uint heroId) external view returns (uint8);

  function payTokenInfo(address hero) external view returns (address token, uint amount);

  function heroReinforcementHelp(address hero, uint heroId) external view returns (address helperHeroToken, uint helperHeroId);

  function score(address hero, uint heroId) external view returns (uint);

  function isAllowedToTransfer(address hero, uint heroId) external view returns (bool);

  function heroTokensVault() external view returns (address);

  // ---

  function create(address hero, string memory heroName_, bool enter) external returns (uint);

  function kill(address hero, uint heroId) external returns (bytes32[] memory dropItems);

  function releaseReinforcement(address hero, uint heroId) external returns (address helperToken, uint helperId);

}
