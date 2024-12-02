// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../nft/NftBase.sol";
import "../openzeppelin/ERC721Holder.sol";
import "../interfaces/IHero.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IStatController.sol";
import "../interfaces/IApplicationEvents.sol";

contract HeroBase is NftBase, IHero, ERC721Holder {

  //region ------------------------ Data types and constants
  /// @custom:storage-location erc7201:hero.base.storage
  struct HeroBaseStorage {
    mapping(uint => string) _heroUriByStatus;
  }

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant override VERSION = "2.0.1";
  // keccak256(abi.encode(uint256(keccak256("hero.base.storage")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant HeroBaseStorageLocation = 0xc546abf9ed7c8d4a6ded82a0edfd8f66c8300256eba0932933c3d559a091ea00;
  uint public constant KILL_PENALTY = 70;
  //endregion ------------------------ Data types and constants

  //region ------------------------ Initializer

  function init(
    string memory name_,
    string memory symbol_,
    address controller_,
    string memory uri
  ) external initializer {
    __NftBase_init(name_, symbol_, controller_, uri);
  }
  //endregion ------------------------ Initializer

  //region ------------------------ Restrictions

  function _beforeTokenTransfer(uint heroId) internal override {
    if (
      ! IHeroController(IController(controller()).heroController()).beforeTokenTransfer(address(this), heroId)
    ) revert IAppErrors.TokenTransferNotAllowed();
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Views

  function _getHeroBaseStorage() private pure returns (HeroBaseStorage storage $) {
    assembly {
      $.slot := HeroBaseStorageLocation
    }
    return $;
  }

  function isHero() external pure override returns (bool) {
    return true;
  }

  /// @dev Every 10 levels we can show uniq img
  function _specificURI(uint heroId) internal view override returns (string memory) {
    uint level = IStatController(IController(controller()).statController()).heroStats(address(this), heroId).level;
    if (level / 10 == 0) {
      return "";
    }
    return _getHeroBaseStorage()._heroUriByStatus[level / 10];
  }
  //endregion ------------------------ Views

  //region ------------------------ Governance actions

  /// @dev Every 10 levels we can show uniq img
  function setHeroUriByStatus(string memory uri, uint statusLvl) external {
    onlyDeployer();

    _getHeroBaseStorage()._heroUriByStatus[statusLvl] = uri;

    emit IApplicationEvents.HeroUriByStatusChanged(uri, statusLvl);
  }
  //endregion ------------------------ Governance actions

  //region ------------------------ IHero actions

  function mintFor(address recipient) external override returns (uint heroId) {
    if (IController(controller()).heroController() != msg.sender) revert IAppErrors.ErrorNotHeroController(msg.sender);

    heroId = _incrementAndGetId();
    _safeMint(recipient, heroId);

    emit IApplicationEvents.HeroMinted(heroId);
  }

  function burn(uint heroId) external override {
    if (IController(controller()).heroController() != msg.sender) revert IAppErrors.ErrorNotHeroController(msg.sender);

    _burn(heroId);

    emit IApplicationEvents.HeroBurned(heroId);
  }
  //endregion ------------------------ IHero actions

}
