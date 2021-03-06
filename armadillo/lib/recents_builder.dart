// Copyright 2017 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:lib.widgets/model.dart';

import 'armadillo_overlay.dart';
import 'edge_scroll_drag_target.dart';
import 'now_builder.dart';
import 'scroll_locker.dart';
import 'size_model.dart';
import 'story_cluster.dart';
import 'story_drag_transition_model.dart';
import 'story_list.dart';
import 'vertical_shifter.dart';

/// If the user releases their finger when overscrolled more than this amount,
/// we snap suggestions open.
const double _kOverscrollAutoSnapThreshold = -250.0;

/// If the user releases their finger when overscrolled more than this amount
/// and  the user dragged their finger at least
/// [_kOverscrollSnapDragDistanceThreshold], we snap suggestions open.
const double _kOverscrollSnapDragThreshold = -50.0;

/// See [_kOverscrollSnapDragThreshold].
const double _kOverscrollSnapDragDistanceThreshold = 200.0;

/// Builds recents.
class RecentsBuilder {
  /// The [VerticalShifter] is used to shift the [StoryList] up when Now's
  /// inline quick settings are activated.
  final GlobalKey<VerticalShifterState> _verticalShifterKey =
      new GlobalKey<VerticalShifterState>();
  final GlobalKey<ScrollLockerState> _scrollLockerKey =
      new GlobalKey<ScrollLockerState>();
  final GlobalKey<ArmadilloOverlayState> _overlayKey =
      new GlobalKey<ArmadilloOverlayState>();
  final GlobalKey<EdgeScrollDragTargetState> _edgeScrollDragTargetKey =
      new GlobalKey<EdgeScrollDragTargetState>();
  final ScrollController _scrollController = new ScrollController();

  /// Builds recents.
  Widget build(
    BuildContext context, {
    ValueChanged<double> onScroll,
    VoidCallback onStoryClusterFocusStarted,
    OnStoryClusterEvent onStoryClusterFocusCompleted,
    VoidCallback onStoryClusterVerticalEdgeHover,
  }) =>
      new ScopedModelDescendant<SizeModel>(
        builder: (_, Widget child, SizeModel sizeModel) =>
            new ScopedModelDescendant<IdleModel>(
              builder: (_, Widget child, IdleModel idleModel) => new Transform(
                    transform: new Matrix4.translationValues(
                      0.0,
                      lerpDouble(
                        0.0,
                        -sizeModel.screenSize.height * 1.2,
                        idleModel.value,
                      ),
                      0.0,
                    ),
                    child: new Offstage(
                      offstage: idleModel.value == 1.0,
                      child: child,
                    ),
                  ),
              child: child,
            ),
        child: _buildRecents(
          context,
          onScroll: onScroll,
          onStoryClusterFocusStarted: onStoryClusterFocusStarted,
          onStoryClusterFocusCompleted: onStoryClusterFocusCompleted,
          onStoryClusterVerticalEdgeHover: onStoryClusterVerticalEdgeHover,
        ),
      );

  Widget _buildRecents(
    BuildContext context, {
    ValueChanged<double> onScroll,
    VoidCallback onStoryClusterFocusStarted,
    OnStoryClusterEvent onStoryClusterFocusCompleted,
    VoidCallback onStoryClusterVerticalEdgeHover,
  }) =>
      new Stack(
        children: <Widget>[
          new ScopedModelDescendant<SizeModel>(
            builder: (_, __, SizeModel sizeModel) =>
                new ScopedModelDescendant<StoryDragTransitionModel>(
                  builder: (
                    BuildContext context,
                    Widget child,
                    StoryDragTransitionModel storyDragTransitionModel,
                  ) =>
                      new Positioned(
                        left: 0.0,
                        right: 0.0,
                        top: 0.0,
                        bottom: lerpDouble(
                          sizeModel.minimizedNowHeight,
                          0.0,
                          storyDragTransitionModel.value,
                        ),
                        child: child,
                      ),
                  child: new VerticalShifter(
                    key: _verticalShifterKey,
                    verticalShift: NowBuilder.kQuickSettingsHeightBump,
                    child: new ScrollLocker(
                      key: _scrollLockerKey,
                      child: new StoryList(
                        scrollController: _scrollController,
                        overlayKey: _overlayKey,
                        onScroll: onScroll,
                        onStoryClusterFocusStarted: onStoryClusterFocusStarted,
                        onStoryClusterFocusCompleted:
                            onStoryClusterFocusCompleted,
                        onStoryClusterVerticalEdgeHover:
                            onStoryClusterVerticalEdgeHover,
                      ),
                    ),
                  ),
                ),
          ),

          // Top and bottom edge scrolling drag targets.
          new Positioned.fill(
            child: new EdgeScrollDragTarget(
              key: _edgeScrollDragTargetKey,
              scrollController: _scrollController,
            ),
          ),
        ],
      );

  /// Call when a story cluster comes into focus.
  void onStoryFocused() {
    _scrollLockerKey.currentState.lock();
    _edgeScrollDragTargetKey.currentState.disable();
  }

  /// Call when a story cluster leaves focus.
  void onStoryUnfocused() {
    _scrollLockerKey.currentState.unlock();
    _edgeScrollDragTargetKey.currentState.enable();
  }

  /// Call when quick settings progress changes.
  void onQuickSettingsProgressChanged(double quickSettingsProgress) {
    _verticalShifterKey.currentState.shiftProgress = quickSettingsProgress;
  }

  /// Call to reset the recents scrolling to 0.0.
  void resetScroll({bool jump: false}) {
    if (jump) {
      _scrollController.jumpTo(0.0);
    } else {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  /// Indicates if we're significantly overscrolled for the given
  /// [dragDistance].
  bool isSignificantlyOverscrolled(double dragDistance) =>
      _scrollController.offset < _kOverscrollAutoSnapThreshold ||
      (_scrollController.offset < _kOverscrollSnapDragThreshold &&
          dragDistance > _kOverscrollSnapDragDistanceThreshold);
}
