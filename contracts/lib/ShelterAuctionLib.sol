// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IERC20.sol";
import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IController.sol";
import "../interfaces/IGuildController.sol";
import "../interfaces/IShelterAuction.sol";
import "../interfaces/IShelterController.sol";
import "../openzeppelin/EnumerableSet.sol";

library ShelterAuctionLib {
  using EnumerableSet for EnumerableSet.UintSet;

  //region ------------------------ Constants
  /// @dev keccak256(abi.encode(uint256(keccak256("shelter.auction.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant SHELTER_AUCTION_MAIN_STORAGE_LOCATION = 0x597e4e55fd306bfc6bfaaa6b3e10d80a4b0fe770b166ac704f10504e76e97c00; // shelter.auction.main

  uint internal constant AUCTION_DURATION = 1 days;

  uint internal constant FEE_DENOMINATOR = 100_000;
  uint internal constant DEFAULT_FEE = 100;
  uint internal constant MAX_FEE = 50_000;

  /// @notice Min allowed amount of next bid is {prev amount} * {NEXT_AMOUNT_RATIO} / 100
  uint internal constant NEXT_AMOUNT_RATIO = 110;
  //endregion ------------------------ Constants

  //region ------------------------ Storage

  function _S() internal pure returns (IShelterAuction.MainState storage s) {
    assembly {
      s.slot := SHELTER_AUCTION_MAIN_STORAGE_LOCATION
    }
    return s;
  }
  //endregion ------------------------ Storage

  //region ------------------------ Restrictions
  function _onlyNotPaused(IController controller) internal view {
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
  }

  function _onlyDeployer(IController controller) internal view {
    if (!controller.isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }

  //endregion ------------------------ Restrictions

  //region ------------------------ View
  function getBid(uint bidId_) internal view returns (IShelterAuction.AuctionBid memory) {
    return _S().auctionBids[bidId_];
  }

  function getPosition(uint positionId_) internal view returns (IShelterAuction.Position memory) {
    return _S().positions[positionId_];
  }

  function positionBySeller(uint sellerGuildId_) internal view returns (uint positionId) {
    return _S().sellerPosition[sellerGuildId_];
  }

  function posByShelter(IController controller, uint shelterId_) internal view returns (uint positionId) {
    IGuildController guildController = IGuildController(controller.guildController());
    address shelterController = guildController.shelterController();
    return shelterController == address(0)
      ? 0
      : positionBySeller(IShelterController(shelterController).shelterToGuild(shelterId_));
  }

  function positionByBuyer(uint buyerGuildId) internal view returns (IShelterAuction.BuyerPositionData memory) {
    return _S().buyerPosition[buyerGuildId];
  }

  function openPositionsLength() internal view returns (uint) {
    return _S().openPositions.length();
  }

  function openPositionByIndex(uint index) internal view returns (uint positionId) {
    return _S().openPositions.at(index);
  }

  function lastAuctionBidTs(uint positionId) internal view returns (uint timestamp) {
    return _S().lastAuctionBidTs[positionId];
  }

  function positionBidsLength(uint positionId) internal view returns (uint) {
    return _S().positionToBidIds[positionId].length;
  }

  function positionBidByIndex(uint positionId, uint bidIndex) internal view returns (uint) {
    return _S().positionToBidIds[positionId][bidIndex];
  }

  function positionCounter() internal view returns (uint) {
    return _S().params[IShelterAuction.ShelterAuctionParams.POSITION_COUNTER_1];
  }

  function bidCounter() internal view returns (uint) {
    return _S().params[IShelterAuction.ShelterAuctionParams.BID_COUNTER_2];
  }

  function fee() internal view returns (uint) {
    return _S().params[IShelterAuction.ShelterAuctionParams.FEE_3];
  }

  function nextAmount(uint positionId) internal view returns (uint) {
    uint[] storage bidIds = _S().positionToBidIds[positionId];

    uint length = bidIds.length;
    if (length == 0) {
      return _S().positions[positionId].minAuctionPrice;
    } else {
      IShelterAuction.AuctionBid storage lastBid = _S().auctionBids[bidIds[length - 1]];
      return lastBid.amount * NEXT_AMOUNT_RATIO / 100;
    }
  }

  function auctionEndTs(uint positionId, uint auctionDuration) internal view returns (uint timestamp) {
    uint lastBidTimestamp = _S().lastAuctionBidTs[positionId];
    return lastBidTimestamp == 0
      ? 0
      : lastBidTimestamp + auctionDuration;
  }
  //endregion ------------------------ View

  //region ------------------------ Actions
  /// @notice Seller action. Open new position, setup min allowed auction price.
  function openPosition(IController controller, address msgSender, uint shelterId, uint minAuctionPrice) internal returns (uint) {
    _onlyNotPaused(controller);
    if (minAuctionPrice == 0) revert IAppErrors.ZeroValueNotAllowed();

    IGuildController guildController = IGuildController(controller.guildController());
    (uint sellerGuildId, ) = _checkPermissions(msgSender, guildController, IGuildController.GuildRightBits.CHANGE_SHELTER_3);

    uint existPositionId = _S().sellerPosition[sellerGuildId];
    if (existPositionId != 0) revert IAppErrors.AuctionPositionOpened(existPositionId);

    if (guildController.guildToShelter(sellerGuildId) != shelterId) revert IAppErrors.ShelterIsNotOwnedByTheGuild();
    if (shelterId == 0) revert IAppErrors.ZeroValueNotAllowed();

    uint positionId = _generateId(IShelterAuction.ShelterAuctionParams.POSITION_COUNTER_1);

    _S().openPositions.add(positionId);
    _S().positions[positionId] = IShelterAuction.Position({
      positionId: uint128(positionId),
      shelterId: uint64(shelterId),
      open: true,
      sellerGuildId: uint128(sellerGuildId),
      seller: msgSender,
      minAuctionPrice: uint128(minAuctionPrice)
    });

    _S().sellerPosition[sellerGuildId] = positionId;

    emit IApplicationEvents.AuctionPositionOpened(positionId, shelterId, sellerGuildId, msgSender, minAuctionPrice);
    return positionId;
  }

  /// @notice Seller action. Close position without any bids.
  function closePosition(IController controller, address msgSender, uint positionId) internal {
    _onlyNotPaused(controller);

    // Any member of the seller-guild can close position if he has enough permission.
    // On the contrary, original position creator is NOT able to close position if he has not rights anymore
    IGuildController guildController = IGuildController(controller.guildController());
    (uint sellerGuildId, ) = _checkPermissions(msgSender, guildController, IGuildController.GuildRightBits.CHANGE_SHELTER_3);

    IShelterAuction.Position storage pos = _S().positions[positionId];
    if (pos.positionId != positionId) revert IAppErrors.WrongAuctionPosition();
    if (pos.sellerGuildId != sellerGuildId) revert IAppErrors.AuctionSellerOnly();
    if (!pos.open) revert IAppErrors.AuctionPositionClosed();

    uint lastBidTimestamp = _S().lastAuctionBidTs[positionId];
    if (lastBidTimestamp != 0) revert IAppErrors.AuctionBidExists();

    _S().openPositions.remove(positionId);
    delete _S().sellerPosition[sellerGuildId];

    pos.open = false;

    emit IApplicationEvents.AuctionPositionClosed(positionId, msgSender);
  }

  /// @notice Buyer action. Create new bid with amount higher than the amount of previously registered bid.
  /// Close previous auction bid and transfer bid-amount back to the buyer.
  /// Assume approve for bid-amount.
  function bid(
    IController controller,
    address msgSender,
    uint positionId,
    uint amount,
    uint auctionDuration,
    uint blockTimestamp
  ) internal {
    _onlyNotPaused(controller);

    IGuildController guildController = IGuildController(controller.guildController());
    (uint buyerGuildId, ) = _checkPermissions(msgSender, guildController, IGuildController.GuildRightBits.CHANGE_SHELTER_3);

    IShelterAuction.Position storage pos = _S().positions[positionId];
    if (pos.positionId != positionId) revert IAppErrors.WrongAuctionPosition();
    if (!pos.open) revert IAppErrors.AuctionPositionClosed();
    if (pos.sellerGuildId == buyerGuildId) revert IAppErrors.AuctionSellerCannotBid();

    {
      IShelterAuction.BuyerPositionData storage buyerPos = _S().buyerPosition[buyerGuildId];
      if (buyerPos.positionId != 0) revert IAppErrors.AuctionBidOpened(buyerPos.positionId);
    }

    uint[] storage bidIds = _S().positionToBidIds[positionId];

    // assume here that shelterController cannot be 0 (it's useless to use ShelterAuction otherwise)
    if (0 != IShelterController(guildController.shelterController()).guildToShelter(buyerGuildId)) revert IAppErrors.AuctionGuildWithShelterCannotBid();

    // open auction bid
    uint length = bidIds.length;
    if (length == 0) {
      if (amount < pos.minAuctionPrice) revert IAppErrors.TooLowAmountToBid();
    } else {
      if (_S().lastAuctionBidTs[positionId] + auctionDuration < blockTimestamp) revert IAppErrors.AuctionEnded();
      IShelterAuction.AuctionBid storage lastBid = _S().auctionBids[bidIds[length - 1]];
      if (lastBid.amount * NEXT_AMOUNT_RATIO / 100 > amount) revert IAppErrors.TooLowAmountForNewBid();

      // automatically close previous last bid and return full amount to the bid's owner
      _closeBidAndReturnAmount(lastBid, guildController, controller);
    }

    IShelterAuction.AuctionBid memory newBid = IShelterAuction.AuctionBid({
      bidId: uint128(_generateId(IShelterAuction.ShelterAuctionParams.BID_COUNTER_2)),
      amount: uint128(amount),
      positionId: uint128(positionId),
      open: true,
      buyer: msgSender,
      buyerGuildId: uint128(buyerGuildId)
    });

    bidIds.push(newBid.bidId);

    _S().auctionBids[newBid.bidId] = newBid;
    _S().buyerPosition[buyerGuildId] = IShelterAuction.BuyerPositionData({
      positionId: uint128(positionId),
      bidIndex: uint128(length)
    });
    _S().lastAuctionBidTs[positionId] = blockTimestamp;

    // get amount from buyer guild bank on the balance of this contract
    guildController.payForAuctionBid(buyerGuildId, amount, newBid.bidId);

    emit IApplicationEvents.AuctionBidOpened(newBid.bidId, positionId, amount, msgSender);
  }

  /// @notice Apply winner-bid by seller or by buyer. Assume that auction ended.
  /// Transfer winner-bid-amount to the seller. Transfer shelter from seller to the buyer. CLose the position.
  function applyAuctionBid(IController controller, address msgSender, uint bidId, uint auctionDuration, uint blockTimestamp) internal {
    _onlyNotPaused(controller);

    IGuildController guildController = IGuildController(controller.guildController());
    (uint guildId, ) = _checkPermissions(msgSender, guildController, IGuildController.GuildRightBits.CHANGE_SHELTER_3);

    IShelterAuction.AuctionBid storage _bid = _S().auctionBids[bidId];
    uint positionId = _bid.positionId;
    if (positionId == 0) revert IAppErrors.AuctionBidNotFound();
    if (!_bid.open) revert IAppErrors.AuctionBidClosed();

    IShelterAuction.Position storage pos = _S().positions[positionId];
    // assume here that only last bid can be opened, all previous bids are closed automatically
    if (!pos.open) revert IAppErrors.AuctionPositionClosed();

    if (_S().lastAuctionBidTs[positionId] + auctionDuration >= blockTimestamp) revert IAppErrors.AuctionNotEnded();

    uint sellerGuildId = pos.sellerGuildId;
    {
      uint buyerGuildId = _bid.buyerGuildId;
      if (guildId != sellerGuildId && guildId != buyerGuildId) revert IAppErrors.ErrorNotAllowedSender();

      // close the bid, close the position
      pos.open = false;
      _bid.open = false;
      _S().openPositions.remove(positionId);
      delete _S().sellerPosition[sellerGuildId];
      delete _S().buyerPosition[buyerGuildId];

      // move shelter from the seller to the buyer
      IShelterController shelterController = IShelterController(guildController.shelterController());
      shelterController.changeShelterOwner(pos.shelterId, buyerGuildId);
    }

    // transfer amount to balance of guild bank of the seller, transfer fee to controller
    address gameToken = controller.gameToken();
    uint amount = _bid.amount;
    uint toGov = amount * fee() / FEE_DENOMINATOR;
    if (toGov != 0) {
      IERC20(gameToken).transfer(address(controller), toGov);
    }

    address sellerGuildBank = guildController.getGuildBank(sellerGuildId);
    IERC20(gameToken).transfer(sellerGuildBank, amount - toGov);

    emit IApplicationEvents.ApplyAuctionBid(bidId, msgSender);
  }
  //endregion ------------------------ Actions

  //region ------------------------ Deployer actions
  function setFee(IController controller, uint fee_) internal {
    _onlyDeployer(controller);

    if (fee_ > MAX_FEE) revert IAppErrors.TooHighValue(fee_);
    _S().params[IShelterAuction.ShelterAuctionParams.FEE_3] = fee_;

    emit IApplicationEvents.AuctionSetFee(fee_);
  }
  //endregion ------------------------ Deployer actions

  //region ------------------------ Internal logic
  /// @notice Close auction bid and transfer bid-amount back to the buyer.
  function _closeBidAndReturnAmount(
    IShelterAuction.AuctionBid storage bid_,
    IGuildController guildController,
    IController controller
  ) internal {
    uint guildId = bid_.buyerGuildId;

    bid_.open = false;
    delete _S().buyerPosition[guildId];

    // return full amount back to the buyer
    address buyerGuildBank = guildController.getGuildBank(guildId);
    address gameToken = controller.gameToken();
    IERC20(gameToken).transfer(buyerGuildBank, bid_.amount);
  }

  /// @notice Generate id, increment id-counter
  /// @dev uint is used to store id. In the code we assume that it's safe to use uint128 to store such ids
  function _generateId(IShelterAuction.ShelterAuctionParams paramId) internal returns (uint uid) {
    uid = _S().params[paramId] + 1;
    _S().params[paramId] = uid;
  }

  /// @notice Check if the {user} has given permission in the guild. Permissions are specified by bitmask {rights}.
  /// Admin is marked by zero bit, he has all permissions always.
  function _checkPermissions(address user, IGuildController guildController, IGuildController.GuildRightBits right) internal view returns (uint guildId, uint rights) {
    guildId = guildController.memberOf(user);
    if (guildId == 0) revert IAppErrors.NotGuildMember();

    rights = guildController.getRights(user);

    if (!(
      (rights & (2**uint(IGuildController.GuildRightBits.ADMIN_0))) != 0
      || (rights & (2**uint(right))) != 0
    )) {
      revert IAppErrors.GuildActionForbidden(uint(right));
    }
  }
  //endregion ------------------------ Internal logic
}