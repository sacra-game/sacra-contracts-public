// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

interface IHeroTokensVault {

  function process(
    address token,
    uint amount,
    address from
  ) external;

}
