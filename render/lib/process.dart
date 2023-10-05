import 'dart:io';

import 'package:ffmpeg_kit_flutter_https_gpl/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_https_gpl/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_https_gpl/log.dart';
import 'package:ffmpeg_kit_flutter_https_gpl/statistics.dart';
import 'package:render/formats/abstract.dart';
import 'package:render/services/settings.dart';
import 'package:render_core/render_core.dart';

class FFMpegRenderProcessor {
  final RenderSession<File, RealRenderSettings<FFMpegSettings>> session;

  FFMpegRenderProcessor(this.session);

  /// Processes task frames and writes the output with the specific format
  /// Returns the process output file.
  Future<void> process(
      FFmpegRenderOperation operation, double progressShare) async {
    await _executeCommand(
      operation.arguments,
      progressShare: progressShare,
    );
  }

  /// Wrapper around the FFmpeg command execution. Takes care of notifying the
  /// session about the progress of execution.
  Future<void> _executeCommand(List<String> command,
      {required double progressShare}) async {
    final ffmpegSession = await FFmpegSession.create(
      command,
      (ffmpegSession) async {
        session.recordActivity(
          RenderState.processing,
          progressShare,
          message: "Completed ffmpeg operation",
          details: "[async notification] Ffmpeg session completed: "
              "${ffmpegSession.getSessionId()}, time needed: "
              "${await ffmpegSession.getDuration()}, execution: "
              "${ffmpegSession.getCommand()}, logs: "
              "${await ffmpegSession.getLogsAsString()}, return code: "
              "${await ffmpegSession.getReturnCode()}, stack trace: "
              "${await ffmpegSession.getFailStackTrace()}",
        );
      },
      (Log log) {
        final message = log.getMessage();
        if (message.toLowerCase().contains("error")) {
          session.recordError(RenderException(
            "[Ffmpeg execution error] $message",
            fatal: true,
          ));
        } else {
          session.recordLog(message);
        }
      },
      (Statistics statistics) {
        final progression = ((statistics.getTime() * 100) ~/
                    session.settings.capturingDuration.inMilliseconds)
                .clamp(0, 100) /
            100;
        session.recordActivity(
          RenderState.processing,
          progression.toDouble(),
          message: "Converting captures",
        );
      },
    );
    await FFmpegKitConfig.ffmpegExecute(ffmpegSession).timeout(
      session.settings.originSettings.processTimeout,
      onTimeout: () {
        session.recordError(
          const RenderException(
            "Processing session timeout",
            fatal: true,
          ),
        );
        ffmpegSession.cancel();
      },
    );
  }
}
