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

import "../interfaces/IAppErrors.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IGuildBank.sol";
import "../interfaces/IGuildController.sol";
import {IApplicationEvents} from "../interfaces/IApplicationEvents.sol";

contract GuildBank is IGuildBank {

  //region ------------------------ CONSTANTS
  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant VERSION = "1.0.1";
  //endregion ------------------------ CONSTANTS

  //region ------------------------ Members
  IGuildController immutable public guildController;
  uint immutable public guildId;
  //endregion ------------------------ Members

  //region ------------------------ Restrictions and constructor
  function _onlyGuildController(address msgSender) internal view {
    if (msgSender != address(guildController)) revert IAppErrors.GuildControllerOnly();
  }

  constructor (address guildController_, uint guildId_) {
    guildController = IGuildController(guildController_);
    guildId = guildId_;
  }
  //endregion ------------------------ Restrictions and constructor

  //region ------------------------ ERC20
  function transfer(address token, address recipient, uint amount) external {
    _onlyGuildController(msg.sender);

    IERC20(token).transfer(recipient, amount);
    emit IApplicationEvents.GuildBankTransfer(token, recipient, amount);
  }

  function approve(address token, address spender, uint256 amount) external returns (bool) {
    _onlyGuildController(msg.sender);

    return IERC20(token).approve(spender, amount);
  }
  //endregion ------------------------ ERC20

  //region ------------------------ ERC721
  function transferNft(address to, address nft, uint256 tokenId) external {
    _onlyGuildController(msg.sender);

    IERC721(nft).transferFrom(address(this), to, tokenId);
    emit IApplicationEvents.GuildBankTransferNft(to, nft, tokenId);
  }

  function transferNftMulti(address to, address[] memory nfts, uint256[] memory tokenIds) external {
    _onlyGuildController(msg.sender);

    uint len = nfts.length;
    if (len != tokenIds.length) revert IAppErrors.LengthsMismatch();

    for (uint i; i < len; ++i) {
      IERC721(nfts[i]).transferFrom(address(this), to, tokenIds[i]);
    }
    emit IApplicationEvents.GuildBankTransferNftMulti(to, nfts, tokenIds);
  }

  function approveNft(address to, address nft, uint256 tokenId) external {
    _onlyGuildController(msg.sender);

    IERC721(nft).approve(to, tokenId);
  }

  function approveNftMulti(address to, address[] memory nfts, uint256[] memory tokenIds) external {
    _onlyGuildController(msg.sender);

    uint len = nfts.length;
    if (len != tokenIds.length) revert IAppErrors.LengthsMismatch();

    for (uint i; i < len; ++i) {
      IERC721(nfts[i]).approve(to, tokenIds[i]);
    }
  }
  //endregion ------------------------ ERC721
}