// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IGuildController.sol";
import "../interfaces/IShelterAuction.sol";
import "../interfaces/IShelterController.sol";
import "../interfaces/IUserController.sol";
import "../lib/StringLib.sol";
import "../token/GuildBank.sol";
import "./ReinforcementControllerLib.sol";
import "./StatLib.sol";

library GuildLib {
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.UintSet;

  //region ------------------------ Constants
  /// @dev keccak256(abi.encode(uint256(keccak256("guild.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant GUILD_CONTROLLER_STORAGE_LOCATION = 0x1c4340ff8478a236ed13a5ce46f8e8b8a6037975df340a04c54725978699d100;
  uint8 internal constant FIRST_LEVEL = 1;
  uint8 internal constant MAX_LEVEL = 10;
  /// @notice Default fee for creation guild, renaming, etc. in terms of game token
  uint internal constant DEFAULT_BASE_FEE = 10_000e18;
  uint internal constant MAX_LOGO_URL_LENGTH = 256;
  uint internal constant MAX_DESCRIPTION_LENGTH = 10240;

  uint internal constant MAX_GUILD_NAME_LENGTH = 20;
  uint internal constant MAX_GUILD_REQUEST_MESSAGE_LENGTH = 256;

  uint internal constant MAX_GUILD_MEMBERS_ON_LEVEL_1 = 10;
  uint internal constant MAX_GUILD_MEMBERS_INC_PER_LEVEL = 2;

  /// @notice Default amount of deposit required to create a guild request
  uint internal constant DEFAULT_REQUEST_GUILD_MEMBERSHIP_DEPOSIT_AMOUNT = 1e18;
  //endregion ------------------------ Constants

  //region ------------------------ Restrictions
  function _onlyEoa(bool isEoa) internal pure {
    if (!isEoa) revert IAppErrors.ErrorOnlyEoa();
  }

  function _onlyGovernance(IController controller) internal view {
    if (controller.governance() != msg.sender) revert IAppErrors.NotGovernance(msg.sender);
  }

  function _onlyDeployer(IController controller) internal view {
    if (!controller.isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }

  function _onlyShelterController() internal view {
    if (msg.sender != _shelterController()) revert IAppErrors.ErrorNotShelterController();
  }

  function _notPaused(IController controller) internal view {
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
  }

  function _onlyNotGuildMember(address user) internal view {
    if (_S().memberToGuild[user] != 0) revert IAppErrors.AlreadyGuildMember();
  }

  function _onlyFreeValidGuildName(string memory name) internal view {
    if (_S().nameToGuild[name] != 0) revert IAppErrors.NameTaken();
    if (bytes(name).length >= MAX_GUILD_NAME_LENGTH) revert IAppErrors.TooBigName();
    if (!StringLib.isASCIILettersOnly(name)) revert IAppErrors.WrongSymbolsInTheName();
    if (bytes(name).length == 0) revert IAppErrors.EmptyNameNotAllowed();
  }

  function _onlyValidLogo(string memory urlLogo) internal pure {
    // check logo url, empty logo and duplicates are allowed
    if (bytes(urlLogo).length >= MAX_LOGO_URL_LENGTH) revert IAppErrors.TooLongUrl();
  }

  function _onlyNotZeroAddress(address a) internal pure {
    if (a == address(0)) revert IAppErrors.ZeroAddress();
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Storage

  function _S() internal pure returns (IGuildController.MainState storage s) {
    assembly {
      s.slot := GUILD_CONTROLLER_STORAGE_LOCATION
    }
    return s;
  }
  //endregion ------------------------ Storage

  //region ------------------------ Views
  function getGuildParamValue(uint paramId) internal view returns (uint) {
    return _S().guildsParam[IGuildController.GuildsParams(paramId)];
  }

  function getGuildData(uint guildId) internal view returns (IGuildController.GuildData memory) {
    return _S().guildData[guildId];
  }

  function getGuildByName(string memory name) internal view returns (uint guildId) {
    return _S().nameToGuild[name];
  }

  function memberOf(address user) internal view returns (uint guildId) {
    return _S().memberToGuild[user];
  }

  function guildMembers(uint guildId) internal view returns (address[] memory) {
    return _S().members[guildId].values();
  }

  function getRights(address user) internal view returns (uint) {
    return _S().rights[user];
  }

  function isPeacefulRelation(uint guildId, uint guildId2) internal view returns (bool) {
    return _S().relationsPeaceful[_getGuildsPairKey(guildId, guildId2)];
  }

  function getGuildBank(uint guildId) internal view returns (address) {
    return _S().guildBanks[guildId];
  }

  function getBaseFee() internal view returns (uint) {
    return _S().guildsParam[IGuildController.GuildsParams.BASE_FEE_2];
  }

  function getGuildDescription(uint guildId) internal view returns (string memory) {
    return _S().guildDescription[guildId];
  }

  function getUserPvpPoints(uint guildId, address user) internal view returns (uint64 capacityPvpPoints, uint64 spentPvpPoints) {
    IGuildController.UserPvpPoints memory data = _S().userPvpPoints[guildId][user];
    return (data.capacityPvpPoints, data.spentPvpPoints);
  }

  /// @return guildRequestIds Return full list of guild-requests with given status for the given guild
  /// @param status 0 - not checked, 1 - accepted, 2 - canceled, 3 - removed by the user
  function listGuildRequests(uint guildId, uint8 status) internal view returns (uint[] memory guildRequestIds) {
    // assume here that the total number of guild requests of any kind is not too big
    return _S().guildRequests[guildId][IGuildController.GuildRequestStatus(status)].values();
  }

  /// @return status 0 - not checked, 1 - accepted, 2 - canceled, 3 - removed by the user
  /// @return user
  /// @return guildId
  /// @return userMessage Message to the guild owner from the user
  function getGuildRequest(uint guildRequestId) internal view returns (
    uint8 status,
    address user,
    uint guildId,
    string memory userMessage
  ) {
    IGuildController.GuildRequestData memory data = _S().guildRequestData[guildRequestId];
    return (uint8(data.status), data.user, data.guildId, data.userMessage);
  }

  /// @notice Get all requests registered by the user and not yet accepted/rejected/canceled
  function getUserActiveGuildRequests(address user) internal view returns(uint[] memory guildRequestIds) {
    return _S().userActiveGuildRequests[user].values();
  }

  /// @notice Deposit amount required to create a guild request. Amount is configured by guild, 0 is allowed.
  function getGuildRequestDepositAmount(uint guildId) internal view returns (uint) {
    IGuildController.GuildRequestDeposit memory data = _S().guildRequestDepositAmounts[guildId];
    return data.initialized
      ? data.amount
      : DEFAULT_REQUEST_GUILD_MEMBERSHIP_DEPOSIT_AMOUNT;
  }

  function guildToShelter(uint guildId) internal view returns (uint shelterId) {
    IShelterController sc = IShelterController(_shelterController());
    return address(sc) == address(0) ? 0 : sc.guildToShelter(guildId);
  }
  //endregion ------------------------ Views

  //region ------------------------ Gov actions

  /// @param fee Base fee value in terms of game token
  function setBaseFee(IController controller, uint fee) external {
    _onlyGovernance(controller);

    if (fee == 0) revert IAppErrors.ZeroValueNotAllowed();

    _S().guildsParam[IGuildController.GuildsParams.BASE_FEE_2] = fee;

    emit IApplicationEvents.SetGuildBaseFee(fee);
  }

  function setShelterController(IController controller, address shelterController) external {
    _setAddress(controller, IGuildController.GuildsParams.SHELTER_CONTROLLER_5, shelterController);
    emit IApplicationEvents.SetShelterController(shelterController);
  }

  function setShelterAuctionController(IController controller, address shelterAuction) external {
    _setAddress(controller, IGuildController.GuildsParams.SHELTER_AUCTION_6, shelterAuction);
    emit IApplicationEvents.SetShelterAuction(shelterAuction);
  }

  function _setAddress(IController controller, IGuildController.GuildsParams paramId, address value) internal {
    _onlyDeployer(controller);
    if (_S().guildsParam[paramId] != 0) revert IAppErrors.AlreadyInitialized();
    _S().guildsParam[paramId] = uint160(value);
  }
  //endregion ------------------------ Gov actions

  //region ------------------------ Guild requests
  /// @notice User sends request to join to the guild. Assume approve on guild-request deposit amount.
  /// @dev User is able to send multiple requests. But any user can belong to single guild only.
  /// Any attempts to accept request for the user that is already member of a guild will revert.
  /// @param userMessage Any info provided by the user to the guild
  function addGuildRequest(
    bool isEoa,
    IController controller,
    address msgSender,
    uint guildId,
    string memory userMessage
  ) internal {
    _onlyEoa(isEoa);
    _notPaused(controller);
    _onlyNotGuildMember(msgSender);

    if (bytes(userMessage).length >= MAX_GUILD_REQUEST_MESSAGE_LENGTH) revert IAppErrors.TooLongString();

    uint depositAmount = getGuildRequestDepositAmount(guildId);
    if (depositAmount != 0) {
      // take deposit from user
      IERC20(controller.gameToken()).transferFrom(msgSender, _S().guildBanks[guildId], depositAmount);
    }

    // register new guild request
    uint guildRequestId = _generateGuildId(IGuildController.GuildsParams.COUNTER_GUILD_REQUESTS_3);
    _S().guildRequests[guildId][IGuildController.GuildRequestStatus.NONE_0].add(guildRequestId);
    _S().userActiveGuildRequests[msgSender].add(guildRequestId);
    _S().guildRequestData[guildRequestId] = IGuildController.GuildRequestData({
      guildId: guildId,
      user: msgSender,
      userMessage: userMessage,
      status: IGuildController.GuildRequestStatus.NONE_0
    });

    emit IApplicationEvents.GuildRequestRegistered(msgSender, guildId, userMessage, depositAmount);
  }

  /// @notice Guild owner or user with permissions accepts guild request and so add the user to the guild
  /// Guild-request is marked as accepted and removed from the list of user guild requests
  /// @param maskRights Set of rights of the new guild member.
  /// if NOT-admin accepts the request then {maskRights} should be equal to 0.
  /// Admin is able to set any value of {maskRights} except ADMIN_0
  function acceptGuildRequest(IController controller, address msgSender, uint guildRequestId, uint maskRights) internal {
    _changeGuildRequestStatus(controller, msgSender, guildRequestId, true, maskRights);
  }

  /// @notice Guild owner or user with permissions rejects guild request and so doesn't add the user to the guild
  /// Guild-request is marked as rejected and removed from the list of user guild requests
  function rejectGuildRequest(IController controller, address msgSender, uint guildRequestId) internal {
    _changeGuildRequestStatus(controller, msgSender, guildRequestId, false, 0);
  }

  /// @notice The user cancels his guild request.
  /// Guild-request is marked as canceled and removed from the list of user guild requests
  function cancelGuildRequest(IController controller, address msgSender, uint guildRequestId) internal {
    IGuildController.GuildRequestData storage requestData = _S().guildRequestData[guildRequestId];
    if (msgSender != requestData.user) revert IAppErrors.GuildRequestNotAvailable();
    _notPaused(controller);

    _setGuildRequestStatus(
      msgSender,
      requestData,
      requestData.guildId,
      guildRequestId,
      IGuildController.GuildRequestStatus.CANCELED_3,
      msgSender
    );
  }

  function setGuildRequestDepositAmount(IController controller, address msgSender, uint amount) external {
    (uint guildId,) = _checkPermissions(controller, msgSender, IGuildController.GuildRightBits.SET_GUILD_PARAMS_11);

    _S().guildRequestDepositAmounts[guildId] = IGuildController.GuildRequestDeposit({
      initialized: true,
      amount: uint192(amount)
    });

    emit IApplicationEvents.SetGuildRequestDepositAmount(guildId, msgSender, amount);
  }
  //endregion ------------------------ Guild requests

  //region ------------------------ Guild requests internal
  function _changeGuildRequestStatus(IController controller, address msgSender, uint guildRequestId, bool accept, uint maskRights) internal {
    (uint guildId, uint msgSenderRights) = _checkPermissions(controller, msgSender, IGuildController.GuildRightBits.ADD_MEMBER_4);

    IGuildController.GuildRequestData storage requestData = _S().guildRequestData[guildRequestId];
    if (guildId != requestData.guildId) revert IAppErrors.WrongGuild();
    address user = requestData.user;

    _setGuildRequestStatus(
      msgSender,
      requestData,
      guildId,
      guildRequestId,
      accept ? IGuildController.GuildRequestStatus.ACCEPTED_1 : IGuildController.GuildRequestStatus.REJECTED_2,
      user
    );

    if (accept) {
      if (maskRights != 0 && (msgSenderRights & _getMaskRights(IGuildController.GuildRightBits.ADMIN_0)) == 0) revert IAppErrors.NotAdminCannotAddMemberWithNotZeroRights();
      _addGuildMember(guildId, user, maskRights);
    }
  }

  /// @notice Add new member to the guild to which msgSender belongs
  function _addGuildMember(uint guildId, address newUser, uint maskRights) internal {
    IGuildController.GuildData memory guildData = _S().guildData[guildId];
    _onlyNotGuildMember(newUser);

    if ((maskRights & _getMaskRights(IGuildController.GuildRightBits.ADMIN_0)) != 0) revert IAppErrors.SecondGuildAdminIsNotAllowed();

    uint guildSize = _S().members[guildId].length();
    if (guildSize == _getMaxMembersNumber(guildData.guildLevel)) revert IAppErrors.GuildHasMaxSize(guildSize);

    _S().members[guildId].add(newUser);
    _S().memberToGuild[newUser] = guildId;
    _S().rights[newUser] = maskRights;

    emit IApplicationEvents.AddToGuild(guildId, newUser);
  }

  /// @notice Change status of the guild request, unregister it from the list of active user requests, return deposit
  function _setGuildRequestStatus(
    address msgSender,
    IGuildController.GuildRequestData storage requestData,
    uint guildId,
    uint guildRequestId,
    IGuildController.GuildRequestStatus newStatus,
    address user
  ) internal {
    mapping(IGuildController.GuildRequestStatus => EnumerableSet.UintSet) storage guildRequests = _S().guildRequests[guildId];
    if (!guildRequests[IGuildController.GuildRequestStatus.NONE_0].contains(guildRequestId)) {
      revert IAppErrors.GuildRequestNotActive();
    }

    // move request to the list with different status
    // guild owner should always be able to view any request and access user-message-info stored in the request-data
    guildRequests[IGuildController.GuildRequestStatus.NONE_0].remove(guildRequestId);
    guildRequests[newStatus].add(guildRequestId);
    requestData.status = newStatus;

    _S().userActiveGuildRequests[user].remove(guildRequestId);

    emit IApplicationEvents.GuildRequestStatusChanged(msgSender, guildRequestId, uint8(newStatus), user);
  }
  //endregion ------------------------ Guild requests internal

  //region ------------------------ Actions

  /// @notice Create new guild, return ID of the new guild
  /// @param toHelperRatio Percent of fee for guild reinforcement. Value in range [_FEE_MIN ... _TO_HELPER_RATIO_MAX]
  function createGuild(
    bool isEoa,
    IController controller,
    address msgSender,
    string memory name,
    string memory urlLogo,
    uint8 toHelperRatio
  ) internal returns (uint) {
    _onlyEoa(isEoa);
    _notPaused(controller);

    // user can be a member of a single guild only
    _onlyNotGuildMember(msgSender);
    _onlyFreeValidGuildName(name);
    validateToHelperRatio(toHelperRatio);
    _onlyValidLogo(urlLogo);

    uint guildId = _generateGuildId(IGuildController.GuildsParams.COUNTER_GUILD_IDS_1);
    IGuildController.GuildData memory guildData = IGuildController.GuildData({
      owner: msgSender,
      urlLogo: urlLogo,
      guildName: name,
      guildLevel: FIRST_LEVEL,
      pvpCounter: 0,
      toHelperRatio: toHelperRatio
    });

    _S().guildData[guildId] = guildData;
    _S().nameToGuild[name] = guildId;

    _S().members[guildId].add(msgSender);
    _S().memberToGuild[msgSender] = guildId;
    _S().rights[msgSender] = _getMaskRights(IGuildController.GuildRightBits.ADMIN_0);

    _S().guildBanks[guildId] = _deployNewGuildBank(controller.guildController(), guildId);

    // pay base fee for guild creation
    _process(controller, getBaseFee(), msgSender);

    emit IApplicationEvents.GuildCreated(guildData.owner, guildId, guildData.guildName, guildData.urlLogo);

    return guildId;
  }

  /// @notice Edit roles of the given member of the guild to which msgSender belongs
  function changeRoles(IController controller, address msgSender, address user, uint maskRights) external {
    (uint senderGuildId, uint senderRights) = _checkPermissions(controller, msgSender, IGuildController.GuildRightBits.CHANGE_ROLES_7);
    (uint userGuildId, uint userRights, bool isUserAdmin) = _hasPermission(user, IGuildController.GuildRightBits.ADMIN_0);
    if (senderGuildId != userGuildId) revert IAppErrors.NotGuildMember();

    if (
      // don't allow to change rights of the owner
      // owner is not able to change even own rights - his rights should be ADMIN_0 always
      isUserAdmin

      // don't allow to set admin rights to any other user - assume, that there is only 1 admin = owner of the guild
      || ((maskRights & _getMaskRights(IGuildController.GuildRightBits.ADMIN_0)) != 0)
    ) revert IAppErrors.ErrorForbidden(user);

    if ((senderRights & _getMaskRights(IGuildController.GuildRightBits.ADMIN_0)) == 0) {
      if (
        // don't allow to change ANY rights of the user with users-control permissions
        ((userRights & _getMaskRights(IGuildController.GuildRightBits.CHANGE_ROLES_7)) != 0)
        || ((userRights & _getMaskRights(IGuildController.GuildRightBits.REMOVE_MEMBER_5)) != 0)

        // don't allow to set users-control permissions
        || ((maskRights & _getMaskRights(IGuildController.GuildRightBits.CHANGE_ROLES_7)) != 0)
        || ((maskRights & _getMaskRights(IGuildController.GuildRightBits.REMOVE_MEMBER_5)) != 0)
      ) revert IAppErrors.AdminOnly();
    }

    _S().rights[user] = maskRights;

    emit IApplicationEvents.ChangeGuildRights(senderGuildId, user, maskRights);
  }

  /// @notice Remove given member from the guild to which msgSender belongs
  /// @dev To delete the guild the owner should remove all members and remove himself at the end
  function removeGuildMember(IController controller, address msgSender, address userToRemove) internal {
    uint guildId;
    if (msgSender == userToRemove) {
      _notPaused(controller);
      guildId = _getValidGuildId(msgSender, true); // user is always able to remove himself from a guild
    } else {
      uint maskRights;
      (guildId, maskRights) = _checkPermissions(controller, msgSender, IGuildController.GuildRightBits.REMOVE_MEMBER_5);
      _onlyNotZeroAddress(userToRemove);

      (uint userGuildId, uint userRights, bool admin) = _hasPermission(userToRemove, IGuildController.GuildRightBits.ADMIN_0);
      if (
        admin
        || userGuildId != guildId
        || (( // don't allow not-admin to remove a user with users-control permissions
            ((userRights & _getMaskRights(IGuildController.GuildRightBits.CHANGE_ROLES_7)) != 0)
            || ((userRights & _getMaskRights(IGuildController.GuildRightBits.REMOVE_MEMBER_5)) != 0)
          ) && (
            ((maskRights & _getMaskRights(IGuildController.GuildRightBits.ADMIN_0)) == 0)
        ))
      ) revert IAppErrors.ErrorForbidden(userToRemove);
    }

    IGuildController.GuildData memory guildData = _S().guildData[guildId];
    if (guildData.owner == userToRemove) {
      // owner can be removed by the last one only
      if (_S().members[guildId].length() > 1) revert IAppErrors.CannotRemoveGuildOwnerFromNotEmptyGuild();
    }

    _S().members[guildId].remove(userToRemove);
    delete _S().memberToGuild[userToRemove];
    delete _S().rights[userToRemove];

    emit IApplicationEvents.RemoveFromGuild(guildId, userToRemove);

    // Removed member can have staked heroes in guild reinforcement.
    // The heroes are NOT withdrawn automatically, the member is responsible to withdraw them himself
    // All rewards for staked heroes will continue to be transferred to guild bank until the heroes are withdrawn.

    uint guildSize = _S().members[guildId].length();
    if (guildSize == 0) {
      _deleteGuild(guildId, guildData);
    }
  }

  /// @notice Increment level of the guild, pay base_fee * new level
  function guildLevelUp(IController controller, address msgSender) internal {
    (uint guildId,) = _checkPermissions(controller, msgSender, IGuildController.GuildRightBits.LEVEL_UP_8);

    uint8 oldGuildLevel = _S().guildData[guildId].guildLevel;
    if (oldGuildLevel == MAX_LEVEL) revert IAppErrors.GuildHasMaxLevel(oldGuildLevel);

    // level up
    uint8 guildLevel = oldGuildLevel + 1;
    _S().guildData[guildId].guildLevel = guildLevel;

    // pay for level up
    _process(controller, getBaseFee() * guildLevel, msgSender);

    emit IApplicationEvents.GuildLevelUp(guildId, guildLevel);
  }

  /// @notice Rename the guild, pay base_fee
  function rename(IController controller, address msgSender, string memory newGuildName) internal {
    (uint guildId,) = _checkPermissions(controller, msgSender, IGuildController.GuildRightBits.RENAME_1);
    _onlyFreeValidGuildName(newGuildName);

    // rename
    string memory oldGuildName = _S().guildData[guildId].guildName;
    delete _S().nameToGuild[oldGuildName]; // old name is free to use now

    _S().guildData[guildId].guildName = newGuildName;
    _S().nameToGuild[newGuildName] = guildId;

    // pay for renaming
    _process(controller, getBaseFee(), msgSender);

    emit IApplicationEvents.GuildRename(guildId, newGuildName);
  }

  /// @notice Free change of the guild logo
  function changeLogo(IController controller, address msgSender, string memory newLogoUrl) internal {
    (uint guildId,) = _checkPermissions(controller, msgSender, IGuildController.GuildRightBits.CHANGE_LOGO_2);

    _onlyValidLogo(newLogoUrl);

    // free change (no payment)
    _S().guildData[guildId].urlLogo = newLogoUrl;

    emit IApplicationEvents.GuildLogoChanged(guildId, newLogoUrl);
  }

  /// @notice Free change of the guild description
  function changeDescription(IController controller, address msgSender, string memory newDescription) internal {
    (uint guildId,) = _checkPermissions(controller, msgSender, IGuildController.GuildRightBits.RENAME_1);

    if (bytes(newDescription).length >= MAX_DESCRIPTION_LENGTH) revert IAppErrors.TooLongDescription();

    _S().guildDescription[guildId] = newDescription;

    emit IApplicationEvents.GuildDescriptionChanged(guildId, newDescription);
  }

  /// @notice Set relation between two guilds
  function setRelation(IController controller, address msgSender, uint otherGuildId, bool peace) internal {
    (uint guildId,) = _checkPermissions(controller, msgSender, IGuildController.GuildRightBits.SET_RELATION_KIND_9);

    // todo check alliances: it's not allowed to set war-relation to the co-member of the alliance

    _S().relationsPeaceful[_getGuildsPairKey(guildId, otherGuildId)] = peace;

    emit IApplicationEvents.SetGuildRelation(guildId, otherGuildId, peace);
  }

  function setToHelperRatio(IController controller, address msgSender, uint8 value) external {
    (uint guildId,) = _checkPermissions(controller, msgSender, IGuildController.GuildRightBits.SET_GUILD_PARAMS_11);
    validateToHelperRatio(value);

    _S().guildData[guildId].toHelperRatio = value;

    emit IApplicationEvents.SetToHelperRatio(guildId, value, msgSender);
  }

  function setPvpPointsCapacity(IController controller, address msgSender, uint64 capacityPvpPoints, address[] memory users) external {
    (uint senderGuildId,) = _checkPermissions(controller, msgSender, IGuildController.GuildRightBits.CHANGE_PURCHASING_SHELTER_ITEMS_CAPACITY_12);

    uint len = users.length;
    for (uint i; i < len; ++i) {
      uint userGuildId = _S().memberToGuild[users[i]];
      if (senderGuildId != userGuildId) revert IAppErrors.NotGuildMember();

      _S().userPvpPoints[senderGuildId][users[i]].capacityPvpPoints = capacityPvpPoints;
    }

    emit IApplicationEvents.SetPvpPointsCapacity(msgSender, capacityPvpPoints, users);
  }

  function transferOwnership(IController controller, address msgSender, address newAdmin) external {
    (uint oldAdminGuildId,) = _checkPermissions(controller, msgSender, IGuildController.GuildRightBits.ADMIN_0);
    uint newAdminGuildId = _getValidGuildId(newAdmin, true);
    if (oldAdminGuildId != newAdminGuildId) revert IAppErrors.WrongGuild();

    _S().rights[msgSender] = 0;
    _S().rights[newAdmin] = _getMaskRights(IGuildController.GuildRightBits.ADMIN_0);
    _S().guildData[oldAdminGuildId].owner = newAdmin;
  }
  //endregion ------------------------ Actions

  //region ------------------------ Guild bank
  /// @notice Deploy guild bank contract instance
  function _deployNewGuildBank(address guildController, uint guildId) internal returns (address deployed) {
    // Assume that this internal function can be called by GuildController only, so there are no restriction checks here
    deployed = address(new GuildBank(guildController, guildId));

    emit IApplicationEvents.GuildBankDeployed(guildId, deployed);
  }

  /// @notice Transfer given {amount} of {token} from guild bank to {recipient}
  function transfer(IController controller, address msgSender, address token, address recipient, uint amount) internal {
    IGuildBank guildBank = _getGuildBankCheckBankOperationPermission(controller, msgSender, IGuildController.GuildRightBits.BANK_TOKENS_OPERATION_6);
    _transferFromGuildBank(guildBank, msgSender, token, recipient, amount);
  }

  function transferMulti(IController controller, address msgSender, address token, address[] memory recipients, uint[] memory amounts) internal {
    IGuildBank guildBank = _getGuildBankCheckBankOperationPermission(controller, msgSender, IGuildController.GuildRightBits.BANK_TOKENS_OPERATION_6);

    uint len = recipients.length;
    if (len != amounts.length) revert IAppErrors.LengthsMismatch();

    for (uint i; i < len; ++i) {
      _transferFromGuildBank(guildBank, msgSender, token, recipients[i], amounts[i]);
    }
  }

  /// @notice Transfer given {nfts} from guild bank to {recipient}
  function transferNftMulti(IController controller, address msgSender, address recipient, address[] memory nfts, uint256[] memory tokenIds) internal {
    IGuildBank guildBank = _getGuildBankCheckBankOperationPermission(controller, msgSender, IGuildController.GuildRightBits.BANK_ITEMS_OPERATION_10);

    guildBank.transferNftMulti(recipient, nfts, tokenIds);
    emit IApplicationEvents.TransferNftFromGuildBank(msgSender, nfts, tokenIds, recipient);
  }

  function topUpGuildBank(IController controller, address msgSender, address token, uint amount) internal {
    // no restrictions - any guild member is allowed to top up balance of the guild bank
    _notPaused(controller);

    if (amount != 0) {
      uint guildId = _getValidGuildId(msgSender, true);
      IGuildBank guildBank = IGuildBank(_S().guildBanks[guildId]);

      IERC20(token).transferFrom(msgSender, address(guildBank), amount);
      emit IApplicationEvents.TopUpGuildBank(msgSender, guildId, address(guildBank), amount);
    }
  }

  //endregion ------------------------ Guild bank

  //region ------------------------ Shelters

  function usePvpPoints(uint guildId, address user, uint64 priceInPvpPoints) external {
    _onlyShelterController();

    // the guild should have enough PVP points
    IGuildController.GuildData storage guildData = _S().guildData[guildId];
    uint64 pvpCounter = guildData.pvpCounter;
    if (pvpCounter < priceInPvpPoints) revert IAppErrors.GuildHasNotEnoughPvpPoints(pvpCounter, priceInPvpPoints);

    guildData.pvpCounter = pvpCounter - priceInPvpPoints;

    // the user should have permission to use required amount of PVP-points from the guild balance
    IGuildController.UserPvpPoints storage userPvpPoints = _S().userPvpPoints[guildId][user];
    IGuildController.UserPvpPoints memory pvpPointsLocal = userPvpPoints;

    if (pvpPointsLocal.spentPvpPoints + priceInPvpPoints > pvpPointsLocal.capacityPvpPoints && guildData.owner != user) {
      revert IAppErrors.NotEnoughPvpPointsCapacity(user, pvpPointsLocal.spentPvpPoints, priceInPvpPoints, pvpPointsLocal.capacityPvpPoints);
    }

    userPvpPoints.spentPvpPoints = pvpPointsLocal.spentPvpPoints + priceInPvpPoints;
  }

  /// @notice pay for the shelter from the guild bank
  function payFromGuildBank(IController controller, uint guildId, uint shelterPrice) external {
    _onlyShelterController();

    address gameToken = controller.gameToken();

    address guildBank = getGuildBank(guildId);
    if (IERC20(gameToken).balanceOf(guildBank) < shelterPrice) revert IAppErrors.NotEnoughGuildBankBalance(guildId);

    IGuildBank(guildBank).approve(gameToken, address(controller), shelterPrice);
    controller.process(gameToken, shelterPrice, guildBank);
  }

  function payFromBalance(IController controller, uint amount, address from) internal {
    _onlyShelterController();

    _process(controller, amount, from);
  }

  function payForAuctionBid(IController controller, uint guildId, uint amount, uint bid) external {
    address shelterAuction = _shelterAuctionController();
    if (shelterAuction == address(0)) revert IAppErrors.NotInitialized();

    if (msg.sender != shelterAuction) revert IAppErrors.OnlyShelterAuction();

    if (amount != 0) {
      address guildBank = getGuildBank(guildId);
      IGuildBank(guildBank).transfer(controller.gameToken(), shelterAuction, amount);

      emit IApplicationEvents.PayForBidFromGuildBank(guildId, amount, bid);
    }
  }

  //endregion ------------------------ Shelters

  //region ------------------------ Internal logic
  /// @notice Check if the {user} has given permission in the guild. Permissions are specified by bitmask {rights}.
  /// Admin is marked by zero bit, he has all permissions always.
  function _checkPermissions(IController controller, address user, IGuildController.GuildRightBits right) internal view returns (uint guildId, uint rights) {
    _notPaused(controller);

    bool userHasRight;
    (guildId, rights, userHasRight) = _hasPermission(user, right);
    if (guildId == 0) revert IAppErrors.NotGuildMember();
    if (!userHasRight) {
      revert IAppErrors.GuildActionForbidden(uint(right));
    }
  }

  /// @notice Check if the {user} has given permission in the guild, no revert.
  function _hasPermission(address user, IGuildController.GuildRightBits rightBit) internal view returns (uint guildId, uint rights, bool userHasRight) {
    guildId = _getValidGuildId(user, false);
    rights = _S().rights[user];
    userHasRight = (
      (rights & _getMaskRights(IGuildController.GuildRightBits.ADMIN_0)) != 0
      || (rights & _getMaskRights(rightBit)) != 0
    );
  }

  function _getValidGuildId(address user, bool revertOnZero) internal view returns (uint guildId) {
    guildId = _S().memberToGuild[user];
    if (guildId == 0 && revertOnZero) revert IAppErrors.NotGuildMember();
  }

  function _getGuildBankCheckBankOperationPermission(
    IController controller,
    address user,
    IGuildController.GuildRightBits right
  ) internal view returns (IGuildBank guildBank) {
    (uint guildId,) = _checkPermissions(controller, user, right);
    return IGuildBank(_S().guildBanks[guildId]);
  }

  /// @notice Max number of guild members depends on guildLevel as 25 + 5 * level
  function _getMaxMembersNumber(uint8 guildLevel) internal pure returns (uint) {
    return MAX_GUILD_MEMBERS_ON_LEVEL_1 + (guildLevel - 1) * MAX_GUILD_MEMBERS_INC_PER_LEVEL;
  }

  /// @notice Generate unique pair key for (G1, G2). Guarantee that F(G1, G2) == F(G2, G1)
  function _getGuildsPairKey(uint guildId1, uint guildId2) internal pure returns (bytes32) {
    return guildId1 < guildId2
      ? keccak256(abi.encodePacked(guildId1, guildId2))
      : keccak256(abi.encodePacked(guildId2, guildId1));
  }

  /// @notice Generate mask-rights with given permission
  function _getMaskRights(IGuildController.GuildRightBits right) internal pure returns (uint) {
    return 2 ** uint(right);
  }

  function validateToHelperRatio(uint8 toHelperRatio) internal pure {
    if (toHelperRatio > ReinforcementControllerLib._TO_HELPER_RATIO_MAX) revert IAppErrors.MaxFee(toHelperRatio);
    if (toHelperRatio < ReinforcementControllerLib._FEE_MIN) revert IAppErrors.MinFee(toHelperRatio);
  }

  function _process(IController controller, uint amount, address from) internal {
    controller.process(controller.gameToken(), amount, from);
  }

  /// @notice Delete the guild as soon as last member has left it
  function _deleteGuild(uint guildId, IGuildController.GuildData memory guildData) internal{

    delete _S().nameToGuild[guildData.guildName];
    delete _S().guildData[guildId];

    // guild bank is not cleared, guildId is never reused

    IShelterController sc = IShelterController(_shelterController());
    if (address(sc) != address(0)) {
      sc.clearShelter(guildId);
    }

    // ensure that the guild has no bid to purchase any shelter
    address shelterAuction = _shelterAuctionController();
    if (shelterAuction != address(0)) {
      (uint positionId, ) = IShelterAuction(shelterAuction).positionByBuyer(guildId);
      if (positionId != 0) revert IAppErrors.AuctionBidOpened(positionId);
    }

    emit IApplicationEvents.GuildDeleted(guildId);
  }

  /// @notice Generate id for new guild, increment id-counter
  /// @dev uint is used to store id. In the code of auction we assume that it's safe to use uint128 to store such ids
  function _generateGuildId(IGuildController.GuildsParams guildParamId) internal returns (uint uid) {
    uid = _S().guildsParam[guildParamId] + 1;
    _S().guildsParam[guildParamId] = uid;
  }

  function _shelterController() internal view returns (address) {
    return address(uint160(_S().guildsParam[IGuildController.GuildsParams.SHELTER_CONTROLLER_5]));
  }

  function _shelterAuctionController() internal view returns (address) {
    return address(uint160(_S().guildsParam[IGuildController.GuildsParams.SHELTER_AUCTION_6]));
  }

  function _transferFromGuildBank(IGuildBank guildBank, address msgSender, address token, address recipient, uint amount) internal {
    if (amount != 0) {
      _onlyNotZeroAddress(recipient);
      guildBank.transfer(token, recipient, amount);
      emit IApplicationEvents.TransferFromGuildBank(msgSender, token, amount, recipient);
    }
  }
  //endregion ------------------------ Internal logic
}
