// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "./IERC20.sol";

interface IGameToken is IERC20 {

  function minter() external view returns (address);

  function mint(address account, uint amount) external returns (bool);

  function burn(uint amount) external returns (bool);

  function setMinter(address minter_) external;

  function pause(bool value) external;

}
