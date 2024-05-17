// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.23;

import "../openzeppelin/MerkleProof.sol";
import "../openzeppelin/ERC721Holder.sol";
import "../relay/ERC2771Context.sol";
import "../interfaces/IApplicationEvents.sol";
import "../interfaces/IHeroController.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IAppErrors.sol";
import "../interfaces/IERC721.sol";

contract SponsoredHero is ERC2771Context, ERC721Holder {
  //region ------------------------ Members
  IHeroController public immutable heroController;
  IERC20 public immutable gameToken;
  IController public immutable controller;

  /// @notice List of roots of registered merkle trees
  /// @dev First tree is registered in constructor. Other trees can be added later using {addTree}
  bytes32[] public merkleRoots;

  /// @notice merkleRoot => claimant => started claim marker
  mapping(bytes32 merkleRoot => mapping (address user => bool isClaimStarted)) public claimStarted;

  /// @notice merkleRoot => claimant => remain available heroes (or 0 if the claim is not started)
  /// @dev lazy initialization of first create
  mapping(bytes32 merkleRoot => mapping (address user => uint heroesAvailable)) public heroesAvailable;
  //endregion ------------------------ Members

  //region ------------------------ Constructor

  /// @dev Use {addTree} to registry first tree
  constructor(address controller_) {
    controller = IController(controller_);

    address _gameToken = IController(controller_).gameToken();
    gameToken = IERC20(_gameToken);

    address _heroController = IController(controller_).heroController();
    heroController = IHeroController(_heroController);

    // infinity approve
    IERC20(_gameToken).approve(IHeroController(_heroController).heroTokensVault(), type(uint256).max);
  }
  //endregion ------------------------ Constructor

  //region ------------------------ View
  /// @return claimStartedOut Values of is-claim-started for each registered merkle tree
  /// @return heroesAvailableOut Count of heroes available for each registered merkle tree.
  /// If claiming for the given tree is not started heroesAvailable is 0
  /// because the value is initialized at the first call of create().
  function userInfo(address user) external view returns (bool[] memory claimStartedOut, uint[] memory heroesAvailableOut) {
    uint len = merkleRoots.length;
    claimStartedOut = new bool[](len);
    heroesAvailableOut = new uint[](len);
    for (uint i; i < len; ++i) {
      bytes32 merkleRoot = merkleRoots[i];
      claimStartedOut[i] = claimStarted[merkleRoot][user];
      heroesAvailableOut[i] = heroesAvailable[merkleRoot][user];
    }
  }

  /// @notice Try to verify using the merkle tree with the given {indexTree}
  function verify(bytes32[] memory proof, address addr, uint256 amount, uint indexTree) public view returns (bool) {
    bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr, amount))));
    return MerkleProof.verify(proof, merkleRoots[indexTree], leaf);
  }

  /// @notice Total count of registered merkle trees >= 1
  function merkleRootsLength() external view returns (uint) {
    return merkleRoots.length;
  }
  //endregion ------------------------ View

  //region ------------------------ Logic

  /// @notice Create new hero using. Verification is made using merkle tree with the given {indexTree}.
  /// @notice Signer should put enough game token on balance of the contract before the call.
  /// Simplest way to do it is to approve {heroCreationFee} amount and call {sendHeroCreationFee}
  /// @param indexTree Index of the required tree in {merkleRoots}.
  /// The merkle tree is selected by signer off-chain according to data received through {userInfo}.
  function create(
    bytes32[] memory proof,
    uint airdroppedAmount,
    uint indexTree,
    address heroAddress,
    string memory heroName_,
    bool enter
  ) external {
    onlyEOA();

    address user = _msgSender();
    uint heroClass = heroController.heroClass(heroAddress);

    // only 4 hero classes available (heroes 5 and 6 are free)
    if (heroClass == 0 || heroClass >= 5) revert IAppErrors.InvalidHeroClass();

    bytes32 merkleRoot = merkleRoots[indexTree];

    if (claimStarted[merkleRoot][user]) {
      uint _heroesAvailable = heroesAvailable[merkleRoot][user];
      if (_heroesAvailable == 0) revert IAppErrors.NoHeroesAvailable();
      heroesAvailable[merkleRoot][user] = _heroesAvailable - 1;
    } else {
      if (airdroppedAmount == 0) revert IAppErrors.ZeroAmount();

      if (!verify(proof, user, airdroppedAmount, indexTree)) revert IAppErrors.InvalidProof();
      claimStarted[merkleRoot][user] = true;
      heroesAvailable[merkleRoot][user] = airdroppedAmount - 1;
    }

    uint heroId = heroController.create(heroAddress, heroName_, enter);

    IERC721(heroAddress).safeTransferFrom(address(this), user, heroId);

    emit IApplicationEvents.SponsoredHeroCreated(user, heroAddress, heroId, heroName_);
  }

  /// @notice Register a merkle tree
  /// @param amount Total fee required to create all heroes from the tree.
  /// The given amount of {gameToken} will be transferred from the signer to the balance.
  /// Pass 0 to skip transferring.
  function addTree(bytes32 root_, uint amount) external {
    if (controller.governance() != msg.sender) revert IAppErrors.NotGovernance(msg.sender);
    if (amount == 0) revert IAppErrors.ZeroAmount();

    IERC20(gameToken).transferFrom(msg.sender, address(this), amount);

    // don't allow to add same tree twice
    uint len = merkleRoots.length;
    for (uint i; i < len; ++i) {
      if (merkleRoots[i] == root_) revert IAppErrors.AlreadyRegistered();
    }

    merkleRoots.push(root_);
  }

  function salvage(address receiver_, address token_, uint amount_) external {
    if (controller.governance() != msg.sender) revert IAppErrors.ErrorForbidden(msg.sender);

    IERC20(token_).transfer(receiver_, amount_);
  }
  //endregion ------------------------ Logic
}
