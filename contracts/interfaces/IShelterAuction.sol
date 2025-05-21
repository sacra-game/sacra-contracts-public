// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;
import "../openzeppelin/EnumerableSet.sol";
import "../openzeppelin/EnumerableMap.sol";

interface IShelterAuction {
  enum ShelterAuctionParams {
    NONE_0,
    POSITION_COUNTER_1,
    BID_COUNTER_2,
    FEE_3

    // max 255 params because enum is uint8 by default
  }

  //region ------------------------ Data types
  /// @custom:storage-location erc7201:shelter.auction.main
  struct MainState {

    /// @notice Mapping to store auction params (i.e. counters)
    mapping(ShelterAuctionParams param => uint value) params;

    /// @notice Hold all positions. Any record should not be removed
    mapping(uint positionId => Position) positions;

    /// @dev BidId => Bid. Hold all bids. Any record should not be removed
    mapping(uint bidId => AuctionBid) auctionBids;

    /// @notice List of currently opened positions
    EnumerableSet.UintSet openPositions;

    /// @notice Seller to position map
    /// At any moment each guild can have only one opened position to sell
    mapping(uint sellerGuildId => uint openedPositionId) sellerPosition;

    /// @notice Position that the buyer is going to purchase.
    /// At any moment each guild can have only one opened position to purchase
    mapping(uint buyerGuildId => BuyerPositionData) buyerPosition;

    /// @notice All open and close bids for the given position
    mapping(uint positionId => uint[] bidIds) positionToBidIds;

    /// @notice Timestamp of the last bid for the auction
    mapping(uint positionId => uint timestamp) lastAuctionBidTs;
}

  struct Position {
    bool open;
    /// @notice User that opens the position. The user belongs to the guild with id = {sellerGuildId}
    address seller;

    /// @notice Assume that shelter can be stored as uint64
    uint64 shelterId;

    uint128 positionId;

    /// @notice Min allowed (initial) auction price. Only first bid is able to use it.
    uint128 minAuctionPrice;

    uint128 sellerGuildId;
  }

  struct AuctionBid {
    /// @notice Only last bid is opened, all previous bids are closed automatically
    bool open;
    /// @notice User that opens the bid. The user belongs to the guild with id = {buyerGuildId}
    address buyer;

    uint128 bidId;
    uint128 positionId;
    /// @notice Bid amount in terms of game token. This amount is transferred from guild Bank to ShelterAuction balance
    uint128 amount;
    uint128 buyerGuildId;
  }

  struct BuyerPositionData {
    /// @notice ID of the position that the buyer is going to purchase
    uint128 positionId;

    /// @notice 0-based index of the opened bid in {positionToBidIds}
    uint128 bidIndex;
  }

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  function positionBySeller(uint sellerGuildId_) external view returns (uint positionId);
  function positionByBuyer(uint buyerGuildId) external view returns (uint positionId, uint bidIndex);
  function posByShelter(uint shelterId_) external view returns (uint positionId);
}