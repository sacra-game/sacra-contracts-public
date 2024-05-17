// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";
import "../lib/HeroLib.sol";
import "../lib/PackingLib.sol";
import "../lib/ScoreLib.sol";
import "../interfaces/IHeroController.sol";

library HeroControllerLib {
  using PackingLib for bytes32;
  using PackingLib for address;

  //region ------------------------ RESTRICTIONS

  function onlyDeployer(IController controller) internal view {
    if (! controller.isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }

  function onlyEOA(bool isEoa) internal view {
    if (!isEoa) {
      revert IAppErrors.NotEOA(msg.sender);
    }
  }
  //endregion ------------------------ RESTRICTIONS

  //region ------------------------ VIEWS

  function _S() internal pure returns (IHeroController.MainState storage s) {
    return HeroLib._S();
  }

  function heroTokensVault() internal view returns (address) {
    return _S().heroTokensVault;
  }

  function payTokenInfo(address hero) internal view returns (address token, uint amount) {
    return _S().payToken[hero].unpackAddressWithAmount();
  }

  function heroClass(address hero) internal view returns (uint8) {
    return _S().heroClass[hero];
  }

  function heroName(address hero, uint heroId) internal view returns (string memory) {
    return _S().heroName[hero.packNftId(heroId)];
  }

  function nameToHero(string memory name) internal view returns (address hero, uint heroId) {
    return _S().nameToHero[name].unpackNftId();
  }

  function heroBiome(address hero, uint heroId) internal view returns (uint8) {
    return _S().heroBiome[hero.packNftId(heroId)];
  }

  function heroReinforcementHelp(address hero, uint heroId) internal view returns (
    address helperHeroToken,
    uint helperHeroId
  ) {
    return _S().reinforcementHero[hero.packNftId(heroId)].unpackNftId();
  }

  function score(IController controller, address hero, uint heroId) internal view returns (uint) {
    IStatController _statController = IStatController(controller.statController());
    return ScoreLib.heroScore(
      _statController.heroAttributes(hero, heroId),
      _statController.heroStats(hero, heroId).level
    );
  }

  function isAllowedToTransfer(IController controller, address hero, uint heroId) internal view returns (bool) {
    return HeroLib.isAllowedToTransfer(controller, hero, heroId);
  }
  //endregion ------------------------ VIEWS

  //region ------------------------ GOV ACTIONS

  function setHeroTokensVault(IController controller, address value) internal {
    onlyDeployer(controller);
    HeroLib.setHeroTokensVault(value);
  }

  function registerHero(IController controller, address hero, uint8 heroClass_, address payToken, uint payAmount) internal {
    onlyDeployer(controller);
    HeroLib.registerHero(hero, heroClass_, payToken, payAmount);
  }
  //endregion ------------------------ GOV ACTIONS

  //region ------------------------ USER ACTIONS

  function create(
    IController controller,
    address msgSender,
    address hero,
    string calldata _heroName,
    bool enter
  ) internal returns (uint) {
    // allow create for contracts for SponsoredHero flow  // onlyEOA(isEoa);
    return HeroLib.create(controller, msgSender, hero, _heroName, "", enter);
  }

  function createWithRefCode(
    bool isEoa,
    IController controller,
    address msgSender,
    address hero,
    string calldata _heroName,
    string memory refCode,
    bool enter
  ) internal returns (uint) {
    onlyEOA(isEoa);
    return HeroLib.create(controller, msgSender, hero, _heroName, refCode, enter);
  }


  function setBiome(bool isEoa, IController controller, address msgSender, address hero, uint heroId, uint8 biome) internal {
    onlyEOA(isEoa);
    HeroLib.setBiome(controller, msgSender, hero, heroId, biome);
  }

  function levelUp(
    bool isEoa,
    IController controller,
    address msgSender,
    address hero,
    uint heroId,
    IStatController.CoreAttributes memory change
  ) internal {
    onlyEOA(isEoa);
    HeroLib.levelUp(controller, msgSender, hero, heroId, change);
  }

  function askReinforcement(bool isEoa, IController controller, address msgSender, address hero, uint heroId) internal {
    onlyEOA(isEoa);
    HeroLib.askReinforcement(controller, msgSender, hero, heroId);
  }
  //endregion ------------------------ USER ACTIONS

  //region ------------------------ DUNGEON ACTIONS

  function kill(IController controller, address msgSender, address hero, uint heroId) internal returns (
    bytes32[] memory dropItems
  ) {
    // restrictions are checked in HeroLib
    return HeroLib.kill(controller, msgSender, hero, heroId);
  }

  function releaseReinforcement(IController controller, address msgSender, address hero, uint heroId) internal returns (
    address helperToken,
    uint helperId
  ) {
    // restrictions are checked in HeroLib
    return HeroLib.releaseReinforcement(controller, msgSender, hero, heroId);
  }
  //endregion ------------------------ DUNGEON ACTIONS

}
