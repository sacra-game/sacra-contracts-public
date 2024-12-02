// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IShelterController.sol";
import "../interfaces/IShelterController.sol";
import "../interfaces/IUserController.sol";
import "../lib/StringLib.sol";
import "../token/GuildBank.sol";
import "./StatLib.sol";
import "../interfaces/IShelterAuction.sol";

library ShelterLib {
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.UintSet;

  //region ------------------------ Constants
  /// @dev keccak256(abi.encode(uint256(keccak256("shelter.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant SHELTER_CONTROLLER_STORAGE_LOCATION = 0x5a293071b39954a4fcf98ae7184af7c6201e972e15842b884f1ad071e9bded00; // shelter.controller.main

  uint8 internal constant MIN_SHELTER_LEVEL = 1;
  uint8 internal constant MAX_SHELTER_LEVEL = 3;
  //endregion ------------------------ Constants

  //region ------------------------ Restrictions
  function _onlyDeployer(IController controller) internal view {
    if (!controller.isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }

  function _onlyGuildController(address guildController) internal view {
    if (msg.sender != guildController) revert IAppErrors.ErrorNotGuildController();
  }

  function _notPaused(IController controller) internal view {
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Storage

  function _S() internal pure returns (IShelterController.MainState storage s) {
    assembly {
      s.slot := SHELTER_CONTROLLER_STORAGE_LOCATION
    }
    return s;
  }
  //endregion ------------------------ Storage

  //region ------------------------ Shelter view
  /// @notice Get list of all registered shelters in the given {biome}
  function getShelters(uint8 biome) internal view returns (uint[] memory shelterIds) {
    return _S().shelters[biome].values();
  }

  /// @notice Get initial price of the given shelter. The price is used if the shelter doesn't belong to any guild
  function getShelterPrice(uint shelterId) internal view returns (uint price) {
    return _S().shelterPrices[shelterId];
  }

  /// @notice Get shelter which belongs to the given guild
  function guildToShelter(uint guildId) internal view returns (uint shelterId) {
    return _S().guildToShelter[guildId];
  }

  /// @notice Get guild to which the given shelter belongs
  function shelterToGuild(uint shelterId) internal view returns (uint guildId) {
    return _S().shelterToGuild[shelterId];
  }

  /// @notice Get shelter of the guild to which the user belongs
  function getShelterId(IGuildController guildController, address user) internal view returns (uint shelterId) {
    uint guildId = guildController.memberOf(user);
    return guildId == 0
      ? 0
      : _S().guildToShelter[guildId];
  }

  /// @notice List of items that can be bought in the shelter of the given level in the given biome
  function getShelterItems(uint shelterId) internal view returns (address[] memory items) {
    return _S().shelterItems[shelterId].values();
  }

  function getShelterItemData(uint shelterId, address item) internal view returns (
    uint64 priceInPvpPoints,
    uint128 priceInGameToken,
    uint16 maxItemsPerDayLimit
  ) {
    IShelterController.ShelterItemData memory data = _S().shelterItemData[shelterId][item];
    return (
      data.priceInPvpPoints,
      data.priceInGameToken,
      data.maxItemsPerDayLimit
    );
  }

  /// @notice How many {item} instances were purchased per {epochDay} in the given {shelterId}
  /// @param epochDay TimestampInSeconds / 24 * 60 * 60
  function getCountPurchasedItems(address item, uint shelterId, uint32 epochDay) internal view returns (uint) {
    return _S().countPurchasedItems[shelterId][epochDay][item];
  }

  //endregion ------------------------ Shelter view

  //region ------------------------ Shelter config
  /// @notice Register new shelter or overwrite exist. Only registered shelters can be purchased.
  /// @param shelterId ID should be generated using {PackingLib.packShelterId}
  /// @param price Initial shelter price in game tokens
  function setShelter(IController controller, uint shelterId, uint price) internal {
    ShelterLib._onlyDeployer(controller);

    (uint8 biome, uint8 shelterLevel, ) = PackingLib.unpackShelterId(shelterId);

    if (biome == 0 || biome > StatLib.MAX_POSSIBLE_BIOME) revert IAppErrors.ErrorIncorrectBiome(biome);
    if (price == 0) revert IAppErrors.ZeroValueNotAllowed();
    if (shelterLevel < MIN_SHELTER_LEVEL || shelterLevel > MAX_SHELTER_LEVEL) revert IAppErrors.IncorrectShelterLevel(shelterLevel);

    _S().shelterPrices[shelterId] = price;
    _S().shelters[biome].add(shelterId);

    emit IApplicationEvents.RegisterShelter(shelterId, price);
  }

  /// @notice Set items that can be purchases in the given shelter: remove previously stored items, add new items.
  /// @param shelterId ID should be generated using {PackingLib.packShelterId}
  /// @param items List of item tokens
  /// @param pricesInPvpPoints Prices in pvp-points. The points are taken from guild balance at the moment of purchasing
  /// @param pricesInGameTokens Additional prices in game tokens. Can contain zeros.
  /// @param maxItemsPerDayLimits Indicate how many item instances the users can purchase per day. 0 - no limitations
  function setShelterItems(
    IController controller,
    uint shelterId,
    address[] memory items,
    uint64[] memory pricesInPvpPoints,
    uint128[] memory pricesInGameTokens,
    uint16[] memory maxItemsPerDayLimits
  ) internal {
    ShelterLib._onlyDeployer(controller);

    uint len = items.length;
    if (len != pricesInPvpPoints.length || len != pricesInGameTokens.length || len != maxItemsPerDayLimits.length) {
      revert IAppErrors.LengthsMismatch();
    }

    EnumerableSet.AddressSet storage set = _S().shelterItems[shelterId];

    // remove previously stored items
    address[] memory prevItems = set.values();
    uint prevItemsLen = prevItems.length;
    for (uint i; i < prevItemsLen; ++i) {
      set.remove(prevItems[i]);
      delete _S().shelterItemData[shelterId][prevItems[i]];
    }

    // add new items
    for (uint i; i < len; ++i) {
      set.add(items[i]);
      if (pricesInPvpPoints[i] == 0 && pricesInGameTokens[i] == 0) revert IAppErrors.FreeShelterItemsAreNotAllowed(shelterId, items[i]);
      _S().shelterItemData[shelterId][items[i]] = IShelterController.ShelterItemData({
        priceInPvpPoints: pricesInPvpPoints[i],
        priceInGameToken: pricesInGameTokens[i],
        maxItemsPerDayLimit: maxItemsPerDayLimits[i]
      });
    }

    emit IApplicationEvents.SetShelterItems(shelterId, items, pricesInPvpPoints, pricesInGameTokens, maxItemsPerDayLimits);
  }
  //endregion ------------------------ Shelter config

  //region ------------------------ Shelter actions

  /// @notice Guild buys a shelter that doesn't belong to any guild. It pays default prices and changes owner of the shelter.
  function buyShelter(IController controller, address msgSender, uint shelterId) internal {
    _notPaused(controller);

    IGuildController guildController = IGuildController(controller.guildController());
    (uint guildId,) = guildController.checkPermissions(msgSender, uint(IGuildController.GuildRightBits.CHANGE_SHELTER_3));

    // only registered shelter can be purchased
    (uint8 biome, , ) = PackingLib.unpackShelterId(shelterId);
    if (!_S().shelters[biome].contains(shelterId)) revert IAppErrors.ShelterIsNotRegistered();

    // Each guild is able to have only 1 shelter. Exist shelter should be sold or left
    if (_S().guildToShelter[guildId] != 0) revert IAppErrors.GuildAlreadyHasShelter();
    if (_S().shelterToGuild[shelterId] != 0) revert IAppErrors.ShelterIsBusy();

    { // Shelter can be bought only if there is no auction bid
      address shelterAuction = guildController.shelterAuctionController();
      if (shelterAuction != address(0)) {
        (uint positionId,) = IShelterAuction(shelterAuction).positionByBuyer(guildId);
        if (positionId != 0) revert IAppErrors.AuctionBidOpened(positionId);
      }
    }

    // pay for the shelter from the guild bank
    uint shelterPrice = getShelterPrice(shelterId);
    guildController.payFromGuildBank(guildId, shelterPrice);

    // register ownership
    _S().guildToShelter[guildId] = shelterId;
    _S().shelterToGuild[shelterId] = guildId;

    emit IApplicationEvents.BuyShelter(guildId, shelterId);
  }

  /// @notice Guild leaves the shelter. The shelter becomes free, it can be bought by any guild by default price
  function leaveShelter(IController controller, address msgSender, uint shelterId) internal {
    _notPaused(controller);

    IGuildController guildController = IGuildController(controller.guildController());
    (uint guildId,) = guildController.checkPermissions(msgSender, uint(IGuildController.GuildRightBits.CHANGE_SHELTER_3));

    if (_S().guildToShelter[guildId] != shelterId) revert IAppErrors.ShelterIsNotOwnedByTheGuild();
    if (shelterId == 0) revert IAppErrors.GuildHasNoShelter();

    { // Shelter can be sold only if there is no opened auction position
      address shelterAuction = guildController.shelterAuctionController();
      if (shelterAuction != address(0)) {
        uint positionId = IShelterAuction(shelterAuction).positionBySeller(guildId);
        if (positionId != 0) revert IAppErrors.AuctionPositionOpened(positionId);
      }
    }

    // unregister ownership
    delete _S().guildToShelter[guildId];
    delete _S().shelterToGuild[shelterId];

    emit IApplicationEvents.LeaveShelter(guildId, shelterId);
  }

  /// @notice Purchase the {item} in the shelter that belongs to the guild to which {msgSender} belongs
  function purchaseShelterItem(IController controller, address msgSender, address item, uint blockTimestamp) internal {
    _notPaused(controller);

    IGuildController guildController = IGuildController(controller.guildController());
    // no permission are required - any guild member is able to purchase shelter item
    // but the member should either be owner or should have enough pvp-points capacity, see restriction below
    uint guildId = _getValidGuildId(guildController, msgSender);

    uint shelterId = _S().guildToShelter[guildId];
    if (shelterId == 0) revert IAppErrors.GuildHasNoShelter();

    if (! _S().shelterItems[shelterId].contains(item)) revert IAppErrors.ShelterHasNotItem(shelterId, item);

    // total number of the item instances that can be minted per day CAN BE limited
    IShelterController.ShelterItemData memory itemData = _S().shelterItemData[shelterId][item];
    uint numSoldItems;
    {
      uint32 epochDay = uint32(blockTimestamp / 86400);

      mapping(address => uint) storage countPurchasedItems = _S().countPurchasedItems[shelterId][epochDay];
      numSoldItems = countPurchasedItems[item];

      if (itemData.maxItemsPerDayLimit != 0) {
        if (numSoldItems >= itemData.maxItemsPerDayLimit) revert IAppErrors.MaxNumberItemsSoldToday(numSoldItems, itemData.maxItemsPerDayLimit);
      }
      countPurchasedItems[item] = numSoldItems + 1;
    }

    // user pays for the item by pvp-points and/or by game token (it depends on the item settings)
    if (itemData.priceInPvpPoints != 0) {
      guildController.usePvpPoints(guildId, msgSender, itemData.priceInPvpPoints);
    }

    if (itemData.priceInGameToken != 0) {
      guildController.payFromBalance(itemData.priceInGameToken, msgSender);
      //_process(controller, itemData.priceInGameToken, msgSender);
    }

    // mint the item
    IItemController(controller.itemController()).mint(item, msgSender);

    emit IApplicationEvents.PurchaseShelterItem(msgSender, item, numSoldItems + 1, itemData.priceInPvpPoints, itemData.priceInGameToken);
  }

  /// @notice clear necessary data to indicate that the guiles leaves the shelter
  function clearShelter(address guildController, uint guildId) internal {
    _onlyGuildController(guildController);

    uint shelterId = _S().guildToShelter[guildId];
    if (shelterId != 0) {
      // assume, that msgSender shouldn't have permission CHANGE_SHELTER_3 here

      // ensure that there is no open position for the shelter on auction
      address shelterAuction = IGuildController(guildController).shelterAuctionController();
      if (shelterAuction != address(0)) {
        uint positionId = IShelterAuction(shelterAuction).positionBySeller(guildId);
        if (positionId != 0) revert IAppErrors.AuctionPositionOpened(positionId);
      }

      delete _S().guildToShelter[guildId];
      delete _S().shelterToGuild[shelterId];

      emit IApplicationEvents.LeaveShelter(guildId, shelterId);
    }

  }
  //endregion ------------------------ Shelter actions

  //region ------------------------ Interaction with auctions
  function changeShelterOwner(IController controller, uint shelterId, uint newOwnerGuildId) internal {
    // we assume, that all checks are performed on ShelterAuction side, so we need min checks here
    address shelterAuction = IGuildController(controller.guildController()).shelterAuctionController();
    if (shelterAuction == address(0) || msg.sender != shelterAuction) revert IAppErrors.NotShelterAuction();

    uint prevGuildId = _S().shelterToGuild[shelterId];
    delete _S().guildToShelter[prevGuildId];
    _S().shelterToGuild[shelterId] = newOwnerGuildId;
    _S().guildToShelter[newOwnerGuildId] = shelterId;

    emit IApplicationEvents.ChangeShelterOwner(shelterId, prevGuildId, newOwnerGuildId);
  }

  //endregion ------------------------ Interaction with auctions

  //region ------------------------ Internal logic
  function _getValidGuildId(IGuildController guildController, address user) internal view returns (uint guildId) {
    guildId = guildController.memberOf(user);
    if (guildId == 0) revert IAppErrors.NotGuildMember();
  }
  //endregion ------------------------ Internal logic


}
