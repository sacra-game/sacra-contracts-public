// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "./IItemController.sol";

interface ITreasury {

  function balanceOfToken(address token) external view returns (uint);

  function sendToDungeon(address dungeon, address token, uint amount) external;
}
