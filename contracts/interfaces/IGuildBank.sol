// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IAppErrors.sol";
import "../interfaces/IGuildController.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IERC721.sol";

interface IGuildBank {
  function transfer(address token, address recipient, uint amount) external;

  function approve(address token, address spender, uint256 amount) external returns (bool);

  function transferNft(address to, address nft, uint256 tokenId) external;

  function transferNftMulti(address to, address[] memory nfts, uint256[] memory tokenIds) external;

  function approveNft(address to, address nft, uint256 tokenId) external;

  function approveNftMulti(address to, address[] memory nfts, uint256[] memory tokenIds) external;
}