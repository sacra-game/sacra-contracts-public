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
  string public constant VERSION = "1.0.3";

  //region ------------------------ Initializer

  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ Initializer


  //region ------------------------ Views
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

  function countHeroTransfers(address hero, uint heroId) external view returns (uint) {
    return HeroControllerLib.countHeroTransfers(hero, heroId);
  }

  function getTier(uint8 tier, address hero) external view returns (uint payAmount, uint8[] memory slots, address[][] memory items) {
    return HeroControllerLib.getTier(tier, hero);
  }

  function getHeroInfo(address hero, uint heroId) external view returns (IHeroController.HeroInfo memory data) {
    return HeroLib.getHeroInfo(hero, heroId);
  }

  /// @notice Max value of NG_LEVEL opened by any heroes
  function maxOpenedNgLevel() external view returns (uint) {
    return HeroLib.maxOpenedNgLevel();
  }

  /// @return time stamp of the moment when the boss of the given biome at the given NG_LEVEL was killed by the hero
  function killedBosses(address hero, uint heroId, uint8 biome, uint8 ngLevel) external view returns (uint) {
    return HeroLib.killedBosses(hero, heroId, biome, ngLevel);
  }

  function maxUserNgLevel(address user) external view returns (uint) {
    return HeroLib.maxUserNgLevel(user);
  }

  /// @return Return current status of the sandbox mode for the given hero
  /// 0: The hero is created in normal (not sandbox) mode
  /// 1: The hero was created in sandbox mode and wasn't upgraded.
  /// 2: The hero has been created in sandbox mode and has been upgraded to the normal mode
  function sandboxMode(address hero, uint heroId) external view returns (uint8) {
    return uint8(HeroControllerLib.sandboxMode(hero, heroId));
  }

  /// @notice Get list of items equipped to the hero's helper at the moment of asking help by the helper
  function helperSkills(address hero, uint heroId) external view returns (
    address[] memory items,
    uint[] memory itemIds,
    uint[] memory slots
  ) {
    return HeroLib.helperSkills(hero, heroId);
  }
  //endregion ------------------------ Views

  //region ------------------------ Governance actions

  function registerHero(address hero, uint8 heroClass_, address payToken, uint payAmount) external {
    HeroLib.registerHero(IController(controller()), hero, heroClass_, payToken, payAmount);
  }

  /// @param payAmount Limited by uint72, see remarks to IHeroController.HeroInfo
  function setTier(uint8 tier, address hero, uint72 payAmount, uint8[] memory slots, address[][] memory items) external {
    HeroControllerLib.setTier(IController(controller()), tier, hero, payAmount, slots, items);
  }

  //endregion ------------------------ Governance actions

  //region ------------------------ USER ACTIONS

  function createHero(address hero, HeroCreationData memory data) external returns (uint) {
    return HeroControllerLib.createHero(IController(controller()), _msgSender(), hero, data);
  }

  /// @notice Create a hero in tier 1. Deprecated, use {createHero} instead
  function create(address hero, string calldata heroName_, bool enter) external override returns (uint) {
    return HeroControllerLib.create(IController(controller()), _msgSender(), hero, heroName_, enter);
  }

  /// @notice Create a hero in tier 1 with given {refCode}. Deprecated, use {createHero} instead
  function createWithRefCode(address hero, string calldata heroName_, string calldata refCode, bool enter) external returns (uint) {
    return HeroControllerLib.createWithRefCode(_isNotSmartContract(), IController(controller()), _msgSender(), hero, heroName_, refCode, enter);
  }

  function setBiome(address hero, uint heroId, uint8 biome) external {
    HeroLib.setBiome(_isNotSmartContract(), IController(controller()), _msgSender(), hero, heroId, biome);
  }

  function levelUp(address hero, uint heroId, IStatController.CoreAttributes memory change) external {
    HeroLib.levelUp(_isNotSmartContract(), IController(controller()), _msgSender(), hero, heroId, change);
  }

  function askReinforcement(address hero, uint heroId, address helper, uint helperId) external virtual {
    HeroControllerLib.askReinforcement(_isNotSmartContract(), IController(controller()), _msgSender(), hero, heroId, helper, helperId);
  }

  /// @notice Check if transfer is allowed and increment counter of transfers for the hero
  function beforeTokenTransfer(address hero, uint heroId) external returns (bool isAllowedToTransferOut) {
    return HeroControllerLib.beforeTokenTransfer(IController(controller()), _msgSender(), hero, heroId);
  }

  /// @notice Ask guild-hero for reinforcement
  function askGuildReinforcement(address hero, uint heroId, address helper, uint helperId) external {
    HeroControllerLib.askGuildReinforcement(IController(controller()), hero, heroId, helper, helperId);
  }

  /// @dev Approve to controller is required if the hero is post-paid and upgrade to pre-paid is available.
  /// The hero is upgraded to tier=1 always
  function reborn(address hero, uint heroId) external {
    HeroControllerLib.reborn(IController(controller()), _msgSender(), hero, heroId);
  }

  /// @notice Upgrade sandbox hero to the ordinal pre-paid hero.
  /// The hero is upgraded to tier=1 always
  /// Approve to controller for {payTokenInfo.amount} in {payTokenInfo.token} is required
  function upgradeSandboxHero(address hero, uint heroId) external {
    HeroControllerLib.upgradeSandboxHero(IController(controller()), _msgSender(), hero, heroId);
  }

  //endregion ------------------------ USER ACTIONS

  //region ------------------------ DUNGEON ACTIONS

  function kill(address hero, uint heroId) external override returns (bytes32[] memory dropItems) {
    return HeroLib.kill(IController(controller()), _msgSender(), hero, heroId);
  }

  function releaseReinforcement(address hero, uint heroId) external override returns (address helperToken, uint helperId) {
    return HeroLib.releaseReinforcement(IController(controller()), _msgSender(), hero, heroId);
  }

  /// @notice Life => 1, mana => 0
  function resetLifeAndMana(address hero, uint heroId) external {
    return HeroLib.resetLifeAndMana(IController(controller()), _msgSender(), hero, heroId);
  }

  function registerKilledBoss(address hero, uint heroId, uint32 bossObjectId) external {
    return HeroControllerLib.registerKilledBoss(IController(controller()), _msgSender(), hero, heroId, bossObjectId);
  }
  //endregion ------------------------ DUNGEON ACTIONS
}
