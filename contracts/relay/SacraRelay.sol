// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "../openzeppelin/EnumerableSet.sol";
import "../openzeppelin/ECDSA.sol";
import "../interfaces/IAppErrors.sol";

/// @title Sacra relay contract
contract SacraRelay {
  using EnumerableSet for EnumerableSet.AddressSet;

  //region ------------------------ Data types
  /// @notice Relay call with user signature verification for ERC 2771 compliance
  struct CallWithERC2771 {
    uint chainId;
    address target;
    bytes data;
    address user;
    uint userNonce;
    uint userDeadline;
  }
  //endregion ------------------------ Data types

  //region ------------------------ Constants

  string public constant NAME = "SacraRelay";
  string public constant VERSION = "1.0.1";
  uint public immutable DELEGATION_DEADLINE = 1 weeks;
  bytes32 public immutable DOMAIN_SEPARATOR;
  bytes32 public constant CALL_ERC2771_TYPEHASH =
  keccak256(
    bytes(
      "CallERC2771(uint256 chainId,address target,bytes data,address user,uint256 userNonce,uint256 userDeadline)"
    )
  );

  //endregion ------------------------ Constants

  //region ------------------------ Variables

  /// @dev Suppose to be the game governance
  address public owner;
  /// @dev Allowed EOAs to call game contract on behalf of users
  EnumerableSet.AddressSet private _operators;
  /// @dev Allowance is a sequence of numbers where any non zero value means that operator is allowed to call game contract on behalf of user
  mapping(address => bool) public allowance;
  /// @dev Nonce for each user to prevent tx duplication
  mapping(address => uint) public userTxNonce;
  /// @dev User => Delegator. A user can allow another EOA to call any game action on behalf of him
  mapping(address => address) public delegatedCallers;
  /// @dev Delegator => Deadline for delegation
  mapping(address => uint) public delegatedDeadline;

  //endregion ------------------------ Variables

  //region ------------------------ Events
  event CalledFromOperator(CallWithERC2771 callData);
  event CalledFromDelegator(CallWithERC2771 callData);
  //endregion ------------------------ Events

  //region ------------------------ Constructor

  constructor(address owner_) {
    owner = owner_;

    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        keccak256(
          bytes(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
          )
        ),
        keccak256(bytes(NAME)),
        keccak256(bytes(VERSION)),
        block.chainid,
        address(this)
      )
    );
  }

  //endregion ------------------------ Constructor

  //region ------------------------ Views

  /// @dev Get all operators
  function operatorsList() external view returns (address[] memory) {
    return _operators.values();
  }

  /// @dev Get user info
  function userInfo(address user) external view returns (uint nonce, bool allowed, address delegator, uint delegatorDeadline) {
    delegator = delegatedCallers[user];
    return (userTxNonce[user], allowance[user], delegator, delegatedDeadline[delegator]);
  }

  //endregion ------------------------ Views

  //region ------------------------ Owner actions

  /// @dev Change owner of this contract
  function changeOwner(address newOwner) external {
    if (msg.sender != owner) revert IAppErrors.SacraRelayNotOwner();
    owner = newOwner;
  }

  /// @dev Add or remove operator
  function changeOperator(address operator, bool add) external {
    if (msg.sender != owner) revert IAppErrors.SacraRelayNotOwner();
    if (add) {
      _operators.add(operator);
    } else {
      _operators.remove(operator);
    }
  }
  //endregion ------------------------ Owner actions

  //region ------------------------ Main logic
  /// @dev Approve or disapprove operator to call game contract on behalf of users
  function approve(bool status) external {
    allowance[msg.sender] = status;
  }

  /// @dev Allow to call game contract on behalf of user for given EOA.
  ///      Zero delegator address means that user revoke permission for this EOA.
  ///      A user can refuel his delegator by sending some ether with this call.
  function delegate(address delegator) external payable {
    address oldDelegator = delegatedCallers[msg.sender];
    delegatedCallers[msg.sender] = delegator;

    delete delegatedDeadline[oldDelegator];
    delegatedDeadline[delegator] = block.timestamp + DELEGATION_DEADLINE;

    if (msg.value > 0) {
      payable(delegator).transfer(msg.value);
    }
  }

  /// @dev Close delegation for user.
  ///      Delegator can send back ether to user with this call.
  function closeDelegation(address user) external payable {
    if (delegatedCallers[user] != msg.sender) revert IAppErrors.SacraRelayNotDelegator();
    delete delegatedCallers[user];
    delete delegatedDeadline[msg.sender];

    if (msg.value > 0) {
      payable(user).transfer(msg.value);
    }
  }

  /// @dev Call from delegator. No user signature required.
  ///      We assume delegator is under control of user.
  function callFromDelegator(CallWithERC2771 calldata callInfo) external {
    if (delegatedCallers[callInfo.user] != msg.sender) revert IAppErrors.SacraRelayNotDelegator();
    if (callInfo.chainId != block.chainid) revert IAppErrors.SacraRelayInvalidChainId(callInfo.chainId, block.chainid);

    uint _userTxNonce = userTxNonce[callInfo.user];
    if (callInfo.userNonce != _userTxNonce) revert IAppErrors.SacraRelayInvalidNonce(callInfo.userNonce, _userTxNonce);
    if (callInfo.userDeadline != 0 && callInfo.userDeadline < block.timestamp) revert IAppErrors.SacraRelayDeadline();
    if (delegatedDeadline[msg.sender] < block.timestamp) revert IAppErrors.SacraRelayDelegationExpired();

    userTxNonce[callInfo.user] = _userTxNonce + 1;

    _revertingContractCall(callInfo.target, _encodeERC2771Context(callInfo.data, callInfo.user), "SacraRelay.DelegatedCall");

    emit CalledFromDelegator(callInfo);
  }

  /// @dev Call game contract on behalf of user. Require user signature for every call.
  function callFromOperator(CallWithERC2771 calldata callInfo, bytes calldata userSignature_) external {
    if (!_operators.contains(msg.sender)) revert IAppErrors.SacraRelayNotOperator();
    if (callInfo.chainId != block.chainid) revert IAppErrors.SacraRelayInvalidChainId(callInfo.chainId, block.chainid);

    // a user should allow this contract to call game contracts on behalf of him
    if (!allowance[callInfo.user]) revert IAppErrors.SacraRelayNotAllowed();

    uint _userTxNonce = userTxNonce[callInfo.user];
    if (callInfo.userNonce != _userTxNonce) revert IAppErrors.SacraRelayInvalidNonce(callInfo.userNonce, _userTxNonce);
    if (callInfo.userDeadline != 0 && callInfo.userDeadline < block.timestamp) revert IAppErrors.SacraRelayDeadline();

    // Verify user's signature
    _requireCallERC2771Signature(callInfo, userSignature_);

    userTxNonce[callInfo.user] = _userTxNonce + 1;

    _revertingContractCall(callInfo.target, _encodeERC2771Context(callInfo.data, callInfo.user), "SacraRelay.CallERC2771");

    emit CalledFromOperator(callInfo);
  }
  //endregion ------------------------ Main logic

  //region ------------------------ Internal logic
  /// @dev from GelatoCallUtils
  function _revertingContractCall(
    address _contract,
    bytes memory _data,
    string memory _errorMsg
  ) internal returns (bytes memory returnData) {
    bool success;
    (success, returnData) = _contract.call(_data);

    // solhint-disable-next-line max-line-length
    // https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/f9b6fc3fdab7aca33a9cfa8837c5cd7f67e176be/contracts/utils/AddressUpgradeable.sol#L177
    if (success) {
      if (returnData.length == 0) {
        // only check isContract if the call was successful and the return data is empty
        // otherwise we already know that it was a contract
        if (!_isContract(_contract)) revert IAppErrors.SacraRelayCallToNotContract(_contract, _errorMsg);
      }
    } else {
      _revertWithError(returnData, _errorMsg);
    }
  }

  /// @dev NOT SECURE CHECK! Just for more clear error messages
  function _isContract(address account) internal view returns (bool) {
    return account.code.length > 0;
  }

  function _revertWithError(bytes memory _bytes, string memory _tracingInfo) internal pure {
    // 68: 32-location, 32-length, 4-ErrorSelector, UTF-8 err
    if (_bytes.length % 32 == 4) {
      bytes4 selector;
      assembly {
        selector := mload(add(0x20, _bytes))
      }
      if (selector == 0x08c379a0) {
        // Function selector for Error(string)
        assembly {
          _bytes := add(_bytes, 68)
        }
        revert(string(abi.encodePacked(_tracingInfo, string(_bytes))));
      } else {
        revert IAppErrors.SacraRelayNoErrorSelector(selector, _tracingInfo);
      }
    } else {
      revert IAppErrors.SacraRelayUnexpectedReturnData(_bytes, _tracingInfo);
    }
  }

  /// @dev vanilla ERC2771 context encoding
  function _encodeERC2771Context(bytes calldata _data, address _msgSender) pure internal returns (bytes memory){
    return abi.encodePacked(_data, _msgSender);
  }

  function _requireCallERC2771Signature(CallWithERC2771 calldata callInfo, bytes calldata signature_) internal view returns (bytes32 digest) {
    digest = keccak256(
      abi.encodePacked(
        "\x19\x01",
        DOMAIN_SEPARATOR,
        keccak256(_abiEncodeCallERC2771(callInfo))
      )
    );

    (address recovered, ECDSA.RecoverError error,) = ECDSA.tryRecover(digest, signature_);
    if (error != ECDSA.RecoverError.NoError || recovered != callInfo.user) revert IAppErrors.SacraRelayInvalidSignature();
  }

  function _abiEncodeCallERC2771(CallWithERC2771 calldata callInfo) internal pure returns (bytes memory){
    return abi.encode(
      CALL_ERC2771_TYPEHASH,
      callInfo.chainId,
      callInfo.target,
      keccak256(callInfo.data),
      callInfo.user,
      callInfo.userNonce,
      callInfo.userDeadline
    );
  }
  //endregion ------------------------ Internal logic

  receive() external payable {}
}
