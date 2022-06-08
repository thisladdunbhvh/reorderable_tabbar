library reorderable_tabbar;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';
import 'package:tab_indicator_styler/tab_indicator_styler.dart';

const double _kTabHeight = 46.0;
const double _kTextAndIconTabHeight = 72.0;

class _TabStyle extends AnimatedWidget {
  const _TabStyle({
    Key? key,
    required Animation<double> animation,
    required this.selected,
    required this.labelColor,
    required this.unselectedLabelColor,
    required this.labelStyle,
    required this.unselectedLabelStyle,
    required this.child,
  }) : super(key: key, listenable: animation);

  final TextStyle? labelStyle;
  final TextStyle? unselectedLabelStyle;
  final bool selected;
  final Color? labelColor;
  final Color? unselectedLabelColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData themeData = Theme.of(context);
    final TabBarTheme tabBarTheme = TabBarTheme.of(context);
    final Animation<double> animation = listenable as Animation<double>;

    final TextStyle defaultStyle = (labelStyle ??
            tabBarTheme.labelStyle ??
            themeData.primaryTextTheme.bodyText1!)
        .copyWith(inherit: true);
    final TextStyle defaultUnselectedStyle = (unselectedLabelStyle ??
            tabBarTheme.unselectedLabelStyle ??
            labelStyle ??
            themeData.primaryTextTheme.bodyText1!)
        .copyWith(inherit: true);
    final TextStyle textStyle = selected
        ? TextStyle.lerp(defaultStyle, defaultUnselectedStyle, animation.value)!
        : TextStyle.lerp(
            defaultUnselectedStyle, defaultStyle, animation.value)!;

    final Color selectedColor = labelColor ??
        tabBarTheme.labelColor ??
        themeData.primaryTextTheme.bodyText1!.color!;
    final Color unselectedColor = unselectedLabelColor ??
        tabBarTheme.unselectedLabelColor ??
        selectedColor.withAlpha(0xB2);
    final Color color = selected
        ? Color.lerp(selectedColor, unselectedColor, animation.value)!
        : Color.lerp(unselectedColor, selectedColor, animation.value)!;

    return DefaultTextStyle(
      style: textStyle.copyWith(color: color),
      child: IconTheme.merge(
        data: IconThemeData(
          size: 24.0,
          color: color,
        ),
        child: child,
      ),
    );
  }
}

double _indexChangeProgress(TabController controller) {
  final double controllerValue = controller.animation!.value;
  final double previousIndex = controller.previousIndex.toDouble();
  final double currentIndex = controller.index.toDouble();

  if (!controller.indexIsChanging) {
    return (currentIndex - controllerValue).abs().clamp(0.0, 1.0);
  }

  return (controllerValue - currentIndex).abs() /
      (currentIndex - previousIndex).abs();
}

class _IndicatorPainter extends CustomPainter {
  _IndicatorPainter({
    required this.controller,
    required this.indicator,
    required this.indicatorSize,
    required this.tabKeys,
    required _IndicatorPainter? old,
    required this.indicatorPadding,
  })  : assert(controller != null),
        assert(indicator != null),
        super(repaint: controller.animation) {
    if (old != null) {
      saveTabOffsets(old._currentTabOffsets, old._currentTextDirection);
    }
  }

  final TabController controller;
  final Decoration indicator;
  final TabBarIndicatorSize? indicatorSize;
  final EdgeInsetsGeometry indicatorPadding;
  final List<GlobalKey> tabKeys;

  List<double>? _currentTabOffsets;
  TextDirection? _currentTextDirection;

  Rect? _currentRect;
  BoxPainter? _painter;
  bool _needsPaint = false;
  void markNeedsPaint() {
    _needsPaint = true;
  }

  void dispose() {
    _painter?.dispose();
  }

  void saveTabOffsets(List<double>? tabOffsets, TextDirection? textDirection) {
    _currentTabOffsets = tabOffsets;
    _currentTextDirection = textDirection;
  }

  int get maxTabIndex => _currentTabOffsets!.length - 2;

