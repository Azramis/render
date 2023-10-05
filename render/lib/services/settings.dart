import 'package:render_core/render_core.dart';

abstract class FFMpegSettings extends RenderSettings {
  const FFMpegSettings({
    required super.framesCount,
    required super.frameRate,
    required super.maxDuration,
    super.pixelRatio = 1,
    super.maxSimultaneousCaptureHandlers = 1,
    this.processTimeout = const Duration(minutes: 3),
  });

  /// The time out for processing captures. Note that the process timeout is not
  /// related to the whole process, but rather to each FFmpeg execution.
  /// Meaning that if there are many sub calculations in the format
  /// the timeout will only trigger for each operation.
  final Duration processTimeout;
}

class ImageSettings extends FFMpegSettings {
  ///Settings for rendering an image.
  const ImageSettings({
    super.pixelRatio,
    super.processTimeout,
  }) : super(
          framesCount: 1,
          frameRate: 1,
          maxDuration: null,
        );
}

class MotionSettings extends FFMpegSettings {
  /// Data class for storing render related settings.
  /// Setting the optimal settings is critical for a successfully capturing.
  /// Depending on the device different frame rate and capturing quality might
  /// result in a laggy application and render results. To prevent this
  /// it is important find leveled values and optionally computational scaling
  /// of the output format.
  const MotionSettings({
    int simultaneousCaptureHandlers = 10,
    super.frameRate = 20,
    super.pixelRatio,
    super.processTimeout,
  }) : super(
          maxSimultaneousCaptureHandlers: simultaneousCaptureHandlers,
          framesCount: null,
          maxDuration: null,
        );
}
