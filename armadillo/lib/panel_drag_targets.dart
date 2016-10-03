// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'armadillo_drag_target.dart';
import 'panel.dart';
import 'story.dart';
import 'story_cluster.dart';
import 'story_keys.dart';
import 'story_manager.dart';

const double _kLineWidth = 4.0;
const double _kTopEdgeTargetYOffset = 16.0;
const double _kDiscardTargetTopEdgeYOffset = -48.0;
const double _kBringToFrontTargetBottomEdgeYOffset = 48.0;
const double _kStoryBarTargetYOffset = -16.0;
const double _kStoryTopEdgeTargetYOffset = 48.0;
const double _kStoryEdgeTargetInset = 16.0;
const int _kMaxStoriesPerCluster = 100;
const double _kAddedStorySpan = 0.01;
const Color _kEdgeTargetColor = const Color(0xFFFFFF00);
const Color _kStoryBarTargetColor = const Color(0xFF00FFFF);
const Color _kDiscardTargetColor = const Color(0xFFFF0000);
const Color _kBringToFrontTargetColor = const Color(0xFF00FF00);
const Color _kStoryEdgeTargetColor = const Color(0xFF0000FF);

typedef void _OnPanelEvent(BuildContext context, StoryCluster data);

/// Details about a target used by [PanelDragTargets].
///
/// [LineSegment] specifies a line from [a] to [b].
/// When turned into a widget the [LineSegment] will have the color [color].
/// When the [LineSegment] is being targeted by a draggable [onHover] will be
/// called.
/// When the [LineSegment] is dropped upon with a draggable [onDropped] will be
/// called.
/// This [LineSegment] can only be targeted by [StoryCluster]s with a story
/// count of less than or equal to [maxStoriesCanAccept].
class LineSegment {
  /// [a] always aligns with [b] in either vertically or horizontally.
  /// [a] is always 'less than' [b] in x or y direction.
  final Point a;
  final Point b;
  final Color color;
  final _OnPanelEvent onHover;
  final _OnPanelEvent onDrop;
  final int maxStoriesCanAccept;

  LineSegment(
    Point a,
    Point b, {
    this.color: const Color(0xFFFFFFFF),
    this.onHover,
    this.onDrop,
    this.maxStoriesCanAccept: 1,
  })
      : this.a = (a.x < b.x || a.y < b.y) ? a : b,
        this.b = (a.x < b.x || a.y < b.y) ? b : a {
    // Ensure the line is either vertical or horizontal.
    assert(a.x == b.x || a.y == b.y);
  }

  factory LineSegment.vertical({
    double x,
    double top,
    double bottom,
    Color color,
    _OnPanelEvent onHover,
    _OnPanelEvent onDrop,
    int maxStoriesCanAccept,
  }) =>
      new LineSegment(
        new Point(x, top),
        new Point(x, bottom),
        color: color,
        onHover: onHover,
        onDrop: onDrop,
        maxStoriesCanAccept: maxStoriesCanAccept,
      );

  factory LineSegment.horizontal({
    double y,
    double left,
    double right,
    Color color,
    _OnPanelEvent onHover,
    _OnPanelEvent onDrop,
    int maxStoriesCanAccept,
  }) =>
      new LineSegment(
        new Point(left, y),
        new Point(right, y),
        color: color,
        onHover: onHover,
        onDrop: onDrop,
        maxStoriesCanAccept: maxStoriesCanAccept,
      );

  bool get isHorizontal => a.y == b.y;
  bool get isVertical => !isHorizontal;
  bool canAccept(StoryCluster storyCluster) =>
      storyCluster.stories.length <= maxStoriesCanAccept;

  double distanceFrom(Point p) {
    if (isHorizontal) {
      if (p.x < a.x) {
        return math.sqrt(math.pow(p.x - a.x, 2) + math.pow(p.y - a.y, 2));
      } else if (p.x > b.x) {
        return math.sqrt(math.pow(p.x - b.x, 2) + math.pow(p.y - b.y, 2));
      } else {
        return (p.y - a.y).abs();
      }
    } else {
      if (p.y < a.y) {
        return math.sqrt(math.pow(p.x - a.x, 2) + math.pow(p.y - a.y, 2));
      } else if (p.y > b.y) {
        return math.sqrt(math.pow(p.x - b.x, 2) + math.pow(p.y - b.y, 2));
      } else {
        return (p.x - a.x).abs();
      }
    }
  }

