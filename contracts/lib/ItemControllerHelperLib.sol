// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IERC721.sol";
import "../interfaces/IAppErrors.sol";
import "../interfaces/IItemControllerHelper.sol";
import "./ItemStatsLib.sol";

library ItemControllerHelperLib {
  using EnumerableSet for EnumerableSet.UintSet;

  //region ------------------------ Constants
  /// @dev keccak256(abi.encode(uint256(keccak256("item.controller.helper.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant ITEM_CONTROLLER_HELPER_MAIN_STORAGE_LOCATION = 0x369019597a17a51d9b72838e37238167004097b8e88fd096bb2d3ab0fa92ac00; // item.controller.helper.main
  //endregion ------------------------ Constants

  //region ------------------------ Storage
  function _S() internal pure returns (IItemControllerHelper.MainState storage s) {
    assembly {
      s.slot := ITEM_CONTROLLER_HELPER_MAIN_STORAGE_LOCATION
    }
    return s;
  }
  //endregion ------------------------ Storage

  //region ------------------------ Views
  function listUnionConfigsLength() internal view returns (uint) {
    return _S().listUnionConfigs.length();
  }

  function unionConfigIdByIndex(uint index) internal view returns (uint) {
    return _S().listUnionConfigs.at(index);
  }
  
  function unionConfig(uint configId) internal view returns (IItemControllerHelper.UnionConfig memory) {
    return _S().unionConfig[configId];
  }

  function keyPassItem() internal view returns (address) {
    return address(uint160(_S().globalParam[IItemControllerHelper.GlobalParam.UNION_KEY_PASS_ITEM_1]));
  }

  function getGlobalParamValue(uint8 globalParam) internal view returns (uint) {
    return _S().globalParam[IItemControllerHelper.GlobalParam(globalParam)];
  }

  //endregion ------------------------ Views

  //region ------------------------ Deployer actions
  function addUnionConfig(IController controller, address[] memory items, uint[] memory count, address itemToMint) internal returns (uint) {
    ItemStatsLib.onlyDeployer(controller, msg.sender);

    _checkConfigItems(items, count);

    uint configId = _S().globalParam[IItemControllerHelper.GlobalParam.UNION_ID_COUNTER_2] + 1;
    _S().globalParam[IItemControllerHelper.GlobalParam.UNION_ID_COUNTER_2] = configId;

    _S().listUnionConfigs.add(configId);
    _S().unionConfig[configId] = IItemControllerHelper.UnionConfig({
      configId: uint96(configId),
      itemToMint: itemToMint,
      items: items,
      count: count
    });

    emit IApplicationEvents.SetUnionConfig(configId, items, count, itemToMint);

    return configId;
  }

  function updateUnionConfig(IController controller, uint configId, address[] memory items, uint[] memory count, address itemToMint) internal {
    ItemStatsLib.onlyDeployer(controller, msg.sender);

    _checkConfigItems(items, count);

    if (configId == 0 || _S().unionConfig[configId].configId != configId) revert IAppErrors.UnknownUnionConfig(configId);
    _S().unionConfig[configId] = IItemControllerHelper.UnionConfig({
      configId: uint96(configId),
      itemToMint: itemToMint,
      items: items,
      count: count
    });

    emit IApplicationEvents.SetUnionConfig(configId, items, count, itemToMint);
  }

  function removeUnionConfig(IController controller, uint configId) internal {
    ItemStatsLib.onlyDeployer(controller, msg.sender);

    if (configId == 0 || _S().unionConfig[configId].configId != configId) revert IAppErrors.UnknownUnionConfig(configId);
    delete _S().unionConfig[configId];
    _S().listUnionConfigs.remove(configId);

    emit IApplicationEvents.RemoveUnionConfig(configId);
  }

  /// @notice Set key pass item. User should own this item to be able to combine items.
  /// @param item 0 is allowed, it means there is no keyPass item
  function setUnionKeyPassItem(IController controller, address item) internal {
    ItemStatsLib.onlyDeployer(controller, msg.sender);

    _S().globalParam[IItemControllerHelper.GlobalParam.UNION_KEY_PASS_ITEM_1] = uint(uint160(item));
    emit IApplicationEvents.SetUnionKeyPass(item);
  }
  //endregion ------------------------ Deployer actions

  //region ------------------------ Item controller actions
  /// @notice Check if list of {items} passed by {user} fit to config, ensure that user is able to combine items
  /// @param items List of items to destroy. Should contain exactly same items as the config. Items order doesn't matter
  /// @param tokens List of tokens of each item to destroy. Length of the tokens should fit to count specified in config
  /// @dev itemTokenIds[count tokens of i-th item][countItems]
  /// @return Item to mint in exchange of {items}
  function prepareToCombine(address user, uint configId, address[] memory items, uint[][] memory tokens) internal view returns (address) {
    // user must own keyPass item
    address _keyPassItem = keyPassItem();
    if (_keyPassItem != address(0)) {
      if (0 == IERC721(_keyPassItem).balanceOf(user)) revert IAppErrors.UserHasNoKeyPass(user, _keyPassItem);
    }

    // config exists
    IItemControllerHelper.UnionConfig storage config = _S().unionConfig[configId];
    if (configId == 0 || config.configId != configId) revert IAppErrors.UnknownUnionConfig(configId);

    // ensure that {items} and {tokens} are fit to the required config
    checkItemsByConfig(user, config.items, config.count, items, tokens);

    return config.itemToMint;
  }
  //endregion ------------------------ Item controller actions  
  
  //region ------------------------ Internal logic
  /// @notice Ensure that list of passed items fit to the list of the items specified in union config.
  /// Check that the user is owner of each passed token.
  /// @param configItems List of items required by the config.
  /// @param configCount Count of items required by the config.
  /// @param items List of items to destroy. Order of the items doesn't matter.
  /// @param itemTokenIds List of tokens to destroy. itemTokenIds[count tokens of i-th item][countItems]
  function checkItemsByConfig(
    address user,
    address[] memory configItems,
    uint[] memory configCount,
    address[] memory items,
    uint[][] memory itemTokenIds
  ) internal view {
    uint len = configItems.length;
    if (items.length != len || itemTokenIds.length != len) revert IAppErrors.LengthsMismatch();

    // we don't need to check duplicates in {items} - assume that there are no duplicates in config
    for (uint i; i < len; ++i) {
      // find index of the {configItems[i]} in the array {items} passed by the user
      uint index = type(uint).max;
      for (uint j; j < len; ++j) {
        if (items[j] == configItems[i]) {
          index = j;
          break;
        }
      }
      if (index == type(uint).max) revert IAppErrors.UnionItemNotFound(configItems[i]);

      // check ownership of {count} tokens of the given item
      uint[] memory tokens = itemTokenIds[index];
      uint lenTokens = tokens.length;

      if (configCount[i] != lenTokens) revert IAppErrors.WrongListUnionItemTokens(configItems[i], lenTokens, configCount[i]);

      for (uint k; k < lenTokens; ++k) {
        if (IERC721(configItems[i]).ownerOf(tokens[k]) != user) revert IAppErrors.ErrorNotOwner(configItems[i], tokens[k]);
      }

      // we don't check uniqueness of the tokens in {itemTokenIds}
      // if user will try to use same tokenId multiple times, we will have revert on destroying stage
    }
  }

  function _checkConfigItems(address[] memory items, uint[] memory count) internal pure {
    // assume, that the items don't repeat - it's to expensive to check it on-chain
    uint len = items.length;
    if (len == 0) revert IAppErrors.ZeroValueNotAllowed();
    if (len != count.length) revert IAppErrors.LengthsMismatch();
  }
  //endregion ------------------------ Internal logic

}
