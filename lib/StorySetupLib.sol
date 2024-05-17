// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "../interfaces/IStoryController.sol";
import "../interfaces/IAppErrors.sol";
import "../interfaces/IApplicationEvents.sol";
import "../lib/PackingLib.sol";
import "../lib/StatLib.sol";

library StorySetupLib {
  using EnumerableSet for EnumerableSet.UintSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using PackingLib for bytes32;
  using PackingLib for uint16;
  using PackingLib for uint8;
  using PackingLib for address;
  using PackingLib for uint32[];
  using PackingLib for uint32;
  using PackingLib for uint64;
  using PackingLib for int32[];
  using PackingLib for int32;

  //region ------------------ Data types
  struct RemoveStoryContext {
    uint8 heroClass;
    uint8 answerResultId;
    uint8 customDataResultId;
    uint16 storyId;
    uint16 pageId;
    uint16 answerNum;
    uint len;
    uint[] tmpPages;
    bytes32 answerId;
    bytes32[] tmpAnswers;
  }
  //endregion ------------------ Data types

  //region ------------------ Set story fields

  function setAllStoryFields(IStoryController.MainState storage s, IStoryController.StoryMetaInfo memory meta) external {
    setBurnItemsMeta(s, meta.storyId, meta.answerBurnRandomItemMeta);
    setNextObjRewriteMeta(s, meta.storyId, meta.nextObjRewriteMeta);
    setAnswersMeta(
      s,
      meta.storyId,
      meta.answersMeta.answerPageIds,
      meta.answersMeta.answerHeroClasses,
      meta.answersMeta.answerIds
    );
    setAnswerNextPageMeta(s, meta.storyId, meta.answerNextPage);
    setAnswerAttributeRequirements(s, meta.storyId, meta.answerAttributeRequirements);
    setAnswerItemRequirements(s, meta.storyId, meta.answerItemRequirements);
    setAnswerTokenRequirementsMeta(s, meta.storyId, meta.answerTokenRequirements);
    setAnswerAttributes(s, meta.storyId, meta.answerAttributes);
    setAnswerHeroCustomDataRequirementMeta(s, meta.storyId, meta.answerHeroCustomDataRequirement);
    setAnswerGlobalCustomDataRequirementMeta(s, meta.storyId, meta.answerGlobalCustomDataRequirement);

    setSuccessInfo(s, meta.storyId, meta.successInfo);
    setFailInfo(s, meta.storyId, meta.failInfo);

    setCustomDataResult(s, meta.storyId, meta.successHeroCustomData, IStoryController.CustomDataResult.HERO_SUCCESS);
    setCustomDataResult(s, meta.storyId, meta.failHeroCustomData, IStoryController.CustomDataResult.HERO_FAIL);
    setCustomDataResult(s, meta.storyId, meta.successGlobalCustomData, IStoryController.CustomDataResult.GLOBAL_SUCCESS);
    setCustomDataResult(s, meta.storyId, meta.failGlobalCustomData, IStoryController.CustomDataResult.GLOBAL_FAIL);

    setStoryCustomDataRequirements(
      s,
      meta.storyId,
      meta.requiredCustomDataIndex,
      meta.requiredCustomDataMinValue,
      meta.requiredCustomDataMaxValue,
      meta.requiredCustomDataIsHero,
      meta.minLevel
    );

  }

  function setBurnItemsMeta(
    IStoryController.MainState storage s,
    uint16 storyId,
    IStoryController.AnswerBurnRandomItemMeta memory meta
  ) public {
    unchecked {
      uint len = meta.pageId.length;
      for (uint i; i < len; ++i) {
        bytes32 answerPackedId = _registerAnswer(s, storyId, meta.pageId[i], meta.heroClass[i], meta.answerId[i]);
        if (answerPackedId != bytes32(0)) {

          bytes32[] storage answersBurn = s.burnItem[answerPackedId];

          for (uint j; j < meta.slots[i].length; ++j) {
            bytes32 d = meta.slots[i][j].packBurnInfo(meta.chances[i][j], meta.isStopIfBurnt[i][j]);
            if (d != bytes32(0)) {
              answersBurn.push(d);
            }
          }
        }
      }
    }

    emit IApplicationEvents.SetBurnItemsMeta(storyId, meta);
  }

  function setNextObjRewriteMeta(IStoryController.MainState storage s, uint16 storyId, IStoryController.NextObjRewriteMeta memory meta) public {
    unchecked {
      uint len = meta.nextObjPageIds.length;
      for (uint i; i < len; ++i) {
        registerPage(s, storyId, meta.nextObjPageIds[i]);
        bytes32 id = storyId.packStoryPageId(meta.nextObjPageIds[i], meta.nextObjHeroClasses[i]);
        s.nextObjectsRewrite[id] = meta.nextObjIds[i];
      }
    }

    emit IApplicationEvents.SetNextObjRewriteMeta(storyId, meta);
  }

  function setAnswersMeta(
    IStoryController.MainState storage s,
    uint16 storyId,
    uint16[] memory answerPageIds,
    uint8[] memory answerHeroClasses,
    uint16[] memory answerIds
  ) public {
    unchecked {
      uint len = answerPageIds.length;
      for (uint i; i < len; ++i) {
        registerPage(s, storyId, answerPageIds[i]);

        bytes32[] storage answersHashes = s.answers[storyId.packStoryPageId(answerPageIds[i], answerHeroClasses[i])];

        bytes32 answerPackedId = _registerAnswer(s, storyId, answerPageIds[i], answerHeroClasses[i], answerIds[i]);
        if (answerPackedId != bytes32(0)) {
          answersHashes.push(answerPackedId);
        }
      }
    }

    emit IApplicationEvents.SetAnswersMeta(storyId, answerPageIds, answerHeroClasses, answerIds);
  }

  function setAnswerNextPageMeta(IStoryController.MainState storage s, uint16 storyId, IStoryController.AnswerNextPageMeta memory meta) public {
    unchecked {
      uint len = meta.pageId.length;
      for (uint i; i < len; ++i) {
        bytes32 answerPackedId = _registerAnswer(s, storyId, meta.pageId[i], meta.heroClass[i], meta.answerId[i]);
        if (answerPackedId != bytes32(0)) {
          bytes32 pagePackedId = storyId.packStoryNextPagesId(
            meta.pageId[i],
            meta.heroClass[i],
            meta.answerId[i],
            meta.answerResultIds[i]
          );
          // pagePackedId cannot be 0 here because answerPackedId is not 0
          s.nextPageIds[pagePackedId] = meta.answerNextPageIds[i];
        }
      }
    }

    emit IApplicationEvents.SetAnswerNextPageMeta(storyId, meta);
  }

  function setAnswerAttributeRequirements(IStoryController.MainState storage s, uint16 storyId, IStoryController.AnswerAttributeRequirementsMeta memory meta) public {
    unchecked {
      uint len = meta.pageId.length;
      for (uint i; i < len; ++i) {

        bytes32 answerPackedId = _registerAnswer(s, storyId, meta.pageId[i], meta.heroClass[i], meta.answerId[i]);
        if (answerPackedId != bytes32(0)) {
          bytes32[] storage attrs = s.attributeRequirements[answerPackedId];

          for (uint j; j < meta.cores[i].length; ++j) {
            bytes32 attributeRequirementsPacked = meta.ids[i][j].packStoryAttributeRequirement(
              meta.values[i][j],
              meta.cores[i][j]
            );

            if (attributeRequirementsPacked != bytes32(0)) {
              attrs.push(attributeRequirementsPacked);
            }
          }
        }
      }
    }

    emit IApplicationEvents.SetAnswerAttributeRequirements(storyId, meta);
  }

  function setAnswerItemRequirements(IStoryController.MainState storage s, uint16 storyId, IStoryController.AnswerItemRequirementsMeta memory meta) public {
    unchecked {
      uint len = meta.pageId.length;
      for (uint i; i < len; ++i) {

        bytes32 answerPackedId = _registerAnswer(s, storyId, meta.pageId[i], meta.heroClass[i], meta.answerId[i]);
        if (answerPackedId != bytes32(0)) {
          bytes32[] storage attrs = s.itemRequirements[answerPackedId];

          for (uint j; j < meta.requireItems[i].length; ++j) {
            bytes32 d = meta.requireItems[i][j].packStoryItemRequirement(
              meta.requireItemBurn[i][j],
              meta.requireItemEquipped[i][j]);

            if (d != bytes32(0)) {
              attrs.push(d);
            }
          }
        }
      }
    }

    emit IApplicationEvents.SetAnswerItemRequirements(storyId, meta);
  }

  function setAnswerTokenRequirementsMeta(IStoryController.MainState storage s, uint16 storyId, IStoryController.AnswerTokenRequirementsMeta memory meta) public {
    unchecked {
      uint len = meta.pageId.length;
      for (uint i; i < len; ++i) {

        bytes32 answerPackedId = _registerAnswer(s, storyId, meta.pageId[i], meta.heroClass[i], meta.answerId[i]);
        if (answerPackedId != bytes32(0)) {
          bytes32[] storage attrs = s.tokenRequirements[answerPackedId];

          for (uint j; j < meta.requireToken[i].length; ++j) {
            bytes32 d = meta.requireToken[i][j].packStoryTokenRequirement(
              meta.requireAmount[i][j],
              meta.requireTransfer[i][j]
            );
            if (d != bytes32(0)) {
              attrs.push(d);
            }
          }
        }
      }
    }

    emit IApplicationEvents.SetAnswerTokenRequirementsMeta(storyId, meta);
  }

  function setAnswerAttributes(IStoryController.MainState storage s, uint16 storyId, IStoryController.AnswerAttributesMeta memory meta) public {
    unchecked {
      uint len = meta.pageId.length;
      for (uint i; i < len; ++i) {
        bytes32 answerPackedId = _registerAnswer(s, storyId, meta.pageId[i], meta.heroClass[i], meta.answerId[i]);
        if (answerPackedId != bytes32(0)) {
          bytes32 data = meta.randomRequirements[i].packStorySimpleRequirement(
            meta.delayRequirements[i],
            meta.isFinalAnswer[i]
          );

          if (data != bytes32(0)) {
            s.answerAttributes[answerPackedId] = data;
          }
        }
      }
    }

    emit IApplicationEvents.SetAnswerAttributes(storyId, meta);
  }

  function setAnswerHeroCustomDataRequirementMeta(IStoryController.MainState storage s, uint16 storyId, IStoryController.AnswerCustomDataMeta memory meta) public {
    _setCustomDataRequirementMeta(s, storyId, meta, s.heroCustomDataRequirement);
    emit IApplicationEvents.SetAnswerHeroCustomDataRequirementMeta(storyId, meta);
  }

  function setAnswerGlobalCustomDataRequirementMeta(IStoryController.MainState storage s, uint16 storyId, IStoryController.AnswerCustomDataMeta memory meta) public {
    _setCustomDataRequirementMeta(s, storyId, meta, s.globalCustomDataRequirement);
    emit IApplicationEvents.SetAnswerGlobalCustomDataRequirementMeta(storyId, meta);
  }

  function setStoryCustomDataRequirements(
    IStoryController.MainState storage s,
    uint16 storyId,
    bytes32[] memory requiredCustomDataIndex,
    uint64[] memory requiredCustomDataMinValue,
    uint64[] memory requiredCustomDataMaxValue,
    bool[] memory requiredCustomDataIsHero,
    uint minLevel
  ) public {
    s.storyRequiredLevel[storyId] = minLevel;
    emit IApplicationEvents.StoryRequiredLevel(storyId, minLevel);

    IStoryController.CustomDataRequirementRangePacked[] storage allData = s.storyRequiredHeroData[storyId];

    for (uint i; i < requiredCustomDataIndex.length; ++i) {
      allData.push(IStoryController.CustomDataRequirementRangePacked({
        index: requiredCustomDataIndex[i],
        data: requiredCustomDataMinValue[i].packCustomDataRequirements(
          requiredCustomDataMaxValue[i],
          requiredCustomDataIsHero[i]
        )
      }));

      emit IApplicationEvents.StoryCustomDataRequirements(storyId, requiredCustomDataIndex[i], requiredCustomDataMinValue[i], requiredCustomDataMaxValue[i], requiredCustomDataIsHero[i]);
    }
  }

  function setSuccessInfo(IStoryController.MainState storage s, uint16 storyId, IStoryController.AnswerResultMeta memory meta) public {
    _setInfo(s, storyId, meta, s.successInfoAttributes, s.successInfoStats, s.successInfoMintItems);
    emit IApplicationEvents.SetSuccessInfo(storyId, meta);
  }

  function setFailInfo(IStoryController.MainState storage s, uint16 storyId, IStoryController.AnswerResultMeta memory meta) public {
    _setInfo(s, storyId, meta, s.failInfoAttributes, s.failInfoStats, s.failInfoMintItems);
    emit IApplicationEvents.SetFailInfo(storyId, meta);
  }

  function setCustomDataResult(
    IStoryController.MainState storage s,
    uint16 storyId,
    IStoryController.AnswerCustomDataResultMeta memory meta,
    IStoryController.CustomDataResult type_
  ) public {
    unchecked {
      uint len = meta.pageId.length;
      for (uint i; i < len; ++i) {
        if (_registerAnswer(s, storyId, meta.pageId[i], meta.heroClass[i], meta.answerId[i]) != bytes32(0)) {
          bytes32 answerPackedIdWithType = storyId.packStoryCustomDataResult(
            meta.pageId[i],
            meta.heroClass[i],
            meta.answerId[i],
            uint8(type_)
          );

          bytes32[] storage arr = s.customDataResult[answerPackedIdWithType];
          for (uint j; j < meta.dataIndexes[i].length; ++j) {
            arr.push(meta.dataIndexes[i][j].packCustomDataChange(meta.dataValues[i][j]));
          }
        }
      }
    }

    emit IApplicationEvents.SetCustomDataResult(storyId, meta, type_);
  }

  function finalizeStoryRegistration(
    IStoryController.MainState storage s,
    uint16 storyId,
    uint32 objectId,
    uint buildHash
  ) external {
    // it's not necessary to remove previously stored data here
    // we assume, that old data is already removed completely before registering new data

    s.registeredStories[objectId] = true;
    // store new used id
    s._usedStoryIds[storyId] = true;
    // register new id for story
    s.storyIds[objectId] = storyId;
    s.idToStory[storyId] = objectId;
    s.storyBuildHash[storyId] = buildHash;

    emit IApplicationEvents.StoryFinalized(objectId, storyId);
  }
  //endregion ------------------ Set story fields

  //region ------------------ Utils to set story fields
  function _registerAnswer(IStoryController.MainState storage s,  uint16 storyId, uint16 pageId, uint8 heroClass, uint16 answerId)
  internal returns (bytes32 answerPackedId) {
    answerPackedId = storyId.packStoryAnswerId(pageId, heroClass, answerId);
    if (answerPackedId != bytes32(0)) {
      registerAnswer(s, storyId, answerPackedId);
    }
  }

  /// @param map Either heroCustomDataRequirement or globalCustomDataRequirement
  function _setCustomDataRequirementMeta(
    IStoryController.MainState storage s,
    uint16 storyId,
    IStoryController.AnswerCustomDataMeta memory meta,
    mapping(bytes32 => IStoryController.CustomDataRequirementPacked[]) storage map
  ) internal {
    unchecked {
      uint len = meta.pageId.length;
      for (uint i; i < len; ++i) {

        bytes32 answerPackedId = _registerAnswer(s, storyId, meta.pageId[i], meta.heroClass[i], meta.answerId[i]);
        if (answerPackedId != bytes32(0)) {
          IStoryController.CustomDataRequirementPacked[] storage arr = map[answerPackedId];

          bytes32[] memory dataIndexes = meta.dataIndexes[i];
          bool[] memory mandatory = meta.mandatory[i];
          uint64[] memory dataValuesMin = meta.dataValuesMin[i];
          uint64[] memory dataValuesMax = meta.dataValuesMax[i];

          for (uint j; j < dataIndexes.length; ++j) {
            arr.push(
              IStoryController.CustomDataRequirementPacked({
                index: dataIndexes[j],
                data: dataValuesMin[j].packCustomDataRequirements(dataValuesMax[j], mandatory[j])
              })
            );
          }
        }
      }
    }
  }

  function _setInfo(
    IStoryController.MainState storage s,
    uint16 storyId,
    IStoryController.AnswerResultMeta memory meta,
    mapping(bytes32 => bytes32[]) storage infoAttributes,
    mapping(bytes32 => bytes32) storage infoStats,
    mapping(bytes32 => bytes32[]) storage infoMintItems
  ) public {
    unchecked {
      uint len = meta.pageId.length;
      for (uint i; i < len; ++i) {

        bytes32 answerPackedId = _registerAnswer(s, storyId, meta.pageId[i], meta.heroClass[i], meta.answerId[i]);
        if (answerPackedId != bytes32(0)) {
          if (meta.attributeIds[i].length != 0) {
            infoAttributes[answerPackedId] = meta.attributeValues[i].toBytes32ArrayWithIds(meta.attributeIds[i]);
          }

          bytes32 stats = PackingLib.packStatsChange(
            meta.experience[i],
            meta.heal[i],
            meta.manaRegen[i],
            meta.lifeChancesRecovered[i],
            meta.damage[i],
            meta.manaConsumed[i]
          );
          if (stats != bytes32(0)) {
            infoStats[answerPackedId] = stats;
          }

          uint lenItems = meta.mintItems[i].length;
          if (lenItems != 0) {
            bytes32[] memory items = new bytes32[](lenItems);
            for (uint j; j < lenItems; ++j) {
              items[j] = meta.mintItems[i][j].packItemMintInfo(meta.mintItemsChances[i][j]);
            }
            infoMintItems[answerPackedId] = items;
          }
        }
      }
    }
  }
  //endregion ------------------ Utils to set story fields

  //region ------------------ Remove logic
  // WE MUST REMOVE ALL EXIST META!
  // otherwise we will still have meta for story id and will totally mess data
  function removeStory(IStoryController.MainState storage s, uint32 objectId) external {
    if (s.storyIds[objectId] == 0 || !s.registeredStories[objectId]) revert IAppErrors.ZeroStoryIdRemoveStory();

    uint16 storyId = s.storyIds[objectId];
    delete s._usedStoryIds[storyId];
    delete s.storyIds[objectId];
    delete s.idToStory[storyId];
    delete s.registeredStories[objectId];
    delete s.storyBuildHash[storyId];

    delete s.storyRequiredHeroData[storyId];
    delete s.storyRequiredLevel[storyId];


    emit IApplicationEvents.StoryRemoved(objectId, storyId);
  }

  function removeStoryPagesMeta(IStoryController.MainState storage s, uint16 storyId, uint maxIterations) external {
    RemoveStoryContext memory ctx;
    ctx.storyId = storyId;

    // --- clean all data related to pages ---

    EnumerableSet.UintSet storage allPages = s.allStoryPages[ctx.storyId];
    ctx.len = allPages.length();
    if (ctx.len > maxIterations) {
      ctx.len = maxIterations;
    }
    ctx.tmpPages = new uint[](ctx.len);

    for (uint i; i < ctx.len; ++i) {
      ctx.tmpPages[i] = allPages.at(i);
      ctx.pageId = uint16(ctx.tmpPages[i]);

      // zero hero class means all classes
      for (ctx.heroClass = 0; ctx.heroClass < uint(StatLib.HeroClasses.END_SLOT); ++ctx.heroClass) {
        delete s.answers[ctx.storyId.packStoryPageId(ctx.pageId, ctx.heroClass)];
        delete s.nextObjectsRewrite[ctx.storyId.packStoryPageId(ctx.pageId, ctx.heroClass)];
      }
    }

    // remove all pages
    for (uint i; i < ctx.tmpPages.length; ++i) {
      if (!allPages.remove(ctx.tmpPages[i])) {
        revert IAppErrors.PageNotRemovedError(ctx.tmpPages[i]);
      }
    }
  }

  function removeStoryAnswersMeta(IStoryController.MainState storage s, uint16 storyId, uint maxIterations) external {
    RemoveStoryContext memory ctx;
    ctx.storyId = storyId;

    // --- clean all data related to answers ---

    EnumerableSet.Bytes32Set storage allAnswers = s.allStoryAnswers[ctx.storyId];
    ctx.len = allAnswers.length();
    if (ctx.len > maxIterations) {
      ctx.len = maxIterations;
    }
    ctx.tmpAnswers = new bytes32[](ctx.len);

    for (uint i; i < ctx.len; ++i) {
      ctx.answerId = allAnswers.at(i);
      ctx.tmpAnswers[i] = ctx.answerId;

      (, ctx.pageId, ctx.heroClass, ctx.answerNum) = ctx.answerId.unpackStoryAnswerId();

      delete s.answerAttributes[ctx.answerId];
      delete s.attributeRequirements[ctx.answerId];
      delete s.itemRequirements[ctx.answerId];
      delete s.tokenRequirements[ctx.answerId];
      delete s.heroCustomDataRequirement[ctx.answerId];
      delete s.globalCustomDataRequirement[ctx.answerId];
      delete s.successInfoAttributes[ctx.answerId];
      delete s.successInfoStats[ctx.answerId];
      delete s.successInfoMintItems[ctx.answerId];
      delete s.failInfoAttributes[ctx.answerId];
      delete s.failInfoStats[ctx.answerId];
      delete s.failInfoMintItems[ctx.answerId];
      delete s.burnItem[ctx.answerId];

      for (ctx.answerResultId = 0; ctx.answerResultId < uint(IStoryController.AnswerResultId.END_SLOT); ++ctx.answerResultId) {
        delete s.nextPageIds[ctx.storyId.packStoryNextPagesId(
          ctx.pageId,
          ctx.heroClass,
          ctx.answerNum,
          ctx.answerResultId
        )];
      }

      // we assume here, that CustomDataResultId.UNKNOWN = 0 shouldn't be used, so we can skip delete for it
      for (ctx.customDataResultId = 1; ctx.customDataResultId < uint(IStoryController.CustomDataResult.END_SLOT); ++ctx.customDataResultId) {
        delete s.customDataResult[ctx.storyId.packStoryCustomDataResult(
          ctx.pageId,
          ctx.heroClass,
          ctx.answerNum,
          ctx.customDataResultId
        )];
      }
    }

    // ATTENTION! need to remove items one by one from sets

    // remove all answers
    for (uint i; i < ctx.tmpAnswers.length; ++i) {
      allAnswers.remove(ctx.tmpAnswers[i]);
    }
  }
  //endregion ------------------ Remove logic

  //region ------------------ Utils
  function registerAnswer(IStoryController.MainState storage s, uint16 storyId, bytes32 answerId) internal {
    s.allStoryAnswers[storyId].add(answerId);
  }

  function registerPage(IStoryController.MainState storage s, uint16 storyId, uint16 pageId) internal {
    s.allStoryPages[storyId].add(pageId);
  }
  //endregion ------------------ Utils
}
