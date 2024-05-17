// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../openzeppelin/ERC721EnumerableUpgradeable.sol";
import "../interfaces/IApplicationEvents.sol";
import "../proxy/Controllable.sol";

abstract contract NftBase is ERC721EnumerableUpgradeable, Controllable {

  //region ------------------------ Data types and constants
  /// @custom:storage-location erc7201:nft.base.storage
  struct NftBaseStorage {
    uint idCounter;
    string baseUri;
    mapping(uint => string) uniqueUri;
  }

  // keccak256(abi.encode(uint256(keccak256("nft.base.storage")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant NftBaseStorageLocation = 0xda2932ada77a3c8131d8c171a8679090714572b6a41aff2e2186c297ac0f5500;
  //endregion ------------------------ Data types and constants

  //region ------------------------ Initializer

  function __NftBase_init(
    string memory name_,
    string memory symbol_,
    address controller_,
    string memory uri
  ) internal onlyInitializing {
    _init(name_, symbol_, controller_, uri);
  }

  function _init(
    string memory name_,
    string memory symbol_,
    address controller_,
    string memory uri
  ) private {
    __ERC721_init(name_, symbol_);
    __Controllable_init(controller_);
    _getNftBaseStorage().idCounter = 1;
    _getNftBaseStorage().baseUri = uri;
    emit IApplicationEvents.BaseUriChanged(uri);
  }

  function _incrementAndGetId() internal returns (uint){
    uint id = _getNftBaseStorage().idCounter;
    // we are using uint64 id, so higher value will overflow in the game logic
    if (id + 1 >= uint(type(uint64).max)) revert IAppErrors.IdOverflow(id);
    _getNftBaseStorage().idCounter = id + 1;
    return id;
  }
  //endregion ------------------------ Initializer

  //region ------------------------ Restrictions
  function onlyDeployer() internal view {
    if (! IController(controller()).isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Views

  function _getNftBaseStorage() private pure returns (NftBaseStorage storage $) {
    assembly {
      $.slot := NftBaseStorageLocation
    }
    return $;
  }

  function _baseURI() internal view override returns (string memory) {
    return _getNftBaseStorage().baseUri;
  }

  function exists(uint tokenId) external view returns (bool) {
    return _ownerOf(tokenId) != address(0);
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    if (tokenId > _getNftBaseStorage().idCounter) revert IAppErrors.NotExistToken(tokenId);

    // unique uri used for concrete tokenId
    string memory uniqueURI = _getNftBaseStorage().uniqueUri[tokenId];
    if (bytes(uniqueURI).length != 0) {
      return uniqueURI;
    }

    // specific token uri used for group of ids based on nft internal logic (such as item rarity)
    string memory specificURI = _specificURI(tokenId);
    if (bytes(specificURI).length != 0) {
      return specificURI;
    }
    return _baseURI();
  }

  function _specificURI(uint) internal view virtual returns (string memory) {
    return "";
  }

  function baseURI() external view returns (string memory) {
    return _baseURI();
  }
  //endregion ------------------------ Views

  //region ------------------------ Gov actions

  function setUniqueUri(uint tokenId, string memory uri) external {
    onlyDeployer();
    _getNftBaseStorage().uniqueUri[tokenId] = uri;
    emit IApplicationEvents.UniqueUriChanged(tokenId, uri);
  }

  function setBaseUri(string memory value) external {
    onlyDeployer();
    _getNftBaseStorage().baseUri = value;
    emit IApplicationEvents.BaseUriChanged(value);
  }
  //endregion ------------------------ Gov actions

  //region ------------------------ Internal logic

  function _beforeTokenTransfer(uint tokenId) internal virtual {
    // noop
  }

  function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
    _beforeTokenTransfer(tokenId);
    return super._update(to, tokenId, auth);
  }
  //endregion ------------------------ Internal logic

}
