// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./PackingLib.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IHero.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IHeroTokensVault.sol";
import "../interfaces/IDungeonFactory.sol";
import "../interfaces/IReinforcementController.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IAppErrors.sol";

library HeroLib {
  using PackingLib for int32[];
  using PackingLib for bytes32[];
  using PackingLib for address;
  using PackingLib for bytes32;

  /// @dev keccak256(abi.encode(uint256(keccak256("hero.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant HERO_CONTROLLER_STORAGE_LOCATION = 0xd333325b749986e76669f0e0c2c1aa0e0abd19e216c3678477196e4089241400;
  uint public constant KILL_PENALTY = 70;

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
    if (IERC721(token).ownerOf(tokenId) != sender) revert IAppErrors.ErrorNotHeroOwner(token, sender);
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
    ) revert IAppErrors.ItemEquipped();
    onlyNotStaked(controller_, hero, heroId);
    return true;
  }

  function _checkOwnerRegisteredPause(IController c, address msgSender, address hero, uint heroId) internal view {
    onlyOwner(hero, heroId, msgSender);
    if (_S().heroClass[hero] == 0) revert IAppErrors.ErrorHeroIsNotRegistered(hero);
    if (c.onPause()) revert IAppErrors.ErrorPaused();
  }

  function _checkOutDungeonNotStakedAlive(IController c, address hero, uint heroId) internal view returns (IDungeonFactory) {
    IDungeonFactory dungFactory = IDungeonFactory(c.dungeonFactory());

    onlyNotInDungeon(dungFactory, hero, heroId);
    onlyNotStaked(c, hero, heroId);
    if (!IStatController(c.statController()).isHeroAlive(hero, heroId)) revert IAppErrors.ErrorHeroIsDead(hero, heroId);

    return dungFactory;
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Register

  function setHeroTokensVault(address value) internal {
    if (value == address(0)) revert IAppErrors.ZeroAddress();
    if (_S().heroTokensVault != address(0)) revert IAppErrors.HeroTokensVaultAlreadySet();

    _S().heroTokensVault = value;

    emit IApplicationEvents.HeroTokensVaultSet(value);
  }

  function registerHero(address hero, uint8 heroClass, address payToken, uint payAmount) internal {
    _S().heroClass[hero] = heroClass;
    _S().payToken[hero] = payToken.packAddressWithAmount(payAmount);

    emit IApplicationEvents.HeroRegistered(hero, heroClass, payToken, payAmount);
  }
  //endregion ------------------------ Register

  //region ------------------------ User actions: create, setBiome, levelUp

  /// @notice Init new hero, set biome 1, generate hero id, call process() to take specific amount from the sender
  /// @param hero Should support IHero
  /// @param heroName length must be < 20 chars, all chars should be ASCII chars in the range [32, 127]
  /// @param enter Enter to default biome (==1)
  function create(IController c, address msgSender, address hero, string calldata heroName, string memory refCode, bool enter)
  internal returns (uint heroId) {
    if (_S().heroClass[hero] == 0) revert IAppErrors.ErrorHeroIsNotRegistered(hero);
    if (_S().nameToHero[heroName] != bytes32(0)) revert IAppErrors.NameTaken();
    if (bytes(heroName).length >= 20) revert IAppErrors.TooBigName();
    if (!isASCIILettersOnly(heroName)) revert IAppErrors.WrongSymbolsInTheName();
    if (c.onPause()) revert IAppErrors.ErrorPaused();

    heroId = IHero(hero).mintFor(msgSender);
    bytes32 packedId = hero.packNftId(heroId);

    _S().heroName[packedId] = heroName;
    _S().nameToHero[heroName] = packedId;

    IStatController(c.statController()).initNewHero(hero, heroId, _S().heroClass[hero]);

    (address token, uint amount) = _S().payToken[hero].unpackAddressWithAmount();
    if (token != address(0)) {
      IHeroTokensVault(_S().heroTokensVault).process(token, amount, msgSender);
    }

    emit IApplicationEvents.HeroCreated(hero, heroId, heroName, msgSender, refCode);

    // set first biome by default
    _S().heroBiome[packedId] = 1;
    emit IApplicationEvents.BiomeChanged(hero, heroId, 1);

    // enter to the first dungeon
    if (enter) {
      IDungeonFactory(c.dungeonFactory()).launchForNewHero(hero, heroId, msgSender);
    }

    return heroId;
  }

  /// @notice Set hero biome to {biome}, ensure that it's allowed
  /// @param msgSender Sender must be the owner of the hero
  /// @param biome New biome value: (0, maxBiomeCompleted + 1]
  function setBiome(IController controller, address msgSender, address hero, uint heroId, uint8 biome) internal {

    _checkOwnerRegisteredPause(controller, msgSender, hero, heroId);
    IDungeonFactory dungFactory = _checkOutDungeonNotStakedAlive(controller, hero, heroId);

    if (biome == 0) revert IAppErrors.ErrorIncorrectBiome(biome);

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
    _checkOwnerRegisteredPause(controller, msgSender, hero, heroId);
    _checkOutDungeonNotStakedAlive(controller, hero, heroId);

    onlyNotInDungeon(IDungeonFactory(controller.dungeonFactory()), hero, heroId);
    onlyNotStaked(controller, hero, heroId);

    IStatController _statController = IStatController(controller.statController());
    (address token, uint payTokenAmount) = _S().payToken[hero].unpackAddressWithAmount();

    if (token == address(0) || payTokenAmount == 0) revert IAppErrors.NoPayToken(token, payTokenAmount);

    // update stats
    uint level = _statController.levelUp(hero, heroId, _S().heroClass[hero], change);

    // send tokens
    uint amount = payTokenAmount * level;

    IHeroTokensVault(_S().heroTokensVault).process(token, amount, msgSender);

    emit IApplicationEvents.LevelUp(hero, heroId, msgSender, change);
  }

  //endregion ------------------------ User actions: create, setBiome, levelUp

  //region ------------------------ User actions: reinforcement

  /// @notice Ask random other-hero for reinforcement
  function askReinforcement(IController controller, address msgSender, address hero, uint heroId) internal {
    _checkOwnerRegisteredPause(controller, msgSender, hero, heroId);

    onlyInDungeon(IDungeonFactory(controller.dungeonFactory()), hero, heroId);

    bytes32 packedId = hero.packNftId(heroId);
    if (_S().reinforcementHero[packedId] != bytes32(0)) revert IAppErrors.AlreadyHaveReinforcement();

    IStatController _statController = IStatController(controller.statController());
    IReinforcementController rc = IReinforcementController(controller.reinforcementController());

    (address helpHeroToken, uint helpHeroId, int32[] memory helpAttributes) = rc.askHero(uint(_S().heroBiome[packedId]));

    _statController.changeBonusAttributes(IStatController.ChangeAttributesInfo({
      heroToken: hero,
      heroTokenId: heroId,
      changeAttributes: helpAttributes,
      add: true,
      temporally: false
    }));

    _S().reinforcementHero[packedId] = helpHeroToken.packNftId(helpHeroId);
    _S().reinforcementHeroAttributes[packedId] = helpAttributes.toBytes32Array();

    emit IApplicationEvents.ReinforcementAsked(hero, heroId, helpHeroToken, helpHeroId);
  }

  function releaseReinforcement(IController controller, address msgSender, address hero, uint heroId) internal returns (
    address helperToken,
    uint helperId
  ) {
    onlyDungeonFactory(controller.dungeonFactory(), msgSender);
    if (_S().heroClass[hero] == 0) revert IAppErrors.ErrorHeroIsNotRegistered(hero);

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

      emit IApplicationEvents.ReinforcementReleased(hero, heroId, helperToken, helperId);
    }
  }
  //endregion ------------------------ User actions: reinforcement

  //region ------------------------ Kill
  /// @return dropItems List of items (packed: item NFT address + item id)
  function kill(IController controller, address msgSender, address hero, uint heroId) internal returns (
    bytes32[] memory dropItems
  ) {
    onlyDungeonFactory(controller.dungeonFactory(), msgSender);
    if (_S().heroClass[hero] == 0) revert IAppErrors.ErrorHeroIsNotRegistered(hero);

    IStatController statController = IStatController(controller.statController());
    dropItems = _takeOffAll(IItemController(controller.itemController()), statController, hero, heroId, msgSender, true);

    // set life to zero, reduce life-chances on 1
    statController.changeCurrentStats(
      hero,
      heroId,
      IStatController.ChangeableStats({
        level: 0,
        experience: 0,
        life: statController.heroStats(hero, heroId).life,
        mana: 0,
        lifeChances: 1
      }),
      false
    );

    IHero(hero).burn(heroId);

    emit IApplicationEvents.Killed(hero, heroId, msgSender, dropItems, 0);
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
  //endregion ------------------------ Kill

  //region ------------------------ Utils
  function isASCIILettersOnly(string memory str) internal pure returns (bool) {
    bytes memory b = bytes(str);
    for (uint i = 0; i < b.length; i++) {
      if (uint8(b[i]) < 32 || uint8(b[i]) > 127) {
        return false;
      }
    }
    return true;
  }
  //endregion ------------------------ Utils

}