  Positioned buildStackChild({bool highlighted}) => new Positioned(
        left: a.x - _kLineWidth / 2.0,
        top: a.y - _kLineWidth / 2.0,
        width: isHorizontal ? b.x - a.x + _kLineWidth : _kLineWidth,
        height: isVertical ? b.y - a.y + _kLineWidth : _kLineWidth,
        child: new Container(
          decoration: new BoxDecoration(
            backgroundColor: color.withOpacity(highlighted ? 1.0 : 0.3),
          ),
        ),
      );
}

/// Wraps its [child] in an [ArmadilloDragTarget] which tracks any
/// [ArmadilloLongPressDraggable]'s above it such that they can be dropped on
/// specific parts of [storyCluster]'s [storyCluster.stories]'s [Panel]s.
///
/// When an [ArmadilloLongPressDraggable] is above, [child] will be scaled down
/// slightly depending on [focusProgress].
class PanelDragTargets extends StatelessWidget {
  final StoryCluster storyCluster;
  final Size fullSize;
  final Widget child;
  final double scale;
  final double focusProgress;
  final Set<LineSegment> _targetLines = new Set<LineSegment>();

  PanelDragTargets({
    Key key,
    this.storyCluster,
    this.fullSize,
    this.child,
    this.scale,
    this.focusProgress,
  })
      : super(key: key) {
    _populateTargetLines();
  }

  @override
  Widget build(BuildContext context) => new ArmadilloDragTarget(
      onWillAccept: (StoryCluster data, Point point) => true,
      onAccept: (StoryCluster data, Point point) =>
          _getClosestLine(point, data).onDrop?.call(context, data),
      builder: (
        BuildContext context,
        Map<StoryCluster, Point> candidateData,
        Map<dynamic, Point> rejectedData,
      ) {
        // Scale the child.
        double childScale =
            lerpDouble(1.0, candidateData.isEmpty ? 1.0 : scale, focusProgress);

        List<Widget> stackChildren = [
          new Positioned(
            top: 0.0,
            left: 0.0,
            right: 0.0,
            bottom: 0.0,
            child: new Transform(
              transform: new Matrix4.identity().scaled(childScale, childScale),
              alignment: FractionalOffset.center,
              child: child,
            ),
          )
        ];

        // When we have a candidate and we're fully focused, show the target
        // lines.
        if (candidateData.isNotEmpty && focusProgress == 1.0) {
          // Find out which line is the closest.
          List<LineSegment> closestTargetLines = <LineSegment>[];
          candidateData.keys.forEach((StoryCluster key) {
            LineSegment closestTargetLine =
                _getClosestLine(candidateData[key], key);
            closestTargetLine.onHover?.call(context, key);
            closestTargetLines.add(closestTargetLine);
          });

          // Add all the lines.
          stackChildren.addAll(
            _targetLines.where((LineSegment line) {
              bool isValidTarget = false;
              candidateData.keys.forEach((StoryCluster key) {
                if (line.canAccept(key)) {
                  isValidTarget = true;
                }
              });
              return isValidTarget;
            }).map(
              (LineSegment line) => line.buildStackChild(
                    highlighted: closestTargetLines.contains(line),
                  ),
            ),
          );
        }
        return new Stack(children: stackChildren);
      });

  LineSegment _getClosestLine(Point point, StoryCluster data) {
    double minDistance = double.INFINITY;
    LineSegment closestLine;
    _targetLines
        .where((LineSegment line) => line.canAccept(data))
        .forEach((LineSegment line) {
      double targetLineDistance = line.distanceFrom(point);
      if (targetLineDistance < minDistance) {
        minDistance = targetLineDistance;
        closestLine = line;
      }
    });
    return closestLine;
  }

