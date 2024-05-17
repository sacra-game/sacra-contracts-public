// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "../interfaces/IERC20.sol";

contract GameFaucet {

  /////////////////// VARS ////////////////////

  uint public constant DELAY = 1 days;
  address public immutable owner;
  mapping(address => bool) public operators;

  mapping(address => uint) public receivedEth;
  mapping(address => uint) public receivedEthTs;
  uint public ethAmountLimit = 100 ether;

  mapping(address => uint) public receivedToken;
  mapping(address => uint) public receivedTokenTs;
  uint public tokenAmountLimit = 1000 ether;

  /////////////////// CONSTRUCTOR ////////////////////

  constructor() {
    owner = msg.sender;
  }

  /////////////////// MODIFIERS ////////////////////

  modifier onlyOwner() {
    require(msg.sender == owner, "!owner");
    _;
  }

  modifier onlyOwnerOrOperator() {
    require(msg.sender == owner || operators[msg.sender], "!owner && !operator");
    _;
  }

  /////////////////// VIEWS ////////////////////

  function isEligibleForEth(address recipient) public view returns (bool) {
    return receivedEthTs[recipient] + DELAY < block.timestamp
    && receivedEth[recipient] < ethAmountLimit
    && address(this).balance > 1 ether
      && address(recipient).balance < 0.1 ether;
  }

  function isEligibleForToken(address recipient, address token) public view returns (bool) {
    return receivedTokenTs[recipient] + DELAY < block.timestamp
    && receivedToken[recipient] < tokenAmountLimit
    && IERC20(token).balanceOf(address(this)) > 100 ether
      && IERC20(token).balanceOf(recipient) < 10 ether;
  }

  function isEligibleForEthAndToken(address recipient, address token) public view returns (bool forEth, bool forToken) {
    return (isEligibleForEth(recipient), isEligibleForToken(recipient, token));
  }

  /////////////////// GOV ACTIONS ////////////////////

  function withdrawAll() public onlyOwner {
    uint balance = address(this).balance;
    require(balance > 0, "No ether left to withdraw");
    payable(owner).transfer(balance);
  }

  function setEthAmountLimit(uint _gasAmountLimit) public onlyOwner {
    ethAmountLimit = _gasAmountLimit;
  }

  function addOperator(address _operator) public onlyOwner {
    operators[_operator] = true;
  }

  /////////////////// OPERATOR ACTIONS ////////////////////

  function sendEthTo(address payable recipient, uint amount) public onlyOwnerOrOperator {
    require(isEligibleForEth(recipient), "not eligible");

    receivedEth[recipient] += amount;
    receivedEthTs[recipient] = block.timestamp;

    _sendGas(recipient, amount);
  }

  function sendTokenTo(address recipient, address token, uint amount) public onlyOwnerOrOperator {
    require(isEligibleForToken(recipient, token), "not eligible");

    receivedToken[recipient] += amount;
    receivedTokenTs[recipient] = block.timestamp;

    IERC20(token).transfer(recipient, amount);
  }

  function sendTo(address recipient, uint ethAmount, address token, uint tokenAmount) public onlyOwnerOrOperator {
    if(ethAmount > 0) {
      require(isEligibleForEth(recipient), "not eligible");

      receivedEth[recipient] += ethAmount;
      receivedEthTs[recipient] = block.timestamp;

      _sendGas(payable(recipient), ethAmount);
    }

    if(tokenAmount > 0) {
      require(isEligibleForToken(recipient, token), "not eligible");

      receivedToken[recipient] += tokenAmount;
      receivedTokenTs[recipient] = block.timestamp;

      IERC20(token).transfer(recipient, tokenAmount);
    }
  }

  /////////////////// INTERNAL ////////////////////

  function _sendGas(address payable recipient, uint amount) private {
    require(address(this).balance >= amount, "Insufficient funds in the faucet");
    recipient.transfer(amount);
  }

  receive() external payable {}
}
