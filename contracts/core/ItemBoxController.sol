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
import "../lib/ItemBoxLib.sol";
import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";
import "../interfaces/IItemBoxController.sol";
import "../openzeppelin/ERC721Holder.sol";

contract ItemBoxController is Initializable, Controllable, ERC2771Context, ERC721Holder, IItemBoxController {
  //region ------------------------ Constants

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant override VERSION = "1.0.0";
  //endregion ------------------------ Constants

  //region ------------------------ Initializer

  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ Initializer

  //region ------------------------ View
  function firstActiveItemOfHeroByIndex(address hero, uint heroId, address item) external view returns (uint itemId) {
    return ItemBoxLib.firstActiveItemOfHeroByIndex(hero, heroId, item);
  }

  function getHeroRegisteredItems(address hero, uint heroId) external view returns (address[] memory items) {
    return ItemBoxLib.getHeroRegisteredItems(hero, heroId);
  }

  function getActiveItemIds(address hero, uint heroId, address item) external view returns (
    uint[] memory itemIds,
    bool[] memory toWithdraw,
    uint[] memory timestamps
  ) {
    return ItemBoxLib.getActiveItemIds(hero, heroId, item);
  }

  function itemState(address hero, uint heroId, address item, uint itemId) external view returns (
    IItemBoxController.ItemState
  ) {
    return ItemBoxLib.itemState(hero, heroId, item, itemId);
  }

  function getItemInfo(address hero, uint heroId, address item, uint itemId) external view returns (
    bool withdrawn,
    uint tsMinted
  ) {
    return ItemBoxLib.getItemInfo(hero, heroId, item, itemId);
  }

  function itemHero(address item, uint itemId) external view returns (address hero, uint heroId) {
    return ItemBoxLib.itemHero(item, itemId);
  }

  function upgradedAt(address hero, uint heroId) external view returns (uint timestamp) {
    return ItemBoxLib.upgradedAt(hero, heroId);
  }
  //endregion ------------------------ View

  //region ------------------------ Actions
  /// @param countValidItems Count of valid items in {items} and {itemIds}, it should be <= items.length
  function registerItems(address hero, uint heroId, address[] memory items, uint[] memory itemIds, uint countValidItems) external {
    ItemBoxLib.registerItems(IController(controller()), hero, heroId, items, itemIds, countValidItems);
  }

  /// @notice Transfer given items from ItemBox to the hero owner
  /// Use {getHeroItemByIndex} and check {toWithdraw} to detect what items can be withdrawn
  function withdrawActiveItems(address hero, uint heroId, address[] memory items, uint[] memory itemIds, address receiver) external {
    ItemBoxLib.withdrawActiveItems(IController(controller()), _msgSender(), hero, heroId, items, itemIds, receiver);
  }

  function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes memory data
  ) public virtual override returns (bytes4) {
    ItemBoxLib.onERC721ReceivedLogic(IController(controller()), operator, from, tokenId, data);
    return this.onERC721Received.selector;
  }

  /// @notice Transfer given {item} to the given {hero}.
  /// @param itemId The item must belong to the hero OR to the different hero of the same owner
  function transferToHero(address hero, uint heroId, address item, uint itemId) external {
    ItemBoxLib.transferToHero(IController(controller()), hero, heroId, item, itemId);
  }

  function destroyItem(address item, uint itemId) external {
    ItemBoxLib.destroyItem(IController(controller()), item, itemId);
  }

  function registerSandboxUpgrade(bytes32 packedHero) external {
    ItemBoxLib.registerSandboxUpgrade(IController(controller()), packedHero);
  }
  //endregion ------------------------ Actions
}