  void _populateTargetLines() {
    double verticalMargin = (1.0 - scale) / 2.0 * fullSize.height;
    double horizontalMargin = (1.0 - scale) / 2.0 * fullSize.width;

    int availableRows = maxRows(fullSize) - _currentRows;
    if (availableRows > 0) {
      // Top edge target.
      _targetLines.add(
        new LineSegment.horizontal(
          y: verticalMargin + _kTopEdgeTargetYOffset,
          left: horizontalMargin + _kStoryEdgeTargetInset,
          right: fullSize.width - horizontalMargin - _kStoryEdgeTargetInset,
          color: _kEdgeTargetColor,
          maxStoriesCanAccept: availableRows,
          onDrop: _addClusterAbovePanels,
        ),
      );

      // Bottom edge target.
      _targetLines.add(
        new LineSegment.horizontal(
          y: fullSize.height - verticalMargin,
          left: horizontalMargin + _kStoryEdgeTargetInset,
          right: fullSize.width - horizontalMargin - _kStoryEdgeTargetInset,
          color: _kEdgeTargetColor,
          maxStoriesCanAccept: availableRows,
          onDrop: _addClusterBelowPanels,
        ),
      );
    }

    // Left edge target.
    int availableColumns = maxColumns(fullSize) - _currentColumns;
    if (availableColumns > 0) {
      _targetLines.add(
        new LineSegment.vertical(
          x: horizontalMargin,
          top: verticalMargin,
          bottom: fullSize.height - verticalMargin - _kStoryEdgeTargetInset,
          color: _kEdgeTargetColor,
          maxStoriesCanAccept: availableColumns,
          onDrop: _addClusterToLeftOfPanels,
        ),
      );

      // Right edge target.
      _targetLines.add(
        new LineSegment.vertical(
          x: fullSize.width - horizontalMargin,
          top: verticalMargin,
          bottom: fullSize.height - verticalMargin - _kStoryEdgeTargetInset,
          color: _kEdgeTargetColor,
          maxStoriesCanAccept: availableColumns,
          onDrop: _addClusterToRightOfPanels,
        ),
      );
    }

    // Story Bar target.
    _targetLines.add(
      new LineSegment.horizontal(
        y: verticalMargin + _kStoryBarTargetYOffset,
        left: horizontalMargin + _kStoryEdgeTargetInset,
        right: fullSize.width - horizontalMargin - _kStoryEdgeTargetInset,
        color: _kStoryBarTargetColor,
        maxStoriesCanAccept:
            _kMaxStoriesPerCluster - storyCluster.stories.length,
        onDrop: (BuildContext context, StoryCluster data) {
          // TODO(apwilson): Switch all the stories involved into tabs.
        },
      ),
    );

    // Top discard target.
    _targetLines.add(
      new LineSegment.horizontal(
        y: verticalMargin + _kDiscardTargetTopEdgeYOffset,
        left: horizontalMargin * 3.0,
        right: fullSize.width - 3.0 * horizontalMargin,
        color: _kDiscardTargetColor,
        maxStoriesCanAccept: _kMaxStoriesPerCluster,
        onDrop: (BuildContext context, StoryCluster data) {
          // TODO(apwilson): Animate data cluster away.
        },
      ),
    );

    // Bottom bring-to-front target.
    _targetLines.add(
      new LineSegment.horizontal(
        y: fullSize.height -
            verticalMargin +
            _kBringToFrontTargetBottomEdgeYOffset,
        left: horizontalMargin * 3.0,
        right: fullSize.width - 3.0 * horizontalMargin,
        color: _kBringToFrontTargetColor,
        maxStoriesCanAccept: _kMaxStoriesPerCluster,
        onDrop: (BuildContext context, StoryCluster data) {
          // TODO(apwilson): Defocus this cluster away.
          // Bring data cluster into focus.
        },
      ),
    );

    // Story edge targets.
    Point center = new Point(fullSize.width / 2.0, fullSize.height / 2.0);
    storyCluster.panels.forEach((Panel panel) {
      Rect bounds = _transform(panel, center, fullSize);

      // If we can split vertically add vertical targets on left and right.
      int verticalSplits = _getVerticalSplitCount(panel);
      if (verticalSplits > 0) {
        double left = bounds.left + _kStoryEdgeTargetInset;
        double right = bounds.right - _kStoryEdgeTargetInset;
        double top = bounds.top +
            _kStoryEdgeTargetInset +
            (panel.top == 0.0
                ? _kStoryTopEdgeTargetYOffset
                : 2.0 * _kStoryEdgeTargetInset);
        double bottom =
            bounds.bottom - _kStoryEdgeTargetInset - _kStoryEdgeTargetInset;

        // Add left target.
        _targetLines.add(
          new LineSegment.vertical(
            x: left,
            top: top,
            bottom: bottom,
            color: _kStoryEdgeTargetColor,
            maxStoriesCanAccept: verticalSplits,
            onDrop: (BuildContext context, StoryCluster data) =>
                _addClusterToLeftOfPanel(context, data, panel),
          ),
        );

        // Add right target.
        _targetLines.add(
          new LineSegment.vertical(
            x: right,
            top: top,
            bottom: bottom,
            color: _kStoryEdgeTargetColor,
            maxStoriesCanAccept: verticalSplits,
            onDrop: (BuildContext context, StoryCluster data) =>
                _addClusterToRightOfPanel(context, data, panel),
          ),
        );
      }

      // If we can split horizontally add horizontal targets on top and bottom.
      int horizontalSplits = _getHorizontalSplitCount(panel);
      if (horizontalSplits > 0) {
        double top = bounds.top +
            (panel.top == 0.0
                ? _kStoryTopEdgeTargetYOffset
                : _kStoryEdgeTargetInset);
        double left =
            bounds.left + _kStoryEdgeTargetInset + _kStoryEdgeTargetInset;
        double right =
            bounds.right - _kStoryEdgeTargetInset - _kStoryEdgeTargetInset;
        double bottom = bounds.bottom - _kStoryEdgeTargetInset;

        // Add top target.
        _targetLines.add(
          new LineSegment.horizontal(
            y: top,
            left: left,
            right: right,
            color: _kStoryEdgeTargetColor,
            maxStoriesCanAccept: horizontalSplits,
            onDrop: (BuildContext context, StoryCluster data) =>
                _addClusterAbovePanel(context, data, panel),
          ),
        );

        // Add bottom target.
        _targetLines.add(
          new LineSegment.horizontal(
            y: bottom,
            left: left,
            right: right,
            color: _kStoryEdgeTargetColor,
            maxStoriesCanAccept: horizontalSplits,
            onDrop: (BuildContext context, StoryCluster data) =>
                _addClusterBelowPanel(context, data, panel),
          ),
        );
      }
    });
  }

