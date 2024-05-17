// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "../openzeppelin/ERC20.sol";

contract ERC20Wrapper is ERC20 {

  address public immutable asset;

  constructor(string memory name_, string memory symbol_, address _asset) ERC20(name_, symbol_){
    asset = _asset;
  }

  function mint(address to, uint amount) external {
    _mint(to, amount);
    ERC20(asset).transferFrom(msg.sender, address(this), amount);
  }

  function burn(address from, uint amount) external {
    _burn(from, amount);
    ERC20(asset).transfer(from, amount);
  }

}
