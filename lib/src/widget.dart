import 'package:flutter/material.dart';

class OverlayedInteractiveViewer extends StatefulWidget {
  static const Duration defaultResetDuration = Duration(milliseconds: 200);

  /// Create an OverlayedInteractiveViewer,
  /// remeber that is just a little bit of customization over an interactive viewer
  ///
  /// * [child] is the widget used for zooming.
  /// This parameter is required because without a child there is nothing to zoom on
  const OverlayedInteractiveViewer({
    required this.child,
    this.zoomChild,
    this.twoFingersOn,
    this.twoFingersOff,
    this.resetDuration = defaultResetDuration,
    this.resetCurve = Curves.fastLinearToSlowEaseIn,
    this.boundaryMargin = EdgeInsets.zero,
    this.clipBehavior = Clip.none,
    this.minScale = 1,
    this.maxScale = 2.5,
    this.useOverlay = true,
    this.maxOverlayOpacity = 0.5,
    this.overlayColor = Colors.black,
    this.fingersRequiredToPinch = 2,
    super.key,
  })  : assert(minScale > 0),
        assert(maxScale > 0),
        assert(maxScale >= minScale);

  /// Widget where the pinch will be done
  final Widget child;

  /// If you set a zoomChild, the zoom will be done in this widget,
  /// this can be useful if you have an animation in the child widget,
  /// and want to zoom only in the last frame of that animation
  final Widget? zoomChild;

  /// If set to [Clip.none], the child may extend beyond the size of the InteractiveViewer,
  /// but it will not receive gestures in these areas.
  /// Be sure that the InteractiveViewer is the desired size when using [Clip.none].
  ///
  /// Defaults to [Clip.none].
  final Clip clipBehavior;

  /// The maximum allowed scale.
  ///
  /// The scale will be clamped between this and [minScale] inclusively.
  ///
  /// Defaults to 2.5.
  ///
  /// Cannot be null, and must be greater than zero and greater than minScale.
  final double maxScale;

  /// The minimum allowed scale.
  ///
  /// The scale will be clamped between this and [maxScale] inclusively.
  ///
  /// Scale is also affected by [boundaryMargin]. If the scale would result in
  /// viewing beyond the boundary, then it will not be allowed. By default,
  /// boundaryMargin is EdgeInsets.zero, so scaling below 1.0 will not be
  /// allowed in most cases without first increasing the boundaryMargin.
  ///
  /// Defaults to 0.8.
  ///
  /// Cannot be null, and must be a finite number greater than zero and less
  /// than maxScale.
  final double minScale;

  /// The duration of the reset animation
  final Duration resetDuration;

  /// The curve of the reset animation
  final Curve resetCurve;

  /// The boundary margin of the interactive viewer,
  /// this can be used to give margin in the bottom
  /// in case you want the user to zoom out
  final EdgeInsets boundaryMargin;

  /// If it's true will create a new widget to zoom, to occupy the entire screen
  ///
  /// The problem of using an overlay is if you want to zoom in a scrollable widget
  /// as the widget is rebuilt to occupy the entire screen
  /// can lose the scroll or any other state
  final bool useOverlay;

  /// The max opacity of the overlay when users zooms in
  final double maxOverlayOpacity;

  /// Overlay color
  final Color overlayColor;

  /// Fingers required to start a pinch,
  /// if it's zero or below zero no validation will be performed
  final int fingersRequiredToPinch;

  /// This function is super useful to block scroll and make the pinch to zoom easier
  final void Function()? twoFingersOn;

  /// Function to unblock scroll again
  final void Function()? twoFingersOff;


  @override
  State<OverlayedInteractiveViewer> createState() => _OverlayedInteractiveViewerState();
}

class _OverlayedInteractiveViewerState extends State<OverlayedInteractiveViewer>
    with TickerProviderStateMixin {
  late TransformationController transformationController =
      TransformationController();
  late AnimationController animationController = AnimationController(
    vsync: this,
    duration: widget.resetDuration,
  );
  Animation<Matrix4>? animation;
  OverlayEntry? entry;
  List<OverlayEntry> overlayEntries = [];
  double scale = 1;
  final List<int> events = [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    transformationController.dispose();
    animationController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    animationController
      ..addListener(
        () => transformationController.value = animation!.value,
      )
      ..addStatusListener(
        (status) {
          if (status == AnimationStatus.completed && widget.useOverlay) {
            Future.delayed(const Duration(milliseconds: 100), removeOverlay);
          }
        },
      );
    return buildWidget(widget.child);
  }

  void resetAnimation() {
    if (mounted) {
      animation = Matrix4Tween(
        begin: transformationController.value,
        end: Matrix4.identity(),
      ).animate(CurvedAnimation(
        parent: animationController,
        curve: widget.resetCurve,
      ));
      animationController.forward(from: 0);
    }
  }

  Widget buildWidget(Widget zoomableWidget) => Builder(
        builder: (context) => Material(
          type: MaterialType.transparency,
          child: Listener(
            onPointerDown: (PointerEvent event) {
              events.add(event.pointer);
              final int pointers = events.length;

              if (pointers >= 2 && widget.twoFingersOn != null) {
                widget.twoFingersOn!.call();
              }
            },
            onPointerUp: (event) {
              events.clear();
              final int pointers = events.length;

              if (pointers < 2 && widget.twoFingersOff != null) {
                widget.twoFingersOff!.call();
              }
            },
            child: InteractiveViewer(
              clipBehavior: widget.clipBehavior,
              minScale: widget.minScale,
              maxScale: widget.maxScale,
              transformationController: transformationController,
              onInteractionStart: (details) {
                if (widget.fingersRequiredToPinch > 0 &&
                    details.pointerCount != widget.fingersRequiredToPinch) {
                  return;
                }
                if (widget.useOverlay) {
                  showOverlay(context);
                }
              },
              onInteractionEnd: (details) {
                if (overlayEntries.isEmpty) {
                  return;
                }

                resetAnimation();
              },
              onInteractionUpdate: (details) {
                if (entry == null) {
                  return;
                }

                scale = details.scale;
                entry?.markNeedsBuild();
              },
              panEnabled: false,
              boundaryMargin: widget.boundaryMargin,
              child: zoomableWidget,
            ),
          ),
        ),
      );

  void showOverlay(BuildContext context) {
    final OverlayState overlay = Overlay.of(context);
    final RenderBox renderBox = context.findRenderObject()! as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);

    entry = OverlayEntry(builder: (context) {
      final double opacity = ((scale - 1) / (widget.maxScale - 1))
          .clamp(0, widget.maxOverlayOpacity);

      return Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: opacity,
                child: Container(color: widget.overlayColor),
              ),
            ),
            Positioned(
              left: offset.dx,
              top: offset.dy,
              child: SizedBox(
                width: renderBox.size.width,
                height: renderBox.size.height,
                child: buildWidget(widget.zoomChild ?? widget.child),
              ),
            ),
          ],
        ),
      );
    });
    overlay.insert(entry!);

    // We need to control all the overlays added to avoid problems in scrolling,
    overlayEntries.add(entry!);
  }

  void removeOverlay() {
    for (final OverlayEntry entry in overlayEntries) {
      entry.remove();
    }
    overlayEntries.clear();
    entry = null;
  }
}
