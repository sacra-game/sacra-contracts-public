// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./PawnShopRouter.sol";

/// @notice Factory to deploy personal instances of PawnShopRouter
contract PawnShopRouterFactory {
  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant VERSION = "1.0.0";

  address immutable public pawnShop;
  address immutable public gameToken;

  /// @notice Deployed instances of PawnShopRouter for the given users
  mapping(address user => address router) public router;

  constructor(address pawnShop_, address gameToken_) {
    if (pawnShop_ == address(0) || gameToken_ == address(0)) revert IAppErrors.ZeroAddress();

    pawnShop = pawnShop_;
    gameToken = gameToken_;
  }

  /// @notice Deploy {PawnShopRouter} for the given {user}.
  /// Any user is allowed to have only one instance of deployed router.
  /// Address of the deployed router can be taken through {deployedRouter}
  function deployRouter(address user) external {
    // no restrictions
    if (user == address(0)) revert IAppErrors.ZeroAddress();

    address deployed = router[user];
    if (deployed != address(0)) revert IAppErrors.AlreadyDeployed(deployed);

    deployed = address(new PawnShopRouter(address(this), pawnShop, gameToken, user));
    router[user] = deployed;

    emit IApplicationEvents.PawnShopRouterDeployed(pawnShop, gameToken, user, deployed);
  }
}