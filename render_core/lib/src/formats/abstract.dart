import 'dart:ui' as ui;

import 'package:render_core/src/formats/service.dart';
import 'package:render_core/src/service/session.dart';
import 'package:render_core/src/service/settings.dart';

abstract class RenderDelegate<R> {
  Future<void> handleCapture({
    required ui.Image capture,
    required int captureNumber,
  });

  Future<R> process(covariant RenderSession<R, RenderSettings> session);
}

abstract class RenderFormat<R> {
  /// How the format can be handled. This is important for handling the file later
  /// (eg. displaying the file). Some file types might be [FormatType.motion] but
  /// still should be handled like an image (eg. apng, gif, etc.).
  final FormatHandling handling;

  /// The percentage of the main process execution time of the whole render
  /// operation. This value is determined by experimentation.
  ///
  /// Example:
  /// If the [processShare] is 0.5, it means that the main processing time will
  /// take 50% of the render time to finish. Meaning that if the capturing time
  /// is 2min the expected processing time will also be 2min.
  ///
  /// Note that sub-render tasks are not considered in this
  /// value and will be calculated separately, but based on this value.
  final double processShare;

  /// Interpolation in is a method used to calculate new pixel values
  /// when resizing images. It is used to make sure that the resulting image
  /// looks as smooth and natural as possible. Different interpolation methods
  /// are available, each with its own trade-offs in terms of quality and
  /// computational expense.
  ///
  /// Interpolation will only be used if [scale] is specified.
  final Interpolation interpolation;

  /// Scaling frames in video processing refers to the process of resizing the
  /// frames of a video to a different resolution. This is done to adjust the
  /// size of the video to match the resolution of the target device or medium.
  final RenderScale? scale;

  /// A class that defines the format of the output file.
  const RenderFormat({
    required this.handling,
    required this.scale,
    required this.processShare,
    required this.interpolation,
  });

  ///
  RenderDelegate<R> createDelegate(
    String sessionId,
    covariant RenderSettings settings,
  );
}
