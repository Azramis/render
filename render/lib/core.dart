import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:render/formats/abstract.dart';
import 'package:render/formats/image.dart';
import 'package:render/formats/motion.dart';
import 'package:render/services/settings.dart';
import 'package:render_core/render_core.dart';

class RenderController extends BaseRenderController {
  RenderController({
    super.logLevel,
  });

  /// Captures the [Render] widget and returns the result as future.
  ///
  /// Capturing an image is expected not to take too long in normal operations
  /// to make a stream necessary. For large image rendering or detail
  /// notifications of the process use [captureImageWithStream].
  ///
  /// Default file format is [ImageFormat.png]
  Future<RenderResult> captureImage({
    LogLevel? logLevel,
    ImageSettings settings = const ImageSettings(),
    ImageFormat format = const PngFormat(),
  }) =>
      capture(
        settings: settings,
        format: format,
        logLevel: logLevel,
      );

  /// Captures an image and returns the result as future.
  ///
  /// Note that this method replaced the need for the [Render] widget as a parent
  /// widget. Simply pass the widget that need to be rendered in the function.
  ///
  /// Capturing an image is expected not to take too long in normal operations
  /// to make a stream necessary. For large image rendering or detail
  /// notifications of the process use [captureImageFromWidgetWithStream].
  ///
  /// Default file format is [ImageFormat.png]
  Future<RenderResult> captureImageFromWidget(
    BuildContext context,
    Widget widget, {
    LogLevel? logLevel,
    ImageSettings settings = const ImageSettings(),
    ImageFormat format = const PngFormat(),
  }) =>
      captureFromWidget(
        context,
        widget,
        settings: settings,
        format: format,
        logLevel: logLevel,
      );

  /// Captures the motion of a widget and returns a future of the result.
  ///
  /// This function is only recommended for debug purposes.
  ///
  /// It is highly recommended to use [captureMotionWithStream] to capture
  /// motion, as the process usually takes longer and the user will likely wants
  /// to get notified with the stream about the process of rendering for longer
  /// operations.
  ///
  /// Default file format is [MotionFormat.mov]
  Future<RenderResult> captureMotion(
    Duration duration, {
    LogLevel? logLevel,
    MotionSettings settings = const MotionSettings(),
    MotionFormat format = const MovFormat(),
  }) =>
      capture(
        duration: duration,
        settings: settings,
        format: format,
        logLevel: logLevel,
      );

  /// Captures motion of a widget that is out of the widget tree
  /// and returns a future with the result.
  ///
  /// Note that this method replaced the need for the [Render] widget as a parent
  /// widget. Simply pass the widget that need to be rendered in the function.
  ///
  /// This function is only recommended for debug purposes.
  ///
  /// It is highly recommended to use [captureMotionWithStream] to capture
  /// motion, as the process usually takes longer and the user will likely wants
  /// to get notified with the stream about the process of rendering for longer
  /// operations.
  ///
  /// Default file format is [MotionFormat.mov]
  Future<RenderResult> captureMotionFromWidget(
    BuildContext context,
    Widget widget,
    Duration duration, {
    LogLevel? logLevel,
    MotionSettings settings = const MotionSettings(),
    MotionFormat format = const MovFormat(),
  }) =>
      captureFromWidget(
        context,
        widget,
        duration: duration,
        settings: settings,
        format: format,
        logLevel: logLevel,
      );

  /// Captures an image and returns a stream of information of current
  /// operations and errors.
  ///
  /// Capturing an image is expected not to take too long in normal operations
  /// to make a stream necessary. For easy handling, it is recommended to simple
  /// use [captureImage].
  ///
  /// Default file format is [ImageFormat.png]
  Stream<RenderNotifier> captureImageWithStream({
    LogLevel? logLevel,
    ImageSettings settings = const ImageSettings(),
    ImageFormat format = const PngFormat(),
    bool logInConsole = false,
  }) =>
      captureWithStream(
        settings: settings,
        format: format,
        logInConsole: logInConsole,
        logLevel: logLevel,
      );

