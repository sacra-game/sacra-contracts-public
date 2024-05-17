// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IProxyControlled {

  function upgrade(address newImplementation_) external;

  function implementation() external view returns (address);

}
