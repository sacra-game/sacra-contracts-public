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

import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IShelterController.sol";
import "../lib/ShelterLib.sol";
import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";

contract ShelterController is Initializable, Controllable, ERC2771Context, IShelterController {
  //region ------------------------ CONSTANTS

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant override VERSION = "1.0.0";
  //endregion ------------------------ CONSTANTS

  //region ------------------------ INITIALIZER

  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ INITIALIZER

  //region ------------------------ Shelter view
  /// @notice Get list of all registered shelters in the given {biome}
  function getShelters(uint8 biome) external view returns (uint[] memory shelterIds) {
    return ShelterLib.getShelters(biome);
  }

  /// @notice Get initial price of the given shelter. The price is used if the shelter doesn't belong to any guild
  function getShelterPrice(uint shelterId) external view returns (uint price) {
    return ShelterLib.getShelterPrice(shelterId);
  }

  /// @notice Get shelter which belongs to the given guild
  function guildToShelter(uint guildId) external view returns (uint shelterId) {
    return ShelterLib.guildToShelter(guildId);
  }

  /// @notice Get guild to which the given shelter belongs
  function shelterToGuild(uint shelterId) external view returns (uint guildId) {
    return ShelterLib.shelterToGuild(shelterId);
  }

  /// @notice Get shelter of the guild to which the user belongs
  function getShelterId(address user) external view returns (uint shelterId) {
    return ShelterLib.getShelterId(
      IGuildController(IController(controller()).guildController()),
      user
    );
  }

  /// @notice List of items that can be bought in the shelter of the given level in the given biome
  /// (valid only for shelter levels that have any restrictions)
  function getShelterItems(uint shelterId) external view returns (address[] memory items) {
    return ShelterLib.getShelterItems(shelterId);
  }

  /// @notice Get data of the {item} registered for purchasing in the given shelter.
  /// @return priceInPvpPoints Price of the item in pvp-points
  /// @return priceInGameToken Price of the item game token
  /// @return maxItemsPerDayLimit Max number of items that can be purchases per day in the shelter. 0 - no limitations
  function getShelterItemData(uint shelterId, address item) external view returns (
    uint64 priceInPvpPoints,
    uint128 priceInGameToken,
    uint16 maxItemsPerDayLimit
  ) {
    return ShelterLib.getShelterItemData(shelterId, item);
  }

  function getCountPurchasedItems(address item, uint shelterId, uint32 epochDay) external view returns (uint) {
    return ShelterLib.getCountPurchasedItems(item, shelterId, epochDay);
  }

  //endregion ------------------------ Shelter view

  //region ------------------------ Shelter config
  /// @notice Register new or update exist shelter. Only registered shelters can be purchased.
  /// @param shelterId ID generated using PackingLib.packShelterId
  /// @param price Initial price of the shelter in game tokens. It's used to purchase the shelter if it doesn't belong to any guild
  function setShelter(uint shelterId, uint price) external {
    ShelterLib.setShelter(IController(controller()), shelterId, price);
  }

  function setShelterItems(
    uint shelterId,
    address[] memory items,
    uint64[] memory pricesInPvpPoints,
    uint128[] memory pricesInGameTokens,
    uint16[] memory maxItemsPerDayLimits
  ) external {
    ShelterLib.setShelterItems(IController(controller()), shelterId, items, pricesInPvpPoints, pricesInGameTokens, maxItemsPerDayLimits);
  }

  //endregion ------------------------ Shelter config

  //region ------------------------ Shelter actions

  /// @notice Guild buys a shelter that doesn't belong to any guild. It pays default prices and changes owner of the shelter.
  function buyShelter(uint shelterId) external {
    ShelterLib.buyShelter(IController(controller()), _msgSender(), shelterId);
  }

  /// @notice Guild leaves the shelter. The shelter becomes free, it can be bought by any guild by default price
  function leaveShelter(uint shelterId) external {
    ShelterLib.leaveShelter(IController(controller()), _msgSender(), shelterId);
  }

  /// @notice Purchase the {item} in the shelter that belongs to the guild to which message sender belongs
  function purchaseShelterItem(address item) external {
    ShelterLib.purchaseShelterItem(IController(controller()), _msgSender(), item, block.timestamp);
  }

  function clearShelter(uint guildId) external {
    ShelterLib.clearShelter(IController(controller()).guildController(), guildId);
  }
  //endregion ------------------------ Shelter actions

  //region ------------------------ Interaction with auctions
  function changeShelterOwner(uint shelterId, uint newOwnerGuildId) external {
    ShelterLib.changeShelterOwner(IController(controller()), shelterId, newOwnerGuildId);
  }
  //endregion ------------------------ Interaction with auctions
}