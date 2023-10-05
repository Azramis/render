import 'dart:io';

class RenderAudio {
  /// The path to the audio source (must be compatible with ffmpeg source path)
  final String path;

  /// The start time in seconds
  final double startTime;

  /// The end time in seconds
  /// If the time exceeds the duration, it will crop at the end.
  final double endTime;

  /// Audio from a url source. This can also be a video format, where only the
  /// sound is being taken
  RenderAudio.url(Uri url, {this.startTime = 0, this.endTime = 1000})
      : path = url.toString();

  /// Audio from a File source. This can also be a video format, where only the
  /// sound is being taken
  RenderAudio.file(File file, {this.startTime = 0, this.endTime = 1000})
      : path = file.path;

  /// Duration of expected RenderAudio. Duration may not relate to the actual
  /// audio duration, as [endTime] can be specified arbitrarily
  Duration? get duration =>
      Duration(milliseconds: (endTime / 1000 - startTime / 1000).toInt());
}
