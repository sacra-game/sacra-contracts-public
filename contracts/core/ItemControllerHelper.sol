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

import "../interfaces/IItemControllerHelper.sol";
import "../lib/ItemControllerHelperLib.sol";
import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";

contract ItemControllerHelper is Controllable, ERC2771Context, IItemControllerHelper {
  using EnumerableSet for EnumerableSet.AddressSet;

  //region ------------------------ Constants

  /// @notice Version of the contract
  string public constant VERSION = "1.0.0";
  //endregion ------------------------ Constants

  //region ------------------------ Initializer
  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ Initializer

  //region ------------------------ Views
  function listUnionConfigsLength() external view returns (uint) {
    return ItemControllerHelperLib.listUnionConfigsLength();
  }

  function unionConfigIdByIndex(uint index) external view returns (uint) {
    return ItemControllerHelperLib.unionConfigIdByIndex(index);
  }

  function unionConfig(uint configId) external view returns (IItemControllerHelper.UnionConfig memory) {
    return ItemControllerHelperLib.unionConfig(configId);
  }

  function keyPassItem() external view returns (address) {
    return ItemControllerHelperLib.keyPassItem();
  }

  function getGlobalParamValue(uint8 globalParam) external view returns (uint) {
    return ItemControllerHelperLib.getGlobalParamValue(globalParam);
  }

  function getAugmentationProtectiveItem() external view returns (address) {
    return address(uint160(ItemControllerHelperLib.getGlobalParamValue(uint8(IItemControllerHelper.GlobalParam.AUGMENTATION_PROTECTIVE_ITEM_3))));
  }

  function areSkillsAvailableForHero(address[] memory skillTokens, uint[] memory skillTokenIds, address hero, uint heroId) external view returns (bool) {
    return ItemControllerHelperLib.areSkillsAvailableForHero(IController(controller()), skillTokens, skillTokenIds, hero, heroId);
  }
  //endregion ------------------------ Views

  //region ------------------------ Deployer actions
  function addUnionConfig(address[] memory items, uint[] memory count, address itemToMint) external {
    ItemControllerHelperLib.addUnionConfig(IController(controller()), items, count, itemToMint);
  }

  function updateUnionConfig(uint configId, address[] memory items, uint[] memory count, address itemToMint) external {
    ItemControllerHelperLib.updateUnionConfig(IController(controller()), configId, items, count, itemToMint);
  }
  
  function removeUnionConfig(uint configId) external {
    ItemControllerHelperLib.removeUnionConfig(IController(controller()), configId);
  }

  function setUnionKeyPassItem(address item) external {
    ItemControllerHelperLib.setUnionKeyPassItem(IController(controller()), item);
  }

  function setAugmentationProtectiveItem(address item) external {
    ItemControllerHelperLib.setAugmentationProtectiveItem(IController(controller()), item);
  }
  //endregion ------------------------ Deployer actions

  //region ------------------------ Item controller actions
  /// @notice Check if list of {items} passed by {user} fit to config, ensure that user is able to combine items
  /// @param user User that is going to combine items
  /// @param items List of items to destroy. Should contain exactly same items as the config. Items order doesn't matter
  /// @param itemIds List of tokens of each item to destroy. Length of the tokens should fit to count specified in config
  /// @dev itemTokenIds[count tokens of i-th item][countItems]
  /// @return Item to mint in exchange of {items}
  function prepareToCombine(address user, uint configId, address[] memory items, uint[][] memory itemIds) external view returns (address) {
    return ItemControllerHelperLib.prepareToCombine(user, configId, items, itemIds);
  }

  //endregion ------------------------ Item controller actions
}
