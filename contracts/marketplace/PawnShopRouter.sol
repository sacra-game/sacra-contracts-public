// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IApplicationEvents.sol";
import "../lib/PawnShopRouterLib.sol";
import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";
import "../openzeppelin/ERC721Holder.sol";

/// @notice Personal router for the given to user to make bulk selling/buying on the given marketplace.
/// Only instant positions are supported. Auction positions are not supported in bulk operations.
contract PawnShopRouter is ERC2771Context, ERC721Holder {
  //region ------------------------ Constants

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant VERSION = "1.0.1";
  //endregion ------------------------ Constants

  //region ------------------------ Variables
  /// @notice Factory that has created this contract instance
  address immutable public factory;

  /// @notice The marketplace - address of PawnShop contract
  address immutable public pawnShop;

  /// @notice ERC20 token that is used to paying for any positions on the marketplace
  address immutable public gameToken;

  /// @notice This contract instance owner. All functions can be called by the user only.
  address immutable public user;

  /// @notice Value returned by last successful call of "call()"
  bytes public callResultData;

  //endregion ------------------------ Variables

  //region ------------------------ Constructor
  constructor(address factory_, address pawnShop_, address gameToken_, address user_) {
    if (
      factory_ == address(0)
      || pawnShop_ == address(0)
      || gameToken_ == address(0)
      || user_ == address(0)
    ) revert IAppErrors.ZeroAddress();

    factory = factory_;
    gameToken = gameToken_;
    pawnShop = pawnShop_;
    user = user_;

    // infinite approve, 2*255 is more gas efficient then type(uint).max
    IERC20(gameToken).approve(pawnShop, 2 ** 255);
  }

  //endregion ------------------------ Constructor

  //region ------------------------ View
  /// @notice Give current number of opened and unsold positions on the marketplace for the user
  function getOpenedPositionsLength() external view returns (uint) {
    return PawnShopRouterLib.getOpenedPositionsLength(pawnShop);
  }

  /// @param index [0...getOpenedPositionsLength())
  function getOpenedPosition(uint index) external view returns (uint positionId) {
    return PawnShopRouterLib.getOpenedPosition(pawnShop, index);
  }

  /// @notice Get deposit {amount} required to open {countPositionsToSell} positions on the marketplace
  function getDepositAmount(uint countPositionsToSell) external view returns (address positionDepositToken, uint amount) {
    return PawnShopRouterLib.getDepositAmount(pawnShop, countPositionsToSell);
  }

  /// @notice Get amount required to purchase positions with given ids. Revert if any position is not suitable for bulk buying
  function getAmountToBulkBuying(uint[] memory positionIds) external view returns (uint amount) {
    return PawnShopRouterLib.getAmountToBulkBuying(
      IPawnShopRouter.CoreData({user: user, gameToken: gameToken, pawnShop: pawnShop}),
      positionIds
    );
  }
  //endregion ------------------------ View

  //region ------------------------ Bulk instant selling

  /// @notice Bulk selling of the given set of NFT through PawnShop.sol
  /// Assume that deposit amount is approved by the user. Use {getDepositAmount} to get deposit amount.
  /// @param nftOwner Owner of all {nftIds}. Assume that all NFTs are approved to the router by NFT owner.
  function bulkSell(address[] memory nfts, uint[] memory nftIds, uint[] memory prices, address nftOwner) external {
    return PawnShopRouterLib.bulkSell(
      IPawnShopRouter.CoreData({user: user, gameToken: gameToken, pawnShop: pawnShop}),
      _msgSender(),
      nfts,
      nftIds,
      prices,
      nftOwner
    );
  }

  /// @notice Close unsold positions, return NFT back and transfer them to the {receiver}
  function closePositions(uint[] memory positionIds, address receiver) external {
    PawnShopRouterLib.closePositions(
      IPawnShopRouter.CoreData({user: user, gameToken: gameToken, pawnShop: pawnShop}),
      _msgSender(),
      positionIds,
      receiver
    );
  }
  //endregion ------------------------ Bulk instant selling

  //region ------------------------ Bulk instant buying
  /// @notice Buy given positions and send purchased NFT to the {receiver}
  function bulkBuy(uint[] memory positionIds, address receiver) external {
    return PawnShopRouterLib.bulkBuy(
      IPawnShopRouter.CoreData({user: user, gameToken: gameToken, pawnShop: pawnShop}),
      _msgSender(),
      positionIds,
      receiver
    );
  }
  //endregion ------------------------ Bulk instant buying

  //region ------------------------ User actions

  /// @notice Transfer given amount of the game token to the receiver
  function transfer(uint amount, address receiver) external {
    PawnShopRouterLib.transfer(
      IPawnShopRouter.CoreData({user: user, gameToken: gameToken, pawnShop: pawnShop}),
      _msgSender(),
      amount,
      receiver
    );
  }

  /// @notice Transfer given amount of the given token to the receiver
  function salvage(address token, uint amount, address receiver) external {
    PawnShopRouterLib.salvage(
      IPawnShopRouter.CoreData({user: user, gameToken: gameToken, pawnShop: pawnShop}),
      _msgSender(),
      token,
      amount,
      receiver
    );
  }

  /// @notice Allow the user to execute arbitrary code on this contract
  /// Results of successful call are stored to {callResultData}.
  /// Exception CallFailed with error details is generated if the call is failed.
  function call(address target_, bytes memory callData_) external {
    callResultData = PawnShopRouterLib.call(user, _msgSender(), target_, callData_);
  }
  //endregion ------------------------ User actions

}
