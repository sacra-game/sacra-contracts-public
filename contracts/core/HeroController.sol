// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";
import "../lib/HeroLib.sol";
import "../lib/HeroControllerLib.sol";
import "../lib/PackingLib.sol";
import "../lib/ScoreLib.sol";
import "../interfaces/IHeroController.sol";

contract HeroController is Controllable, ERC2771Context, IHeroController {
  using PackingLib for bytes32;
  using PackingLib for address;

  /// @notice Version of the contract
  string public constant VERSION = "1.0.2";

  //region ------------------------ INITIALIZER

  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ INITIALIZER


  //region ------------------------ VIEWS
  function heroTokensVault() external view returns (address) {
    return HeroControllerLib.heroTokensVault();
  }

  function payTokenInfo(address hero) external view returns (address token, uint amount) {
    return HeroControllerLib.payTokenInfo(hero);
  }

  function heroClass(address hero) external view returns (uint8) {
    return HeroControllerLib.heroClass(hero);
  }

  function heroName(address hero, uint heroId) external view returns (string memory) {
    return HeroControllerLib.heroName(hero, heroId);
  }

  function nameToHero(string memory name) external view returns (address hero, uint heroId) {
    return HeroControllerLib.nameToHero(name);
  }

  function heroBiome(address hero, uint heroId) external view override returns (uint8) {
    return HeroControllerLib.heroBiome(hero, heroId);
  }

  function heroReinforcementHelp(address hero, uint heroId) external view override returns (
    address helperHeroToken,
    uint helperHeroId
  ) {
    return HeroControllerLib.heroReinforcementHelp(hero, heroId);
  }

  function score(address hero, uint heroId) external view returns (uint) {
    return HeroControllerLib.score(IController(controller()), hero, heroId);
  }

  function isAllowedToTransfer(address hero, uint heroId) external view override returns (bool) {
    return HeroControllerLib.isAllowedToTransfer(IController(controller()), hero, heroId);
  }
  //endregion ------------------------ VIEWS

  //region ------------------------ GOV ACTIONS

  function setHeroTokensVault(address value) external {
    HeroControllerLib.setHeroTokensVault(IController(controller()), value);
  }

  function registerHero(address hero, uint8 heroClass_, address payToken, uint payAmount) external {
    HeroControllerLib.registerHero(IController(controller()), hero, heroClass_, payToken, payAmount);
  }
  //endregion ------------------------ GOV ACTIONS

  //region ------------------------ USER ACTIONS

  function create(address hero, string calldata heroName_, bool enter) external override returns (uint) {
    return HeroControllerLib.create(IController(controller()), _msgSender(), hero, heroName_, enter);
  }

  function createWithRefCode(address hero, string calldata heroName_, string calldata refCode, bool enter) external returns (uint) {
    return HeroControllerLib.createWithRefCode(_isNotSmartContract(), IController(controller()), _msgSender(), hero, heroName_, refCode, enter);
  }

  function setBiome(address hero, uint heroId, uint8 biome) external {
    HeroControllerLib.setBiome(_isNotSmartContract(), IController(controller()), _msgSender(), hero, heroId, biome);
  }

  function levelUp(address hero, uint heroId, IStatController.CoreAttributes memory change) external {
    HeroControllerLib.levelUp(_isNotSmartContract(), IController(controller()), _msgSender(), hero, heroId, change);
  }

  function askReinforcement(address hero, uint heroId) external virtual {
    HeroControllerLib.askReinforcement(_isNotSmartContract(), IController(controller()), _msgSender(), hero, heroId);
  }
  //endregion ------------------------ USER ACTIONS

  //region ------------------------ DUNGEON ACTIONS

  function kill(address hero, uint heroId) external override returns (bytes32[] memory dropItems) {
    return HeroControllerLib.kill(IController(controller()), _msgSender(), hero, heroId);
  }

  function releaseReinforcement(address hero, uint heroId) external override returns (address helperToken, uint helperId) {
    return HeroControllerLib.releaseReinforcement(IController(controller()), _msgSender(), hero, heroId);
  }
  //endregion ------------------------ DUNGEON ACTIONS
}
