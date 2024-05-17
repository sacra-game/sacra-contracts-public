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
import "../lib/StatControllerLib.sol";

contract StatController is Controllable, IStatController {

  //region ------------------------ CONSTANTS

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant override VERSION = "2.1.1";
  //endregion ------------------------ CONSTANTS

  //region ------------------------ INITIALIZER

  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ INITIALIZER

  //region ------------------------ VIEWS

  function heroInitialAttributes(uint heroClass) external pure returns (StatLib.InitialHero memory) {
    return StatLib.initialHero(heroClass);
  }

  function heroAttributes(address token, uint tokenId) public view override returns (int32[] memory) {
    return StatControllerLib.heroAttributes(StatControllerLib._S(), token, tokenId);
  }

  function heroBonusAttributes(address token, uint tokenId) public view returns (int32[] memory) {
    return StatControllerLib.heroBonusAttributes(StatControllerLib._S(), token, tokenId);
  }

  function heroTemporallyAttributes(address token, uint tokenId) public view returns (int32[] memory) {
    return StatControllerLib.heroTemporallyAttributes(StatControllerLib._S(), token, tokenId);
  }

  function heroAttributesLength(address token, uint tokenId) external pure override returns (uint) {
    return StatControllerLib.heroAttributesLength(token, tokenId);
  }

  function heroAttribute(address token, uint tokenId, uint index) external view override returns (int32) {
    return StatControllerLib.heroAttribute(StatControllerLib._S(), token, tokenId, index);
  }

  function heroBaseAttributes(address token, uint tokenId) public view override returns (CoreAttributes memory core) {
    return StatControllerLib.heroBaseAttributes(StatControllerLib._S(), token, tokenId);
  }

  function heroCustomData(address token, uint tokenId, bytes32 index) external view override returns (uint) {
    return StatControllerLib.heroCustomData(StatControllerLib._S(), token, tokenId, index);
  }

  function globalCustomData(bytes32 index) external view override returns (uint) {
    return StatControllerLib.globalCustomData(StatControllerLib._S(), index);
  }

  function heroStats(address token, uint tokenId) public view override returns (ChangeableStats memory result) {
    return StatControllerLib.heroStats(StatControllerLib._S(), token, tokenId);
  }

  function heroItemSlot(address heroToken, uint64 heroTokenId, uint8 itemSlot) public view override returns (bytes32 nftPacked) {
    return StatControllerLib.heroItemSlot(StatControllerLib._S(), heroToken, heroTokenId, itemSlot);
  }

  function heroItemSlots(address heroToken, uint heroTokenId) external view override returns (uint8[] memory) {
    return StatControllerLib.heroItemSlots(StatControllerLib._S(), heroToken, heroTokenId);
  }

  function isHeroAlive(address heroToken, uint heroTokenId) external view override returns (bool) {
    return StatControllerLib.isHeroAlive(StatControllerLib._S(), heroToken, heroTokenId);
  }

  function isConsumableUsed(address heroToken, uint heroTokenId, address item) external view returns (bool) {
    return StatControllerLib.isConsumableUsed(StatControllerLib._S(), heroToken, heroTokenId, item);
  }

  function buffHero(BuffInfo memory info) external view override returns (int32[] memory, int32) {
    return StatControllerLib.buffHero(StatControllerLib._S(), IController(controller()), info);
  }
  //endregion ------------------------ VIEWS

  //region ------------------------ PURE

  function levelUpExperienceRequired(uint32 level) external pure returns (uint) {
    return StatControllerLib.levelUpExperienceRequired(level);
  }

  function levelExperience(uint32 level) external pure returns (uint) {
    return StatLib.levelExperience(level);
  }
  //endregion ------------------------ PURE

  //region ------------------------ ACTIONS

  function initNewHero(address heroToken, uint heroTokenId, uint heroClass) external override {
    return StatControllerLib.initNewHero(StatControllerLib._S(), IController(controller()), heroToken, heroTokenId, heroClass);
  }

  function changeHeroItemSlot(
    address heroToken,
    uint64 heroTokenId,
    uint itemType,
    uint8 itemSlot,
    address itemToken,
    uint itemTokenId,
    bool equip
  ) external override {
    return StatControllerLib.changeHeroItemSlot(
      StatControllerLib._S(),
      IController(controller()),
      heroToken,
      heroTokenId,
      itemType,
      itemSlot,
      itemToken,
      itemTokenId,
      equip
    );
  }

  function changeCurrentStats(address heroToken, uint heroTokenId, ChangeableStats memory change, bool increase) external override {
    return StatControllerLib.changeCurrentStats(StatControllerLib._S(), IController(controller()), heroToken, heroTokenId, change, increase);
  }

  function registerConsumableUsage(address heroToken, uint heroTokenId, address item) external override {
    return StatControllerLib.registerConsumableUsage(StatControllerLib._S(), IController(controller()), heroToken, heroTokenId, item);
  }

  function clearUsedConsumables(address heroToken, uint heroTokenId) external override {
    return StatControllerLib.clearUsedConsumables(StatControllerLib._S(), IController(controller()), heroToken, heroTokenId);
  }

  function changeBonusAttributes(ChangeAttributesInfo memory info) external override {
    return StatControllerLib.changeBonusAttributes(StatControllerLib._S(), IController(controller()), info);
  }

  function clearTemporallyAttributes(address heroToken, uint heroTokenId) external override {
    return StatControllerLib.clearTemporallyAttributes(StatControllerLib._S(), IController(controller()), heroToken, heroTokenId);
  }

  function levelUp(address heroToken, uint heroTokenId, uint heroClass, CoreAttributes memory change)
  external override returns (uint newLvl) {
    return StatControllerLib.levelUp(StatControllerLib._S(), IController(controller()), heroToken, heroTokenId, heroClass, change);
  }

  function setHeroCustomData(address token, uint tokenId, bytes32 index, uint value) external override {
    return StatControllerLib.setHeroCustomData(StatControllerLib._S(), IController(controller()), token, tokenId, index, value);
  }

  function setGlobalCustomData(bytes32 index, uint value) external override {
    return StatControllerLib.setGlobalCustomData(StatControllerLib._S(), IController(controller()), index, value);
  }
  //endregion ------------------------ ACTIONS

}
