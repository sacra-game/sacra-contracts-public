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

import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IGuildController.sol";
import "../lib/GuildLib.sol";
import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";

contract GuildController is Initializable, Controllable, ERC2771Context, IGuildController {
  //region ------------------------ CONSTANTS

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant override VERSION = "1.0.1";

  uint256 private constant NOT_ENTERED = 1;
  uint256 private constant ENTERED = 2;
  //endregion ------------------------ CONSTANTS

  //region ------------------------ INITIALIZER

  function init(address controller_) external initializer {
    __Controllable_init(controller_);

    GuildLib._S().guildsParam[IGuildController.GuildsParams.BASE_FEE_2] = GuildLib.DEFAULT_BASE_FEE;
  }
  //endregion ------------------------ INITIALIZER

  //region ------------------------ ReentrancyGuard
  /// @notice Prevents a contract from calling itself, directly or indirectly.
  /// @dev Implementation is based on openzeppelin/ReentrancyGuard but no local status variable is used.
  modifier nonReentrant() {
    _nonReentrantBefore();
    _;
    _nonReentrantAfter();
  }

  function _nonReentrantBefore() private {
    // On the first call to nonReentrant, _status will be NOT_ENTERED
    if (_getReentrantStatus() == ENTERED) revert IAppErrors.ReentrancyGuardReentrantCall();

    // Any calls to nonReentrant after this point will fail
    _setReentrantStatus(ENTERED);
  }

  function _nonReentrantAfter() private {
    _setReentrantStatus(NOT_ENTERED);
  }

  function _getReentrantStatus() internal view returns (uint) {
    return GuildLib._S().guildsParam[IGuildController.GuildsParams.REENTRANT_STATUS_4];
  }

  function _setReentrantStatus(uint status) internal {
    GuildLib._S().guildsParam[IGuildController.GuildsParams.REENTRANT_STATUS_4] = status;
  }

  //endregion ------------------------ ReentrancyGuard

  //region ------------------------ Views
  function getGuildParamValue(uint paramId) external view returns (uint) {
    return GuildLib.getGuildParamValue(paramId);
  }

  function getGuildData(uint guildId) external view returns (
    string memory guildName,
    string memory urlLogo,
    address owner,
    uint8 guildLevel,
    uint64 pvpCounter,
    uint toHelperRatio
  ) {
    GuildData memory data = GuildLib.getGuildData(guildId);
    return (data.guildName, data.urlLogo, data.owner, data.guildLevel, data.pvpCounter, data.toHelperRatio);
  }

  function getGuildByName(string memory name) external view returns (uint guildId) {
    return GuildLib.getGuildByName(name);
  }

  function memberOf(address user) external override view returns (uint guildId) {
    return GuildLib.memberOf(user);
  }

  function guildMembers(uint guildId) external view returns (address[] memory) {
    return GuildLib.guildMembers(guildId);
  }

  function getRights(address user) external view returns (uint) {
    return GuildLib.getRights(user);
  }

  function isPeacefulRelation(uint guildId, uint guildId2) external view returns (bool) {
    return GuildLib.isPeacefulRelation(guildId, guildId2);
  }

  /// @notice Amount of base fee in game tokens
  function getBaseFee() external view returns (uint) {
    return GuildLib.getBaseFee();
  }

  function getGuildBank(uint guildId) external view returns (address) {
    return GuildLib.getGuildBank(guildId);
  }

  function getUserPvpPoints(uint guildId, address user) external view returns (uint64 capacityPvpPoints, uint64 spentPvpPoints) {
    return GuildLib.getUserPvpPoints(guildId, user);
  }

  /// @return guildRequestIds Return full list of guild-requests with a given status for a given guild
  /// @param status 0 - not checked, 1 - accepted, 2 - canceled, 3 - removed by the user
  function listGuildRequests(uint guildId, uint8 status) external view returns (uint[] memory guildRequestIds) {
    return GuildLib.listGuildRequests(guildId, status);
  }

  /// @return status 0 - not checked, 1 - accepted, 2 - canceled, 3 - removed by the user
  /// @return user
  /// @return guildId
  /// @return userMessage Message to the guild owner from the user
  function getGuildRequest(uint guildRequestId) external view returns (
    uint8 status,
    address user,
    uint guildId,
    string memory userMessage
  ) {
    return GuildLib.getGuildRequest(guildRequestId);
  }

  /// @notice Get all requests registered by the user and not yet accepted/rejected/canceled
  function getUserActiveGuildRequests(address user) external view returns(uint[] memory guildRequestIds) {
    return GuildLib.getUserActiveGuildRequests(user);
  }

  function getGuildRequestDepositAmount(uint guildId) external view returns (uint) {
    return GuildLib.getGuildRequestDepositAmount(guildId);
  }

  /// @notice Ensure that the {user} has given {right}, revert otherwise
  /// @notice right Value of type IGuildController.GuildRightBits
  function checkPermissions(address user, uint right) external view returns (uint guildId, uint rights) {
    return GuildLib._checkPermissions(IController(controller()), user, IGuildController.GuildRightBits(right));
  }

  /// @notice True if the given {user} has given {right} in the guild to which he belongs currently
  /// @notice right Value of type IGuildController.GuildRightBits
  function hasPermission(address user, uint8 rightBit) external view returns (bool userHasTheRight) {
    (, , userHasTheRight) = GuildLib._hasPermission(user, IGuildController.GuildRightBits(rightBit));
  }

  function getGuildDescription(uint guildId) external view returns (string memory) {
    return GuildLib.getGuildDescription(guildId);
  }

  //endregion ------------------------ Views

  //region ------------------------ Gov actions

  /// @param fee Base fee value in terms of game token
  function setBaseFee(uint fee) external {
    GuildLib.setBaseFee(IController(controller()), fee);
  }

  function setShelterController(address shelterController_) external {
    GuildLib.setShelterController(IController(controller()), shelterController_);
  }

  function setShelterAuctionController(address shelterAuction_) external {
    GuildLib.setShelterAuctionController(IController(controller()), shelterAuction_);
  }

  //endregion ------------------------ Gov actions

  //region ------------------------ Actions

  /// @notice Create new guild, return ID of the new guild
  function createGuild(string memory name, string memory urlLogo, uint8 toHelperRatio) external returns (uint) {
    return GuildLib.createGuild(_isNotSmartContract(), IController(controller()), _msgSender(), name, urlLogo, toHelperRatio);
  }

  /// @notice Edit roles of the given member of the guild to which msgSender belongs
  function changeRoles(address user, uint maskRights) external {
    GuildLib.changeRoles(IController(controller()), _msgSender(), user, maskRights);
  }

  /// @notice Remove given member from the guild to which msgSender belongs
  /// @dev To delete the guild the owner should remove all members and remove himself at the end
  function removeGuildMember(address userToRemove) external {
    GuildLib.removeGuildMember(IController(controller()), _msgSender(), userToRemove);
  }

  /// @notice Increment level of the guild, pay BASE_FEE * new level
  function guildLevelUp() external {
    GuildLib.guildLevelUp(IController(controller()), _msgSender());
  }

  /// @notice Rename the guild, pay BASE_FEE
  function rename(string memory newGuildName) external {
    GuildLib.rename(IController(controller()), _msgSender(), newGuildName);
  }

  function changeLogo(string memory newLogoUrl) external {
    GuildLib.changeLogo(IController(controller()), _msgSender(), newLogoUrl);
  }

  function changeDescription(string memory newDescription) external {
    GuildLib.changeDescription(IController(controller()), _msgSender(), newDescription);
  }

  function setRelation(uint otherGuildId, bool peace) external {
    GuildLib.setRelation(IController(controller()), _msgSender(), otherGuildId, peace);
  }

  /// @notice Set helper ratio for guild reinforcement
  /// @param value Percent in the range [10..50], see constants in ReinforcementControllerLib
  function setToHelperRatio(uint8 value) external {
    GuildLib.setToHelperRatio(IController(controller()), _msgSender(), value);
  }

  /// @notice Set max amount of pvp-points that is allowed to be used by each guild member
  /// Guild owner has no limits even if capacity is set.
  function setPvpPointsCapacity(uint64 capacityPvpPoints, address[] memory users) external {
    GuildLib.setPvpPointsCapacity(IController(controller()), _msgSender(), capacityPvpPoints, users);
  }

  function transferOwnership(address newAdmin) external {
    GuildLib.transferOwnership(IController(controller()), _msgSender(), newAdmin);
  }

  //endregion ------------------------ Actions

  //region ------------------------ Guild requests
  /// @notice User sends request to join to the guild. Assume approve on request-deposit.
  /// @dev User is able to send multiple requests. But any user can belong to single guild only.
  /// Any attempts to accept request for the user that is already member of a guild will revert.
  /// @param userMessage Any info provided by the user to the guild
  function addGuildRequest(uint guildId, string memory userMessage) external {
    GuildLib.addGuildRequest(_isNotSmartContract(), IController(controller()), _msgSender(), guildId, userMessage);
  }

  /// @notice Guild owner or user with permissions accepts guild request and so add the user to the guild
  /// Deposit is returned to the user, guild-request is marked as accepted and removed from the list of user guild requests
  /// @param maskRights Set of rights of the new guild member.
  /// if NOT-admin accepts the request then {maskRights} should be equal to 0.
  /// Admin is able to set any value of {maskRights} except ADMIN_0
  function acceptGuildRequest(uint guildRequestId, uint maskRights) external nonReentrant {
    GuildLib.acceptGuildRequest(IController(controller()), _msgSender(), guildRequestId, maskRights);
  }

  /// @notice Guild owner or user with permissions rejects guild request and so doesn't add the user to the guild
  /// Deposit is returned to the user, guild-request is marked as rejected and removed from the list of user guild requests
  function rejectGuildRequest(uint guildRequestId) external nonReentrant {
    GuildLib.rejectGuildRequest(IController(controller()), _msgSender(), guildRequestId);
  }

  /// @notice The user cancels his guild request.
  /// Deposit is returned to the user, guild-request is marked as canceled and removed from the list of user guild requests
  function cancelGuildRequest(uint guildRequestId) external nonReentrant {
    GuildLib.cancelGuildRequest(IController(controller()), _msgSender(), guildRequestId);
  }

  /// @notice Set deposit amount required to create new guild request
  /// @param amount 0 is allowed
  function setGuildRequestDepositAmount(uint amount) external {
    GuildLib.setGuildRequestDepositAmount(IController(controller()), _msgSender(), amount);
  }
  //endregion ------------------------ Guild requests

  //region ------------------------ Guild bank
  /// @notice Transfer given {amount} of the given {token} from the guild bank to the given {recipient}.
  /// The guild bank belongs to the guild to which the message sender belongs.
  function transfer(address token, address recipient, uint amount) external {
    GuildLib.transfer(IController(controller()), _msgSender(), token, recipient, amount);
  }

  /// @notice Transfer given {amounts} of the given {token} from guild bank to the given {recipients}.
  /// The guild bank belongs to the guild to which the message sender belongs.
  function transferMulti(address token, address[] memory recipients, uint[] memory amounts) external {
    GuildLib.transferMulti(IController(controller()), _msgSender(), token, recipients, amounts);
  }

  function transferNftMulti(address to, address[] memory nfts, uint256[] memory tokenIds) external {
    GuildLib.transferNftMulti(IController(controller()), _msgSender(), to, nfts, tokenIds);
  }

  /// @notice Top up balance of the guild bank of the guild.
  /// The guild bank belongs to the guild to which the message sender belongs.
  function topUpGuildBank(address token, uint amount) external {
    GuildLib.topUpGuildBank(IController(controller()), _msgSender(), token, amount);
  }
  //endregion ------------------------ Guild bank

  //region ------------------------ Shelters
  function usePvpPoints(uint guildId, address user, uint64 priceInPvpPoints) external {
    return GuildLib.usePvpPoints(guildId, user, priceInPvpPoints);
  }

  function guildToShelter(uint guildId) external view returns (uint shelterId) {
    return GuildLib.guildToShelter(guildId);
  }

  function shelterController() external view returns (address) {
    return GuildLib._shelterController();
  }

  function shelterAuctionController() external view returns (address) {
    return GuildLib._shelterAuctionController();
  }

  function payFromGuildBank(uint guildId, uint shelterPrice) external {
    return GuildLib.payFromGuildBank(IController(controller()), guildId, shelterPrice);
  }

  function payFromBalance(uint amount, address from) external {
    return GuildLib.payFromBalance(IController(controller()), amount, from);
  }

  function payForAuctionBid(uint guildId, uint amount, uint bid) external {
    return GuildLib.payForAuctionBid(IController(controller()), guildId, amount, bid);
  }
  //endregion ------------------------ Shelters
}
