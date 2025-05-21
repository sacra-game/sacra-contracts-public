// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IController.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IGuildStakingAdapter.sol";
import "../openzeppelin/EnumerableMap.sol";
import "../openzeppelin/ReentrancyGuard.sol";
import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";

/// @notice Allow users to stake tokens if favor of guilds and so increase possible tax of biome owners
contract GuildStakingManager is Controllable, ERC2771Context, IGuildStakingAdapter, ReentrancyGuard {
  using EnumerableMap for EnumerableMap.UintToUintMap;

  //region ------------------------ Constants
  /// @notice Version of the contract
  string public constant override VERSION = "1.0.0";
  //endregion ------------------------ Constants

  //region ------------------------ Members
  /// @notice Token for staking
  address public token;

  /// @notice GuildId => Total amount staked by the guild
  EnumerableMap.UintToUintMap internal _stakedAmounts;

  /// @notice GuildId => Total amount staked by all guilds (== sum of {_stakedAmounts})
  uint public totalStakedAmount;
  //endregion ------------------------ Members

  //region ------------------------ Initialization
  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ Initialization

  //region ------------------------ Restrictions
  function onlyDeployerOrGovernance(IController controller_) internal view {
    address sender = _msgSender();
    if (
      !controller_.isDeployer(sender)
      && sender != controller_.governance()
    ) revert IAppErrors.ErrorNotAllowedSender();
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Views
  /// @notice All staked amounts
  function stakedAmounts() external view returns (uint[] memory guildIds, uint[] memory amounts) {
    uint len = _stakedAmounts.length();
    guildIds = new uint[](len);
    amounts = new uint[](len);
    for (uint i; i < len; ++i) {
      (guildIds[i], amounts[i]) = _stakedAmounts.at(i);
    }
  }

  /// @notice Amount staked by the given guild
  function stakedByGuild(uint guildId) public view returns (uint amount) {
    bool exist;
    (exist, amount) = _stakedAmounts.tryGet(guildId);
    return (exist ? amount : 0);
  }

  /// @notice Calculate relative increment of the biome tax for the given guild owner, [0..1e18]
  /// 0 - no increment (default 1% is used), 1 - max possible increment (i.e. 5%)
  function getExtraFeeRatio(uint guildId) external view returns (uint) {
    uint _totalStakedAmount = totalStakedAmount;
    return _totalStakedAmount == 0
      ? 0
      : stakedByGuild(guildId) * 1e18 / totalStakedAmount;
  }
  //endregion ------------------------ Views

  //region ------------------------ Deployer action
  function setToken(address token_) external {
    onlyDeployerOrGovernance(IController(controller()));

    token = token_;
    emit IApplicationEvents.SetStakingToken(token_);
  }

  function salvage(address receiver_, address token_, uint amount_) external {
    onlyDeployerOrGovernance(IController(controller()));

    IERC20(token_).transfer(receiver_, amount_);
    emit IApplicationEvents.Salvage(receiver_, token_, amount_);
  }

  //endregion ------------------------ Deployer action

  //region ------------------------ User actions

  /// @notice Stake given {amount} of the {token} forever in favor of the given {guild}
  function stakeTokens(uint amount, uint guildId) external nonReentrant {
    // there are no restrictions for the _msgSender()
    if (amount == 0) revert IAppErrors.ZeroAmount();

    address _token = token;
    IGuildController guildController = IGuildController(IController(controller()).guildController());

    // don't allow to stake tokens in favor of not exist or deleted guild
    (, , address guildOwner, , , ) = guildController.getGuildData(guildId);
    if (guildOwner == address(0)) revert IAppErrors.WrongGuild();

    // assume that _token is set by the governance, no need to check 0
    IERC20(_token).transferFrom(_msgSender(), address(this), amount);

    uint guildAmount = stakedByGuild(guildId);
    _stakedAmounts.set(guildId, guildAmount + amount);

    uint total = totalStakedAmount + amount;
    totalStakedAmount = total;

    emit IApplicationEvents.StakeTokens(_token, amount, guildId, total);
  }
  //endregion ------------------------ User actions
}
