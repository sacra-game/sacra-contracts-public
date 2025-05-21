// SPDX-License-Identifier: BUSL-1.1
/**
            ▒▓▒  ▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓▓▓▓███▓▓▒     ▒▒▒▒▓▓▓▒▓▓▓▓▓▓▓██▓
             ▒██▒▓▓▓▓█▓██████████████████▓  ▒▒▒▓███████████████▒
              ▒██▒▓█████████████████████▒ ▒▓██████████▓███████
               ▒███████████▓▒                   ▒███▓▓██████▓
                 █████████▒                     ▒▓▒▓███████▒
                  ███████▓      ▒▒▒▒▒▓▓█▓▒     ▓█▓████████
                   ▒▒▒▒▒   ▒▒▒▒▓▓▓█████▒      ▓█████████▓
                         ▒▓▓▓▒▓██████▓      ▒▓▓████████▒
                       ▒██▓▓▓███████▒      ▒▒▓███▓████
                        ▒███▓█████▒       ▒▒█████▓██▓
                          ██████▓   ▒▒▒▓██▓██▓█████▒
                           ▒▒▓▓▒   ▒██▓▒▓▓████████
                                  ▓█████▓███████▓
                                 ██▓▓██████████▒
                                ▒█████████████
                                 ███████████▓
      ▒▓▓▓▓▓▓▒▓                  ▒█████████▒                      ▒▓▓
    ▒▓█▒   ▒▒█▒▒                   ▓██████                       ▒▒▓▓▒
   ▒▒█▒       ▓▒                    ▒████                       ▒▓█▓█▓▒
   ▓▒██▓▒                             ██                       ▒▓█▓▓▓██▒
    ▓█▓▓▓▓▓█▓▓▓▒        ▒▒▒         ▒▒▒▓▓▓▓▒▓▒▒▓▒▓▓▓▓▓▓▓▓▒    ▒▓█▒ ▒▓▒▓█▓
     ▒▓█▓▓▓▓▓▓▓▓▓▓▒    ▒▒▒▓▒     ▒▒▒▓▓     ▓▓  ▓▓█▓   ▒▒▓▓   ▒▒█▒   ▒▓▒▓█▓
            ▒▒▓▓▓▒▓▒  ▒▓▓▓▒█▒   ▒▒▒█▒          ▒▒█▓▒▒▒▓▓▓▒   ▓██▓▓▓▓▓▓▓███▓
 ▒            ▒▓▓█▓  ▒▓▓▓▓█▓█▓  ▒█▓▓▒          ▓▓█▓▒▓█▓▒▒   ▓█▓        ▓███▓
▓▓▒         ▒▒▓▓█▓▒▒▓█▒   ▒▓██▓  ▓██▓▒     ▒█▓ ▓▓██   ▒▓▓▓▒▒▓█▓        ▒▓████▒
 ██▓▓▒▒▒▒▓▓███▓▒ ▒▓▓▓▓▒▒ ▒▓▓▓▓▓▓▓▒▒▒▓█▓▓▓▓█▓▓▒▒▓▓▓▓▓▒    ▒▓████▓▒     ▓▓███████▓▓▒
*/
pragma solidity 0.8.23;

import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";
import "../interfaces/IShelterAuction.sol";
import "../interfaces/IApplicationEvents.sol";
import "../lib/PackingLib.sol";
import "../lib/ShelterAuctionLib.sol";

