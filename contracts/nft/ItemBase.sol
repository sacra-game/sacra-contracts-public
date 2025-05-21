// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./NftBase.sol";
import "../interfaces/IItem.sol";
import "../interfaces/IItemController.sol";

/// @title ItemBase implementation.
///        All game logic should be placed in dedicated controllers.
contract ItemBase is NftBase, IItem {

  //region ------------------------ Data types and constants

  /// @custom:storage-location erc7201:item.base.storage
  struct ItemBaseStorage {
    mapping(uint8 => string) itemUriByRarity;
  }

  /// @notice Version of the contract
  string public constant VERSION = "2.0.0";
  // keccak256(abi.encode(uint256(keccak256("item.base.storage")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant ItemBaseStorageLocation = 0x2dd41482e37d186fdf6545c563673785f2bcb485d6039f6c172d58b496a6e000;
  //endregion ------------------------ Data types and constants

  //region ------------------------ Initializer

  function init(
    address controller_,
    string memory name_,
    string memory symbol_,
    string memory uri_
  ) external initializer {
    __NftBase_init(name_, symbol_, controller_, uri_);
  }
  //endregion ------------------------ Initializer

  //region ------------------------ Restrictions

  function onlyItemController(address itemController, address sender) internal pure {
    if (itemController != sender) revert IAppErrors.ErrorNotItemController(sender);
  }

  function onlyItemControllerOrItemBox(IController controller, address sender) internal view {
    if (
      controller.itemController() != sender
      && controller.itemBoxController() != sender
    ) revert IAppErrors.ErrorNotAllowedSender();
  }

  function _beforeTokenTransfer(uint tokenId) internal view override {
    if (
      !IItemController(IController(controller()).itemController()).isAllowedToTransfer(address(this), tokenId)
    ) revert IAppErrors.EquippedItemIsNotAllowedToTransfer(tokenId);
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Views

  function _getItemBaseStorage() private pure returns (ItemBaseStorage storage $) {
    assembly {
      $.slot := ItemBaseStorageLocation
    }
    return $;
  }

  function isItem() external pure override returns (bool) {
    return true;
  }

  function _specificURI(uint tokenId) internal view override returns (string memory) {
    IItemController ic = IItemController(IController(controller()).itemController());
    return _getItemBaseStorage().itemUriByRarity[uint8(ic.itemInfo(address(this), tokenId).rarity)];
  }
  //endregion ------------------------ Views

  //region ------------------------ Gov actions

  function setItemUriByRarity(string memory uri, uint8 rarity) external {
    onlyDeployer();

    _getItemBaseStorage().itemUriByRarity[rarity] = uri;
    emit IApplicationEvents.UriByRarityChanged(uri, rarity);
  }
  //endregion ------------------------ Gov actions

  //region ------------------------ Actions

  function mintFor(address recipient) external override returns (uint tokenId) {
    onlyItemController(IController(controller()).itemController(), msg.sender);

    tokenId = _incrementAndGetId();
    _safeMint(recipient, tokenId);

    emit IApplicationEvents.ItemMinted(tokenId);
  }

  /// @dev Some stories can destroy items
  function burn(uint tokenId) external override {
    onlyItemControllerOrItemBox(IController(controller()), msg.sender);

    _burn(tokenId);

    emit IApplicationEvents.ItemBurned(tokenId);
  }

  /// @dev Controller can transfer item from one address to another.
  ///      It must be performed only with properly check requirements.
  function controlledTransfer(address from, address to, uint tokenId) external override {
    onlyItemControllerOrItemBox(IController(controller()), msg.sender);

    _safeTransfer(from, to, tokenId);
  }
  //endregion ------------------------ Actions

}