  /// Adds the stories of [storyCluster] to the left, spanning the full height.
  void _addClusterToLeftOfPanels(
    BuildContext context,
    StoryCluster storyCluster,
  ) {
    List<Story> storiesToAdd = _getHorizontallySortedStories(storyCluster);

    // 1) Make room for new stories.
    _makeRoom(
      panels: this
          .storyCluster
          .panels
          .where((Panel panel) => panel.left == 0)
          .toList(),
      leftDelta: (_kAddedStorySpan * storiesToAdd.length),
      widthFactorDelta: -(_kAddedStorySpan * storiesToAdd.length),
    );

    // 2) Add new stories.
    _addStoriesHorizontally(
      stories: storiesToAdd,
      x: 0.0,
      top: 0.0,
      bottom: 1.0,
    );

    // 3) Clean up.
    _cleanup(context: context, storyCluster: storyCluster);
  }

  /// Adds the stories of [storyCluster] to the right, spanning the full height.
  void _addClusterToRightOfPanels(
    BuildContext context,
    StoryCluster storyCluster,
  ) {
    List<Story> storiesToAdd = _getHorizontallySortedStories(storyCluster);

    // 1) Make room for new stories.
    _makeRoom(
      panels: this
          .storyCluster
          .panels
          .where((Panel panel) => panel.right == 1.0)
          .toList(),
      widthFactorDelta: -(_kAddedStorySpan * storiesToAdd.length),
    );

    // 2) Add new stories.
    _addStoriesHorizontally(
      stories: storiesToAdd,
      x: 1.0 - (_kAddedStorySpan * storiesToAdd.length),
      top: 0.0,
      bottom: 1.0,
    );

    // 3) Clean up.
    _cleanup(context: context, storyCluster: storyCluster);
  }

  /// Adds the stories of [storyCluster] to the top, spanning the full width.
  void _addClusterAbovePanels(BuildContext context, StoryCluster storyCluster) {
    List<Story> storiesToAdd = _getVerticallySortedStories(storyCluster);

    // 1) Make room for new stories.
    _makeRoom(
      panels: this
          .storyCluster
          .panels
          .where((Panel panel) => panel.top == 0.0)
          .toList(),
      topDelta: (_kAddedStorySpan * storiesToAdd.length),
      heightFactorDelta: -(_kAddedStorySpan * storiesToAdd.length),
    );

    // 2) Add new stories.
    _addStoriesVertically(
      stories: storiesToAdd,
      y: 0.0,
      left: 0.0,
      right: 1.0,
    );

    // 3) Clean up.
    _cleanup(context: context, storyCluster: storyCluster);
  }

