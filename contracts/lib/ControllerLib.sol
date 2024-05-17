// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IERC20.sol";
import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IProxyControlled.sol";

library ControllerLib {
  //region ------------------------ Constants
  /// @dev keccak256(abi.encode(uint256(keccak256("controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant CONTROLLER_STORAGE_LOCATION = 0x4d96152d518acf5697a667aeb82f27b3218b679995afa077296a84fdcb65bb00;
  uint internal constant DEPLOYER_ELIGIBILITY_PERIOD = 7 days;
  //endregion ------------------------ Constants

  //region ------------------------ Data types

  /// @custom:storage-location erc7201:controller.main
  struct MainState {
    address governance;
    address futureGovernance;

    address statController;
    address storyController;
    address oracle;
    address treasury;
    address dungeonFactory;
    address gameObjectController;
    address reinforcementController;
    address itemController;
    address heroController;
    address gameToken;

    mapping(address => bool) validTreasuryTokens;
    /// @dev EOA => eligibility time. We assume that deployer is fresh EOA and will be changed every deploy cycle for security reasons.
    mapping(address => uint) deployers;
    /// @dev In emergency case governance can pause all game
    bool onPause;
  }
  //endregion ------------------------ Data types

  //region ------------------------ Restrictions

  function onlyGovernance() internal view {
    if (!_isGovernance(msg.sender)) revert IAppErrors.NotGovernance(msg.sender);
  }

  function onlyDeployer() internal view {
    if (!isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ Views

  function _S() internal pure returns (MainState storage s) {
    assembly {
      s.slot := CONTROLLER_STORAGE_LOCATION
    }
    return s;
  }

  function isDeployer(address adr) internal view returns (bool) {
    uint t = _S().deployers[adr];
    return (t != 0 && block.timestamp < t) || _isGovernance(adr);
  }

  function governance() internal view returns (address) {return _S().governance;}

  function futureGovernance() internal view returns (address) {return _S().futureGovernance;}

  function statController() internal view returns (address) {return _S().statController;}

  function storyController() internal view returns (address) {return _S().storyController;}

  function oracle() internal view returns (address) {return _S().oracle;}

  function treasury() internal view returns (address) {return _S().treasury;}

  function dungeonFactory() internal view returns (address) {return _S().dungeonFactory;}

  function gameObjectController() internal view returns (address) {return _S().gameObjectController;}

  function reinforcementController() internal view returns (address) {return _S().reinforcementController;}

  function itemController() internal view returns (address) {return _S().itemController;}

  function heroController() internal view returns (address) {return _S().heroController;}

  function gameToken() internal view returns (address) {return _S().gameToken;}

  function validTreasuryTokens(address token) internal view returns (bool) {
    return _S().validTreasuryTokens[token];
  }

  function onPause() internal view returns (bool) {return _S().onPause;}
  //endregion ------------------------ Views

  //region ------------------------ Gov actions - setters

  function changePause(bool value) internal {
    onlyDeployer();
    _S().onPause = value;
  }

  function offerGovernance(address newGov) internal {
    onlyGovernance();
    _S().futureGovernance = newGov;
    emit IApplicationEvents.OfferGovernance(newGov);
  }

  function acceptGovernance() internal {
    if (_S().futureGovernance != msg.sender) revert IAppErrors.NotFutureGovernance(msg.sender);
    _S().governance = msg.sender;
    delete _S().futureGovernance;
    emit IApplicationEvents.GovernanceAccepted(msg.sender);
  }

  function setStatController(address value) internal {
    onlyGovernance();
    if (value == address(0)) revert IAppErrors.ZeroAddress();
    _S().statController = value;
    emit IApplicationEvents.StatControllerChanged(value);
  }

  function setStoryController(address value) internal {
    onlyGovernance();
    if (value == address(0)) revert IAppErrors.ZeroAddress();
    _S().storyController = value;
    emit IApplicationEvents.StoryControllerChanged(value);
  }

  function setGameObjectController(address value) internal {
    onlyGovernance();
    if (value == address(0)) revert IAppErrors.ZeroAddress();
    _S().gameObjectController = value;
    emit IApplicationEvents.GameObjectControllerChanged(value);
  }

  function setReinforcementController(address value) internal {
    onlyGovernance();
    if (value == address(0)) revert IAppErrors.ZeroAddress();
    _S().reinforcementController = value;
    emit IApplicationEvents.ReinforcementControllerChanged(value);
  }

  function setOracle(address value) internal {
    onlyGovernance();
    if (value == address(0)) revert IAppErrors.ZeroAddress();
    _S().oracle = value;
    emit IApplicationEvents.OracleChanged(value);
  }

  function setTreasury(address value) internal {
    onlyGovernance();
    if (value == address(0)) revert IAppErrors.ZeroAddress();
    _S().treasury = value;
    emit IApplicationEvents.TreasuryChanged(value);
  }

  function setItemController(address value) internal {
    onlyGovernance();
    if (value == address(0)) revert IAppErrors.ZeroAddress();
    _S().itemController = value;
    emit IApplicationEvents.ItemControllerChanged(value);
  }

  function setHeroController(address value) internal {
    onlyGovernance();
    if (value == address(0)) revert IAppErrors.ZeroAddress();
    _S().heroController = value;
    emit IApplicationEvents.HeroControllerChanged(value);
  }

  function setGameToken(address value) internal {
    onlyGovernance();
    if (value == address(0)) revert IAppErrors.ZeroAddress();
    _S().gameToken = value;
    emit IApplicationEvents.GameTokenChanged(value);
  }

  function setDungeonFactory(address value) internal {
    onlyGovernance();
    if (value == address(0)) revert IAppErrors.ZeroAddress();
    _S().dungeonFactory = value;
    emit IApplicationEvents.DungeonFactoryChanged(value);
  }

  function changeDeployer(address eoa, bool remove) internal {
    onlyGovernance();
    if (remove) {
      delete _S().deployers[eoa];
    } else {
      _S().deployers[eoa] = block.timestamp + DEPLOYER_ELIGIBILITY_PERIOD;
    }
  }
  //endregion ------------------------ Gov actions - setters

  //region ------------------------ Gov actions - others

  function updateProxies(address[] memory proxies, address newLogic) internal {
    onlyDeployer();
    for (uint i; i < proxies.length; i++) {
      IProxyControlled(proxies[i]).upgrade(newLogic);
      emit IApplicationEvents.ProxyUpdated(proxies[i], newLogic);
    }
  }

  function claimToGovernance(address token) internal {
    onlyGovernance();
    uint amount = IERC20(token).balanceOf(address(this));
    if (amount != 0) {
      IERC20(token).transfer(_S().governance, amount);
      emit IApplicationEvents.Claimed(token, amount);
    }
  }
  //endregion ------------------------ Gov actions - others

  //region ------------------------ REGISTER ACTIONS

  function changeTreasuryTokenStatus(address token, bool status) internal {
    onlyGovernance();
    _S().validTreasuryTokens[token] = status;
    emit IApplicationEvents.TokenStatusChanged(token, status);
  }
  //endregion ------------------------ REGISTER ACTIONS

  //region ------------------------  Internal logic
  function _isGovernance(address _value) internal view returns (bool) {
    return IController(address(this)).governance() == _value;
  }
  //endregion ------------------------  Internal logic
}
