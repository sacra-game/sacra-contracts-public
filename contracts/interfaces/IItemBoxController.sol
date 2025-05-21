// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../openzeppelin/EnumerableSet.sol";
import "../openzeppelin/EnumerableMap.sol";

interface IItemBoxController {
  /// @custom:storage-location erc7201:ItemBox.controller.main
  struct MainState {
    mapping(bytes32 packedHero => HeroData) heroData;

    /// @notice Owners of all items minted in sandbox mode
    mapping(bytes32 packedItem => bytes32 packedHero) heroes;
  }

  struct HeroData {
    /// @notice Moment of upgrading sandbox-hero to normal-hero
    uint tsUpgraded;

    /// @notice List of all items registered for the hero
    EnumerableSet.AddressSet items;

    /// @notice item => (itemId => packedItemBoxItemInfo)
    /// @dev Ids are never deleted from the map, so the order of ids is never changed
    mapping(address item => EnumerableMap.UintToUintMap) states;
  }

  struct ItemBoxItemInfo {
    /// @notice True if the item was withdrawn from balance
    /// It can happens in follow cases:
    /// 1) the hero was upgraded and the item was withdrawn on hero owner balance
    /// 2) the item is used by ItemController:
    /// 2.1) the item is equipped on the hero and so it's transferred to the hero balance
    /// 2.2) the consumable item is used
    /// 3) the item is burnt
    /// @dev Status is required to avoid deletion (and so changing order) of the {items}
    bool withdrawn;

    /// @notice The moment of the initial item minting
    uint64 timestamp;
  }

  enum ItemState {
    /// @notice The item was never registered in the sandbox
    NOT_REGISTERED_0,
    /// @notice The item is not active (outdated) and cannot be used anymore
    NOT_AVAILABLE_1,
    /// @notice The item is active and located inside the sandbox
    INSIDE_2,
    /// @notice The item is either withdrawn or equipped
    OUTSIDE_3
  }

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  function firstActiveItemOfHeroByIndex(address hero, uint heroId, address item) external view returns (uint itemId);
  function registerItems(address hero, uint heroId, address[] memory items, uint[] memory itemIds, uint countValidItems) external;
  function itemState(address hero, uint heroId, address item, uint itemId) external view returns (IItemBoxController.ItemState);
  function itemHero(address item, uint itemId) external view returns (address hero, uint heroId);
  function registerSandboxUpgrade(bytes32 packedHero) external;
  function transferToHero(address hero, uint heroId, address item, uint itemId) external;
  function destroyItem(address item, uint itemId) external;
}