  /// Adds the stories of [storyCluster] to the bottom, spanning the full width.
  void _addClusterBelowPanels(BuildContext context, StoryCluster storyCluster) {
    List<Story> storiesToAdd = _getVerticallySortedStories(storyCluster);

    // 1) Make room for new stories.
    _makeRoom(
      panels: this
          .storyCluster
          .panels
          .where((Panel panel) => panel.bottom == 1.0)
          .toList(),
      heightFactorDelta: -(_kAddedStorySpan * storiesToAdd.length),
    );

    // 2) Add new stories.
    _addStoriesVertically(
      stories: storiesToAdd,
      y: 1.0 - (_kAddedStorySpan * storiesToAdd.length),
      left: 0.0,
      right: 1.0,
    );

    // 3) Clean up.
    _cleanup(context: context, storyCluster: storyCluster);
  }

  /// Adds the stories of [storyCluster] to the left of [panel], spanning
  /// [panel]'s height.
  void _addClusterToLeftOfPanel(
    BuildContext context,
    StoryCluster storyCluster,
    Panel panel,
  ) {
    List<Story> storiesToAdd = _getHorizontallySortedStories(storyCluster);

    // 1) Add new stories.
    _addStoriesHorizontally(
      stories: storiesToAdd,
      x: panel.left,
      top: panel.top,
      bottom: panel.bottom,
    );

    // 2) Make room for new stories.
    _makeRoom(
      panels: [panel],
      leftDelta: (_kAddedStorySpan * storiesToAdd.length),
      widthFactorDelta: -(_kAddedStorySpan * storiesToAdd.length),
    );

    // 3) Clean up.
    _cleanup(context: context, storyCluster: storyCluster);
  }

  /// Adds the stories of [storyCluster] to the right of [panel], spanning
  /// [panel]'s height.
  void _addClusterToRightOfPanel(
    BuildContext context,
    StoryCluster storyCluster,
    Panel panel,
  ) {
    List<Story> storiesToAdd = _getHorizontallySortedStories(storyCluster);
    double newStoryWidth = _kAddedStorySpan;

    // 1) Add new stories.
    _addStoriesHorizontally(
      stories: storiesToAdd,
      x: panel.right - storiesToAdd.length * newStoryWidth,
      top: panel.top,
      bottom: panel.bottom,
    );

    // 2) Make room for new stories.
    _makeRoom(
      panels: [panel],
      widthFactorDelta: -(_kAddedStorySpan * storiesToAdd.length),
    );

    // 3) Clean up.
    _cleanup(context: context, storyCluster: storyCluster);
  }

  /// Adds the stories of [storyCluster] to the top of [panel], spanning
  /// [panel]'s width.
  void _addClusterAbovePanel(
    BuildContext context,
    StoryCluster storyCluster,
    Panel panel,
  ) {
    List<Story> storiesToAdd = _getVerticallySortedStories(storyCluster);

    // 1) Add new stories.
    _addStoriesVertically(
      stories: storiesToAdd,
      y: panel.top,
      left: panel.left,
      right: panel.right,
    );

    // 2) Make room for new stories.
    _makeRoom(
      panels: [panel],
      topDelta: (_kAddedStorySpan * storiesToAdd.length),
      heightFactorDelta: -(_kAddedStorySpan * storiesToAdd.length),
    );

    // 3) Clean up.
    _cleanup(context: context, storyCluster: storyCluster);
  }

  /// Adds the stories of [storyCluster] to the bottom of [panel], spanning
  /// [panel]'s width.
  void _addClusterBelowPanel(
    BuildContext context,
    StoryCluster storyCluster,
    Panel panel,
  ) {
    List<Story> storiesToAdd = _getVerticallySortedStories(storyCluster);

    // 1) Add new stories.
    _addStoriesVertically(
      stories: storiesToAdd,
      y: panel.bottom - storiesToAdd.length * _kAddedStorySpan,
      left: panel.left,
      right: panel.right,
    );

    // 2) Make room for new stories.
    _makeRoom(
      panels: [panel],
      heightFactorDelta: -(_kAddedStorySpan * storiesToAdd.length),
    );

    // 3) Clean up.
    _cleanup(context: context, storyCluster: storyCluster);
  }

  void _cleanup({BuildContext context, StoryCluster storyCluster}) {
    // 1) Normalize sizes.
    _normalizeSizes();

    // 2) Remove dropped cluster from story manager.
    InheritedStoryManager.of(context).remove(storyCluster: storyCluster);
  }

