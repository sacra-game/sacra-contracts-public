// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

// use copies of openzeppelin contracts with changed names for avoid dependency issues
import "../interfaces/IERC20.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IPawnShop.sol";
import "../lib/AppLib.sol";
import "../openzeppelin/ERC721Holder.sol";
import "../openzeppelin/ReentrancyGuard.sol";
import "../relay/ERC2771Context.sol";

interface IDelegation {
  function clearDelegate(bytes32 _id) external;
  function setDelegate(bytes32 _id, address _delegate) external;
}

/// @title PawnShop.sol contract provides a useful and flexible solution for borrowing
///        and lending assets with a unique feature of supporting both ERC721 and ERC20 tokens as collateral.
///        The contract's modular design allows for easy customization of fees, waiting periods,
///        and other parameters, providing a solid foundation for a decentralized borrowing and lending platform.
/// @author belbix
contract PawnShop is ERC721Holder, ReentrancyGuard, IPawnShop, ERC2771Context {

  //region ------------------------ Constants

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant VERSION = "1.0.10";
  /// @dev Time lock for any governance actions
  uint constant public TIME_LOCK = 2 days;
  /// @dev Denominator for any internal computation with low precision
  uint constant public DENOMINATOR = 10000;
  /// @dev Governance can't set fee more than this value
  uint constant public PLATFORM_FEE_MAX = 1000; // 10%
  /// @dev Standard auction duration that refresh when a new bid placed
  uint constant public AUCTION_DURATION = 1 days;
  /// @dev Timestamp date when contract created
  uint public immutable createdTs;
  /// @dev Block number when contract created
  uint public immutable createdBlock;
  //endregion ------------------------ Constants

  //region ------------------------ Changeable variables

  /// @dev Contract owner. Should be a multi-signature wallet.
  address public owner;
  /// @dev Fee recipient. Assume it will be a place with ability to manage different tokens
  address public feeRecipient;
  /// @dev 10% by default, percent of acquired tokens that will be used for buybacks
  uint public platformFee = 1000;
  /// @dev Amount of tokens for open position. Protection against spam
  uint public positionDepositAmount;
  /// @dev Token for antispam protection. Zero address means no protection
  address public positionDepositToken;
  /// @dev Time-locks for governance actions
  mapping(GovernanceAction => TimeLock) public timeLocks;
  //endregion ------------------------ Changeable variables

  //region ------------------------ Positions

  /// @inheritdoc IPawnShop
  uint public override positionCounter = 1;
  /// @dev PosId => Position. Hold all positions. Any record should not be removed
  mapping(uint => Position) public positions;
  /// @inheritdoc IPawnShop
  uint[] public override openPositions;
  /// @inheritdoc IPawnShop
  mapping(address => uint[]) public override positionsByCollateral;
  /// @inheritdoc IPawnShop
  mapping(address => uint[]) public override positionsByAcquired;
  /// @inheritdoc IPawnShop
  mapping(address => uint[]) public override borrowerPositions;
  /// @inheritdoc IPawnShop
  mapping(address => uint[]) public override lenderPositions;
  /// @inheritdoc IPawnShop
  mapping(IndexType => mapping(uint => uint)) public override posIndexes;
  //endregion ------------------------ Positions

  //region ------------------------ Auction

  /// @inheritdoc IPawnShop
  uint public override auctionBidCounter = 1;
  /// @dev BidId => Bid. Hold all bids. Any record should not be removed
  mapping(uint => AuctionBid) public auctionBids;
  /// @inheritdoc IPawnShop
  mapping(address => mapping(uint => uint)) public override lenderOpenBids;
  /// @inheritdoc IPawnShop
  mapping(uint => uint[]) public override positionToBidIds;
  /// @inheritdoc IPawnShop
  mapping(uint => uint) public override lastAuctionBidTs;
  //endregion ------------------------ Auction

  //region ------------------------ Constructor

  constructor(
    address _owner,
    address _depositToken,
    uint _positionDepositAmount,
    address _feeRecipient
  ) {
    if (_owner == address(0)) revert IAppErrors.PawnShopZeroOwner();
    if (_feeRecipient == address(0)) revert IAppErrors.PawnShopZeroFeeRecipient();
    owner = _owner;
    feeRecipient = _feeRecipient;
    positionDepositToken = _depositToken;
    createdTs = block.timestamp;
    createdBlock = block.number;
    positionDepositAmount = _positionDepositAmount;
  }
  //endregion ------------------------ Constructor

  //region ------------------------ Restrictions
  modifier onlyOwner() {
    if (_msgSender() != owner) revert IAppErrors.PawnShopNotOwner();
    _;
  }

  /// @dev Check time lock for governance actions and revert if conditions wrong
  modifier checkTimeLock(GovernanceAction action, address _address, uint _uint){
    TimeLock memory timeLock = timeLocks[action];
    if (timeLock.time == 0 || timeLock.time >= block.timestamp) revert IAppErrors.PawnShopTimeLock();
    if (_address != address(0)) {
      if (timeLock.addressValue != _address) revert IAppErrors.PawnShopWrongAddressValue();
    }
    if (_uint != 0) {
      if (timeLock.uintValue != _uint) revert IAppErrors.PawnShopWrongUintValue();
    }
    _;
    delete timeLocks[action];
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ User actions

  /// @inheritdoc IPawnShop
  function openPosition(
    address _collateralToken,
    uint _collateralAmount,
    uint _collateralTokenId,
    address _acquiredToken,
    uint _acquiredAmount,
    uint _posDurationBlocks,
    uint _posFee,
    uint minAuctionAmount
  ) external nonReentrant override returns (uint){
    if (_posFee > DENOMINATOR * 10) revert IAppErrors.PawnShopPosFeeAbsurdlyHigh();
    if (_posDurationBlocks == 0 && _posFee != 0) revert IAppErrors.PawnShopPosFeeForInstantDealForbidden();
    if (_collateralAmount == 0 && _collateralTokenId == 0) revert IAppErrors.PawnShopWrongAmounts();
    if (_collateralToken == address(0)) revert IAppErrors.PawnShopZeroCToken();
    if (_acquiredToken == address(0)) revert IAppErrors.PawnShopZeroAToken();

    AssetType assetType = _getAssetType(_collateralToken);
    if (
      (!(assetType == AssetType.ERC20 && _collateralAmount != 0 && _collateralTokenId == 0))
      && (!(assetType == AssetType.ERC721 && _collateralAmount == 0 && _collateralTokenId != 0))
    ) revert IAppErrors.PawnShopIncorrect();

    Position memory pos;
    {
      PositionInfo memory info = PositionInfo(
        _posDurationBlocks,
        _posFee,
        block.number,
        block.timestamp
      );

      PositionCollateral memory collateral = PositionCollateral(
        _collateralToken,
        assetType,
        _collateralAmount,
        _collateralTokenId
      );

      PositionAcquired memory acquired = PositionAcquired(
        _acquiredToken,
        _acquiredAmount
      );

      PositionExecution memory execution = PositionExecution(
        address(0),
        0,
        0,
        0
      );

      pos = Position(
        positionCounter, // id
        _msgSender(), // borrower
        positionDepositToken,
        positionDepositAmount,
        true, // open
        minAuctionAmount,
        info,
        collateral,
        acquired,
        execution
      );
    }

    openPositions.push(pos.id);
    posIndexes[IndexType.LIST][pos.id] = openPositions.length - 1;

    positionsByCollateral[_collateralToken].push(pos.id);
    posIndexes[IndexType.BY_COLLATERAL][pos.id] = positionsByCollateral[_collateralToken].length - 1;

    positionsByAcquired[_acquiredToken].push(pos.id);
    posIndexes[IndexType.BY_ACQUIRED][pos.id] = positionsByAcquired[_acquiredToken].length - 1;

    borrowerPositions[_msgSender()].push(pos.id);
    posIndexes[IndexType.BORROWER_POSITION][pos.id] = borrowerPositions[_msgSender()].length - 1;

    positions[pos.id] = pos;
    positionCounter++;

    _takeDeposit(pos.id);
    _transferCollateral(pos.collateral, _msgSender(), address(this));
    emit PositionOpened(
      _msgSender(),
      pos.id,
      _collateralToken,
      _collateralAmount,
      _collateralTokenId,
      _acquiredToken,
      _acquiredAmount,
      _posDurationBlocks,
      _posFee
    );
    return pos.id;
  }

  /// @inheritdoc IPawnShop
  function closePosition(uint id) external nonReentrant override {
    Position storage pos = positions[id];
    if (pos.id != id) revert IAppErrors.PawnShopWrongId();
    if (pos.borrower != _msgSender()) revert IAppErrors.PawnShopNotBorrower();
    if (pos.execution.lender != address(0)) revert IAppErrors.PawnShopPositionExecuted();
    if (!pos.open) revert IAppErrors.PawnShopPositionClosed();

    _removePosFromIndexes(pos);
    removeIndexed(borrowerPositions[pos.borrower], posIndexes[IndexType.BORROWER_POSITION], pos.id);

    _transferCollateral(pos.collateral, address(this), pos.borrower);
    _returnDeposit(id);
    pos.open = false;
    emit PositionClosed(_msgSender(), id);
  }

  /// @inheritdoc IPawnShop
  function bid(uint id, uint amount) external nonReentrant override {
    Position storage pos = positions[id];
    if (pos.id != id) revert IAppErrors.PawnShopWrongId();
    if (!pos.open) revert IAppErrors.PawnShopPositionClosed();
    if (pos.execution.lender != address(0)) revert IAppErrors.PawnShopPositionExecuted();
    if (pos.acquired.acquiredAmount != 0) {
      if (amount != pos.acquired.acquiredAmount) revert IAppErrors.PawnShopWrongBidAmount();
      _executeBid(pos, 0, amount, _msgSender(), _msgSender());
    } else {
      _auctionBid(pos, amount, _msgSender());
    }
  }

  /// @inheritdoc IPawnShop
  function claim(uint id) external nonReentrant override {
    Position storage pos = positions[id];
    if (pos.id != id) revert IAppErrors.PawnShopWrongId();
    if (pos.execution.lender != _msgSender()) revert IAppErrors.PawnShopNotLender();
    uint posEnd = pos.execution.posStartBlock + pos.info.posDurationBlocks;
    if (posEnd >= block.number) revert IAppErrors.PawnShopTooEarlyToClaim();
    if (!pos.open) revert IAppErrors.PawnShopPositionClosed();

    _endPosition(pos);
    _transferCollateral(pos.collateral, address(this), _msgSender());
    _returnDeposit(id);
    emit PositionClaimed(_msgSender(), id);
  }

  /// @inheritdoc IPawnShop
  function redeem(uint id) external nonReentrant override {
    Position storage pos = positions[id];
    if (pos.id != id) revert IAppErrors.PawnShopWrongId();
    if (pos.borrower != _msgSender()) revert IAppErrors.PawnShopNotBorrower();
    if (pos.execution.lender == address(0)) revert IAppErrors.PawnShopPositionNotExecuted();
    if (!pos.open) revert IAppErrors.PawnShopPositionClosed();

    _endPosition(pos);
    uint toSend = _toRedeem(id);
    IERC20(pos.acquired.acquiredToken).transferFrom(_msgSender(), pos.execution.lender, toSend);
    _transferCollateral(pos.collateral, address(this), _msgSender());
    _returnDeposit(id);
    emit PositionRedeemed(_msgSender(), id);
  }

  /// @inheritdoc IPawnShop
  function acceptAuctionBid(uint posId) external nonReentrant override {
    if (lastAuctionBidTs[posId] + AUCTION_DURATION >= block.timestamp) revert IAppErrors.PawnShopAuctionNotEnded();
    if (positionToBidIds[posId].length == 0) revert IAppErrors.PawnShopNoBids();
    uint bidId = positionToBidIds[posId][positionToBidIds[posId].length - 1];

    AuctionBid storage _bid = auctionBids[bidId];
    if (_bid.id == 0) revert IAppErrors.PawnShopAuctionBidNotFound();
    if (!_bid.open) revert IAppErrors.PawnShopBidClosed();
    if (_bid.posId != posId) revert IAppErrors.PawnShopWrongBid();

    Position storage pos = positions[posId];
    if (pos.borrower != _msgSender()) revert IAppErrors.PawnShopNotBorrower();
    if (!pos.open) revert IAppErrors.PawnShopPositionClosed();

    pos.acquired.acquiredAmount = _bid.amount;
    _executeBid(pos, bidId, _bid.amount, address(this), _bid.lender);
    lenderOpenBids[_bid.lender][pos.id] = 0;
    _bid.open = false;
    emit AuctionBidAccepted(_msgSender(), posId, _bid.id);
  }

  /// @inheritdoc IPawnShop
  function closeAuctionBid(uint bidId) external nonReentrant override {
    AuctionBid storage _bid = auctionBids[bidId];
    address lender = _bid.lender;

    if (_bid.id == 0) revert IAppErrors.PawnShopBidNotFound();
    if (!_bid.open) revert IAppErrors.PawnShopBidClosed();
    if (lender != _msgSender()) revert IAppErrors.PawnShopNotLender();
    Position storage pos = positions[_bid.posId];

    uint _lastAuctionBidTs = lastAuctionBidTs[pos.id];
    bool isAuctionEnded = _lastAuctionBidTs + AUCTION_DURATION < block.timestamp;
    // in case if auction is not accepted during 2 weeks lender can close the bid
    bool isAuctionOverdue = _lastAuctionBidTs + AUCTION_DURATION + 2 weeks < block.timestamp;
    bool isLastBid = false;
    if (positionToBidIds[pos.id].length != 0) {
      uint lastBidId = positionToBidIds[pos.id][positionToBidIds[pos.id].length - 1];
      isLastBid = lastBidId == bidId;
    }
    if (!((isLastBid && isAuctionEnded) || !isLastBid || !pos.open || isAuctionOverdue)) revert IAppErrors.PawnShopAuctionNotEnded();

    lenderOpenBids[lender][pos.id] = 0;
    _bid.open = false;
    IERC20(pos.acquired.acquiredToken).transfer(lender, _bid.amount);
    emit AuctionBidClosed(pos.id, bidId);
  }
  //endregion ------------------------ User actions

  //region ------------------------ Internal functions

  /// @dev Transfer to this contract a deposit
  function _takeDeposit(uint posId) internal {
    Position storage pos = positions[posId];
    if (pos.depositToken != address(0)) {
      IERC20(pos.depositToken).transferFrom(pos.borrower, address(this), pos.depositAmount);
    }
  }

  /// @dev Return to borrower a deposit
  function _returnDeposit(uint posId) internal {
    Position storage pos = positions[posId];
    if (pos.depositToken != address(0)) {
      IERC20(pos.depositToken).transfer(pos.borrower, pos.depositAmount);
    }
  }

  /// @dev Execute bid for the open position
  ///      Transfer acquired tokens to borrower
  ///      In case of instant deal transfer collateral to lender
  function _executeBid(
    Position storage pos,
    uint bidId,
    uint amount,
    address acquiredMoneyHolder,
    address lender
  ) internal {
    uint feeAmount = amount * platformFee / DENOMINATOR;
    uint toSend = amount - feeAmount;
    if (acquiredMoneyHolder == address(this)) {
      IERC20(pos.acquired.acquiredToken).transfer(pos.borrower, toSend);
    } else {
      IERC20(pos.acquired.acquiredToken).transferFrom(acquiredMoneyHolder, pos.borrower, toSend);
      IERC20(pos.acquired.acquiredToken).transferFrom(acquiredMoneyHolder, address(this), feeAmount);
    }
    _transferFee(pos.acquired.acquiredToken, feeAmount);

    pos.execution.lender = lender;
    pos.execution.posStartBlock = block.number;
    pos.execution.posStartTs = block.timestamp;
    _removePosFromIndexes(pos);

    lenderPositions[lender].push(pos.id);
    posIndexes[IndexType.LENDER_POSITION][pos.id] = lenderPositions[lender].length - 1;

    // instant buy
    if (pos.info.posDurationBlocks == 0) {
      _transferCollateral(pos.collateral, address(this), lender);
      _returnDeposit(pos.id); // fix for SCB-1029
      _endPosition(pos);
    }
    emit BidExecuted(pos.id, bidId, amount, acquiredMoneyHolder, lender);
  }

  /// @dev Open an auction bid
  ///      Transfer acquired token to this contract
  function _auctionBid(Position storage pos, uint amount, address lender) internal {
    if (lenderOpenBids[lender][pos.id] != 0) revert IAppErrors.PawnShopBidAlreadyExists();
    if (amount < pos.minAuctionAmount) revert IAppErrors.PawnShopTooLowBid();

    if (positionToBidIds[pos.id].length != 0) {
      // if we have bids need to check auction duration
      if (lastAuctionBidTs[pos.id] + AUCTION_DURATION <= block.timestamp) revert IAppErrors.PawnShopAuctionEnded();

      uint lastBidId = positionToBidIds[pos.id][positionToBidIds[pos.id].length - 1];
      AuctionBid storage lastBid = auctionBids[lastBidId];
      if (lastBid.amount * 110 / 100 >= amount) revert IAppErrors.PawnShopNewBidTooLow();
    }

    AuctionBid memory _bid = AuctionBid(
      auctionBidCounter,
      pos.id,
      lender,
      amount,
      true
    );

    positionToBidIds[pos.id].push(_bid.id);
    // write index + 1 for keep zero as empty value
    lenderOpenBids[lender][pos.id] = positionToBidIds[pos.id].length;

    IERC20(pos.acquired.acquiredToken).transferFrom(_msgSender(), address(this), amount);

    lastAuctionBidTs[pos.id] = block.timestamp;
    auctionBids[_bid.id] = _bid;
    auctionBidCounter++;
    emit AuctionBidOpened(pos.id, _bid.id, amount, lender);
  }

  /// @dev Finalize position. Remove position from indexes
  function _endPosition(Position storage pos) internal {
    if (pos.execution.posEndTs != 0) revert IAppErrors.PawnShopAlreadyClaimed();
    pos.open = false;
    pos.execution.posEndTs = block.timestamp;
    removeIndexed(borrowerPositions[pos.borrower], posIndexes[IndexType.BORROWER_POSITION], pos.id);
    if (pos.execution.lender != address(0)) {
      removeIndexed(lenderPositions[pos.execution.lender], posIndexes[IndexType.LENDER_POSITION], pos.id);
    }

  }

  /// @dev Transfer collateral from sender to recipient
  function _transferCollateral(PositionCollateral memory _collateral, address _sender, address _recipient) internal {
    if (_collateral.collateralType == AssetType.ERC20) {
      if (_sender == address(this)) {
        IERC20(_collateral.collateralToken).transfer(_recipient, _collateral.collateralAmount);
      } else {
        IERC20(_collateral.collateralToken).transferFrom(_sender, _recipient, _collateral.collateralAmount);
      }
    } else if (_collateral.collateralType == AssetType.ERC721) {
      IERC721(_collateral.collateralToken).transferFrom(_sender, _recipient, _collateral.collateralTokenId);
    } else {
      revert("TPS: Wrong asset type");
    }
  }

  /// @dev Transfer fee to platform. Assume that token inside this contract
  ///      Do buyback if possible, otherwise just send to controller for manual handling
  function _transferFee(address token, uint amount) internal {
    // little deals can have zero fees
    if (amount == 0) {
      return;
    }
    IERC20(token).transfer(feeRecipient, amount);
  }

  /// @dev Remove position from common indexes
  function _removePosFromIndexes(Position memory _pos) internal {
    removeIndexed(openPositions, posIndexes[IndexType.LIST], _pos.id);
    removeIndexed(positionsByCollateral[_pos.collateral.collateralToken], posIndexes[IndexType.BY_COLLATERAL], _pos.id);
    removeIndexed(positionsByAcquired[_pos.acquired.acquiredToken], posIndexes[IndexType.BY_ACQUIRED], _pos.id);
  }
  //endregion ------------------------ Internal functions

  //region ------------------------ Views

  /// @inheritdoc IPawnShop
  function toRedeem(uint id) external view override returns (uint){
    return _toRedeem(id);
  }

  function _toRedeem(uint id) private view returns (uint){
    Position memory pos = positions[id];
    return pos.acquired.acquiredAmount +
    (pos.acquired.acquiredAmount * pos.info.posFee / DENOMINATOR);
  }

  /// @inheritdoc IPawnShop
  function getAssetType(address _token) external view override returns (AssetType){
    return _getAssetType(_token);
  }

  function _getAssetType(address _token) private view returns (AssetType){
    if (_isERC721(_token)) {
      return AssetType.ERC721;
    } else if (_isERC20(_token)) {
      return AssetType.ERC20;
    } else {
      revert("TPS: Unknown asset");
    }
  }

  /// @dev Return true if given token is ERC721 token
  function isERC721(address _token) external view override returns (bool) {
    return _isERC721(_token);
  }

  //noinspection NoReturn
  function _isERC721(address _token) private view returns (bool) {
    //slither-disable-next-line unused-return,variable-scope,uninitialized-local
    try IERC721(_token).supportsInterface{gas: 30000}(type(IERC721).interfaceId) returns (bool result){
      return result;
    } catch {
      return false;
    }
  }

  /// @dev Return true if given token is ERC20 token
  function isERC20(address _token) external view override returns (bool) {
    return _isERC20(_token);
  }

  //noinspection NoReturn
  function _isERC20(address _token) private view returns (bool) {
    //slither-disable-next-line unused-return,variable-scope,uninitialized-local
    try IERC20(_token).totalSupply{gas: 30000}() returns (uint){
      return true;
    } catch {
      return false;
    }
  }

  /// @inheritdoc IPawnShop
  function openPositionsSize() external view override returns (uint) {
    return openPositions.length;
  }

  /// @inheritdoc IPawnShop
  function auctionBidSize(uint posId) external view override returns (uint) {
    return positionToBidIds[posId].length;
  }

  function positionsByCollateralSize(address collateral) external view override returns (uint) {
    return positionsByCollateral[collateral].length;
  }

  function positionsByAcquiredSize(address acquiredToken) external view override returns (uint) {
    return positionsByAcquired[acquiredToken].length;
  }

  function borrowerPositionsSize(address borrower) external view override returns (uint) {
    return borrowerPositions[borrower].length;
  }

  function lenderPositionsSize(address lender) external view override returns (uint) {
    return lenderPositions[lender].length;
  }

  /// @inheritdoc IPawnShop
  function getPosition(uint posId) external view override returns (Position memory) {
    return positions[posId];
  }

  /// @inheritdoc IPawnShop
  function getAuctionBid(uint bidId) external view override returns (AuctionBid memory) {
    return auctionBids[bidId];
  }
  //endregion ------------------------ Views

  //region ------------------------ Governance actions

  /// @inheritdoc IPawnShop
  function announceGovernanceAction(
    GovernanceAction id,
    address addressValue,
    uint uintValue
  ) external onlyOwner override {
    if (timeLocks[id].time != 0) revert IAppErrors.PawnShopAlreadyAnnounced();
    timeLocks[id] = TimeLock(
      block.timestamp + TIME_LOCK,
      addressValue,
      uintValue
    );
    emit GovernanceActionAnnounced(uint(id), addressValue, uintValue);
  }

  /// @inheritdoc IPawnShop
  function setOwner(address _newOwner) external onlyOwner override
  checkTimeLock(GovernanceAction.ChangeOwner, _newOwner, 0) {
    if (_newOwner == address(0)) revert IAppErrors.PawnShopZeroAddress();
    emit OwnerChanged(owner, _newOwner);
    owner = _newOwner;
  }

  /// @inheritdoc IPawnShop
  function setFeeRecipient(address _newFeeRecipient) external onlyOwner override
  checkTimeLock(GovernanceAction.ChangeFeeRecipient, _newFeeRecipient, 0) {
    if (_newFeeRecipient == address(0)) revert IAppErrors.PawnShopZeroAddress();
    emit FeeRecipientChanged(feeRecipient, _newFeeRecipient);
    feeRecipient = _newFeeRecipient;
  }

  /// @inheritdoc IPawnShop
  function setPlatformFee(uint _value) external onlyOwner override
  checkTimeLock(GovernanceAction.ChangePlatformFee, address(0), _value) {
    if (_value > PLATFORM_FEE_MAX) revert IAppErrors.PawnShopTooHighValue();
    emit PlatformFeeChanged(platformFee, _value);
    platformFee = _value;
  }

  /// @inheritdoc IPawnShop
  function setPositionDepositAmount(uint _value) external onlyOwner override
  checkTimeLock(GovernanceAction.ChangePositionDepositAmount, address(0), _value) {
    emit DepositAmountChanged(positionDepositAmount, _value);
    positionDepositAmount = _value;
  }

  /// @inheritdoc IPawnShop
  function setPositionDepositToken(address _value) external onlyOwner override
  checkTimeLock(GovernanceAction.ChangePositionDepositToken, _value, 0) {
    emit DepositTokenChanged(positionDepositToken, _value);
    positionDepositToken = _value;
  }

  /// @dev Delegate snapshot votes to another address
  function delegateVotes(address _delegateContract,bytes32 _id, address _delegate) external onlyOwner {
    IDelegation(_delegateContract).setDelegate(_id, _delegate);
  }

  /// @dev Remove delegated votes.
  function clearDelegatedVotes(address _delegateContract, bytes32 _id) external onlyOwner {
    IDelegation(_delegateContract).clearDelegate(_id);
  }
  //endregion ------------------------ Governance actions

  //region ------------------------ ArrayLib
  /// @dev Remove from array the item with given id and move the last item on it place
  ///      Use with mapping for keeping indexes in correct ordering
  function removeIndexed(
    uint256[] storage array,
    mapping(uint256 => uint256) storage indexes,
    uint256 id
  ) internal {
    AppLib.removeIndexed(array, indexes, id);
  }
  //endregion ------------------------ ArrayLib
}
