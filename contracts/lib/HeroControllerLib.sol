// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IHeroController.sol";
import "../interfaces/IUserController.sol";
import "../lib/HeroLib.sol";
import "../lib/PackingLib.sol";
import "../lib/ScoreLib.sol";
import "../proxy/Controllable.sol";
import "../relay/ERC2771Context.sol";
import "./ControllerContextLib.sol";

library HeroControllerLib {
  using PackingLib for bytes32;
  using PackingLib for address;
  using EnumerableSet for EnumerableSet.UintSet;

  //region ------------------------ Restrictions

  function onlyDeployer(IController controller) internal view {
    if (! controller.isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }

  function onlyEOA(bool isEoa) internal view {
    if (!isEoa) {
      revert IAppErrors.NotEOA(msg.sender);
    }
  }

  function onlyItemController(IController controller_) internal view {
    if (controller_.itemController() != msg.sender) revert IAppErrors.ErrorNotItemController(msg.sender);
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Views

  function _S() internal pure returns (IHeroController.MainState storage s) {
    return HeroLib._S();
  }

  function payTokenInfo(address hero) internal view returns (address token, uint amount) {
    return _S().payToken[hero].unpackAddressWithAmount();
  }

  function heroClass(address hero) internal view returns (uint8) {
    return _S().heroClass[hero];
  }

  function heroName(address hero, uint heroId) internal view returns (string memory) {
    return _S().heroName[hero.packNftId(heroId)];
  }

  function nameToHero(string memory name) internal view returns (address hero, uint heroId) {
    return _S().nameToHero[name].unpackNftId();
  }

  function heroBiome(address hero, uint heroId) internal view returns (uint8) {
    return _S().heroBiome[hero.packNftId(heroId)];
  }

  function heroReinforcementHelp(address hero, uint heroId) internal view returns (
    address helperHeroToken,
    uint helperHeroId
  ) {
    return _S().reinforcementHero[hero.packNftId(heroId)].unpackNftId();
  }

  function score(IController controller, address hero, uint heroId) internal view returns (uint) {
    IStatController _statController = IStatController(controller.statController());
    return ScoreLib.heroScore(
      _statController.heroAttributes(hero, heroId),
      _statController.heroStats(hero, heroId).level
    );
  }

  function isAllowedToTransfer(IController controller, address hero, uint heroId) internal view returns (bool) {
    return HeroLib.isAllowedToTransfer(controller, hero, heroId);
  }

  function countHeroTransfers(address hero, uint heroId) internal view returns (uint) {
    return _S().countHeroTransfers[PackingLib.packNftId(hero, heroId)];
  }

  function getTier(uint8 tier, address hero) internal view returns (uint payAmount, uint8[] memory slots, address[][] memory items) {
    if (tier == HeroLib.TIER_1) {
      (, payAmount) = payTokenInfo(hero);
    }
    if (tier == HeroLib.TIER_2 || tier == HeroLib.TIER_3) {
      IHeroController.TierInfo storage tierInfo = _S().tiers[PackingLib.packTierHero(tier, hero)];
      payAmount = tierInfo.amount;

      uint len = tierInfo.slots.length();

      slots = new uint8[](len);
      items = new address[][](len);

      for (uint i; i < len; ++i) {
        slots[i] = uint8(tierInfo.slots.at(i));
        items[i] = tierInfo.itemsToMint[slots[i]];
      }
    }

    return (payAmount, slots, items);
  }

  //endregion ------------------------ Views

  //region ------------------------ Governance actions

  function registerHero(IController controller, address hero, uint8 heroClass_, address payToken, uint payAmount) internal {
    onlyDeployer(controller);
    HeroLib.registerHero(hero, heroClass_, payToken, payAmount);
  }

  /// @dev payAmount is limited by uint72, see remarks to IHeroController.HeroInfo
  function setTier(IController controller, uint8 tier, address hero, uint72 payAmount, uint8[] memory slots, address[][] memory items) internal {
    onlyDeployer(controller);

    if (tier != HeroLib.TIER_2 && tier != HeroLib.TIER_3) revert IAppErrors.WrongTier(tier);

    IHeroController.TierInfo storage tierInfo = _S().tiers[PackingLib.packTierHero(tier, hero)];

    // ------- clear prev stored tier data if any
    // tierInfo.amount is not cleared, set 0 if you need to reset it

    uint prevLen = tierInfo.slots.length();
    if (prevLen != 0) {
      for (uint i; i < prevLen; ++i) {
        uint8 slot = uint8(tierInfo.slots.at(0));
        tierInfo.slots.remove(slot);
        delete tierInfo.itemsToMint[slot];
      }
    }

    // ------- register new tier data
    uint len = slots.length;
    if (len != items.length) revert IAppErrors.LengthsMismatch();

    tierInfo.amount = payAmount;
    for (uint i; i < len; ++i) {
      tierInfo.slots.add(slots[i]);
      tierInfo.itemsToMint[slots[i]] = items[i];
    }

    emit IApplicationEvents.TierSetup(tier, hero, payAmount, slots, items);
  }
  //endregion ------------------------ Governance actions

  //region ------------------------ User actions - create hero
  function createHero(IController controller, address msgSender, address hero, IHeroController.HeroCreationData memory data) external returns (
    uint heroId
  ) {
    return _createHero(controller, msgSender, hero, data);
  }

  function create(
    IController controller,
    address msgSender,
    address hero,
    string calldata _heroName,
    bool enter
  ) external returns (uint) {
    // allow create for contracts for SponsoredHero flow  // onlyEOA(isEoa);
    return _create(controller, msgSender, hero, _heroName, "", enter);
  }

  function createWithRefCode(
    bool isEoa,
    IController controller,
    address msgSender,
    address hero,
    string calldata _heroName,
    string memory refCode,
    bool enter
  ) external returns (uint) {
    onlyEOA(isEoa);
    return _create(controller, msgSender, hero, _heroName, refCode, enter);
  }

  /// @notice Init new hero, set biome 1, generate hero id, call process() to take specific amount from the sender
  /// @param hero Should support IHero
  /// @param heroName_ length must be < 20 chars, all chars should be ASCII chars in the range [32, 127]
  /// @param enter Enter to default biome (==1)
  function _create(IController controller, address msgSender, address hero, string calldata heroName_, string memory refCode, bool enter)
  internal returns (uint heroId) {
    IHeroController.HeroCreationData memory data;
    data.heroName = heroName_;
    data.refCode = refCode;
    data.enter = enter;
    data.tier = HeroLib.TIER_DEFAULT;

    return _createHero(controller, msgSender, hero, data);
  }

  function _createHero(IController controller, address msgSender, address hero, IHeroController.HeroCreationData memory data) internal returns (
    uint heroId
  ) {
    ControllerContextLib.ControllerContext memory cc = ControllerContextLib.init(controller);
    HeroLib._checkRegisteredNotPaused(controller, hero);
    if (_S().nameToHero[data.heroName] != bytes32(0)) revert IAppErrors.NameTaken();
    if (bytes(data.heroName).length >= 20) revert IAppErrors.TooBigName();
    if (!StringLib.isASCIILettersOnly(data.heroName)) revert IAppErrors.WrongSymbolsInTheName();

    if (data.targetUserAccount == address(0)) {
      data.targetUserAccount = msgSender;
    }

    // ----------- get pay token and pay amount
    (address payToken, uint amount) = _S().payToken[hero].unpackAddressWithAmount();
    if (payToken == address(0)) revert IAppErrors.ZeroToken();

    bool prepayment = payToken != address(ControllerContextLib.getGameToken(cc));
    if (prepayment) {
      if (data.tier == HeroLib.TIER_DEFAULT) data.tier = HeroLib.TIER_1; // use tier 1 by default
      if (data.tier > HeroLib.TIER_1) {
        amount = _S().tiers[PackingLib.packTierHero(data.tier, hero)].amount;
      }
    } else {
      if (data.tier != HeroLib.TIER_DEFAULT) revert IAppErrors.NgpNotActive(hero);
    }
    if (amount == 0) revert IAppErrors.ZeroAmount();
    if (_S().maxUserNgLevel[data.targetUserAccount] < data.ngLevel) revert IAppErrors.NotEnoughNgLevel(data.ngLevel);

    // ----------- mint new hero on selected NG+ level
    heroId = IHero(hero).mintFor(data.targetUserAccount);
    bytes32 packedId = hero.packNftId(heroId);

    _S().heroName[packedId] = data.heroName;
    _S().nameToHero[data.heroName] = packedId;

    if (data.ngLevel != 0 && prepayment) {
      // discount for hero = 100% of lost profit
      uint lostProfitPercent = ControllerContextLib.getRewardsPool(cc).lostProfitPercent(
        ControllerContextLib.getDungeonFactory(cc).maxAvailableBiome(),
        _S().maxOpenedNgLevel,
        data.ngLevel
      );
      uint discount = amount * lostProfitPercent / 1e18;
      if (discount > amount) revert IAppErrors.TooHighValue(discount);
      amount -= discount;
    }

    if (prepayment) {
      _S().heroInfo[packedId] = IHeroController.HeroInfo({
        tier: data.tier,
        ngLevel: data.ngLevel,
        rebornAllowed: false,
        paidAmount: amount > type(uint72).max ? type(uint72).max : uint72(amount), // edge case, uint72 is enough for any reasonable amount of stable coins with decimals 18
        paidToken : payToken
      });
    } else {
      _S().heroInfo[packedId] = IHeroController.HeroInfo({
        tier: 0,
        ngLevel: data.ngLevel,
        rebornAllowed: false,
        paidAmount: 0,
        paidToken: address(0)
      });
    }

    ControllerContextLib.getStatController(cc).initNewHero(hero, heroId, _S().heroClass[hero]);

    // ----------- pay for the hero creation
    controller.process(payToken, amount, msgSender);
    emit IApplicationEvents.HeroCreatedNgp(hero, heroId, data.heroName, data.targetUserAccount, data.refCode, data.tier, data.ngLevel);

    // ----------- enter to the first biome/dungeon
    // set first biome by default
    _S().heroBiome[packedId] = 1;
    emit IApplicationEvents.BiomeChanged(hero, heroId, 1);

    // ----------- mint and equip items
    if (data.tier > HeroLib.TIER_1) {
      // attributes before items equipment
      int32[] memory attributes = ControllerContextLib.getStatController(cc).heroAttributes(hero, heroId);

      _mintAndEquipItems(
        ControllerContextLib.getItemController(cc),
        _S().tiers[PackingLib.packTierHero(data.tier, hero)],
        hero,
        heroId,
        data.targetUserAccount
      );

      // restore hp/mp after equipments: increase life and mana on {current attr.value - attr.value before equip}
      ControllerContextLib.getStatController(cc).restoreLifeAndMana(hero, heroId, attributes);
    }

    // enter to the first dungeon
    if (data.enter) {
      ControllerContextLib.getDungeonFactory(cc).launchForNewHero(hero, heroId, data.targetUserAccount);
    }

    return heroId;
  }

  /// @notice Mint and equip all items specified in the tire
  function _mintAndEquipItems(
    IItemController itemController,
    IHeroController.TierInfo storage tierInfo,
    address hero,
    uint heroId,
    address msgSender
  ) internal {
    EnumerableSet.UintSet storage slots = tierInfo.slots;
    mapping(uint8 slot => address[] items) storage itemsToMint = tierInfo.itemsToMint;

    uint len = slots.length();
    if (len != 0) {
      address[] memory items = new address[](len);
      uint[] memory itemIds = new uint[](len);
      uint8[] memory itemSlots = new uint8[](len);

      for (uint i; i < len; ++i) {
        itemSlots[i] = uint8(slots.at(i));
        address[] storage listItems = itemsToMint[itemSlots[i]];
        items[i] = listItems[CalcLib.pseudoRandom(listItems.length - 1)];
        itemIds[i] = itemController.mint(items[i], msgSender);
      }

      itemController.equip(hero, heroId, items, itemIds, itemSlots);
    }
  }
  //endregion ------------------------ User actions - create hero

  //region ------------------------ User actions - biome, level up, reborn
  function setBiome(bool isEoa, IController controller, address msgSender, address hero, uint heroId, uint8 biome) internal {
    onlyEOA(isEoa);
    HeroLib.setBiome(controller, msgSender, hero, heroId, biome);
  }

  function levelUp(
    bool isEoa,
    IController controller,
    address msgSender,
    address hero,
    uint heroId,
    IStatController.CoreAttributes memory change
  ) internal {
    onlyEOA(isEoa);
    HeroLib.levelUp(controller, msgSender, hero, heroId, change);
  }

  function beforeTokenTransfer(IController controller, address msgSender, address hero, uint heroId) internal returns (
    bool isAllowedToTransferOut
  ) {
    if (msgSender != hero) revert IAppErrors.ErrorForbidden(msgSender);
    HeroLib.onlyRegisteredHero(hero);

    isAllowedToTransferOut = HeroLib.isAllowedToTransfer(controller, hero, heroId);
    _S().countHeroTransfers[PackingLib.packNftId(hero, heroId)] += 1;
  }

  function reborn(IController controller, address msgSender, address hero, uint heroId) external {
    HeroLib._checkRegisteredNotPaused(controller, hero);
    HeroLib.onlyOwner(hero, heroId, msgSender);
    (IDungeonFactory dungFactory, IStatController statController) = HeroLib._checkOutDungeonNotStakedAlive(controller, hero, heroId);
    // restriction "no equipped items" is checked on statController side

    bytes32 packedHero = PackingLib.packNftId(hero, heroId);

    // -------------- update HeroInfo
    IHeroController.HeroInfo memory heroInfo = _S().heroInfo[packedHero];
    if (!heroInfo.rebornAllowed) revert IAppErrors.RebornNotAllowed();

    heroInfo = _upgradeToPrePaidHero(controller, heroInfo, hero, msgSender);

    if (heroInfo.ngLevel == HeroLib.MAX_NG_LEVEL) revert IAppErrors.TooHighValue(heroInfo.ngLevel);
    uint8 newNgLevel = heroInfo.ngLevel + 1;
    _S().heroInfo[packedHero] = IHeroController.HeroInfo({
      tier: heroInfo.tier,
      ngLevel: newNgLevel,
      rebornAllowed: false,
      paidToken: heroInfo.paidToken,
      paidAmount: heroInfo.paidAmount
    });

    // statController.reborn expects that it's called AFTER incrementing NG_LVL
    statController.reborn(hero, heroId, _S().heroClass[hero]);

    // -------------- update max-ng-level, register the hero in Hall Of Fame
    uint8 _maxUserNgLevel = _S().maxUserNgLevel[msgSender];
    if (newNgLevel > _maxUserNgLevel) {
      _S().maxUserNgLevel[msgSender] = newNgLevel;

      // assume that if for a user it is new max ng then possible it is new max ng globally
      // the hero who has opened NG_LEVEL first is registered in Hall of Fame
      if (newNgLevel > _S().maxOpenedNgLevel) {
        IUserController(controller.userController()).registerFameHallHero(hero, heroId, newNgLevel);
        _S().maxOpenedNgLevel = newNgLevel;
      }
    }

    dungFactory.reborn(hero, heroId);

    emit IApplicationEvents.Reborn(hero, heroId, newNgLevel);
  }

  /// @notice Update Post-paid hero to Pre-paid hero if it's necessary and allowed
  function _upgradeToPrePaidHero(
    IController controller,
    IHeroController.HeroInfo memory heroInfo,
    address hero,
    address msgSender
  ) internal returns (IHeroController.HeroInfo memory) {
    if (heroInfo.paidToken == address(0)) {
      // the hero is post-paid, need to upgrade
      address gameToken = controller.gameToken();

      (address payToken, uint payAmountForTier1) = payTokenInfo(hero);
      if (payToken != gameToken) {
        // hero token is not game token, post-paid hero can be upgraded to pre-paid with tier 1
        if (payAmountForTier1 == 0) revert IAppErrors.ZeroAmount();

        heroInfo.paidAmount = payAmountForTier1 > type(uint72).max ? type(uint72).max : uint72(payAmountForTier1);
        heroInfo.paidToken = payToken;
        heroInfo.tier = HeroLib.TIER_1;

        controller.process(payToken, heroInfo.paidAmount, msgSender);
      }
    }

    return heroInfo;
  }
  //endregion ------------------------ User actions

  //region ------------------------ Dungeon actions
  function registerKilledBoss(IController controller, address msgSender, address hero, uint heroId, uint32 bossObjectId) external {
    HeroLib.onlyDungeonFactory(controller.dungeonFactory(), msgSender);

    uint biome = _S().heroBiome[PackingLib.packNftId(hero, heroId)];

    (uint8 bossBiome, ) = IGOC(controller.gameObjectController()).getObjectMeta(bossObjectId);
    if (bossBiome == biome) {
      IHeroController.HeroInfo memory heroInfo = _S().heroInfo[PackingLib.packNftId(hero, heroId)];

      bytes32 packedBiomeNgLevel = PackingLib.packUint8Array3(uint8(biome), heroInfo.ngLevel, 0);

      mapping (bytes32 packedBiomeNgLevel => uint timestamp) storage killedBosses = _S().killedBosses[PackingLib.packNftId(hero, heroId)];
      uint8 maxAvailableBiome = IDungeonFactory(controller.dungeonFactory()).maxAvailableBiome();
      if (killedBosses[packedBiomeNgLevel] == 0) {
        // the boss is killed first time - pay reward to pre-paid hero
        killedBosses[packedBiomeNgLevel] = block.timestamp;

        uint rewardAmount;
        if (heroInfo.paidToken != controller.gameToken()) {
          // The hero is pre-paid, he is allowed to receive rewards from reward pool
          IRewardsPool rewardsPool = IRewardsPool(controller.rewardsPool());
          rewardAmount = rewardsPool.rewardAmount(
            heroInfo.paidToken,
            maxAvailableBiome,
            _S().maxOpenedNgLevel,
            biome,
            heroInfo.ngLevel
          );
          if (rewardAmount != 0) {
            rewardsPool.sendReward(heroInfo.paidToken, rewardAmount, IERC721(hero).ownerOf(heroId));
          }
        }

        emit IApplicationEvents.BossKilled(msgSender, hero, heroId, bossBiome, heroInfo.ngLevel, maxAvailableBiome == bossBiome, rewardAmount);
      }

      if(maxAvailableBiome == bossBiome) {
        _S().heroInfo[PackingLib.packNftId(hero, heroId)].rebornAllowed = true;
      }
    }

  }
  //endregion ------------------------ Dungeon actions

  //region ------------------------ Classic and guild reinforcement
  function askReinforcement(bool isEoa, IController controller, address msgSender, address hero, uint heroId, address helper, uint helperId) internal {
    onlyEOA(isEoa);
    HeroLib.askReinforcement(controller, msgSender, hero, heroId, helper, helperId);
  }

  function askGuildReinforcement(IController controller, address hero, uint heroId, address helper, uint helperId) internal {
    onlyItemController(controller);
    HeroLib.askGuildReinforcement(controller, hero, heroId, helper, helperId);
  }
  //endregion ------------------------ Classic and guild reinforcement
}