  double centerOf(int tabIndex) {
    assert(_currentTabOffsets != null);
    assert(_currentTabOffsets!.isNotEmpty);
    assert(tabIndex >= 0);
    assert(tabIndex <= maxTabIndex);
    return (_currentTabOffsets![tabIndex] + _currentTabOffsets![tabIndex + 1]) /
        2.0;
  }

  Rect indicatorRect(Size tabBarSize, int tabIndex) {
    assert(_currentTabOffsets != null);
    assert(_currentTextDirection != null);
    assert(_currentTabOffsets!.isNotEmpty);
    assert(tabIndex >= 0);
    assert(tabIndex <= maxTabIndex);
    double tabLeft, tabRight;
    switch (_currentTextDirection!) {
      case TextDirection.rtl:
        tabLeft = _currentTabOffsets![tabIndex + 1];
        tabRight = _currentTabOffsets![tabIndex];
        break;
      case TextDirection.ltr:
        tabLeft = _currentTabOffsets![tabIndex];
        tabRight = _currentTabOffsets![tabIndex + 1];
        break;
    }

    if (indicatorSize == TabBarIndicatorSize.label) {
      final double tabWidth = tabKeys[tabIndex].currentContext!.size!.width;
      final double delta = ((tabRight - tabLeft) - tabWidth) / 2.0;
      tabLeft += delta;
      tabRight -= delta;
    }

    final EdgeInsets insets = indicatorPadding.resolve(_currentTextDirection);
    final Rect rect =
        Rect.fromLTWH(tabLeft, 0.0, tabRight - tabLeft, tabBarSize.height);

    if (!(rect.size >= insets.collapsedSize)) {
      throw FlutterError(
        'indicatorPadding insets should be less than Tab Size\n'
        'Rect Size : ${rect.size}, Insets: ${insets.toString()}',
      );
    }
    return insets.deflateRect(rect);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _needsPaint = false;
    _painter ??= indicator.createBoxPainter(markNeedsPaint);

    final double index = controller.index.toDouble();
    final double value = controller.animation!.value;
    final bool ltr = index > value;
    final int from = (ltr ? value.floor() : value.ceil()).clamp(0, maxTabIndex);
    final int to = (ltr ? from + 1 : from - 1).clamp(0, maxTabIndex);
    final Rect fromRect = indicatorRect(size, from);
    final Rect toRect = indicatorRect(size, to);
    _currentRect = Rect.lerp(fromRect, toRect, (value - from).abs());
    assert(_currentRect != null);

    final ImageConfiguration configuration = ImageConfiguration(
      size: _currentRect!.size,
      textDirection: _currentTextDirection,
    );
    _painter!.paint(canvas, _currentRect!.topLeft, configuration);
  }

  @override
  bool shouldRepaint(_IndicatorPainter old) {
    bool rePaint = _needsPaint ||
        controller != old.controller ||
        indicator != old.indicator ||
        tabKeys.length != old.tabKeys.length ||
        (!listEquals(_currentTabOffsets, old._currentTabOffsets)) ||
        _currentTextDirection != old._currentTextDirection;

    return rePaint;
  }
}

class _ChangeAnimation extends Animation<double>
    with AnimationWithParentMixin<double> {
  _ChangeAnimation(this.controller);

  final TabController controller;

  @override
  Animation<double> get parent => controller.animation!;

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    if (controller.animation != null) super.removeStatusListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (controller.animation != null) super.removeListener(listener);
  }

  @override
  double get value => _indexChangeProgress(controller);
}

class _DragAnimation extends Animation<double>
    with AnimationWithParentMixin<double> {
  _DragAnimation(this.controller, this.index);

  final TabController controller;
  final int index;

  @override
  Animation<double> get parent => controller.animation!;

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    if (controller.animation != null) super.removeStatusListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (controller.animation != null) super.removeListener(listener);
  }

  @override
  double get value {
    assert(!controller.indexIsChanging);
    final double controllerMaxValue = (controller.length - 1).toDouble();
    final double controllerValue =
        controller.animation!.value.clamp(0.0, controllerMaxValue);
    return (controllerValue - index.toDouble()).abs().clamp(0.0, 1.0);
  }
}

typedef OnReorder = void Function(int, int);

