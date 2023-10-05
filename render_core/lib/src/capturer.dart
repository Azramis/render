import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:render_core/src/service/notifier.dart';
import 'package:render_core/src/service/session.dart';
import 'package:render_core/src/service/settings.dart';
import 'package:render_core/src/service/task_identifier.dart';

import 'service/exception.dart';

class RenderCapturer<R> {
  /// Settings of how each frame should be rendered.

  /// Current session captures should be assigned to.
  final RenderSession<R, RenderSettings> session;

  /// Context of the flutter app, if a widget should be captured
  final BuildContext? context;

  RenderCapturer(this.session, [this.context]);

  int _activeHandlers = 0;

  /// Captures that are yet to be handled. Handled images will be disposed.
  final List<ui.Image> _unhandledCaptures = [];

  /// Current image handling process. Handlers are being handles asynchronous
  /// as conversion and file writing is involved.
  final List<Future<void>> _handlers = [];

  /// A flag to indicate whether the capturing process is running or not.
  bool _rendering = false;

  ///The time position of capture start of the duration of the scheduler binding.
  Duration? startingDuration;

  /// Start tim of capturing
  DateTime? startTime;

  /// The size of the first frame. Used to maintain equality of size throughout
  /// capturing.
  /// In duration the actual "first" frame will be disposed and the next frame
  /// will be seen as first frame.
  Size? firstFrameSize;

  final Completer<RenderSession<R, RealRenderSettings>> _captureCompleter =
      Completer<RenderSession<R, RealRenderSettings>>();

  /// Starts new capturing process for unknown duration
  Future<RenderSession<R, RealRenderSettings>> run([Duration? duration]) async {
    assert(!_rendering, "Cannot start new process, during an active one.");
    _rendering = true;
    startTime = DateTime.now();
    startingDuration = session.binding.currentFrameTimeStamp;
    _postFrameCallback(
      binderTimeStamp: startingDuration!,
      frame: 0,
    );

    if (duration != null) {
      Future.delayed(
        duration,
        () {
          if (!_captureCompleter.isCompleted) {
            finish();
          }
        },
      );
    }

    return _captureCompleter.future;
  }

  /// Finishes current capturing process. Returns the total capturing time.
  void finish() {
    assert(_rendering, "Cannot finish capturing as, no active capturing.");

    _captureCompleter.complete(Future.sync(
      () async {
        final capturingDuration = Duration(
            milliseconds: DateTime.now().millisecondsSinceEpoch -
                startTime!.millisecondsSinceEpoch); // log end of capturing
        _rendering = false;
        startingDuration = null;
        // * wait for handlers
        await Future.doWhile(() async {
          //await all active capture handlers
          await Future.wait(_handlers);
          return _handlers.length < _unhandledCaptures.length;
        });
        // * finish capturing, notify session
        final frameAmount = _unhandledCaptures.length;
        _handlers.clear();
        _unhandledCaptures.clear();

        return session.upgrade(capturingDuration, frameAmount);
      },
    ));
  }

  /// A callback function that is called after each frame is rendered.
  void _postFrameCallback({
    required Duration binderTimeStamp,
    required int frame,
  }) async {
    if (!_rendering) return;
    final targetFrameRate = session.settings.frameRate;
    final relativeTimeStamp =
        binderTimeStamp - (startingDuration ?? Duration.zero);
    final nextMilliSecond = (1 / targetFrameRate) * frame * 1000;
    if (nextMilliSecond > relativeTimeStamp.inMilliseconds) {
      // add a new PostFrameCallback to know about the next frame
      session.binding.addPostFrameCallback(
        (binderTimeStamp) => _postFrameCallback(
          binderTimeStamp: binderTimeStamp,
          frame: frame,
        ),
      );
      // but we do nothing, because we skip this frame
      return;
    }

    final maxFramesCount = session.settings.framesCount;

    if (maxFramesCount != null && maxFramesCount <= frame) {
      // Captured frames count reached, now time to quit
      finish();
      return;
    }

    try {
      _captureFrame(frame);
    } on RenderException catch (exception) {
      session.recordError(exception);
      if (exception.fatal) return;
    }
    session.binding.addPostFrameCallback(
      (binderTimeStamp) => _postFrameCallback(
        binderTimeStamp: binderTimeStamp,
        frame: frame + 1,
      ),
    );
  }

  /// Converting the raw image data to a png file and writing the capture.
  Future<void> _handleCapture(
    int captureNumber,
  ) async {
    _activeHandlers++;
    try {
      final ui.Image capture = _unhandledCaptures.elementAt(captureNumber);

      session.delegate.handleCapture(
        capture: capture,
        captureNumber: captureNumber,
      );

      // * finish
      capture.dispose();
      if (!_rendering) {
        //only record next state, when rendering is done not to mix up notification
        _recordActivity(
          RenderState.handleCaptures,
          captureNumber,
          "Handled frame $captureNumber",
        );
      }
    } catch (e) {
      session.recordError(
        RenderException(
          "Handling frame $captureNumber unsuccessful.",
          details: e,
        ),
      );
    }
    _activeHandlers--;
    _triggerHandler();
  }

