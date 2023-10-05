import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_https_gpl/ffmpeg_kit.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:render/formats/image.dart';
import 'package:render/formats/motion.dart';
import 'package:render/formats/service.dart';
import 'package:render/process.dart';
import 'package:render/services/settings.dart';
import 'package:render_core/render_core.dart';

/// Arguments associated for ffmpeg execution. Note, that calling "ffmpeg"
/// is not needed.
class FFmpegRenderOperation {
  final List<String> arguments;

  /// Takes ffmpeg arguments and null. Nulls will simply be converted to string.
  /// Will split arguments into two, if a `??` is found
  FFmpegRenderOperation(List<String?> arguments)
      : arguments = arguments
            .whereType<String>()
            .expand((element) => element.split("??"))
            .toList();
}

class FFMpegRenderDelegate extends RenderDelegate<File> {
  FFMpegRenderDelegate(
    this.sessionId, {
    required this.ffmpegOperationBuilder,
    required this.inputPathBuilder,
    required this.extension,
    required this.progressShare,
  }) {
    _initialization.complete(Future.sync(() async {
      final tmpDir = await getTemporaryDirectory();
      temporaryDirectory = tmpDir.path;
    }));
  }

  final Completer<void> _initialization = Completer<void>();

  final String sessionId;

  final FFmpegRenderOperation Function({
    required String inputPath,
    required String outputPath,
    required double frameRate,
  }) ffmpegOperationBuilder;

  final String Function(String inputDirectory) inputPathBuilder;

  final String extension;

  final double progressShare;

  /// Directory of a temporary storage, where files can be used for processing.
  /// This should be somewhere in a RAM location for fast processing.
  late final String temporaryDirectory;

  /// Where internal files are being written (frames, layers, palettes, etc.)
  /// Note that there will be additional sub-directories that separate different
  /// internal actions and sessions. Directories will be deleted after a session.
  String get inputDirectory => "$temporaryDirectory/render/$sessionId/input";

  /// Where result files are being written
  String get outputDirectory => "$temporaryDirectory/render/$sessionId/output";

  /// A directory where files are being written that are used for processing.
  String get processDirectory =>
      "$temporaryDirectory/render/$sessionId/process";

  ///Creates a new file path if not present and returns the file as directory
  File _createFile(String path) {
    final outputFile = File(path);
    if (!outputFile.existsSync()) outputFile.createSync(recursive: true);
    return outputFile;
  }

  /// Creating a file in the input directory.
  File createInputFile(String subPath) =>
      _createFile("$inputDirectory/$subPath");

  /// Creating a file in the output directory.
  File createOutputFile(String subPath) =>
      _createFile("$outputDirectory/$subPath");

  /// Creating a file in the process directory.
  File createProcessFile(String subPath) =>
      _createFile("$processDirectory/$subPath");

  @override
  Future<void> handleCapture({
    required ui.Image capture,
    required int captureNumber,
  }) async {
    // * retrieve bytes
    // toByteData(format: ui.ImageByteFormat.png) takes way longer than raw
    // and then converting to png with ffmpeg
    final ByteData? byteData =
        await capture.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rawIntList = byteData!.buffer.asInt8List();
    // * write raw file for processing
    final rawFile =
        createProcessFile("frameHandling/frame_raw$captureNumber.bmp");
    await rawFile.writeAsBytes(rawIntList);
    // * write & convert file (to save storage)
    final file = createInputFile("frame$captureNumber.png");
    final saveSize = Size(
      // adjust frame size, so that it can be divided by 2
      (capture.width / 2).ceil() * 2,
      (capture.height / 2).ceil() * 2,
    );
    await FFmpegKit.executeWithArguments([
      "-y",
      "-f", "rawvideo", // specify input format
      "-pixel_format", "rgba", // maintain transparency
      "-video_size", "${capture.width}x${capture.height}", // set capture size
      "-i", rawFile.path, // input the raw frame
      "-vf", "scale=${saveSize.width}:${saveSize.height}", // scale to save
      file.path, //out put png
    ]);

    rawFile.deleteSync();
  }

  @override
  Future<File> process(
      covariant RenderSession<File, RealRenderSettings<FFMpegSettings>>
          session) async {
    await _initialization.future;

    final processor = FFMpegRenderProcessor(session);
    final inputPath = inputPathBuilder(inputDirectory);
    final output = createOutputFile("output_main.$extension");
    final operation = ffmpegOperationBuilder(
      inputPath: inputPath,
      outputPath: output.path,
      frameRate: session.settings.realFrameRate,
    );

    await processor.process(
      operation,
      progressShare,
    );

    return output;
  }
}

abstract class FFMpegRenderFormat extends RenderFormat<File> {
  const FFMpegRenderFormat({
    required super.handling,
    required super.scale,
    required super.processShare,
    required super.interpolation,
  });