class ReorderableTabBar extends StatefulWidget implements PreferredSizeWidget {
  const ReorderableTabBar({
    Key? key,
    required this.tabs,
    this.controller,
    this.isScrollable = false,
    this.padding,
    this.indicatorColor,
    this.automaticIndicatorColorAdjustment = true,
    this.indicatorWeight = 2.0,
    this.indicatorPadding = EdgeInsets.zero,
    this.indicator,
    this.indicatorSize,
    this.labelColor,
    this.labelStyle,
    this.labelPadding,
    this.unselectedLabelColor,
    this.unselectedLabelStyle,
    this.dragStartBehavior = DragStartBehavior.start,
    this.overlayColor,
    this.mouseCursor,
    this.enableFeedback,
    this.onTap,
    this.physics,
    this.onReorder,
    this.defaultIndicator = false,
    this.tabBorderRadius,
    this.reorderingTabBackgroundColor,
    this.tabBackgroundColor,
  })  : assert(tabs != null),
        assert(isScrollable != null),
        assert(dragStartBehavior != null),
        assert(indicator != null ||
            (indicatorWeight != null && indicatorWeight > 0.0)),
        assert(indicator != null || (indicatorPadding != null)),
        super(key: key);

  final BorderRadius? tabBorderRadius;

  final Color? tabBackgroundColor;

  final bool defaultIndicator;

  final OnReorder? onReorder;

  final Color? reorderingTabBackgroundColor;

  final List<Widget> tabs;

  final TabController? controller;

  final bool isScrollable;

  final EdgeInsetsGeometry? padding;

  final Color? indicatorColor;

  final double indicatorWeight;

  final EdgeInsetsGeometry indicatorPadding;

  final Decoration? indicator;

  final bool automaticIndicatorColorAdjustment;

  final TabBarIndicatorSize? indicatorSize;

  final Color? labelColor;

  final Color? unselectedLabelColor;

  final TextStyle? labelStyle;

  final EdgeInsetsGeometry? labelPadding;

  final TextStyle? unselectedLabelStyle;

  final MaterialStateProperty<Color?>? overlayColor;

  final DragStartBehavior dragStartBehavior;

  final MouseCursor? mouseCursor;

  final bool? enableFeedback;

  final ValueChanged<int>? onTap;

  final ScrollPhysics? physics;

  @override
  Size get preferredSize {
    double maxHeight = _kTabHeight;
    for (final Widget item in tabs) {
      if (item is PreferredSizeWidget) {
        final double itemHeight = item.preferredSize.height;
        maxHeight = math.max(itemHeight, maxHeight);
      }
    }
    return Size.fromHeight(maxHeight + indicatorWeight);
  }

  bool get tabHasTextAndIcon {
    for (final Widget item in tabs) {
      if (item is PreferredSizeWidget) {
        if (item.preferredSize.height == _kTextAndIconTabHeight) return true;
      }
    }
    return false;
  }

  @override
  State<ReorderableTabBar> createState() => _ReorderableTabBarState();
}