  void _normalizeSizes() => storyCluster.normalizeSizes();

  /// Resizes the existing panels just enough to add new ones.
  void _makeRoom({
    List<Panel> panels,
    double topDelta: 0.0,
    double leftDelta: 0.0,
    double widthFactorDelta: 0.0,
    double heightFactorDelta: 0.0,
  }) {
    panels.forEach((Panel panel) {
      storyCluster.replace(
        panel: panel,
        withPanel: new Panel(
          origin: new FractionalOffset(
            panel.left + leftDelta,
            panel.top + topDelta,
          ),
          widthFactor: panel.width + widthFactorDelta,
          heightFactor: panel.height + heightFactorDelta,
        ),
      );
    });
  }

  /// Adds stories horizontally starting from [x] with vertical bounds of
  /// [top] to [bottom].
  void _addStoriesHorizontally({
    List<Story> stories,
    double x,
    double top,
    double bottom,
  }) {
    double dx = x;
    stories.forEach((Story story) {
      storyCluster.add(
        story: story,
        withPanel: new Panel(
          origin: new FractionalOffset(dx, top),
          widthFactor: _kAddedStorySpan,
          heightFactor: bottom - top,
        ),
      );
      dx += _kAddedStorySpan;
      StoryKeys.storyBarKey(story).currentState.maximize(jumpToFinish: true);
    });
  }

  /// Adds stories vertically starting from [y] with horizontal bounds of
  /// [left] to [right].
  void _addStoriesVertically({
    List<Story> stories,
    double y,
    double left,
    double right,
  }) {
    double dy = y;
    stories.forEach((Story story) {
      storyCluster.add(
        story: story,
        withPanel: new Panel(
          origin: new FractionalOffset(left, dy),
          widthFactor: right - left,
          heightFactor: _kAddedStorySpan,
        ),
      );
      dy += _kAddedStorySpan;
      StoryKeys.storyBarKey(story).currentState.maximize(jumpToFinish: true);
    });
  }

  int get _currentRows => _getRows(left: 0.0, right: 1.0);

  int get _currentColumns => _getColumns(top: 0.0, bottom: 1.0);

  int _getRows({double left, double right}) {
    Set<double> tops = new Set<double>();
    storyCluster.panels
        .where((Panel panel) =>
            (left <= panel.left && right > panel.left) ||
            (panel.left < left && panel.right > left))
        .forEach((Panel panel) {
      tops.add(panel.top);
    });
    return tops.length;
  }

  int _getColumns({double top, double bottom}) {
    Set<double> lefts = new Set<double>();
    storyCluster.panels
        .where((Panel panel) =>
            (top <= panel.top && bottom > panel.top) ||
            (top < panel.top && panel.bottom > top))
        .forEach((Panel panel) {
      lefts.add(panel.left);
    });
    return lefts.length;
  }

  int _getHorizontalSplitCount(Panel panel) =>
      maxRows(fullSize) - _getRows(left: panel.left, right: panel.right);

  int _getVerticalSplitCount(Panel panel) =>
      maxColumns(fullSize) - _getColumns(top: panel.top, bottom: panel.bottom);

  Rect _bounds(Panel panel, Size size) => new Rect.fromLTRB(
        panel.left * size.width,
        panel.top * size.height,
        panel.right * size.width,
        panel.bottom * size.height,
      );

  Rect _transform(Panel panel, Point origin, Size size) =>
      Rect.lerp(origin & Size.zero, _bounds(panel, size), scale);

  static List<Story> _getVerticallySortedStories(StoryCluster storyCluster) {
    List<Story> sortedStories = new List.from(storyCluster.stories);
    sortedStories.sort(
      (Story a, Story b) => a.panel.top < b.panel.top
          ? -1
          : a.panel.top > b.panel.top
              ? 1
              : a.panel.left < b.panel.left
                  ? -1
                  : a.panel.left > b.panel.left ? 1 : 0,
    );
    return sortedStories;
  }

  static List<Story> _getHorizontallySortedStories(StoryCluster storyCluster) {
    List<Story> sortedStories = new List.from(storyCluster.stories);
    sortedStories.sort(
      (Story a, Story b) => a.panel.left < b.panel.left
          ? -1
          : a.panel.left > b.panel.left
              ? 1
              : a.panel.top < b.panel.top
                  ? -1
                  : a.panel.top > b.panel.top ? 1 : 0,
    );
    return sortedStories;
  }
}
