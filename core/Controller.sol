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
import "../proxy/Controllable.sol";
import "../lib/ControllerLib.sol";

contract Controller is Controllable, IController {

  //region ------------------------ Constants
  /// @notice Version of the contract
  string public constant override VERSION = "1.0.3";
  uint public constant DEPLOYER_ELIGIBILITY_PERIOD = ControllerLib.DEPLOYER_ELIGIBILITY_PERIOD;
  //endregion ------------------------ Constants

  //region ------------------------ Initializer
  function init(address governance_) external initializer {
    __Controllable_init(address(this));
    ControllerLib._S().governance = governance_;
  }
  //endregion ------------------------ Initializer

  //region ------------------------ Views

  function isDeployer(address adr) public view override returns (bool) {
    return ControllerLib.isDeployer(adr);
  }

  function governance() external view override returns (address) {
    return ControllerLib.governance();
  }

  function futureGovernance() external view returns (address) {
    return ControllerLib.futureGovernance();
  }

  function statController() external view override returns (address) {
    return ControllerLib.statController();
  }

  function storyController() external view override returns (address) {
    return ControllerLib.storyController();
  }

  function oracle() external view override returns (address) {
    return ControllerLib.oracle();
  }

  function treasury() external view override returns (address) {
    return ControllerLib.treasury();
  }

  function dungeonFactory() external view override returns (address) {
    return ControllerLib.dungeonFactory();
  }

  function gameObjectController() external view override returns (address) {
    return ControllerLib.gameObjectController();
  }

  function reinforcementController() external view override returns (address) {
    return ControllerLib.reinforcementController();
  }

  function itemController() external view override returns (address) {
    return ControllerLib.itemController();
  }

  function heroController() external view override returns (address) {
    return ControllerLib.heroController();
  }

  function gameToken() external view override returns (address) {
    return ControllerLib.gameToken();
  }

  function validTreasuryTokens(address token) external view override returns (bool) {
    return ControllerLib.validTreasuryTokens(token);
  }

  function onPause() external view override returns (bool) {
    return ControllerLib.onPause();
  }
  //endregion ------------------------ Views

  //region ------------------------ Gov actions - setters

  function changePause(bool value) external {
    ControllerLib.changePause(value);
  }

  function offerGovernance(address newGov) external {
    ControllerLib.offerGovernance(newGov);
  }

  function acceptGovernance() external {
    ControllerLib.acceptGovernance();
  }

  function setStatController(address value) external {
    ControllerLib.setStatController(value);
  }

  function setStoryController(address value) external {
    ControllerLib.setStoryController(value);
  }

  function setGameObjectController(address value) external {
    ControllerLib.setGameObjectController(value);
  }

  function setReinforcementController(address value) external {
    ControllerLib.setReinforcementController(value);
  }

  function setOracle(address value) external {
    ControllerLib.setOracle(value);
  }

  function setTreasury(address value) external {
    ControllerLib.setTreasury(value);
  }

  function setItemController(address value) external {
    ControllerLib.setItemController(value);
  }

  function setHeroController(address value) external {
    ControllerLib.setHeroController(value);
  }

  function setGameToken(address value) external {
    ControllerLib.setGameToken(value);
  }

  function setDungeonFactory(address value) external {
    ControllerLib.setDungeonFactory(value);
  }

  function changeDeployer(address eoa, bool remove) external {
    ControllerLib.changeDeployer(eoa, remove);
  }
  //endregion ------------------------ Gov actions - setters

  //region ------------------------ Gov actions - others

  function updateProxies(address[] memory proxies, address newLogic) external {
    ControllerLib.updateProxies(proxies, newLogic);
  }

  function claimToGovernance(address token) external {
    ControllerLib.claimToGovernance(token);
  }
  //endregion ------------------------ Gov actions - others

  //region ------------------------ REGISTER ACTIONS

  function changeTreasuryTokenStatus(address token, bool status) external {
    ControllerLib.changeTreasuryTokenStatus(token, status);
  }
  //endregion ------------------------ REGISTER ACTIONS
}