  /// Captures motion of the [Render] widget and returns a stream of information
  /// of current operations and errors.
  ///
  /// It is highly recommended to use this method for capturing motion, as the
  /// process usually takes longer and the user will likely wants to get
  /// notified the process of rendering for longer operations.
  ///
  /// Default file format is [MotionFormat.mov]
  Stream<RenderNotifier> captureMotionWithStream(
    Duration duration, {
    LogLevel? logLevel,
    MotionSettings settings = const MotionSettings(),
    MotionFormat format = const MovFormat(),
    bool logInConsole = false,
  }) =>
      captureWithStream(
        duration: duration,
        settings: settings,
        format: format,
        logInConsole: logInConsole,
        logLevel: logLevel,
      );

  /// Captures an image from a provided widget that is not in a widget tree
  /// and returns a stream of information of current operations and errors.
  ///
  /// Note that this method replaced the need for the [Render] widget as a parent
  /// widget. Simply pass the widget that need to be rendered in the function.
  ///
  /// Capturing an image is expected not to take too long in normal operations
  /// to make a stream necessary. For easy handling, it is recommended to simple
  /// use [captureImageFromWidget].
  ///
  /// Default file format is [ImageFormat.png]
  Stream<RenderNotifier> captureImageFromWidgetWithStream(
    BuildContext context,
    Widget widget, {
    LogLevel? logLevel,
    ImageSettings settings = const ImageSettings(),
    ImageFormat format = const PngFormat(),
    bool logInConsole = false,
  }) =>
      captureFromWidgetWithStream(
        context,
        widget,
        settings: settings,
        format: format,
        logInConsole: logInConsole,
        logLevel: logLevel,
      );

  /// Captures motion of a widget that is out of the widget tree
  /// and returns a stream of information of current operations and errors.
  ///
  /// Note that this method replaced the need for the [Render] widget as a parent
  /// widget. Simply pass the widget that need to be rendered in the function.
  ///
  /// It is highly recommended to use this method for capturing motion, as the
  /// process usually takes longer and the user will likely wants to get
  /// notified the process of rendering for longer operations.
  ///
  /// For debugging it might be easier to use [captureMotion].
  ///
  /// Default file format is [MotionFormat.mov]
  Stream<RenderNotifier> captureMotionFromWidgetWithStream(
    BuildContext context,
    Widget widget,
    Duration duration, {
    LogLevel? logLevel,
    MotionSettings settings = const MotionSettings(),
    MotionFormat format = const MovFormat(),
    bool logInConsole = false,
  }) =>
      captureFromWidgetWithStream(
        context,
        widget,
        duration: duration,
        settings: settings,
        format: format,
        logInConsole: logInConsole,
        logLevel: logLevel,
      );

  /// Records motion of the [Render] widget and returns a recording controller to
  /// `stop()` the recording or listen to a stream of information's and errors.
  ///
  /// Default file format is [MotionFormat.mov]
  MotionRecorder recordMotion({
    LogLevel? logLevel,
    MotionSettings settings = const MotionSettings(),
    MotionFormat format = const MovFormat(),
    bool logInConsole = false,
  }) {
    assert(!kIsWeb, "Render does not support Web yet");
    assert(
        globalTask?.key.currentWidget != null,
        "RenderController must have a Render instance "
        "to start recording.");
    return MotionRecorder.start(
      format: format,
      capturingSettings: settings,
      task: globalTask!,
      logLevel: logLevel ?? this.logLevel,
      controller: this,
      logInConsole: logInConsole,
    );
  }

  /// Records motion of a widget and returns a recording controller to
  /// `stop()` the recording or listen to a stream of information's and errors.
  ///
  /// [context] is required to
  ///
  /// Default file format is [MotionFormat.mov]
  MotionRecorder recordMotionFromWidget(
    BuildContext context,
    Widget widget, {
    LogLevel? logLevel,
    MotionSettings settings = const MotionSettings(),
    MotionFormat format = const MovFormat(),
    bool logInConsole = false,
  }) {
    assert(!kIsWeb, "Render does not support Web yet");
    return MotionRecorder.start(
      context: context,
      format: format,
      capturingSettings: settings,
      task: WidgetIdentifier(controllerId: id, widget: widget),
      logLevel: logLevel ?? this.logLevel,
      controller: this,
      logInConsole: logInConsole,
    );
  }
}

class MotionRecorder extends RenderRecorder<File> {
  MotionRecorder.start({
    required RenderController controller,
    required super.logLevel,
    required MotionFormat format,
    required FFMpegSettings capturingSettings,
    required super.task,
    required super.logInConsole,
    BuildContext? context,
  }) : super.start(
          controller: controller,
          format: format,
          capturingSettings: capturingSettings,
        );
}
