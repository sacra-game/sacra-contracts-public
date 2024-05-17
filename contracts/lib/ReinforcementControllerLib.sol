// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IReinforcementController.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IDungeonFactory.sol";
import "../lib/CalcLib.sol";
import "../lib/PackingLib.sol";

library ReinforcementControllerLib {
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableMap for EnumerableMap.AddressToUintMap;
  using PackingLib for bytes32;
  using PackingLib for address;
  using PackingLib for uint8[];

  //region ------------------------ CONSTANTS

  /// @dev keccak256(abi.encode(uint256(keccak256("reinforcement.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant MAIN_STORAGE_LOCATION = 0x5a053c541e08c6bd7dfc3042a100e83af246544a23ecda1a47bf22b441b00c00;
  uint internal constant _SEARCH_LOOPS = 10;
  int32 internal constant _ATTRIBUTES_RATIO = 20;
  uint internal constant _TO_HELPER_RATIO_MAX = 50;
  uint internal constant _STAKE_REDUCE_DELAY = 7 days;
  uint internal constant _DELAY_FACTOR = 2;
  //endregion ------------------------ CONSTANTS

  //region ------------------------ VIEWS

  function _S() internal pure returns (IReinforcementController.MainState storage s) {
    assembly {
      s.slot := MAIN_STORAGE_LOCATION
    }
    return s;
  }

  function minLevel() internal view returns (uint8 _minLevel) {
    (_minLevel,) = unpackConfig(_S().config);
    return _minLevel;
  }

  function minLifeChances() internal view returns (uint8 _minLifeChances) {
    (, _minLifeChances) = unpackConfig(_S().config);
    return _minLifeChances;
  }

  function toHelperRatio(address heroToken, uint heroId) internal view returns (uint) {
    return heroInfo(heroToken, heroId).fee;
  }

  function heroInfo(address heroToken, uint heroId) internal view returns (IReinforcementController.HeroInfo memory) {
    return unpackHeroInfo(_S()._stakedHeroes[heroToken.packNftId(heroId)]);
  }

  function isStaked(address heroToken, uint heroId) internal view returns (bool) {
    return heroInfo(heroToken, heroId).biome != 0;
  }

  function maxScore(uint biome) internal view returns (uint) {
    return _S().maxScore[biome];
  }

  function earned(address heroToken, uint heroId) internal view returns (
    address[] memory tokens,
    uint[] memory amounts,
    address[] memory nfts,
    uint[] memory ids
  ){
    EnumerableMap.AddressToUintMap storage erc20Rewards = _S()._heroTokenRewards[heroToken.packNftId(heroId)];
    uint length = erc20Rewards.length();
    tokens = new address[](length);
    amounts = new uint[](length);
    for (uint i; i < length; ++i) {
      (tokens[i], amounts[i]) = erc20Rewards.at(i);
    }

    bytes32[] storage nftRewards = _S()._heroNftRewards[heroToken.packNftId(heroId)];
    length = nftRewards.length;
    nfts = new address[](length);
    ids = new uint[](length);
    for (uint i; i < length; ++i) {
      (nfts[i], ids[i]) = PackingLib.unpackNftId(nftRewards[i]);
    }
  }

  function heroScoreAdjusted(address heroToken, uint heroId) internal view returns (uint) {
    IReinforcementController.HeroInfo memory info = unpackHeroInfo(_S()._stakedHeroes[heroToken.packNftId(heroId)]);
    if (info.stakeTs > block.timestamp) {
      return 0;
    }
    uint time = block.timestamp - info.stakeTs;
    if (time > _STAKE_REDUCE_DELAY) {
      time -= _STAKE_REDUCE_DELAY;
    } else {
      // if staked less then delay ago hero has 100% scores
      return info.score;
    }
    if (time > _STAKE_REDUCE_DELAY * _DELAY_FACTOR) {
      // if hero staked more than delay*2 days return zero
      return 0;
    }
    return info.score * (_STAKE_REDUCE_DELAY * _DELAY_FACTOR - time) / (_STAKE_REDUCE_DELAY * _DELAY_FACTOR);
  }
  //endregion ------------------------ VIEWS

  //region ------------------------ GOV ACTIONS

  function setMinLevel(bool isGovernance, uint8 value) internal {
    if (!isGovernance) revert IAppErrors.NotGovernance(msg.sender);

    (, uint8 _minLifeChances) = unpackConfig(_S().config);
    _S().config = packConfig(value, _minLifeChances);

    emit IApplicationEvents.MinLevelChanged(value);
  }

  function setMinLifeChances(bool isGovernance, uint8 value) internal {
    if (!isGovernance) revert IAppErrors.NotGovernance(msg.sender);

    (uint8 _minLevel,) = unpackConfig(_S().config);
    _S().config = packConfig(_minLevel, value);

    emit IApplicationEvents.MinLifeChancesChanged(value);
  }

  //endregion ------------------------ GOV ACTIONS

  //region ------------------------ USER ACTIONS

  /// @notice Mark the hero as staked in _stakedHeroes and _internalIdsByBiomes, update maxScore for biome if necessary
  /// @param fee [0..._TO_HELPER_RATIO_MAX], higher fee => less score
  function stakeHero(bool isEoa, IController controller, address msgSender, address heroToken, uint heroId, uint8 fee) internal {
    IReinforcementController.MainState storage s = _S();
    if (!isEoa) revert IAppErrors.ErrorOnlyEoa();
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
    if (IERC721(heroToken).ownerOf(heroId) != msgSender) revert IAppErrors.ErrorNotHeroOwner(heroToken, msgSender);

    IHeroController hc = IHeroController(controller.heroController());
    if (hc.heroClass(heroToken) == 0) revert IAppErrors.ErrorHeroIsNotRegistered(heroToken);

    if (IDungeonFactory(controller.dungeonFactory()).currentDungeon(heroToken, heroId) != 0) revert IAppErrors.HeroInDungeon();
    if (isStaked(heroToken, heroId)) revert IAppErrors.AlreadyStaked();
    if (fee > _TO_HELPER_RATIO_MAX) revert IAppErrors.MaxFee(fee);

    IStatController.ChangeableStats memory stats = IStatController(controller.statController()).heroStats(heroToken, heroId);

    {
      (uint8 _minLevel, uint8 _minLifeChances) = unpackConfig(s.config);
      if (stats.level < _minLevel || stats.lifeChances < _minLifeChances) revert IAppErrors.StakeHeroNotStats();
      if (stats.lifeChances == 0) revert IAppErrors.ErrorHeroIsDead(heroToken, heroId); // for the case _minLifeChances == 0
    }

    uint8 biome = hc.heroBiome(heroToken, heroId);
    uint score = hc.score(heroToken, heroId);

    // x10 for each % discount
    score += score * (_TO_HELPER_RATIO_MAX - fee) / 10;
    EnumerableSet.Bytes32Set storage internalIds = s._internalIdsByBiomes[biome];

    uint _maxScore = s.maxScore[biome];
    if (score > _maxScore) {
      s.maxScore[biome] = score;
    }

    internalIds.add(heroToken.packNftId(heroId));

    s._stakedHeroes[heroToken.packNftId(heroId)] = packHeroInfo(IReinforcementController.HeroInfo({
      biome: biome,
      score: score,
      fee: fee,
      stakeTs: uint64(block.timestamp)
    }));

    emit IApplicationEvents.HeroStaked(heroToken, heroId, biome, score);
  }

  /// @notice Reverse operation for {stakeHero}
  function withdrawHero(bool isEoa, IController controller, address msgSender, address heroToken, uint heroId) internal {
    IReinforcementController.MainState storage s = _S();

    if (!isEoa) revert IAppErrors.ErrorOnlyEoa();
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
    if (IERC721(heroToken).ownerOf(heroId) != msgSender) revert IAppErrors.ErrorNotHeroOwner(heroToken, msgSender);
    if (IHeroController(controller.heroController()).heroClass(heroToken) == 0) revert IAppErrors.ErrorHeroIsNotRegistered(heroToken);

    IReinforcementController.HeroInfo memory _heroInfo = unpackHeroInfo(s._stakedHeroes[heroToken.packNftId(heroId)]);
    if (_heroInfo.biome == 0) revert IAppErrors.NotStaked();

    s._internalIdsByBiomes[_heroInfo.biome].remove(heroToken.packNftId(heroId));
    delete s._stakedHeroes[heroToken.packNftId(heroId)];

    emit IApplicationEvents.HeroWithdraw(heroToken, heroId);
  }

  /// @dev It's view like function but we need to touch slots in oracle function.
  function askHero(IController controller, uint biome) internal returns (
    address heroToken,
    uint heroId,
    int32[] memory attributes
  ) {
    heroToken = address(0);
    heroId = 0;
    {
      IOracle oracle = IOracle(controller.oracle());
      EnumerableSet.Bytes32Set storage internalIds = _S()._internalIdsByBiomes[biome];
      uint length = internalIds.length();
      if (length == 0) revert IAppErrors.NoStakedHeroes();
      uint _maxScore = _S().maxScore[biome];
      uint maxScoreSqrt = CalcLib.sqrt(_maxScore);

      for (uint i; i < _SEARCH_LOOPS; ++i) {
        uint random = oracle.getRandomNumber(1e18, length);
        uint b = (random * maxScoreSqrt / 1e18) ** 2;
        (heroToken, heroId) = internalIds.at(random % length).unpackNftId();

        if (
          heroScoreAdjusted(heroToken, heroId)
          >=
          (b < _maxScore ? _maxScore - b : 0)
        ) break;
      }
    }
    {
      IStatController sc = IStatController(controller.statController());
      uint[] memory indexes = new uint[](12);

      indexes[0] = uint(IStatController.ATTRIBUTES.STRENGTH);
      indexes[1] = uint(IStatController.ATTRIBUTES.DEXTERITY);
      indexes[2] = uint(IStatController.ATTRIBUTES.VITALITY);
      indexes[3] = uint(IStatController.ATTRIBUTES.ENERGY);
      indexes[4] = uint(IStatController.ATTRIBUTES.DAMAGE_MIN);
      indexes[5] = uint(IStatController.ATTRIBUTES.DAMAGE_MAX);
      indexes[6] = uint(IStatController.ATTRIBUTES.ATTACK_RATING);
      indexes[7] = uint(IStatController.ATTRIBUTES.DEFENSE);
      indexes[8] = uint(IStatController.ATTRIBUTES.BLOCK_RATING);
      indexes[9] = uint(IStatController.ATTRIBUTES.FIRE_RESISTANCE);
      indexes[10] = uint(IStatController.ATTRIBUTES.COLD_RESISTANCE);
      indexes[11] = uint(IStatController.ATTRIBUTES.LIGHTNING_RESISTANCE);

      attributes = _generateReinforcementAttributes(sc, indexes, heroToken, heroId);
    }
    emit IApplicationEvents.HeroAsk(heroToken, heroId);
  }

  /// @dev Only for dungeon. Assume the tokens already sent to this contract.
  function registerTokenReward(IController controller, address heroToken, uint heroId, address token, uint amount) internal {
    if (controller.dungeonFactory() != msg.sender) revert IAppErrors.ErrorNotDungeonFactory(msg.sender);

    EnumerableMap.AddressToUintMap storage rewards = _S()._heroTokenRewards[heroToken.packNftId(heroId)];

    (,uint existAmount) = rewards.tryGet(token);
    rewards.set(token, existAmount + amount);

    emit IApplicationEvents.TokenRewardRegistered(heroToken, heroId, token, amount, existAmount + amount);
  }

  /// @dev Only for dungeon. Assume the NFT already sent to this contract.
  function registerNftReward(IController controller, address heroToken, uint heroId, address token, uint tokenId) internal {
    if (controller.dungeonFactory() != msg.sender) revert IAppErrors.ErrorNotDungeonFactory(msg.sender);

    _S()._heroNftRewards[heroToken.packNftId(heroId)].push(token.packNftId(tokenId));

    emit IApplicationEvents.NftRewardRegistered(heroToken, heroId, token, tokenId);
  }

  function claimAll(bool isEoa, IController controller, address msgSender, address heroToken, uint heroId) internal {
    if (IERC721(heroToken).ownerOf(heroId) != msgSender) revert IAppErrors.ErrorNotHeroOwner(heroToken, msgSender);
    if (controller.onPause()) revert IAppErrors.ErrorPaused();
    if (!isEoa) revert IAppErrors.ErrorOnlyEoa();

    _claimAllTokenRewards(heroToken, heroId, msgSender);
    _claimAllNftRewards(heroToken, heroId, msgSender);
  }
  //endregion ------------------------ USER ACTIONS

  //region ------------------------ Internal logic
  /// @notice Claim all rewards from {_heroTokenRewards} to {recipient}, remove data from {_heroTokenRewards}
  function _claimAllTokenRewards(address heroToken, uint heroId, address recipient) internal {
    EnumerableMap.AddressToUintMap storage rewards = _S()._heroTokenRewards[heroToken.packNftId(heroId)];
    uint length = rewards.length();
    address[] memory tokens = new address[](length);
    for (uint i; i < length; ++i) {
      (address token, uint amount) = rewards.at(i);
      IERC20(token).transfer(recipient, amount);
      emit IApplicationEvents.ClaimedToken(heroToken, heroId, token, amount, recipient);

      tokens[i] = token;
    }

    // need to remove after the ordered reading for handle all elements, just remove the struct will not work coz contains mapping inside
    for (uint i; i < length; ++i) {
      rewards.remove(tokens[i]);
    }
  }

  function _claimAllNftRewards(address heroToken, uint heroId, address recipient) internal {
    bytes32[] storage rewards = _S()._heroNftRewards[heroToken.packNftId(heroId)];
    uint length = rewards.length;
    for (uint i; i < length; ++i) {
      (address token, uint id) = rewards[i].unpackNftId();
      IERC721(token).safeTransferFrom(address(this), recipient, id);
      emit IApplicationEvents.ClaimedItem(heroToken, heroId, token, id, recipient);
    }
    // a simple array can be just deleted
    delete _S()._heroNftRewards[heroToken.packNftId(heroId)];
  }

  function _generateReinforcementAttributes(IStatController sc, uint[] memory indexes, address heroToken, uint heroId)
  internal view returns (int32[] memory attributes) {
    attributes = new int32[](uint(IStatController.ATTRIBUTES.END_SLOT));
    for (uint i; i < indexes.length; ++i) {
      attributes[indexes[i]] = CalcLib.max32(sc.heroAttribute(heroToken, heroId, indexes[i]) * _ATTRIBUTES_RATIO / 100, 1);
    }
  }
  //endregion ------------------------ Internal logic

  //region ------------------------ Packing utils

  function packHeroInfo(IReinforcementController.HeroInfo memory info) internal pure returns (bytes32) {
    return PackingLib.packReinforcementHeroInfo(info.biome, uint128(info.score), info.fee, info.stakeTs);
  }

  function unpackHeroInfo(bytes32 packed) internal pure returns (IReinforcementController.HeroInfo memory info) {
    (info.biome, info.score, info.fee, info.stakeTs) = PackingLib.unpackReinforcementHeroInfo(packed);
    return info;
  }

  function packConfig(uint8 minLevel_, uint8 minLifeChances_) internal pure returns (bytes32) {
    return PackingLib.packUint8Array3(minLevel_, minLifeChances_, 0);
  }

  function unpackConfig(bytes32 packed) internal pure returns (uint8 minLevel_, uint8 minLifeChances_) {
    (minLevel_, minLifeChances_,) = PackingLib.unpackUint8Array3(packed);
  }

  //endregion ------------------------ Packing utils

}