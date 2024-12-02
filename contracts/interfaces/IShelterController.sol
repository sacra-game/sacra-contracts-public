// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../openzeppelin/EnumerableSet.sol";

interface IShelterController {
  /// @custom:storage-location erc7201:shelter.controller.main
  struct MainState {
    /// @notice List of items allowed to be purchased in the shelter
    mapping(uint shelterId => EnumerableSet.AddressSet) shelterItems;

    /// @notice Data of items available for purchasing in the given shelter
    mapping(uint shelterId => mapping(address item => ShelterItemData)) shelterItemData;

    // @notice Statistics how much items were purchased per day
    mapping(uint shelterId => mapping(uint32 epochDay => mapping(address item => uint))) countPurchasedItems;

    /// @notice List of registered shelters in {biome}
    mapping(uint biome => EnumerableSet.UintSet shelterUids) shelters;

    /// @notice Initial price of the shelters in game tokens
    mapping(uint shelterId => uint) shelterPrices;

    /// @notice Shelters belong to a specific guild (not the player)
    /// Shelters can be free (don't belong to any guild)
    mapping(uint shelterId => uint guildId) shelterToGuild;

    /// @notice Each guild can own 0 or 1 shelter
    mapping(uint guildId => uint shelterId) guildToShelter;
  }

  struct ShelterItemData {
    /// @notice Price of the item in pvp-points
    uint64 priceInPvpPoints;
    /// @notice Price of the item game token
    uint128 priceInGameToken;
    /// @notice Max number of items that can be purchases per day in the shelter. 0 - no limitations
    uint16 maxItemsPerDayLimit;
  }

  /// ----------------------------------------------------------------------------------------------

  function clearShelter(uint guildId) external;
  function guildToShelter(uint guildId) external view returns (uint shelterId);
  function changeShelterOwner(uint shelterId, uint newOwnerGuildId) external;
  function shelterToGuild(uint shelterId) external view returns (uint guildId);
}