contract ShelterAuctionController is Controllable, IShelterAuction, ERC2771Context {
  //region ------------------------ Constants

  /// @notice Version of the contract
  string public constant override VERSION = "1.0.1";
  //endregion ------------------------ Constants

  //region ------------------------ Initializer

  function init(address controller_) external initializer {
    __Controllable_init(controller_);
    ShelterAuctionLib._S().params[IShelterAuction.ShelterAuctionParams.FEE_3] = ShelterAuctionLib.DEFAULT_FEE;
  }
  //endregion ------------------------ Initializer  
  
  //region ------------------------ View
  function getBid(uint bidId_) external view returns (IShelterAuction.AuctionBid memory) {
    return ShelterAuctionLib.getBid(bidId_);
  }

  function getPosition(uint positionId_) external view returns (IShelterAuction.Position memory) {
    return ShelterAuctionLib.getPosition(positionId_);
  }

  /// @notice Get position currently opened by the given guild. Only one position can be opened at any time.
  function positionBySeller(uint sellerGuildId_) external view returns (uint positionId) {
    return ShelterAuctionLib.positionBySeller(sellerGuildId_);
  }

  /// @notice Get position currently opened for the given shelter or 0
  function posByShelter(uint shelterId_) external view returns (uint positionId) {
    return ShelterAuctionLib.posByShelter(IController(controller()), shelterId_);
  }

  /// @notice Get info about bid opened by the given guild. Only one bid can be opened at any time.
  /// @return positionId ID of the position that the buyer is going to purchase
  /// @return bidIndex 0-based index of the opened bid in {positionToBidIds}
  function positionByBuyer(uint buyerGuildId) external view returns (uint positionId, uint bidIndex) {
    IShelterAuction.BuyerPositionData memory data = ShelterAuctionLib.positionByBuyer(buyerGuildId);
    return (data.positionId, data.bidIndex);
  }

  /// @notice Total number of currently opened positions
  function openPositionsLength() external view returns (uint) {
    return ShelterAuctionLib.openPositionsLength();
  }

  function openPositionByIndex(uint index) external view returns (uint positionId) {
    return ShelterAuctionLib.openPositionByIndex(index);
  }

  /// @notice Timestamp (in seconds) of last created bid for the given position
  function lastAuctionBidTs(uint positionId) external view returns (uint timestamp) {
    return ShelterAuctionLib.lastAuctionBidTs(positionId);
  }

  /// @notice Total number of currently opened bids for the given position
  function positionBidsLength(uint positionId) external view returns (uint) {
    return ShelterAuctionLib.positionBidsLength(positionId);
  }

  function positionBidByIndex(uint positionId, uint bidIndex) external view returns (uint) {
    return ShelterAuctionLib.positionBidByIndex(positionId, bidIndex);
  }

  function positionCounter() external view returns (uint) {
    return ShelterAuctionLib.positionCounter();
  }

  function bidCounter() external view returns (uint) {
    return ShelterAuctionLib.bidCounter();
  }

  /// @notice Percent of fee (100% = 100_000) that is taken in behalf of the governance from each sold shelter.
  function fee() external view returns (uint) {
    return ShelterAuctionLib.fee();
  }

  /// @notice Min amount that is valid to be passed to {bid} for the given position.
  /// Initial amount is specified by seller in openPosition, than amount is increased with rate {NEXT_AMOUNT_RATIO}
  /// on creation of each new bid
  function nextAmount(uint positionId) external view returns (uint) {
    return ShelterAuctionLib.nextAmount(positionId);
  }

  /// @notice Deadline of auction ending. The deadline is changed on each creation of new bid for the given position.
  function auctionEndTs(uint positionId) external view returns (uint timestamp) {
    return ShelterAuctionLib.auctionEndTs(positionId, ShelterAuctionLib.AUCTION_DURATION);
  }

  //endregion ------------------------ View

  //region ------------------------ Actions
  /// @notice Seller action. Open new position, setup min allowed auction price.
  /// @param shelterId Shelter to be sold. Assume, that message sender belongs to the guild that owns the shelter.
  /// @param minAuctionPrice Min allowed initial price, 0 is not allowed
  /// @return id of newly crated position. You can get this ID also by using {positionBySeller}
  function openPosition(uint shelterId, uint minAuctionPrice) external returns (uint) {
    return ShelterAuctionLib.openPosition(IController(controller()), _msgSender(), shelterId, minAuctionPrice);
  }

  /// @notice Seller action. Close position without any bids.
  function closePosition(uint positionId) external {
    ShelterAuctionLib.closePosition(IController(controller()), _msgSender(), positionId);
  }

  /// @notice Buyer action. Create new bid with amount higher than the amount of previously registered bid.
  /// The amount is taken from guild bank to balance of this contract and returned if the bid is closed.
  /// Close previous auction bid and transfer bid-amount back to the buyer.
  /// @param amount Amount of the bid in terms of the game token. Use {nextAmount} to know min valid value
  function bid(uint positionId, uint amount) external {
    ShelterAuctionLib.bid(IController(controller()), _msgSender(), positionId, amount, ShelterAuctionLib.AUCTION_DURATION, block.timestamp);
  }

  /// @notice Apply winner-bid by seller or by buyer. Assume that auction ended.
  /// Transfer winner-bid-amount to the seller. Transfer shelter from seller to the buyer. CLose the position.
  function applyAuctionBid(uint bidId) external {
    ShelterAuctionLib.applyAuctionBid(IController(controller()), _msgSender(), bidId, ShelterAuctionLib.AUCTION_DURATION, block.timestamp);
  }
  //endregion ------------------------ Actions

  //region ------------------------ Deployer actions
  function setFee(uint fee_) external {
    ShelterAuctionLib.setFee(IController(controller()), fee_);
  }
  //endregion ------------------------ Deployer actions
}
