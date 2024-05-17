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

import "../interfaces/IGameToken.sol";
import "../interfaces/IApplicationEvents.sol";
import "../relay/ERC2771Context.sol";

contract GameToken is IGameToken, ERC2771Context {

  //region ------------------------ Constants

  string public constant symbol = "SACRA";
  string public constant name = "Sacra token";
  uint8 public constant decimals = 18;
  //endregion ------------------------ Constants

  //region ------------------------ Variables

  uint public override totalSupply = 0;
  bool public paused;

  mapping(address => uint) public override balanceOf;
  mapping(address => mapping(address => uint)) public override allowance;

  address public override minter;
  //endregion ------------------------ Variables

  //region ------------------------ Constructor

  constructor() {
    minter = _msgSender();
    _mint(_msgSender(), 0);
  }
  //endregion ------------------------ Constructor

  //region ------------------------ Main logic

  function approve(address spender_, uint value_) external override returns (bool) {
    if (spender_ == address(0)) revert IAppErrors.ApproveToZeroAddress();
    allowance[_msgSender()][spender_] = value_;
    emit Approval(_msgSender(), spender_, value_);
    return true;
  }

  function _mint(address to_, uint amount_) internal returns (bool) {
    if (to_ == address(0)) revert IAppErrors.MintToZeroAddress();
    require(!paused, "Paused");
    balanceOf[to_] += amount_;
    totalSupply += amount_;
    emit Transfer(address(0x0), to_, amount_);
    return true;
  }

  function _transfer(address from_, address to_, uint value_) internal returns (bool) {
    if (to_ == address(0)) revert IAppErrors.TransferToZeroAddress();
    if (paused) revert IAppErrors.ErrorPaused();

    uint fromBalance = balanceOf[from_];
    if (fromBalance < value_) revert IAppErrors.TransferAmountExceedsBalance(fromBalance, value_);
    unchecked {
      balanceOf[from_] = fromBalance - value_;
    }

    balanceOf[to_] += value_;
    emit Transfer(from_, to_, value_);
    return true;
  }

  function transfer(address to_, uint value_) external override returns (bool) {
    return _transfer(_msgSender(), to_, value_);
  }

  function transferFrom(address from_, address to_, uint value_) external override returns (bool) {
    address spender = _msgSender();
    uint spenderAllowance = allowance[from_][spender];
    if (spenderAllowance != type(uint).max) {
      if (spenderAllowance < value_) revert IAppErrors.InsufficientAllowance();
      unchecked {
        uint newAllowance = spenderAllowance - value_;
        allowance[from_][spender] = newAllowance;
        emit Approval(from_, spender, newAllowance);
      }
    }
    return _transfer(from_, to_, value_);
  }

  function burn(uint amount) external override returns (bool) {
    address from = _msgSender();
    uint accountBalance = balanceOf[from];
    if (accountBalance < amount) revert IAppErrors.BurnAmountExceedsBalance();
    unchecked {
      balanceOf[from] = accountBalance - amount;
    // Overflow not possible: amount <= accountBalance <= totalSupply.
      totalSupply -= amount;
    }

    emit Transfer(from, address(0), amount);
    return true;
  }
  //endregion ------------------------ Main logic

  //region ------------------------ Minter actions

  function mint(address account, uint amount) external override returns (bool) {
    if (msg.sender != minter) revert IAppErrors.NotMinter(msg.sender);
    _mint(account, amount);
    return true;
  }

  // No checks as its meant to be once off to set minting rights to Minter
  function setMinter(address minter_) external override {
    if (msg.sender != minter) revert IAppErrors.NotMinter(msg.sender);
    minter = minter_;
    emit IApplicationEvents.MinterChanged(minter_);
  }

  function pause(bool value) external override {
    if (msg.sender != minter) revert IAppErrors.NotMinter(msg.sender);
    paused = value;
    emit IApplicationEvents.ChangePauseStatus(value);
  }
  //endregion ------------------------ Minter actions
}