  /// The ffmpeg processing function for this format. The task is to convert
  /// png frame(s) to the exportable format.
  ///
  /// #### Parameters
  /// The function provides you with [inputPath] of the frames, which will have
  /// `/frame%d.png` structure or `/frame.png` depending on the format type.
  /// The [outputPath] is the path of the file that should be written to.
  /// Note that the output file will have the format type of [extension].
  ///
  /// The [frameRate] refers to the frame rate based on the amount of inputPath
  /// and duration of capturing.
  ///
  /// The [inputPath] directory is associated to the current session, and will
  /// be cleared after completion.
  ///
  /// #### Return
  /// The return of this function has to be a list of [FFmpegRenderOperation]s.
  /// In case that there are sub tasks you can pass multiple operations here.
  /// The asynchronous execution of those arguments will be in a synchronous
  /// sequence.
  ///
  /// Waiting time of processor will be treated as preparation time for
  /// processing (should not contain the main process)
  FFmpegRenderOperation processor({
    required String inputPath,
    required String outputPath,
    required double frameRate,
  });

  /// Scaling ffmpeg filter with appropriate interpolation integration
  /// While maintaing aspect ratio
  String? get scalingFilter =>
      scale != null ? "scale=w=${scale!.w}:-1:${interpolation.name}" : null;

  String _inputPathBuilder(String inputDirectoryPath);

  String get extension;

  @override
  RenderDelegate<File> createDelegate(
    String sessionId,
    covariant FFMpegSettings settings,
  ) =>
      FFMpegRenderDelegate(
        sessionId,
        ffmpegOperationBuilder: processor,
        inputPathBuilder: _inputPathBuilder,
        extension: extension,
        progressShare: processShare,
      );
}

abstract class MotionFormat extends FFMpegRenderFormat {
  /// Additional audio for the motion format (if supported by output format)
  /// Make sure that the audio file has the same length as the output video.
  ///
  /// If you provide multiple audios, it will takes the longest and will freeze
  /// video at the last frame, if the audio is exceeds the video duration.
  final List<RenderAudio>? audio;

  /// Formats that include some sort of motion and have multiple frames.
  const MotionFormat({
    required this.audio,
    required super.handling,
    required super.scale,
    required super.interpolation,
    required super.processShare,
  });

  /// A function that allows you to copy the format with new parameters.
  /// This is useful for creating a new format with the same base but different
  /// parameters. Alternatively you can call the Format directly (eg. [MovFormat]).
  MotionFormat copyWith({
    RenderScale? scale,
    Interpolation? interpolation,
  });

  @override
  String _inputPathBuilder(String inputDirectoryPath) =>
      '$inputDirectoryPath/frame%d.png';

  /// Default motion processor. This can be override, if more/other settings are
  /// needed.
  @override
  FFmpegRenderOperation processor(
      {required String inputPath,
      required String outputPath,
      required double frameRate}) {
    final audioInput = audio != null && audio!.isNotEmpty
        ? audio!.map((e) => "-i??${e.path}").join('??')
        : null;
    final mergeAudiosList = audio != null && audio!.isNotEmpty
        ? ";${List.generate(audio!.length, (index) => "[${index + 1}:a]" // list audio
                "atrim=start=${audio![index].startTime}" // start time of audio
                ":${"end=${audio![index].endTime}"}[a${index + 1}];").join()}" // end time of audio
            "${List.generate(audio!.length, (index) => "[a${index + 1}]").join()}" // list audio
            "amix=inputs=${audio!.length}[a]" // merge audios
        : "";
    final overwriteAudioExecution =
        audio != null && audio!.isNotEmpty // merge audios with existing (none)
            ? "-map??[v]??-map??[a]??-c:v??libx264??-c:a??"
                "aac??-shortest??-pix_fmt??yuv420p??-vsync??2"
            : "-map??[v]??-pix_fmt??yuv420p";
    return FFmpegRenderOperation([
      "-i", inputPath, // retrieve  captures
      audioInput,
      "-filter_complex",
      "[0:v]${scalingFilter != null ? "$scalingFilter," : ""}"
          "setpts=N/($frameRate*TB)[v]$mergeAudiosList",
      overwriteAudioExecution,
      "-y",
      outputPath, // write output file
    ]);
  }

  static MovFormat get mov => const MovFormat();

  static Mp4Format get mp4 => const Mp4Format();

  static GifFormat get gif => const GifFormat();
}

abstract class ImageFormat extends FFMpegRenderFormat {
  /// Formats that are static images with one single frame.
  const ImageFormat({
    required super.scale,
    required super.handling,
    required super.interpolation,
    required super.processShare,
  });

  /// A function that allows you to copy the format with new parameters.
  /// This is useful for creating a new format with the same base but different
  /// parameters. Alternatively you can call the Format directly (eg. [PngFormat]).
  ImageFormat copyWith({
    RenderScale? scale,
    Interpolation? interpolation,
  });

  @override
  String _inputPathBuilder(String inputDirectoryPath) =>
      '$inputDirectoryPath/frame0.png';

  /// Default image processor. This can be override, if more settings are
  /// needed.
  @override
  FFmpegRenderOperation processor(
      {required String inputPath,
      required String outputPath,
      required double frameRate}) {
    return FFmpegRenderOperation([
      "-y",
      "-i", inputPath, // input image
      scalingFilter != null ? "-vf??$scalingFilter" : null,
      "-vframes", "1", // indicate that there is only one frame
      outputPath,
    ]);
  }

  static ImageFormat get png => const PngFormat();

  static ImageFormat get jpg => const JpgFormat();

  static ImageFormat get bmp => const BmpFormat();

  static ImageFormat get tiff => const TiffFormat();
}
