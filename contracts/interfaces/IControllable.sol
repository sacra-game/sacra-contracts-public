// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IControllable {

  function VERSION() external pure returns (string memory);

  function revision() external view returns (uint);

  function previousImplementation() external view returns (address);

  function isController(address contract_) external view returns (bool);

  function isGovernance(address contract_) external view returns (bool);

  function created() external view returns (uint256);

  function createdBlock() external view returns (uint256);

  function controller() external view returns (address);

  function increaseRevision(address oldLogic) external;

}
