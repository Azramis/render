abstract class RenderSettings {
  /// The pixelRatio describes the scale between the logical pixels and the size
  /// of images or video frames captured. Specifying 1.0 will give you a 1:1
  /// mapping between logical pixels and the output pixels in the image.
  ///
  /// See [RenderRepaintBoundary](https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary/toImage.html)
  /// for the underlying implementation.
  ///
  /// Please take into account, that certain platform players might not be able
  /// to visualize extremely high pixel resolution.
  final double pixelRatio;

  /// Limit the count of captured frames to this value.
  ///
  /// For a screenshot, value will be 1, while this value will be **null** for a movie (infinity)
  ///
  /// Should be strictly superior to 0
  final int? framesCount;

  /// Limits the capture duration.
  ///
  /// May conflict with the [framesCount], but the capture will as soon as any of these limits is reached
  ///
  /// Should be positive duration, or **null** if infinite
  final Duration? maxDuration;

  /// Frame count per second.
  ///
  /// This will determine how much time gap is between frame.
  /// If [framesCount] equals to 1, then frameRate has no incidence.
  ///
  /// Should be strictly superior to 0
  final double frameRate;

  /// The max amount of capture handlers that should process captures at once.
  ///
  /// Handlers process and write frames from the RAM to a local directory.
  /// Having multiple handlers at the same time heavily influences the
  /// performance of the application during rendering.
  ///
  /// The more handlers are running simultaneously the worse gets the framerate
  /// and might result in a "laggy" behavior. Less simultaneously handlers result
  /// in longer loading phases.
  ///
  /// Note, that if there a lot of unhandled frames it might still result in
  /// laggy behavior, as the application's RAM gets filled with UI images,
  /// instead of many handler operations.
  ///
  /// To get a good sweet spot you can follow the following introduction for
  /// your specific situation:
  ///
  /// Low pixelRatio - high frameRate - many handlers
  /// high pixelRatio - low frameRate - many handlers
  /// high pixelRatio - high frameRate - few handlers
  final int maxSimultaneousCaptureHandlers;

  /// A data class for storing render related settings.
  const RenderSettings({
    required this.framesCount,
    required this.frameRate,
    required this.maxDuration,
    this.pixelRatio = 1,
    this.maxSimultaneousCaptureHandlers = 1,
  }) : assert(frameRate < 100, "Frame rate unrealistic high.");

  const RenderSettings.screenshot({
    double pixelRatio = 1,
  }) : this(
          framesCount: 1,
          frameRate: 1,
          maxDuration: null,
          pixelRatio: pixelRatio,
        );

  const RenderSettings.movie({
    double pixelRatio = 1,
    double frameRate = 30,
    int maxSimultaneousCaptureHandlers = 10,
    Duration? maxDuration,
  }) : this(
          framesCount: null,
          frameRate: frameRate,
          pixelRatio: pixelRatio,
          maxSimultaneousCaptureHandlers: maxSimultaneousCaptureHandlers,
          maxDuration: maxDuration,
        );
}

class RealRenderSettings<T extends RenderSettings> implements RenderSettings {
  /// The duration of the capturing.
  final Duration capturingDuration;

  /// The amount of frames that are captured.
  final int frameAmount;

  // Original settings
  final T originSettings;

  /// The settings after capturing. This class hold the actual frame rate and and
  /// duration and might vary slightly from targeted settings.
  const RealRenderSettings({
    required this.originSettings,
    required this.capturingDuration,
    required this.frameAmount,
  });

  /// In frames per second
  double get realFrameRate =>
      frameAmount / (capturingDuration.inMilliseconds / 1000);

  @override
  double get frameRate => originSettings.frameRate;

  @override
  int? get framesCount => originSettings.framesCount;

  @override
  Duration? get maxDuration => originSettings.maxDuration;

  @override
  int get maxSimultaneousCaptureHandlers =>
      originSettings.maxSimultaneousCaptureHandlers;

  @override
  double get pixelRatio => originSettings.pixelRatio;
}