  /// Triggers the next handler, if within allowed simultaneous handlers
  /// and images still available.
  void _triggerHandler() {
    final nextCaptureIndex = _handlers.length;
    if (_activeHandlers <
            max(1, session.settings.maxSimultaneousCaptureHandlers) &&
        nextCaptureIndex < _unhandledCaptures.length) {
      _handlers.add(_handleCapture(nextCaptureIndex));
    }
  }

  /// Captures associated task of this frame
  void _captureFrame(int frameNumber) {
    // * capture
    ui.Image image;
    if (session.task is KeyIdentifier) {
      image = _captureContext((session.task as KeyIdentifier).key);
    } else if (session.task is WidgetIdentifier) {
      image = _captureWidget((session.task as WidgetIdentifier).widget);
    } else {
      throw const RenderException("Could not identify render task.");
    }
    // * Check for valid frame size
    // [Resolved] https://github.com/polarby/render/issues/9
    final frameSize = Size(image.width.toDouble(), image.height.toDouble());
    firstFrameSize ??= frameSize;
    if (frameSize != firstFrameSize) {
      throw const RenderException(
        "Invalid frame sizes. "
        "All Render frames must have a fixed size during capturing",
        details:
            "The render widget might be wrapped by an expandable widget that "
            "changes size during capturing.",
        fatal: true,
      );
    }
    // * initiate handler
    _unhandledCaptures.add(image);
    _triggerHandler();
    _recordActivity(
        RenderState.capturing, frameNumber, "Captured frame $frameNumber");
  }

  /// Using the `RenderRepaintBoundary` to capture the current frame.
  ui.Image _captureContext(GlobalKey key) {
    try {
      final renderObject =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (renderObject == null) {
        throw const RenderException(
          "Capturing frame context unsuccessful as context is null."
          " Trying next frame.",
        );
      }
      return renderObject.toImageSync(pixelRatio: session.settings.pixelRatio);
    } catch (e) {
      throw RenderException(
        "Unknown error while capturing frame context. Trying next frame.",
        details: e,
      );
    }
  }

  /// Captures a widget-frame that is not build in a widget tree.
  /// Inspired by [screenshot plugin](https://github.com/SachinGanesh/screenshot)
  ui.Image _captureWidget(Widget widget) {
    assert(context != null,
        "Capturing from widget requires valid context of in RenderCapturer.");
    try {
      final RenderRepaintBoundary repaintBoundary = RenderRepaintBoundary();

      final flutterView = View.of(context!);
      Size logicalSize =
          flutterView.physicalSize / flutterView.devicePixelRatio;
      Size imageSize = flutterView.physicalSize;

      assert(logicalSize.aspectRatio.toStringAsPrecision(5) ==
          imageSize.aspectRatio.toStringAsPrecision(5));

      final RenderView renderView = RenderView(
        view: flutterView,
        child: RenderPositionedBox(
            alignment: Alignment.center, child: repaintBoundary),
        configuration: ViewConfiguration(
          size: logicalSize,
          devicePixelRatio: session.settings.pixelRatio,
        ),
      );

      final PipelineOwner pipelineOwner = PipelineOwner();
      final BuildOwner buildOwner =
          BuildOwner(focusManager: FocusManager(), onBuildScheduled: () {});

      pipelineOwner.rootNode = renderView;
      renderView.prepareInitialFrame();

      final RenderObjectToWidgetElement<RenderBox> rootElement =
          RenderObjectToWidgetAdapter<RenderBox>(
              container: repaintBoundary,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: widget,
              )).attachToRenderTree(
        buildOwner,
      );
      buildOwner.buildScope(
        rootElement,
      );
      buildOwner.finalizeTree();

      pipelineOwner.flushLayout();
      pipelineOwner.flushCompositingBits();
      pipelineOwner.flushPaint();
      /*
      try {
        /// Dispose All widgets
        rootElement.visitChildren((Element element) {
          rootElement.deactivateChild(element);
        });
        buildOwner.finalizeTree();
      } catch (_) {}
       */

      return repaintBoundary.toImageSync(
          pixelRatio: session.settings.pixelRatio);
    } catch (e) {
      throw RenderException(
        "Unknown error while capturing frame context. Trying next frame.",
        details: e,
      );
    }
  }

  /// Recording the activity of the current session specifically for capturing
  void _recordActivity(RenderState state, int frame, String message) {
    final totalFrameTarget = session.settings.framesCount;

    if (totalFrameTarget != null) {
      session.recordActivity(
          state, ((1 / totalFrameTarget) * frame).clamp(0.0, 1.0),
          message: message);
    } else {
      // capturing activity when recording (no time limit set)
      session.recordActivity(state, null, message: message);
    }
  }
}
