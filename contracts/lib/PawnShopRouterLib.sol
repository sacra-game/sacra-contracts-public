// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IController.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IPawnShopRouter.sol";
import "../interfaces/IPawnShop.sol";
import "../interfaces/IAppErrors.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IApplicationEvents.sol";
import "./PackingLib.sol";

library PawnShopRouterLib {
  //region ------------------------ Restrictions
  function userOnly(address msgSender, address user) internal pure {
    if (msgSender != user) revert IAppErrors.ErrorForbidden(msgSender);
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ View
  function getOpenedPositionsLength(address pawnShop) internal view returns (uint) {
    return IPawnShop(pawnShop).borrowerPositionsSize(address(this));
  }

  function getOpenedPosition(address pawnShop, uint index) internal view returns (uint positionId) {
    return IPawnShop(pawnShop).borrowerPositions(address(this), index);
  }

  function getDepositAmount(address pawnShop, uint countPositionsToSell) internal view returns (
    address positionDepositToken,
    uint amount
  ) {
    return (
      IPawnShop(pawnShop).positionDepositToken(),
      IPawnShop(pawnShop).positionDepositAmount() * countPositionsToSell
    );
  }

  function getAmountToBulkBuying(IPawnShopRouter.CoreData memory p, uint[] memory positionIds) internal view returns (uint amount) {
    uint len = positionIds.length;
    for (uint i; i < len; ++i) {
      IPawnShop.Position memory position = _getValidPositionToBuy(p, positionIds[i]);
      amount += position.acquired.acquiredAmount;
    }
    return amount;
  }
  //endregion ------------------------ View

  //region ------------------------ User actions

  /// @notice Transfer given amount of the game token to the receiver
  function transfer(IPawnShopRouter.CoreData memory p, address msgSender, uint amount, address receiver) internal {
    userOnly(msgSender, p.user);

    IERC20(p.gameToken).transfer(receiver, amount);
    emit IApplicationEvents.PawnShopRouterTransfer(p.gameToken, amount, receiver);
  }

  function salvage(IPawnShopRouter.CoreData memory p, address msgSender, address token, uint amount, address receiver) internal {
    userOnly(msgSender, p.user);

    IERC20(token).transfer(receiver, amount);
    emit IApplicationEvents.PawnShopRouterTransfer(token, amount, receiver);
  }

  /// @notice Function to call arbitrary code
  function call(address user, address msgSender, address target, bytes memory callData) internal returns (
    bytes memory data
  ) {
    userOnly(msgSender, user);

    bool success;
    (success, data) = target.call(callData);
    if (!success) {
      revert IAppErrors.CallFailed(data);
    }
  }
  //endregion ------------------------ User actions

  //region ------------------------ Bulk instant selling

  /// @notice Bulk selling of the given set of NFT through PawnShop.sol
  function bulkSell(
    IPawnShopRouter.CoreData memory p,
    address msgSender,
    address[] memory nfts,
    uint[] memory nftIds,
    uint[] memory prices,
    address nftOwner
  ) internal {
    userOnly(msgSender, p.user);

    uint len = nftIds.length;
    if (len != prices.length || len != nfts.length) revert IAppErrors.LengthsMismatch();

    uint positionDepositAmount = IPawnShop(p.pawnShop).positionDepositAmount();

    if (positionDepositAmount != 0) {
      // take deposit from user and approve the deposit for pawnShop
      address token = IPawnShop(p.pawnShop).positionDepositToken();

      IERC20(token).transferFrom(msgSender, address(this), positionDepositAmount * len);
      _approveIfNeeded(token, positionDepositAmount * len, p.pawnShop);
    }

    // open and register positions
    uint[] memory positionIds = new uint[](len);
    for (uint i; i < len; ++i) {
      address nft = nfts[i];
      IERC721(nft).transferFrom(nftOwner, address(this), nftIds[i]);
      _approveIfNeededNft(nft, p.pawnShop);

      positionIds[i] = IPawnShop(p.pawnShop).openPosition(
        nft,
        0,
        nftIds[i],
        p.gameToken,
        prices[i],
        // 0 for instant selling
        0, // posDurationBlocks
        0, // posFee,
        0  // minAuctionAmount
      );
    }

    emit IApplicationEvents.PawnShopRouterBulkSell(nfts, nftIds, prices, nftOwner, positionIds);
  }

  /// @notice Close unsold positions, transfer NFTs to {receiver}
  function closePositions(
    IPawnShopRouter.CoreData memory p,
    address msgSender,
    uint[] memory positionIds,
    address receiver
  ) internal {
    userOnly(msgSender, p.user);

    IPawnShop _pawnShop = IPawnShop(p.pawnShop);

    uint len = positionIds.length;
    for (uint i; i < len; ++i) {
      IPawnShop.Position memory position = _pawnShop.getPosition(positionIds[i]);
      _pawnShop.closePosition(positionIds[i]);
      IERC721(position.collateral.collateralToken).transferFrom(
        address(this),
        receiver,
        position.collateral.collateralTokenId
      );
    }

    emit IApplicationEvents.PawnShopRouterClosePositions(positionIds, receiver);
  }

  //endregion ------------------------ Bulk instant selling

  //region ------------------------ Bulk instant buying
  function bulkBuy(
    IPawnShopRouter.CoreData memory p,
    address msgSender,
    uint[] memory positionIds,
    address receiver
  ) internal {
    userOnly(msgSender, p.user);

    IPawnShop _pawnShop = IPawnShop(p.pawnShop);

    uint len = positionIds.length;
    IPawnShop.Position[] memory positions = new IPawnShop.Position[](len);
    uint totalAmount;

    // get all amounts and total amount required to be approved
    // ensure that all positions are instant and they use game token as the deposit token
    for (uint i; i < len; ++i) {
      positions[i] = _getValidPositionToBuy(p, positionIds[i]);
      totalAmount += positions[i].acquired.acquiredAmount;
    }

    // take deposit from user and approve the deposit for pawnShop
    IERC20(p.gameToken).transferFrom(msgSender, address(this), totalAmount);
    // no need to approve totalAmount, there is infinite approve

    // bulk buying
    for (uint i; i < len; ++i) {
      _pawnShop.bid(positionIds[i], positions[i].acquired.acquiredAmount);
      // transfer purchased nft to the receiver
      IERC721(positions[i].collateral.collateralToken).transferFrom(address(this), receiver, positions[i].collateral.collateralTokenId);
    }

    emit IApplicationEvents.PawnShopRouterBulkBuy(positionIds, receiver);
  }
  //endregion ------------------------ Bulk instant buying

  //region ------------------------ Internal logic
  function _getValidPositionToBuy(IPawnShopRouter.CoreData memory p, uint positionId) internal view returns (IPawnShop.Position memory) {
    IPawnShop.Position memory position = IPawnShop(p.pawnShop).getPosition(positionId);
    if (position.acquired.acquiredAmount == 0) revert IAppErrors.AuctionPositionNotSupported(positionId);
    if (position.acquired.acquiredToken != p.gameToken) revert IAppErrors.PositionNotSupported(positionId);
    if (position.collateral.collateralType != IPawnShop.AssetType.ERC721) revert IAppErrors.NotNftPositionNotSupported(positionId);
    return position;
  }

  /// @notice Make infinite approve of {token} to {spender} if the approved amount is less than {amount}
  function _approveIfNeeded(address token, uint amount, address spender) internal {
    if (IERC20(token).allowance(address(this), spender) < amount) {
      // infinite approve, 2*255 is more gas efficient then type(uint).max
      IERC20(token).approve(spender, 2 ** 255);
    }
  }

  /// @notice Make infinite approve of {token} to {spender} if the approved amount is less than {amount}
  function _approveIfNeededNft(address nft, address spender) internal {
    if (!IERC721(nft).isApprovedForAll(address(this), spender)) {
      IERC721(nft).setApprovalForAll(spender, true);
    }
  }
  //endregion ------------------------ Internal logic
}
