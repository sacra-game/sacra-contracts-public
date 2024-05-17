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

import "../proxy/Controllable.sol";
import "../interfaces/IStoryController.sol";
import "../interfaces/IGOC.sol";
import "../lib/StoryControllerLib.sol";
import "../openzeppelin/ERC721Holder.sol";

contract StoryController is Controllable, IStoryController, ERC721Holder {
  //region ------------------------ CONSTANTS

  /// @notice Version of the contract
  /// @dev Should be incremented when contract changed
  string public constant override VERSION = "2.1.1";
  //endregion ------------------------ CONSTANTS

  //region ------------------------ INITIALIZER

  function init(address controller_) external initializer {
    __Controllable_init(controller_);
  }
  //endregion ------------------------ INITIALIZER

  //region ------------------------ VIEWS
  function idToStory(uint16 storyId) external view returns (uint32) {
    return StoryControllerLib.idToStory(storyId);
  }

  function storyBuildHash(uint16 storyId) external view returns (uint) {
    return StoryControllerLib.storyBuildHash(storyId);
  }

  function heroPage(address hero, uint80 heroId, uint16 storyId) external view override returns (uint16 pageId) {
    return StoryControllerLib.heroPage(hero, heroId, storyId);
  }

  function storyIds(uint32 objectId) external view override returns (uint16) {
    return StoryControllerLib.storyIds(objectId);
  }

  function registeredStories(uint32 objectId) external view override returns (bool) {
    return StoryControllerLib.registeredStories(objectId);
  }

  function allStoryPagesLength(uint16 storyId) external view returns (uint) {
    return StoryControllerLib.allStoryPagesLength(storyId);
  }

  function allStoryPages(uint16 storyId, uint index) external view returns (uint) {
    return StoryControllerLib.allStoryPages(storyId, index);
  }

  function allStoryAnswersLength(uint16 storyId) external view returns (uint) {
    return StoryControllerLib.allStoryAnswersLength(storyId);
  }

  function allStoryAnswers(uint16 storyId, uint index) external view returns (bytes32) {
    return StoryControllerLib.allStoryAnswers(storyId, index);
  }

  function currentHeroAnswers(uint16 storyId, address hero, uint80 heroId) public view returns (bytes32[] memory) {
    return StoryControllerLib.currentHeroAnswers(IController(controller()), storyId, hero, heroId);
  }

  function isStoryAvailableForHero(uint32 objectId, address heroToken, uint heroTokenId) external view override returns (bool) {
    return StoryControllerLib.isStoryAvailableForHero(IController(controller()), objectId, heroToken, heroTokenId);
  }

  //endregion ------------------------ VIEWS

  //region ------------------------ SETTERS

  function setAllStoryFields(StoryMetaInfo calldata meta) external {
    StoryControllerLib.setAllStoryFields(IController(controller()), meta);
  }

  function setBurnItemsMeta(uint16 storyId, AnswerBurnRandomItemMeta calldata meta) external {
    StoryControllerLib.setBurnItemsMeta(IController(controller()), storyId, meta);
  }

  function setNextObjRewriteMeta(uint16 storyId, NextObjRewriteMeta calldata meta) external {
    StoryControllerLib.setNextObjRewriteMeta(IController(controller()), storyId, meta);
  }

  function setAnswersMeta(
    uint16 storyId,
    uint16[] calldata answerPageIds,
    uint8[] calldata answerHeroClasses,
    uint16[] calldata answerIds
  ) external {
    StoryControllerLib.setAnswersMeta(IController(controller()), storyId, answerPageIds, answerHeroClasses, answerIds);
  }

  function setAnswerNextPageMeta(uint16 storyId, AnswerNextPageMeta calldata meta) external {
    StoryControllerLib.setAnswerNextPageMeta(IController(controller()), storyId, meta);
  }

  function setAnswerAttributeRequirements(uint16 storyId, AnswerAttributeRequirementsMeta calldata meta) external {
    StoryControllerLib.setAnswerAttributeRequirements(IController(controller()), storyId, meta);
  }

  function setAnswerItemRequirements(uint16 storyId, AnswerItemRequirementsMeta calldata meta) external {
    StoryControllerLib.setAnswerItemRequirements(IController(controller()), storyId, meta);
  }

  function setAnswerTokenRequirementsMeta(uint16 storyId, AnswerTokenRequirementsMeta calldata meta) external {
    StoryControllerLib.setAnswerTokenRequirementsMeta(IController(controller()), storyId, meta);
  }

  function setAnswerAttributes(uint16 storyId, AnswerAttributesMeta calldata meta) external {
    StoryControllerLib.setAnswerAttributes(IController(controller()), storyId, meta);
  }

  function setAnswerHeroCustomDataRequirementMeta(uint16 storyId, AnswerCustomDataMeta calldata meta) external {
    StoryControllerLib.setAnswerHeroCustomDataRequirementMeta(IController(controller()), storyId, meta);
  }

  function setAnswerGlobalCustomDataRequirementMeta(uint16 storyId, AnswerCustomDataMeta calldata meta) external {
    StoryControllerLib.setAnswerGlobalCustomDataRequirementMeta(IController(controller()), storyId, meta);
  }

  function setSuccessInfo(uint16 storyId, AnswerResultMeta calldata meta) external {
    StoryControllerLib.setSuccessInfo(IController(controller()), storyId, meta);
  }

  function setFailInfo(uint16 storyId, AnswerResultMeta calldata meta) external {
    StoryControllerLib.setFailInfo(IController(controller()), storyId, meta);
  }

  function setCustomDataResult(uint16 storyId, AnswerCustomDataResultMeta calldata meta, CustomDataResult type_) external {
    StoryControllerLib.setCustomDataResult(IController(controller()), storyId, meta, type_);
  }

  function setStoryCustomDataRequirements(
    uint16 storyId,
    bytes32[] calldata requiredCustomDataIndex,
    uint64[] calldata requiredCustomDataMinValue,
    uint64[] calldata requiredCustomDataMaxValue,
    bool[] calldata requiredCustomDataIsHero,
    uint minLevel
  ) external {
    StoryControllerLib.setStoryCustomDataRequirements(
      IController(controller()),
      storyId,
      requiredCustomDataIndex,
      requiredCustomDataMinValue,
      requiredCustomDataMaxValue,
      requiredCustomDataIsHero,
      minLevel
    );
  }

  function finalizeStoryRegistration(uint16 storyId, uint32 objectId, uint buildHash) external {
    StoryControllerLib.finalizeStoryRegistration(IController(controller()), storyId, objectId, buildHash);
  }
  //endregion ------------------------ SETTERS

  //region ------------------------ CHANGE META

  function removeStory(uint32 objectId) external {
    StoryControllerLib.removeStory(IController(controller()), objectId);
  }

  function removeStoryPagesMeta(uint16 storyId, uint maxIterations) external {
    StoryControllerLib.removeStoryPagesMeta(IController(controller()), storyId, maxIterations);
  }

  function removeStoryAnswersMeta(uint16 storyId, uint maxIterations) external {
    StoryControllerLib.removeStoryAnswersMeta(IController(controller()), storyId, maxIterations);
  }
  //endregion ------------------------ CHANGE META

  //region ------------------------ MAIN LOGIC

  function storyAction(
    address sender,
    uint64 dungeonId,
    uint32 objectId,
    uint stageId,
    address heroToken,
    uint heroTokenId,
    uint8 biome,
    uint iteration,
    bytes memory data
  ) external override returns (IGOC.ActionResult memory result) {
    return StoryControllerLib.storyAction(
      IController(controller()),
      sender,
      dungeonId,
      objectId,
      stageId,
      heroToken,
      heroTokenId,
      biome,
      iteration,
      data
    );
  }
  //endregion ------------------------ MAIN LOGIC

}