class _ReorderableTabBarState extends State<ReorderableTabBar> {
  ScrollController? _scrollController;
  TabController? _controller;
  _IndicatorPainter? _indicatorPainter;
  ScrollController? _reorderController;
  int? _currentIndex;
  double? _tabStripWidth;
  List<double> xOffsets = [];
  double? height;
  bool isScrollToCurrentIndex = false;
  Reordered? isReordered;
  late double screenWidth;
  late List<GlobalKey> _tabKeys;
  late List<GlobalKey> _tabExtendKeys;
  late LinkedScrollControllerGroup _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = LinkedScrollControllerGroup();
    _reorderController = _controllers.addAndGet();
    _scrollController = _controllers.addAndGet();
    _tabKeys = widget.tabs.map((Widget tab) => GlobalKey()).toList();
    _tabExtendKeys = widget.tabs.map((Widget tab) => GlobalKey()).toList();
  }

  Decoration get _indicator {
    if (widget.indicator != null) return widget.indicator!;
    final TabBarTheme tabBarTheme = TabBarTheme.of(context);
    if (tabBarTheme.indicator != null) return tabBarTheme.indicator!;

    Color color = widget.indicatorColor ?? Theme.of(context).indicatorColor;

    if (widget.automaticIndicatorColorAdjustment &&
        color.value == Material.of(context)?.color?.value) color = Colors.white;

    if (widget.defaultIndicator) {
      return UnderlineTabIndicator(
        borderSide: BorderSide(
          width: widget.indicatorWeight,
          color: color,
        ),
      );
    }

    return MaterialIndicator(
      height: widget.indicatorWeight,
      color: color,
      tabPosition: TabPosition.bottom,
    );
  }

  bool get _controllerIsValid => _controller?.animation != null;

  void _updateTabController() {
    final TabController? newController =
        widget.controller ?? DefaultTabController.of(context);
    assert(() {
      if (newController == null) {
        throw FlutterError(
          'No TabController for ${widget.runtimeType}.\n'
          'When creating a ${widget.runtimeType}, you must either provide an explicit '
          'TabController using the "controller" property, or you must ensure that there '
          'is a DefaultTabController above the ${widget.runtimeType}.\n'
          'In this case, there was neither an explicit controller nor a default controller.',
        );
      }
      return true;
    }());

    if (newController == _controller) return;

    if (_controllerIsValid) {
      _controller!.animation!.removeListener(_handleTabControllerAnimationTick);
      _controller!.removeListener(_handleTabControllerTick);
    }
    _controller = newController;
    if (_controller != null) {
      _controller!.animation!.addListener(_handleTabControllerAnimationTick);
      _controller!.addListener(_handleTabControllerTick);
      _currentIndex = _controller!.index;
    }
  }

  void _initIndicatorPainter() {
    _indicatorPainter = !_controllerIsValid
        ? null
        : _IndicatorPainter(
            controller: _controller!,
            indicator: _indicator,
            indicatorSize:
                widget.indicatorSize ?? TabBarTheme.of(context).indicatorSize,
            indicatorPadding: widget.indicatorPadding,
            tabKeys: _tabKeys,
            old: _indicatorPainter,
          );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    assert(debugCheckHasMaterial(context));
    screenWidth = MediaQuery.of(context).size.width;
    _updateTabController();
    _initIndicatorPainter();
  }

  @override
  void didUpdateWidget(ReorderableTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.controller != oldWidget.controller) {
      _updateTabController();
      _initIndicatorPainter();
    } else if (widget.indicatorColor != oldWidget.indicatorColor ||
        widget.indicatorWeight != oldWidget.indicatorWeight ||
        widget.indicatorSize != oldWidget.indicatorSize ||
        widget.indicator != oldWidget.indicator) {
      _initIndicatorPainter();
    }

    if (widget.tabs.length > oldWidget.tabs.length) {
      final int delta = widget.tabs.length - oldWidget.tabs.length;
      _tabKeys.addAll(List<GlobalKey>.generate(delta, (int n) => GlobalKey()));
      _tabExtendKeys
          .addAll(List<GlobalKey>.generate(delta, (int n) => GlobalKey()));
    } else if (widget.tabs.length < oldWidget.tabs.length) {
      _tabKeys.removeRange(widget.tabs.length, oldWidget.tabs.length);
      _tabExtendKeys.removeRange(widget.tabs.length, oldWidget.tabs.length);
    }
    if (!listEquals(oldWidget.tabs, widget.tabs)) {
      if (isReordered != null) {
        _scrollToNewCurrentIndex();
      }
    }
    if (oldWidget.isScrollable != widget.isScrollable) {
      if (widget.isScrollable) {
        isScrollToCurrentIndex = true;
      }
    }
  }

  @override
  void dispose() {
    _indicatorPainter!.dispose();
    if (_controllerIsValid) {
      _controller!.animation!.removeListener(_handleTabControllerAnimationTick);
      _controller!.removeListener(_handleTabControllerTick);
    }
    _controller = null;

    super.dispose();
  }

  int get maxTabIndex => _indicatorPainter!.maxTabIndex;

  double _tabScrollOffset(
      int index, double viewportWidth, double minExtent, double maxExtent) {
    if (!widget.isScrollable) return 0.0;

    double tabCenter = _indicatorPainter!.centerOf(index);
    switch (Directionality.of(context)) {
      case TextDirection.rtl:
        tabCenter = _tabStripWidth! - tabCenter;
        break;
      case TextDirection.ltr:
        break;
    }
    return (tabCenter - viewportWidth / 2.0).clamp(minExtent, maxExtent);
  }

  double _tabCenteredScrollOffset(int index) {
    final ScrollPosition? position = _reorderController?.position;

    return _tabScrollOffset(
        index,
        position?.viewportDimension ?? screenWidth,
        position?.minScrollExtent ?? 0,
        position?.maxScrollExtent ?? screenWidth);
  }

  void _initialScrollOffset() {
    if (!widget.isScrollable) {
      _controllers.animateTo(0.01,
          curve: Curves.linear, duration: const Duration(milliseconds: 1));
    }
  }

  void _scrollToCurrentIndex() {
    final double offset = _tabCenteredScrollOffset(_currentIndex!);

    _controllers.animateTo(offset,
        duration: kTabScrollDuration, curve: Curves.ease);
  }

  void _scrollToControllerValue() {
    final double? leadingPosition = _currentIndex! > 0
        ? _tabCenteredScrollOffset(_currentIndex! - 1)
        : null;
    final double middlePosition = _tabCenteredScrollOffset(_currentIndex!);
    final double? trailingPosition = _currentIndex! < maxTabIndex
        ? _tabCenteredScrollOffset(_currentIndex! + 1)
        : null;

    final double index = _controller!.index.toDouble();
    final double value = _controller!.animation!.value;
    final double offset;
    if (value == index - 1.0) {
      offset = leadingPosition ?? middlePosition;
    } else if (value == index + 1.0) {
      offset = trailingPosition ?? middlePosition;
    } else if (value == index) {
      offset = middlePosition;
    } else if (value < index) {
      offset = leadingPosition == null
          ? middlePosition
          : lerpDouble(middlePosition, leadingPosition, index - value)!;
    } else {
      offset = trailingPosition == null
          ? middlePosition
          : lerpDouble(middlePosition, trailingPosition, value - index)!;
    }

    _controllers.jumpTo(offset);
  }

  void _handleTabControllerAnimationTick() {
    assert(mounted);
    if (!_controller!.indexIsChanging && widget.isScrollable) {
      _currentIndex = _controller!.index;
      _scrollToControllerValue();
    }
  }

  void _handleTabControllerTick() {
    if (_controller!.index != _currentIndex) {
      _currentIndex = _controller!.index;
      if (widget.isScrollable) _scrollToCurrentIndex();
    }
    setState(() {});
  }

  void _saveTabOffsets(
      List<double> tabOffsets, TextDirection textDirection, double width) {
    xOffsets = tabOffsets;
    _tabStripWidth = width;
    _indicatorPainter?.saveTabOffsets(tabOffsets, textDirection);
  }

  void _handleTap(int index) async {
    assert(index >= 0 && index < widget.tabs.length);
    _controller!.animateTo(index);
    widget.onTap?.call(index);
  }

  Widget _buildStyledTab(
      Widget child, bool selected, Animation<double> animation) {
    return _TabStyle(
      animation: animation,
      selected: selected,
      labelColor: widget.labelColor,
      unselectedLabelColor: widget.unselectedLabelColor,
      labelStyle: widget.labelStyle,
      unselectedLabelStyle: widget.unselectedLabelStyle,
      child: child,
    );
  }

  calculateTabStripWidth() {
    WidgetsBinding.instance!.addPostFrameCallback((timeStamp) {
      double width = 0;
      List<double> offsets = [0];
      TextDirection textDirection = Directionality.maybeOf(context)!;
      for (var key in (textDirection == TextDirection.rtl
          ? _tabExtendKeys.reversed.toList()
          : _tabExtendKeys)) {
        width += key.currentContext?.size?.width ?? 40;
        switch (textDirection) {
          case TextDirection.rtl:
            offsets.insert(0, width);
            break;
          case TextDirection.ltr:
            offsets.add(width);
            break;
        }
      }
      if ((_tabStripWidth ?? 0).floor() != width.floor() ||
          !listEquals<double>(offsets, xOffsets)) {
        _saveTabOffsets(offsets, textDirection, width);
        if (!widget.isScrollable) {
          _initialScrollOffset();
        }
        setState(() {});
      }

      if (isScrollToCurrentIndex) {
        _scrollToCurrentIndex();
        isScrollToCurrentIndex = false;
      }
    });
  }

  void _scrollToNewCurrentIndex() {
    int oldIndex = isReordered!.oldIndex;
    int newIndex = isReordered!.newIndex;

    if (oldIndex == _currentIndex) {
      _checkAndAnimateTo(newIndex);
    } else if (oldIndex > (_currentIndex ?? 0)) {
      if (newIndex < (_currentIndex ?? 0) || newIndex == _currentIndex) {
        int index = (_currentIndex ?? 0);
        _checkAndAnimateTo(++index);
      }
    } else {
      if (newIndex > (_currentIndex ?? 0) || newIndex == _currentIndex) {
        int index = (_currentIndex ?? 0);
        _checkAndAnimateTo(--index);
      }
    }

    isReordered = null;
  }

  _checkAndAnimateTo(int index) {
    if (index < widget.tabs.length) {
      _controller!.animateTo(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMaterialLocalizations(context));
    assert(() {
      if (_controller!.length != widget.tabs.length) {
        throw FlutterError(
          "Controller's length property (${_controller!.length}) does not match the "
          "number of tabs (${widget.tabs.length}) present in TabBar's tabs property.",
        );
      }
      return true;
    }());
    final MaterialLocalizations localizations =
        MaterialLocalizations.of(context);
    if (_controller!.length == 0) {
      return Container(
        height: _kTabHeight + widget.indicatorWeight,
      );
    }

    final TabBarTheme tabBarTheme = TabBarTheme.of(context);

    final List<Widget> wrappedTabs =
        List<Widget>.generate(widget.tabs.length, (int index) {
      const double verticalAdjustment =
          (_kTextAndIconTabHeight - _kTabHeight) / 2.0;
      EdgeInsetsGeometry? adjustedPadding;

      if (widget.tabs[index] is PreferredSizeWidget) {
        final PreferredSizeWidget tab =
            widget.tabs[index] as PreferredSizeWidget;
        if (widget.tabHasTextAndIcon &&
            tab.preferredSize.height == _kTabHeight) {
          if (widget.labelPadding != null || tabBarTheme.labelPadding != null) {
            adjustedPadding = (widget.labelPadding ?? tabBarTheme.labelPadding!)
                .add(const EdgeInsets.symmetric(vertical: verticalAdjustment));
          } else {
            adjustedPadding = const EdgeInsets.symmetric(
                vertical: verticalAdjustment, horizontal: 16.0);
          }
        }
      }

      return Center(
        heightFactor: 1.0,
        child: Padding(
          padding: adjustedPadding ??
              widget.labelPadding ??
              tabBarTheme.labelPadding ??
              kTabLabelPadding,
          child: KeyedSubtree(
            key: _tabKeys[index],
            child: widget.tabs[index],
          ),
        ),
      );
    });

    if (_controller != null) {
      final int previousIndex = _controller!.previousIndex;

      if (_controller!.indexIsChanging) {
        assert(_currentIndex != previousIndex);
        final Animation<double> animation = _ChangeAnimation(_controller!);
        wrappedTabs[_currentIndex!] =
            _buildStyledTab(wrappedTabs[_currentIndex!], true, animation);
        wrappedTabs[previousIndex] =
            _buildStyledTab(wrappedTabs[previousIndex], false, animation);
      } else {
        final int tabIndex = _currentIndex!;
        final Animation<double> centerAnimation =
            _DragAnimation(_controller!, tabIndex);
        wrappedTabs[tabIndex] =
            _buildStyledTab(wrappedTabs[tabIndex], true, centerAnimation);
        if (_currentIndex! > 0) {
          final int tabIndex = _currentIndex! - 1;
          final Animation<double> previousAnimation =
              ReverseAnimation(_DragAnimation(_controller!, tabIndex));
          wrappedTabs[tabIndex] =
              _buildStyledTab(wrappedTabs[tabIndex], false, previousAnimation);
        }
        if (_currentIndex! < widget.tabs.length - 1) {
          final int tabIndex = _currentIndex! + 1;
          final Animation<double> nextAnimation =
              ReverseAnimation(_DragAnimation(_controller!, tabIndex));
          wrappedTabs[tabIndex] =
              _buildStyledTab(wrappedTabs[tabIndex], false, nextAnimation);
        }
      }
    }

    final int tabCount = widget.tabs.length;
    for (int index = 0; index < tabCount; index += 1) {
      wrappedTabs[index] = InkWell(
        borderRadius: widget.tabBorderRadius,
        mouseCursor: widget.mouseCursor ?? SystemMouseCursors.click,
        onTap: () async {
          _handleTap(index);
        },
        enableFeedback: widget.enableFeedback ?? true,
        overlayColor: widget.overlayColor,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: widget.tabBorderRadius,
            color: widget.tabBackgroundColor,
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: widget.indicatorWeight),
            child: Stack(
              children: <Widget>[
                wrappedTabs[index],
                Semantics(
                  selected: index == _currentIndex,
                  label: localizations.tabLabel(
                      tabIndex: index + 1, tabCount: tabCount),
                ),
              ],
            ),
          ),
        ),
      );
    }
    Widget? tabBar;

    height ??= widget.preferredSize.height;

    double? tabWidth;
    if (!widget.isScrollable) {
      tabWidth = (screenWidth - (widget.padding?.horizontal ?? 0)) /
          wrappedTabs.length;
    }
    for (var i = 0; i < wrappedTabs.length; i++) {
      Widget child = wrappedTabs[i];

      wrappedTabs[i] = SizedBox(
        key: _tabExtendKeys[i],
        width: tabWidth,
        height: height,
        child: _TabStyle(
          animation: kAlwaysDismissedAnimation,
          selected: false,
          labelColor: widget.labelColor,
          unselectedLabelColor: widget.unselectedLabelColor,
          labelStyle: widget.labelStyle,
          unselectedLabelStyle: widget.unselectedLabelStyle,
          child: child,
        ),
      );
    }
    tabBar = Stack(
      children: [
        SizedBox(
          height: height,
          width: double.maxFinite,
          child: ReorderableListView(
            physics: widget.physics,
            scrollController: _reorderController,
            scrollDirection: Axis.horizontal,
            children: wrappedTabs,
            proxyDecorator: (child, index, anim) {
              return Material(
                color:
                    widget.reorderingTabBackgroundColor ?? Colors.transparent,
                borderRadius: widget.tabBorderRadius,
                child: child,
              );
            },
            onReorder: (oldIndex, newIndex) async {
              if (oldIndex < newIndex) {
                newIndex--;
              }
              if (widget.onReorder != null) {
                isReordered = Reordered(
                  oldIndex: oldIndex,
                  newIndex: newIndex,
                );
                widget.onReorder!(oldIndex, newIndex);
              }
            },
          ),
        ),
        if (_tabStripWidth != null) getIndicatorPainter(),
      ],
    );
    if (widget.padding != null) {
      tabBar = Padding(
        padding: widget.padding!,
        child: tabBar,
      );
    }
    calculateTabStripWidth();
    return tabBar;
  }

  Positioned getIndicatorPainter() {
    double width = _tabStripWidth!;
    if (!widget.isScrollable) {
      if (width > (screenWidth - (widget.padding?.horizontal ?? 0))) {
        width = screenWidth - (widget.padding?.horizontal ?? 0);
      }
    }
    return Positioned(
      bottom: 0,
      right: 0,
      left: 0,
      height: widget.indicatorWeight,
      child: SingleChildScrollView(
        physics: widget.physics,
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: CustomPaint(
          painter: _indicatorPainter,
          child: SizedBox(
            height: widget.indicatorWeight,
            width: width,
          ),
        ),
      ),
    );
  }
}

class Reordered {
  int oldIndex;
  int newIndex;
  Reordered({
    required this.oldIndex,
    required this.newIndex,
  });
}
