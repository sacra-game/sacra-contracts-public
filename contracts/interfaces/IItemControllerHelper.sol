// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "../openzeppelin/EnumerableSet.sol";

/// @notice Helper contract owned by ItemController only, it reduces data and code size in ItemController
interface IItemControllerHelper {

  enum GlobalParam {
    UNKNOWN_0,

    /// @notice Address of the nft. User should own such nft to be able to combine items. 0 is allowed (no keyPass)
    UNION_KEY_PASS_ITEM_1,

    /// @notice Generator of ID for union combinations
    UNION_ID_COUNTER_2
  }

  /// @custom:storage-location erc7201:item.controller.helper.main
  struct MainState {
    /// @notice Universal mapping to store various addresses and numbers (params of the contract)
    mapping (GlobalParam param => uint value) globalParam;

    //region ------------------------ SCB-1028: combine multiple items to new more powerful item

    /// @notice Union ID generated using {UNION_ID_COUNTER_2} => configuration
    mapping (uint configId => UnionConfig) unionConfig;

    /// @notice List of configId of all registered union configs
    EnumerableSet.UintSet listUnionConfigs;

    //endregion ------------------------ SCB-1028: combine multiple items to new more powerful item
  }

  struct UnionConfig {
    /// @notice Each union has unique ID
    /// @dev Assume that 96 bits are enough to store any id => configId + itemToMint = 1 slot
    uint96 configId;

    /// @notice Result item that will be minted in exchange of destroying of the combined {items} of the given {count}
    address itemToMint;

    /// @notice List of items that can be combined. We need to store the list to be able to display it on UI only
    address[] items;

    /// @notice Count of items that can be combined. We need to store the list to be able to display it on UI only
    uint[] count;
  }


  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  function prepareToCombine(address user, uint configId, address[] memory items, uint[][] memory tokens) external view returns (address);
}
