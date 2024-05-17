// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;
import "../proxy/Controllable.sol";
import "../interfaces/IStoryController.sol";
import "../interfaces/IStatController.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ITreasury.sol";
import "../interfaces/IGOC.sol";
import "../interfaces/IHeroController.sol";
import "../lib/StoryLib.sol";
import "../lib/PackingLib.sol";
import "../lib/StorySetupLib.sol";


library StoryControllerLib {
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using CalcLib for uint;
  using PackingLib for bytes32;
  using PackingLib for uint16;
  using PackingLib for uint8;
  using PackingLib for address;
  using PackingLib for uint32[];
  using PackingLib for uint32;
  using PackingLib for uint64;
  using PackingLib for int32[];
  using PackingLib for int32;


  //region ------------------------ CONSTANTS
  /// @dev keccak256(abi.encode(uint256(keccak256("story.controller.main")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant MAIN_STORAGE_LOCATION = 0x1fbca2ab9841348cca3f2687c48325e9989a76ad929b9970d1c11e233677cf00;
  //endregion ------------------------ CONSTANTS


  //region ------------------------ Restrictions
  function onlyDeployer(IController controller) internal view {
    if (!controller.isDeployer(msg.sender)) revert IAppErrors.ErrorNotDeployer(msg.sender);
  }
  //endregion ------------------------ Restrictions

  //region ------------------------ VIEWS


  function _S() internal pure returns (IStoryController.MainState storage s) {
    assembly {
      s.slot := MAIN_STORAGE_LOCATION
    }
    return s;
  }

  function idToStory(uint16 storyId) internal view returns (uint32) {
    return _S().idToStory[storyId];
  }

  function storyBuildHash(uint16 storyId) internal view returns (uint) {
    return _S().storyBuildHash[storyId];
  }

  function heroPage(address hero, uint80 heroId, uint16 storyId) internal view returns (uint16 pageId) {
    (pageId,) = _S().heroState[hero.packStoryHeroStateId(heroId, storyId)].unpackStoryHeroState();
  }

  function storyIds(uint32 objectId) internal view returns (uint16) {
    return _S().storyIds[objectId];
  }

  function registeredStories(uint32 objectId) internal view returns (bool) {
    return _S().registeredStories[objectId];
  }

  function allStoryPagesLength(uint16 storyId) internal view returns (uint) {
    return _S().allStoryPages[storyId].length();
  }

  function allStoryPages(uint16 storyId, uint index) internal view returns (uint) {
    return _S().allStoryPages[storyId].at(index);
  }

  function allStoryAnswersLength(uint16 storyId) internal view returns (uint) {
    return _S().allStoryAnswers[storyId].length();
  }

  function allStoryAnswers(uint16 storyId, uint index) internal view returns (bytes32) {
    return _S().allStoryAnswers[storyId].at(index);
  }

  /// @notice Get list of answers for the current page stored in the hero state
  /// @return List of answers for the (page, heroClass). If the list is empty return default answers for (page, 0)
  function currentHeroAnswers(IController controller, uint16 storyId, address hero, uint80 heroId) internal view returns (
    bytes32[] memory
  ) {
    IHeroController hc = IHeroController(controller.heroController());

    (uint16 pageId,) = _S().heroState[hero.packStoryHeroStateId(heroId, storyId)].unpackStoryHeroState();
    bytes32[] memory heroAnswers = _S().answers[storyId.packStoryPageId(pageId, hc.heroClass(hero))];

    if (heroAnswers.length == 0) {
      heroAnswers = _S().answers[storyId.packStoryPageId(pageId, 0)];
    }

    if (heroAnswers.length != 0) {
      // shuffle answers using Fisher–Yates shuffle algorithm
      for (uint i; i < heroAnswers.length - 1; i++) {
        uint randomIndex = CalcLib.pseudoRandomInRange(i, heroAnswers.length - 1);
        (heroAnswers[randomIndex], heroAnswers[i]) = (heroAnswers[i], heroAnswers[randomIndex]);
      }
    }

    return heroAnswers;
  }

  function isStoryAvailableForHero(IController controller, uint32 objectId, address heroToken, uint heroTokenId) internal view returns (bool) {
    return StoryLib.isStoryAvailableForHero(_S(), _S().storyIds[objectId], heroToken, heroTokenId, controller.statController());
  }

  //endregion ------------------------ VIEWS

  //region ------------------------ SETTERS

  function setAllStoryFields(IController controller, IStoryController.StoryMetaInfo calldata meta) internal {
    onlyDeployer(controller);
    StorySetupLib.setAllStoryFields(_S(), meta);
  }

  function setBurnItemsMeta(
    IController controller,
    uint16 storyId,
    IStoryController.AnswerBurnRandomItemMeta calldata meta
  ) internal {
    onlyDeployer(controller);
    StorySetupLib.setBurnItemsMeta(_S(), storyId, meta);
  }

  function setNextObjRewriteMeta(IController controller, uint16 storyId, IStoryController.NextObjRewriteMeta calldata meta) internal {
    onlyDeployer(controller);
    StorySetupLib.setNextObjRewriteMeta(_S(), storyId, meta);
  }

  function setAnswersMeta(
    IController controller,
    uint16 storyId,
    uint16[] calldata answerPageIds,
    uint8[] calldata answerHeroClasses,
    uint16[] calldata answerIds
  ) internal {
    onlyDeployer(controller);
    StorySetupLib.setAnswersMeta(_S(), storyId, answerPageIds, answerHeroClasses, answerIds);
  }

  function setAnswerNextPageMeta(IController controller, uint16 storyId, IStoryController.AnswerNextPageMeta calldata meta) internal {
    onlyDeployer(controller);
    StorySetupLib.setAnswerNextPageMeta(_S(), storyId, meta);
  }

  function setAnswerAttributeRequirements(IController controller, uint16 storyId, IStoryController.AnswerAttributeRequirementsMeta calldata meta) internal {
    onlyDeployer(controller);
    StorySetupLib.setAnswerAttributeRequirements(_S(), storyId, meta);
  }

  function setAnswerItemRequirements(IController controller, uint16 storyId, IStoryController.AnswerItemRequirementsMeta calldata meta) internal {
    onlyDeployer(controller);
    StorySetupLib.setAnswerItemRequirements(_S(), storyId, meta);
  }

  function setAnswerTokenRequirementsMeta(IController controller, uint16 storyId, IStoryController.AnswerTokenRequirementsMeta calldata meta) internal {
    onlyDeployer(controller);
    StorySetupLib.setAnswerTokenRequirementsMeta(_S(), storyId, meta);
  }

  function setAnswerAttributes(IController controller, uint16 storyId, IStoryController.AnswerAttributesMeta calldata meta) internal {
    onlyDeployer(controller);
    StorySetupLib.setAnswerAttributes(_S(), storyId, meta);
  }

  function setAnswerHeroCustomDataRequirementMeta(IController controller, uint16 storyId, IStoryController.AnswerCustomDataMeta calldata meta) internal {
    onlyDeployer(controller);
    StorySetupLib.setAnswerHeroCustomDataRequirementMeta(_S(), storyId, meta);
  }

  function setAnswerGlobalCustomDataRequirementMeta(IController controller, uint16 storyId, IStoryController.AnswerCustomDataMeta calldata meta) internal {
    onlyDeployer(controller);
    StorySetupLib.setAnswerGlobalCustomDataRequirementMeta(_S(), storyId, meta);

  }

  function setSuccessInfo(IController controller, uint16 storyId, IStoryController.AnswerResultMeta calldata meta) internal {
    onlyDeployer(controller);
    StorySetupLib.setSuccessInfo(_S(), storyId, meta);
  }

  function setFailInfo(IController controller, uint16 storyId, IStoryController.AnswerResultMeta calldata meta) internal {
    onlyDeployer(controller);
    StorySetupLib.setFailInfo(_S(), storyId, meta);
  }

  function setCustomDataResult(
    IController controller,
    uint16 storyId,
    IStoryController.AnswerCustomDataResultMeta calldata meta,
    IStoryController.CustomDataResult type_
  ) internal {
    onlyDeployer(controller);
    StorySetupLib.setCustomDataResult(_S(), storyId, meta, type_);
  }

  function setStoryCustomDataRequirements(
    IController controller,
    uint16 storyId,
    bytes32[] calldata requiredCustomDataIndex,
    uint64[] calldata requiredCustomDataMinValue,
    uint64[] calldata requiredCustomDataMaxValue,
    bool[] calldata requiredCustomDataIsHero,
    uint minLevel
  ) internal {
    onlyDeployer(controller);
    StorySetupLib.setStoryCustomDataRequirements(_S(), storyId, requiredCustomDataIndex, requiredCustomDataMinValue, requiredCustomDataMaxValue, requiredCustomDataIsHero, minLevel);
  }

  function finalizeStoryRegistration(IController controller, uint16 storyId, uint32 objectId, uint buildHash) internal {
    onlyDeployer(controller);
    StorySetupLib.finalizeStoryRegistration(_S(), storyId, objectId, buildHash);
  }
  //endregion ------------------------ SETTERS

  //region ------------------------ CHANGE META

  function removeStory(IController controller, uint32 objectId) internal {
    onlyDeployer(controller);
    StorySetupLib.removeStory(_S(), objectId);
  }

  function removeStoryPagesMeta(IController controller, uint16 storyId, uint maxIterations) internal {
    onlyDeployer(controller);
    StorySetupLib.removeStoryPagesMeta(_S(), storyId, maxIterations);
  }

  function removeStoryAnswersMeta(IController controller, uint16 storyId, uint maxIterations) internal {
    onlyDeployer(controller);
    StorySetupLib.removeStoryAnswersMeta(_S(), storyId, maxIterations);
  }
  //endregion ------------------------ CHANGE META

  //region ------------------------ MAIN LOGIC

  function storyAction(
    IController controller,
    address sender,
    uint64 dungeonId,
    uint32 objectId,
    uint stageId,
    address heroToken,
    uint heroTokenId,
    uint8 biome,
    uint iteration,
    bytes memory data
  ) internal returns (IGOC.ActionResult memory result) {
    if (controller.gameObjectController() != msg.sender) revert IAppErrors.ErrorNotObjectController(msg.sender);

    IStatController statController = IStatController(controller.statController());
    IStoryController.StoryActionContext memory context = IStoryController.StoryActionContext({
      sender: sender,
      dungeonId: dungeonId,
      objectId: objectId,
      storyId: _S().storyIds[objectId],
      stageId: stageId,
      controller: controller,
      statController: statController,
      heroToken: heroToken,
      heroTokenId: uint80(heroTokenId),
      heroClass: 0,
      storyIdFromAnswerHash: 0,
      pageIdFromAnswerHash: 0,
      heroClassFromAnswerHash: 0,
      answerNumber: 0,
      answerIdHash: _decodeAnswerId(data),
      pageId: 0,
      heroLastActionTS: 0,
      answerAttributes: bytes32(0),
      heroStats: statController.heroStats(heroToken, heroTokenId),
      biome: biome,
      oracle: IOracle(controller.oracle()),
      iteration: iteration,
      heroController: IHeroController(controller.heroController()),
      itemController: IItemController(controller.itemController())
    });

    if (context.storyId == 0) revert IAppErrors.ZeroStoryIdStoryAction();

    context.heroClass = context.heroController.heroClass(heroToken);
    context.answerAttributes = _S().answerAttributes[context.answerIdHash];

    (context.pageId, context.heroLastActionTS) = _S().heroState[heroToken.packStoryHeroStateId(uint80(heroTokenId), context.storyId)].unpackStoryHeroState();

    (context.storyIdFromAnswerHash,
      context.pageIdFromAnswerHash,
      context.heroClassFromAnswerHash,
      context.answerNumber
    ) = context.answerIdHash.unpackStoryAnswerId();

    result = _handleAnswer(context, currentHeroAnswers(controller, context.storyId, heroToken, uint80(heroTokenId)));
  }

  /// @param heroAnswers Full list of possible answers (to be able to check that the answer belongs to the list)
  function _handleAnswer(IStoryController.StoryActionContext memory context, bytes32[] memory heroAnswers) internal returns (
    IGOC.ActionResult memory results
  ) {
    IStoryController.MainState storage s = _S();

    if (heroAnswers.length == 0) {
      results.objectId = context.objectId;
      results.heroTokenId = context.heroTokenId;
      results.heroToken = context.heroToken;
      results.completed = true;
    } else {
      // check ids only if answer exists, for empty answers we can accept empty answer hash from user
      if (context.storyId != context.storyIdFromAnswerHash) revert IAppErrors.AnswerStoryIdMismatch(context.storyId, context.storyIdFromAnswerHash);
      if (context.pageId != context.pageIdFromAnswerHash) revert IAppErrors.AnswerPageIdMismatch(context.pageId, context.pageIdFromAnswerHash);

      // ensure that the given answer belongs to the list of the available answers
      StoryLib.checkAnswerIndexValid(heroAnswers, context.answerIdHash);
      (,, bool finalAnswer) = context.answerAttributes.unpackStorySimpleRequirement();

      // check answer requirements, burn items, transfer tokens and so on
      IStoryController.AnswerResultId answerResult = StoryLib.checkAnswer(context, s);

      // burn randomly selected items
      StoryLib.burn(context, s);

      // handle answer - refresh states
      uint16 nextPage;
      uint16[] memory nextPages;
      (results, nextPage, nextPages) = StoryLib.handleAnswer(answerResult, s, context);

      if (finalAnswer || nextPages.length == 0) {
        results.completed = true;
      } else {
        s.heroState[context.heroToken.packStoryHeroStateId(context.heroTokenId, context.storyId)] = nextPage.packStoryHeroState(uint40(block.timestamp));
      }
    }

    if (results.completed) {
      results.rewriteNextObject = StoryLib.finishStory(context, s);
    }

    return results;
  }
  //endregion ------------------------ MAIN LOGIC

  //region ------------------------ Utils
  function _decodeAnswerId(bytes memory data) internal pure returns (bytes32 answerId) {
    (answerId) = abi.decode(data, (bytes32));
  }
  //endregion ------------------------ Utils

}
