// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'armadillo_drag_target.dart';
import 'armadillo_overlay.dart';
import 'nothing.dart';
import 'optional_wrapper.dart';
import 'panel_drag_targets.dart';
import 'story.dart';
import 'story_cluster.dart';
import 'story_cluster_drag_feedback.dart';
import 'story_cluster_drag_state_model.dart';
import 'story_cluster_id.dart';
import 'story_drag_transition_model.dart';
import 'story_list.dart';
import 'story_panels.dart';
import 'story_rearrangement_scrim_model.dart';
import 'story_title.dart';

/// The minimum story height.
const double _kMinimumStoryHeight = 200.0;

/// In multicolumn mode, the distance from the parent's edge the largest story
/// will be.
const double _kMultiColumnMargin = 64.0;

/// In multicolumn mode, the aspect ratio of a story.
const double _kWidthToHeightRatio = 16.0 / 9.0;

/// In single column mode, the distance from a story and other UI elements.
const double _kSingleColumnStoryMargin = 8.0;

/// In multicolumn mode, the minimum distance from a story and other UI
/// elements.
const double _kMultiColumnMinimumStoryMargin = 8.0;

/// The height of the vertical gesture detector used to reveal the story bar in
/// full screen mode.
/// TODO(apwilson): Reduce the height of this.  It's large for now for ease of
/// use.
const double _kVerticalGestureDetectorHeight = 32.0;

const double _kStoryInlineTitleHeight = 20.0;
const double _kDraggedStoryRadius = 75.0;
const int _kMaxStories = 4;
const Color _kTargetOverlayColor = const Color.fromARGB(128, 153, 234, 216);

const double _kDragScale = 0.8;

/// The visual representation of a [Story].  A [Story] has a default size but
/// will expand to full size when it comes into focus.  [StoryClusterWidget]s
/// are intended to be children of [StoryList].
class StoryClusterWidget extends StatelessWidget {
  final StoryCluster storyCluster;
  final bool multiColumn;
  final double focusProgress;
  final VoidCallback onAccept;
  final VoidCallback onTap;
  final VoidCallback onVerticalEdgeHover;
  final GlobalKey<ArmadilloOverlayState> overlayKey;
  final Map<StoryId, Widget> storyWidgets;

  StoryClusterWidget({
    Key key,
    this.storyCluster,
    this.multiColumn,
    this.focusProgress,
    this.onAccept,
    this.onTap,
    this.onVerticalEdgeHover,
    this.overlayKey,
    this.storyWidgets,
  })
      : super(key: key);

  @override
  Widget build(BuildContext context) => _isUnfocused
      ? _getUnfocusedDragTargetChild(context)
      : _getStoryClusterWithInlineStoryTitle(context);

  Widget _getUnfocusedDragTargetChild(BuildContext context) {
    Rect initialBoundsOnDrag;
    return new OptionalWrapper(
      useWrapper: _isUnfocused,
      builder: (BuildContext context, Widget child) =>
          new ArmadilloLongPressDraggable<StoryClusterId>(
            key: storyCluster.clusterDraggableKey,
            overlayKey: overlayKey,
            data: storyCluster.id,
            childWhenDragging: Nothing.widget,
            onDragStarted: () {
              RenderBox box =
                  storyCluster.panelsKey.currentContext.findRenderObject();
              Point boxTopLeft = box.localToGlobal(Point.origin);
              Point boxBottomRight = box.localToGlobal(
                new Point(box.size.width, box.size.height),
              );
              initialBoundsOnDrag = new Rect.fromLTRB(
                boxTopLeft.x,
                boxTopLeft.y,
                boxBottomRight.x,
                boxBottomRight.y,
              );
              StoryClusterDragStateModel.of(context).addDragging(
                    storyCluster.id,
                  );
            },
            onDragEnded: () {
              StoryClusterDragStateModel.of(context).removeDragging(
                    storyCluster.id,
                  );
            },
            feedbackBuilder: (Point localDragStartPoint) =>
                new StoryClusterDragFeedback(
                  key: storyCluster.dragFeedbackKey,
                  storyCluster: storyCluster,
                  storyWidgets: storyWidgets,
                  localDragStartPoint: localDragStartPoint,
                  initialBounds: initialBoundsOnDrag,
                  focusProgress: 0.0,
                ),
            child: child,
          ),
      child: _getStoryClusterWithInlineStoryTitle(
        context,
      ),
    );
  }

  Widget _getStoryClusterWithInlineStoryTitle(BuildContext context) =>
      new Stack(
        children: <Widget>[
          new Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              new Expanded(child: _getStoryCluster(context)),
              new InlineStoryTitle(
                focusProgress: focusProgress,
                storyCluster: storyCluster,
              ),
            ],
          ),
          _focusOnTap,
        ],
      );

  /// The Story including its StoryBar.
  Widget _getStoryCluster(BuildContext context) => new LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          Size currentSize = new Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          return new PanelDragTargets(
            key: storyCluster.clusterDragTargetsKey,
            scale: _kDragScale,
            focusProgress: focusProgress,
            currentSize: currentSize,
            storyCluster: storyCluster,
            onAccept: onAccept,
            onVerticalEdgeHover: onVerticalEdgeHover,
            child: new StoryPanels(
              key: storyCluster.panelsKey,
              storyCluster: storyCluster,
              focusProgress: focusProgress,
              overlayKey: overlayKey,
              storyWidgets: storyWidgets,
              currentSize: currentSize,
            ),
          );
        },
      );

  Widget get _focusOnTap => new Positioned(
        left: 0.0,
        right: 0.0,
        top: 0.0,
        bottom: 0.0,
        child: new Offstage(
          offstage: !_isUnfocused,
          child: new GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onTap,
          ),
        ),
      );

  bool get _isUnfocused => focusProgress == 0.0;
}

/// The Story Title that hovers below the story itself.
class InlineStoryTitle extends StatelessWidget {
  final double focusProgress;
  final StoryCluster storyCluster;

  InlineStoryTitle({this.focusProgress, this.storyCluster});

  static double getHeight(double focusProgress) =>
      lerpDouble(_kStoryInlineTitleHeight, 0.0, focusProgress);

  @override
  Widget build(BuildContext context) => new ScopedStoryDragTransitionWidget(
        builder: (BuildContext context, Widget child, double progress) =>
            new Opacity(
              opacity: lerpDouble(
                lerpDouble(1.0, 0.5, progress),
                0.0,
                StoryRearrangementScrimModel
                    .of(context, rebuildOnChange: true)
                    .progress,
              ),
              child: child,
            ),
        child: new Container(
          height: getHeight(focusProgress),
          child: new OverflowBox(
            minHeight: _kStoryInlineTitleHeight,
            maxHeight: _kStoryInlineTitleHeight,
            child: new Padding(
              padding: const EdgeInsets.only(
                left: 8.0,
                right: 8.0,
                top: 4.0,
              ),
              child: new Align(
                alignment: FractionalOffset.bottomLeft,
                child: new StoryTitle(
                  title: storyCluster.title,
                  opacity: 1.0 - focusProgress,
                ),
              ),
            ),
          ),
        ),
      );
}
