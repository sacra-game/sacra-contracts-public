// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IDungeonFactory.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IHero.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IReinforcementController.sol";
import "../interfaces/IRewardsPool.sol";
import "../interfaces/IStatController.sol";
import "../lib/StringLib.sol";
import "./PackingLib.sol";

library HeroLib {
  using PackingLib for int32[];
  using PackingLib for bytes32[];
  using PackingLib for address;
  using PackingLib for bytes32;

  //region ------------------------ Constants
  /// @dev keccak256(abi.encode(uint256(keccak256("hero.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant HERO_CONTROLLER_STORAGE_LOCATION = 0xd333325b749986e76669f0e0c2c1aa0e0abd19e216c3678477196e4089241400;
  uint public constant KILL_PENALTY = 70;

  uint8 public constant TIER_DEFAULT = 0;
  uint8 public constant TIER_1 = 1;
  uint8 public constant TIER_2 = 2;
  uint8 public constant TIER_3 = 3;

  uint8 internal constant MAX_NG_LEVEL = 99;

  /// @notice Cost of level up in game token, final amount is adjusted by game token price
  /// @dev The case: payToken for the hero is changed, postpaid hero makes level up, base amount should be paid.
  uint public constant BASE_AMOUNT_LEVEL_UP = 10e18;
  //endregion ------------------------ Constants

  //region ------------------------ Storage

  function _S() internal pure returns (IHeroController.MainState storage s) {
    assembly {
      s.slot := HERO_CONTROLLER_STORAGE_LOCATION
    }
    return s;
  }
  //endregion ------------------------ Storage

  //region ------------------------ Restrictions
  function onlyEOA(bool isEoa) internal view {
    if (!isEoa) {
      revert IAppErrors.NotEOA(msg.sender);
    }
  }

  function onlyDeployer(IController controller) internal view {
    if (! controller.isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }

  function onlyDungeonFactory(IDungeonFactory dungeonFactory, address sender) internal pure {
    if (address(dungeonFactory) != sender) revert IAppErrors.ErrorNotDungeonFactory(sender);
  }

  function onlyDungeonFactoryOrPvpController(IController controller, address sender) internal view {
    if (
      address(_getDungeonFactory(controller)) != sender
      && address(_getPvpController(controller)) != sender
    ) revert IAppErrors.ErrorNotAllowedSender();
  }

  function onlyOwner(address token, uint tokenId, address sender) internal view {
    if (IERC721(token).ownerOf(tokenId) != sender) revert IAppErrors.ErrorNotOwner(token, tokenId);
  }

  function onlyNotStaked(IController controller_, address hero, uint heroId) internal view {
    if (_getReinforcementController(controller_).isStaked(hero, heroId)) revert IAppErrors.Staked(hero, heroId);

    IPvpController pc = _getPvpController(controller_);
    if (address(pc) != address(0) && pc.isHeroStakedCurrently(hero, heroId)) revert IAppErrors.PvpStaked();
  }

  function checkSandboxMode(bytes32 packedHero, bool sandboxRequired) internal view {
    bool isSandboxMode = _S().sandbox[packedHero] == IHeroController.SandboxMode.SANDBOX_MODE_1;

    if (isSandboxMode != sandboxRequired) {
      if (sandboxRequired) {
        revert IAppErrors.SandboxModeRequired();
      } else {
        revert IAppErrors.SandboxModeNotAllowed();
      }
    }
  }

  function onlyInDungeon(IDungeonFactory dungeonFactory, address hero, uint heroId) internal view {
    if (dungeonFactory.currentDungeon(hero, heroId) == 0) revert IAppErrors.ErrorHeroNotInDungeon();
  }

  function onlyNotInDungeon(IDungeonFactory dungeonFactory, address hero, uint heroId) internal view {
    if (dungeonFactory.currentDungeon(hero, heroId) != 0) revert IAppErrors.HeroInDungeon();
  }

  function isAllowedToTransfer(IController controller_, address hero, uint heroId) internal view returns (bool) {
    onlyNotInDungeon(IDungeonFactory(controller_.dungeonFactory()), hero, heroId);
    if (
      IStatController(controller_.statController()).heroItemSlots(hero, heroId).length != 0
    ) revert IAppErrors.EquippedItemsExist();
    onlyNotStaked(controller_, hero, heroId);
    return true;
  }

  function onlyRegisteredHero(address hero) internal view {
    if (_S().heroClass[hero] == 0) revert IAppErrors.ErrorHeroIsNotRegistered(hero);
  }

  function _checkRegisteredNotPaused(IController c, address hero) internal view {
    onlyRegisteredHero(hero);
    if (c.onPause()) revert IAppErrors.ErrorPaused();
  }

  function onlyAlive(IStatController statController, address hero, uint heroId) internal view {
    if (!statController.isHeroAlive(hero, heroId)) revert IAppErrors.ErrorHeroIsDead(hero, heroId);
  }

  function _checkOutDungeonNotStakedAlive(IController c, address hero, uint heroId) internal view returns (
    IDungeonFactory dungFactory,
    IStatController statController
  ) {
    dungFactory = IDungeonFactory(c.dungeonFactory());
    statController = IStatController(c.statController());

    onlyNotInDungeon(dungFactory, hero, heroId);
    onlyNotStaked(c, hero, heroId);
    onlyAlive(statController, hero, heroId);
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Views
  function getHeroInfo(address hero, uint heroId) internal view returns (IHeroController.HeroInfo memory data) {
    return _S().heroInfo[PackingLib.packNftId(hero, heroId)];
  }

  function maxOpenedNgLevel() internal view returns (uint) {
    return _S().maxOpenedNgLevel;
  }

  /// @return time stamp of the moment when the boss of the given biome at the given NG_LEVEL was killed by the hero
  function killedBosses(address hero, uint heroId, uint8 biome, uint8 ngLevel) internal view returns (uint) {
    return _S().killedBosses[PackingLib.packNftId(hero, heroId)][PackingLib.packUint8Array3(uint8(biome), ngLevel, 0)];
  }

  function maxUserNgLevel(address user) internal view returns (uint) {
    return _S().maxUserNgLevel[user];
  }

  function helperSkills(address hero, uint heroId) internal view returns (
    address[] memory items,
    uint[] memory itemIds,
    uint[] memory slots
  ) {
    bytes32[] memory skills = _S().helperSkills[PackingLib.packNftId(hero, heroId)];
    uint len = skills.length;
    if (len != 0) {
      items = new address[](len);
      itemIds = new uint[](len);
      slots = new uint[](len);
      for (uint i; i < len; ++i) {
        (items[i], itemIds[i], slots[i]) = skills[i].unpackNftIdWithValue();
      }
    }

    return (items, itemIds, slots);
  }
  //endregion ------------------------ Views

  //region ------------------------ Gov actions

  function registerHero(IController controller, address hero, uint8 heroClass, address payToken, uint payAmount) internal {
    onlyDeployer(controller);

    // pay token cannot be 0 even for free heroes
    // the reason: old F2P free heroes didn't have pay tokens, we should have a way to distinguish new heroes from them
    if (payToken == address(0)) revert IAppErrors.ZeroToken();

    _S().heroClass[hero] = heroClass;
    _S().payToken[hero] = payToken.packAddressWithAmount(payAmount);

    emit IApplicationEvents.HeroRegistered(hero, heroClass, payToken, payAmount);
  }
  //endregion ------------------------ Gov actions

  //region ------------------------ User actions: setBiome, levelUp
  /// @notice Set hero biome to {biome}, ensure that it's allowed
  /// @param msgSender Sender must be the owner of the hero
  /// @param biome New biome value: (0, maxBiomeCompleted + 1]
  function setBiome(bool isEoa, IController controller, address msgSender, address hero, uint heroId, uint8 biome) internal {
    onlyEOA(isEoa);
    onlyOwner(hero, heroId, msgSender);
    _checkRegisteredNotPaused(controller, hero);
    (IDungeonFactory dungFactory, ) = _checkOutDungeonNotStakedAlive(controller, hero, heroId);

    if (biome == 0 || biome > dungFactory.maxAvailableBiome()) revert IAppErrors.ErrorIncorrectBiome(biome);

    uint8 maxBiomeCompleted = dungFactory.maxBiomeCompleted(hero, heroId);
    if (biome > maxBiomeCompleted + 1) revert IAppErrors.TooHighBiome(biome);

    _S().heroBiome[hero.packNftId(heroId)] = biome;
    emit IApplicationEvents.BiomeChanged(hero, heroId, biome);
  }

  /// @notice Set level up according to {change}, call process() to take (payTokenAmount * level) from the sender
  function levelUp(
    bool isEoa,
    IController controller,
    address msgSender,
    address hero,
    uint heroId,
    IStatController.CoreAttributes memory change
  ) internal {
    onlyEOA(isEoa);
    onlyOwner(hero, heroId, msgSender);
    _checkRegisteredNotPaused(controller, hero);
    _checkOutDungeonNotStakedAlive(controller, hero, heroId);

    IHeroController.HeroInfo memory heroInfo = getHeroInfo(hero, heroId);

    // update stats
    IStatController _statController = _getStatController(controller);
    uint level = _statController.levelUp(hero, heroId, _S().heroClass[hero], change);

    // NG+ has free level up
    // all heroes created before NG+ and not upgraded to NG+ require payment as before
    if (heroInfo.tier == HeroLib.TIER_DEFAULT) {
      address gameToken = controller.gameToken();
      (address token, uint payTokenAmount) = _S().payToken[hero].unpackAddressWithAmount();
      if (token == address(0)) revert IAppErrors.NoPayToken(token, payTokenAmount);

      if (token != gameToken) {
        token = gameToken;
        payTokenAmount = BASE_AMOUNT_LEVEL_UP;
      }

      uint amount = payTokenAmount * level;
      controller.process(token, amount, msgSender);
    }

    emit IApplicationEvents.LevelUp(hero, heroId, msgSender, change);
  }

  //endregion ------------------------ User actions: setBiome, levelUp

  //region ------------------------ User actions: reinforcement
  function _askReinforcement(IController controller, address hero, uint heroId, bool guildReinforcement, address helper, uint helperId) internal {
    _checkRegisteredNotPaused(controller, hero);

    onlyInDungeon(_getDungeonFactory(controller), hero, heroId);

    bytes32 packedHero = hero.packNftId(heroId);
    if (_S().reinforcementHero[packedHero] != bytes32(0)) revert IAppErrors.AlreadyHaveReinforcement();

    IStatController _statController = _getStatController(controller);
    IReinforcementController rc = _getReinforcementController(controller);

    // Save all skills equipped on the hero's helper at the moment of asking reinforcement
    _S().helperSkills[packedHero] = _getHeroSkills(_statController, helper, helperId);

    // scb-1009: Life and mana are restored during reinforcement as following:
    // Reinforcement increases max value of life/mana on DELTA, current value of life/mana is increased on DELTA too
    int32[] memory helpAttributes;
    helpAttributes = guildReinforcement
      ? rc.askGuildHero(hero, heroId, helper, helperId)
      : rc.askHeroV2(hero, heroId, helper, helperId);

    int32[] memory attributes = _statController.heroAttributes(hero, heroId);

    _statController.changeBonusAttributes(IStatController.ChangeAttributesInfo({
      heroToken: hero,
      heroTokenId: heroId,
      changeAttributes: helpAttributes,
      add: true,
      temporally: false
    }));

    _S().reinforcementHero[packedHero] = helper.packNftId(helperId);
    _S().reinforcementHeroAttributes[packedHero] = helpAttributes.toBytes32Array();

    // restore life and mana to default values from the total attributes
    _statController.restoreLifeAndMana(hero, heroId, attributes);

    if (guildReinforcement) {
      emit IApplicationEvents.GuildReinforcementAsked(hero, heroId, helper, helperId);
    } else {
      emit IApplicationEvents.ReinforcementAsked(hero, heroId, helper, helperId);
    }
  }

  /// @notice Release any reinforcement (v1, v2 or guild)
  function releaseReinforcement(IController controller, address msgSender, address hero, uint heroId) internal returns (
    address helperToken,
    uint helperId
  ) {
    onlyDungeonFactory(_getDungeonFactory(controller), msgSender);
    onlyRegisteredHero(hero);

    bytes32 packedId = hero.packNftId(heroId);

    (helperToken, helperId) = _S().reinforcementHero[packedId].unpackNftId();

    if (helperToken != address(0)) {
      IStatController _statController = _getStatController(controller);

      int32[] memory attributes = _S().reinforcementHeroAttributes[packedId].toInt32Array(uint(IStatController.ATTRIBUTES.END_SLOT));

      _statController.changeBonusAttributes(IStatController.ChangeAttributesInfo({
        heroToken: hero,
        heroTokenId: heroId,
        changeAttributes: attributes,
        add: false,
        temporally: false
      }));

      delete _S().helperSkills[packedId];
      delete _S().reinforcementHero[packedId];
      delete _S().reinforcementHeroAttributes[packedId];

      IReinforcementController rc = _getReinforcementController(controller);
      uint guildId = rc.busyGuildHelperOf(helperToken, helperId);
      if (guildId == 0) {
        emit IApplicationEvents.ReinforcementReleased(hero, heroId, helperToken, helperId);
      } else {
        rc.releaseGuildHero(helperToken, helperId);
        emit IApplicationEvents.GuildReinforcementReleased(hero, heroId, helperToken, helperId);
      }
    }
  }

  /// @notice Get all skills equipped by the hero
  /// @return skills List of packed items: (itemAddress, itemId, slot)
  function _getHeroSkills(IStatController statController, address hero, uint heroId) internal view returns (bytes32[] memory skills) {
    bytes32[] memory dest = new bytes32[](3); // SKILL_1, SKILL_2, SKILL_3
    uint len;
    for (uint8 i; i < 3; ++i) {
      bytes32 data = statController.heroItemSlot(hero, uint64(heroId), uint8(IStatController.ItemSlots.SKILL_1) + i);
      if (data != bytes32(0)) {
        (address item, uint itemId) = data.unpackNftId();
        dest[len++] = PackingLib.packNftIdWithValue(item, itemId, uint8(IStatController.ItemSlots.SKILL_1) + i);
      }
    }
    skills = new bytes32[](len);
    for (uint i; i < len; ++i) {
      skills[i] = dest[i];
    }
  }
  //endregion ------------------------ User actions: reinforcement

  //region ------------------------ Dungeon actions
  /// @return dropItems List of items (packed: item NFT address + item id)
  function kill(IController controller, address msgSender, address hero, uint heroId) internal returns (
    bytes32[] memory dropItems
  ) {
    onlyDungeonFactoryOrPvpController(controller, msgSender);
    onlyRegisteredHero(hero);

    IStatController statController = _getStatController(controller);
    dropItems = _takeOffAll(_getItemController(controller), statController, hero, heroId, msgSender, true);

    _resetLife(statController, hero, heroId, true, false);

    IHero(hero).burn(heroId);

    emit IApplicationEvents.Killed(hero, heroId, msgSender, dropItems, 0);
  }

  /// @notice Life => 1, mana => 0
  function resetLifeAndMana(IController controller, address msgSender, address hero, uint heroId) internal {
    onlyDungeonFactory(_getDungeonFactory(controller), msgSender);
    _resetLife(_getStatController(controller), hero, heroId, false, true);
  }
  //endregion ------------------------ Dungeon actions

  //region ------------------------ Kill internal

  function _resetLife(IStatController statController, address hero, uint heroId, bool decLifeChances, bool resetMana) internal {
    IStatController.ChangeableStats memory heroStats = statController.heroStats(hero, heroId);

    // set life to zero, reduce life-chances on 1
    statController.changeCurrentStats(
      hero,
      heroId,
      IStatController.ChangeableStats({
        level: 0,
        experience: 0,
        life: heroStats.life,
        mana: resetMana ? heroStats.mana : 0,
        lifeChances: decLifeChances ? 1 : 0
      }),
      false
    );
  }

  function _takeOffAll(
    IItemController ic,
    IStatController statController,
    address hero,
    uint heroId,
    address recipient,
    bool broken
  ) internal returns (bytes32[] memory items) {
    uint8[] memory busySlots = statController.heroItemSlots(hero, heroId);
    uint len = busySlots.length;
    items = new bytes32[](len);
    for (uint i; i < len; ++i) {
      bytes32 data = statController.heroItemSlot(hero, uint64(heroId), busySlots[i]);
      (address itemAdr, uint itemId) = data.unpackNftId();

      ic.takeOffDirectly(itemAdr, itemId, hero, heroId, busySlots[i], recipient, broken);
      items[i] = data;
    }
  }
  //endregion ------------------------ Kill internal

  //region ------------------------ Utils to reduce size contract
  function _getStatController(IController controller) internal view returns (IStatController) {
    return IStatController(controller.statController());
  }

  function _getDungeonFactory(IController controller) internal view returns (IDungeonFactory) {
    return IDungeonFactory(controller.dungeonFactory());
  }

  function _getReinforcementController(IController controller) internal view returns (IReinforcementController) {
    return IReinforcementController(controller.reinforcementController());
  }

  function _getPvpController(IController controller) internal view returns (IPvpController) {
    return IPvpController(controller.pvpController());
  }

  function _getItemController(IController controller) internal view returns (IItemController) {
    return IItemController(controller.itemController());
  }
  //endregion ------------------------ Utils to reduce size contract
}
