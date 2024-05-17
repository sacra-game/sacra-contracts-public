// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IController {

  function governance() external view returns (address);

  function statController() external view returns (address);

  function storyController() external view returns (address);

  function gameObjectController() external view returns (address);

  function reinforcementController() external view returns (address);

  function oracle() external view returns (address);

  function treasury() external view returns (address);

  function itemController() external view returns (address);

  function heroController() external view returns (address);

  function dungeonFactory() external view returns (address);

  function gameToken() external view returns (address);

  function validTreasuryTokens(address token) external view returns (bool);

  function isDeployer(address adr) external view returns (bool);

  function onPause() external view returns (bool);

}
