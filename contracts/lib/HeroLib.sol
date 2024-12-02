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

  //region ------------------------ Storage

  function _S() internal pure returns (IHeroController.MainState storage s) {
    assembly {
      s.slot := HERO_CONTROLLER_STORAGE_LOCATION
    }
    return s;
  }
  //endregion ------------------------ Storage

  //region ------------------------ Restrictions

  function onlyDungeonFactory(address dungeonFactory, address sender) internal pure {
    if (dungeonFactory != sender) revert IAppErrors.ErrorNotDungeonFactory(sender);
  }

  function onlyOwner(address token, uint tokenId, address sender) internal view {
    if (IERC721(token).ownerOf(tokenId) != sender) revert IAppErrors.ErrorNotOwner(token, tokenId);
  }

  function onlyNotStaked(IController controller_, address hero, uint heroId) internal view {
    if (IReinforcementController(controller_.reinforcementController()).isStaked(hero, heroId)) revert IAppErrors.Staked(hero, heroId);
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

  function _checkOutDungeonNotStakedAlive(IController c, address hero, uint heroId) internal view returns (
    IDungeonFactory dungFactory,
    IStatController statController
  ) {
    dungFactory = IDungeonFactory(c.dungeonFactory());
    statController = IStatController(c.statController());

    onlyNotInDungeon(dungFactory, hero, heroId);
    onlyNotStaked(c, hero, heroId);
    if (!statController.isHeroAlive(hero, heroId)) revert IAppErrors.ErrorHeroIsDead(hero, heroId);
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

  //endregion ------------------------ Views

  //region ------------------------ Gov actions

  function registerHero(address hero, uint8 heroClass, address payToken, uint payAmount) internal {
    _S().heroClass[hero] = heroClass;
    _S().payToken[hero] = payToken.packAddressWithAmount(payAmount);

    emit IApplicationEvents.HeroRegistered(hero, heroClass, payToken, payAmount);
  }
  //endregion ------------------------ Gov actions

  //region ------------------------ User actions: setBiome, levelUp
  /// @notice Set hero biome to {biome}, ensure that it's allowed
  /// @param msgSender Sender must be the owner of the hero
  /// @param biome New biome value: (0, maxBiomeCompleted + 1]
  function setBiome(IController controller, address msgSender, address hero, uint heroId, uint8 biome) internal {
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
    IController controller,
    address msgSender,
    address hero,
    uint heroId,
    IStatController.CoreAttributes memory change
  ) internal {
    onlyOwner(hero, heroId, msgSender);
    _checkRegisteredNotPaused(controller, hero);
    _checkOutDungeonNotStakedAlive(controller, hero, heroId);

    IHeroController.HeroInfo memory heroInfo = getHeroInfo(hero, heroId);

    // update stats
    IStatController _statController = IStatController(controller.statController());
    uint level = _statController.levelUp(hero, heroId, _S().heroClass[hero], change);

    // NG+ has free level up
    // all heroes created before NG+ and not upgraded to NG+ require payment as before
    if (heroInfo.paidToken == address(0)) {
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

  /// @notice Ask random other-hero for reinforcement
  function askReinforcement(IController controller, address msgSender, address hero, uint heroId, address helper, uint helperId) internal {
    onlyOwner(hero, heroId, msgSender);
    _askReinforcement(controller, hero, heroId, false, helper, helperId);
  }

  /// @notice Ask random staked guild-hero for reinforcement
  function askGuildReinforcement(IController controller, address hero, uint heroId, address helper, uint helperId) internal {
    _askReinforcement(controller, hero, heroId, true, helper, helperId);
  }

  function _askReinforcement(IController controller, address hero, uint heroId, bool guildReinforcement, address helper, uint helperId) internal {
    _checkRegisteredNotPaused(controller, hero);

    onlyInDungeon(IDungeonFactory(controller.dungeonFactory()), hero, heroId);

    bytes32 packedHero = hero.packNftId(heroId);
    if (_S().reinforcementHero[packedHero] != bytes32(0)) revert IAppErrors.AlreadyHaveReinforcement();

    IStatController _statController = IStatController(controller.statController());
    IReinforcementController rc = IReinforcementController(controller.reinforcementController());

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
    onlyDungeonFactory(controller.dungeonFactory(), msgSender);
    onlyRegisteredHero(hero);

    bytes32 packedId = hero.packNftId(heroId);

    (helperToken, helperId) = _S().reinforcementHero[packedId].unpackNftId();

    if (helperToken != address(0)) {
      IStatController _statController = IStatController(controller.statController());

      int32[] memory attributes = _S().reinforcementHeroAttributes[packedId].toInt32Array(uint(IStatController.ATTRIBUTES.END_SLOT));

      _statController.changeBonusAttributes(IStatController.ChangeAttributesInfo({
        heroToken: hero,
        heroTokenId: heroId,
        changeAttributes: attributes,
        add: false,
        temporally: false
      }));

      delete _S().reinforcementHero[packedId];
      delete _S().reinforcementHeroAttributes[packedId];

      IReinforcementController rc = IReinforcementController(controller.reinforcementController());
      uint guildId = rc.busyGuildHelperOf(helperToken, helperId);
      if (guildId == 0) {
        emit IApplicationEvents.ReinforcementReleased(hero, heroId, helperToken, helperId);
      } else {
        rc.releaseGuildHero(helperToken, helperId);
        emit IApplicationEvents.GuildReinforcementReleased(hero, heroId, helperToken, helperId);
      }
    }
  }
  //endregion ------------------------ User actions: reinforcement

  //region ------------------------ Dungeon actions
  /// @return dropItems List of items (packed: item NFT address + item id)
  function kill(IController controller, address msgSender, address hero, uint heroId) internal returns (
    bytes32[] memory dropItems
  ) {
    // restrictions are checked inside softKill
    dropItems = softKill(controller, msgSender, hero, heroId, true, false);

    IHero(hero).burn(heroId);

    emit IApplicationEvents.Killed(hero, heroId, msgSender, dropItems, 0);
  }

  /// @notice Take off all items from the hero, reduce life to 1
  /// Optionally reduce mana to zero and/or decrease life chance
  function softKill(IController controller, address msgSender, address hero, uint heroId, bool decLifeChances, bool resetMana) internal returns (
    bytes32[] memory dropItems
  ) {
    onlyDungeonFactory(controller.dungeonFactory(), msgSender);
    onlyRegisteredHero(hero);

    IStatController statController = IStatController(controller.statController());
    dropItems = _takeOffAll(IItemController(controller.itemController()), statController, hero, heroId, msgSender, true);

    _resetLife(statController, hero, heroId, decLifeChances, resetMana);
  }

  /// @notice Life => 1, mana => 0
  function resetLifeAndMana(IController controller, address msgSender, address hero, uint heroId) internal {
    onlyDungeonFactory(controller.dungeonFactory(), msgSender);
    _resetLife(IStatController(controller.statController()), hero, heroId, false, true);
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

}
