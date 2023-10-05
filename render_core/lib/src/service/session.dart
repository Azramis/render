import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:render_core/src/service/settings.dart';
import 'package:render_core/src/service/task_identifier.dart';
import 'package:uuid/uuid.dart';

import '../formats/abstract.dart';
import 'exception.dart';
import 'notifier.dart';

/// A detached render session is a render session that is not attached to a view
class DetachedRenderSession<R, K extends RenderSettings> {
  /// Pointer to session files and operation.
  final String sessionId;

  /// All render related settings
  final K settings;

  final RenderFormat<R> format;

  /// What notifications should be displayed
  final LogLevel logLevel;

  /// Binding to the Context of the [Render] widget.
  final SchedulerBinding binding;

  final RenderDelegate<R> delegate;

  /// A class that holds information about the current detached session. Ranging
  /// from directories to session identification.
  DetachedRenderSession({
    required LogLevel logLevel,
    required SchedulerBinding binding,
    required String sessionId,
    required K settings,
    required RenderFormat<R> format,
  }) : this._(
          logLevel: logLevel,
          binding: binding,
          sessionId: sessionId,
          settings: settings,
          format: format,
          delegate: format.createDelegate(sessionId, settings),
        );

  DetachedRenderSession._({
    required this.logLevel,
    required this.binding,
    required this.sessionId,
    required this.settings,
    required this.format,
    required this.delegate,
  });

  /// Creates a detached render session from default values (paths & session syntax)
  /// Attach a session by initializing RenderPaint and Context values by
  /// extending with [RenderSession]
  static Future<DetachedRenderSession<R, K>>
      create<R, K extends RenderSettings>(
          RenderFormat<R> format, K settings, LogLevel logLevel) async {
    final sessionId = const Uuid().v4();
    return DetachedRenderSession<R, K>(
      logLevel: logLevel,
      binding: SchedulerBinding.instance,
      sessionId: sessionId,
      settings: settings,
      format: format,
    );
  }

  /// The expected processing state share each part holds. This is relevant for
  /// calculating the expected time remain and progress percentage of rendering.
  /// Values are based on experimentation.
  double processingShare(RenderState state) {
    switch (state) {
      case RenderState.capturing:
        return 0.7 * (1 - format.processShare);
      case RenderState.handleCaptures:
        return 0.3 * (1 - format.processShare);
      case RenderState.processing:
        return format.processShare;
      case RenderState.finishing:
        return 0;
    }
  }
}

class RenderSession<R, K extends RenderSettings>
    extends DetachedRenderSession<R, K> {
  /// Used to identify the tasks that should be rendered. This must include
  /// a main rendering task.
  final TaskIdentifier task;

  /// Session notifier to all activity in this session.
  final StreamController<RenderNotifier> _notifier;

  /// Start time of session. Is the reference for timestamps and
  /// remaining time calculation.
  final DateTime startTime;

  final VoidCallback onDispose;

  /// A class that holds all the information about the current session.
  /// used to pass information between the different parts of the rendering
  /// process.
  RenderSession({
    required super.logLevel,
    required super.settings,
    required super.sessionId,
    required super.format,
    required super.binding,
    required this.task,
    required this.onDispose,
    required StreamController<RenderNotifier> notifier,
    DateTime? startTime,
  })  : _notifier = notifier,
        startTime = startTime ?? DateTime.now();

  RenderState? _currentState;

  /// A constructor that takes a `DetachedRenderSession` and creates a
  /// `RenderSession` from it.
  RenderSession.fromDetached({
    required DetachedRenderSession<R, K> detachedSession,
    required StreamController<RenderNotifier> notifier,
    required this.task,
    required this.onDispose,
    DateTime? startTime,
  })  : _notifier = notifier,
        startTime = DateTime.now(),
        super._(
          logLevel: detachedSession.logLevel,
          binding: detachedSession.binding,
          format: detachedSession.format,
          settings: detachedSession.settings,
          sessionId: detachedSession.sessionId,
          delegate: detachedSession.delegate,
        );

  /// Upgrade the current renderSession to a real session
  RenderSession<R, RealRenderSettings<K>> upgrade(
      Duration capturingDuration, int frameAmount) {
    return RenderSession<R, RealRenderSettings<K>>(
      settings: RealRenderSettings(
        originSettings: settings,
        capturingDuration: capturingDuration,
        frameAmount: frameAmount,
      ),
      onDispose: onDispose,
      startTime: startTime,
      logLevel: logLevel,
      sessionId: sessionId,
      format: format,
      binding: binding,
      task: task,
      notifier: _notifier,
    );
  }

  /// Returns the duration from the start of the session until now.
  Duration get currentTimeStamp {
    return Duration(
      milliseconds: DateTime.now().millisecondsSinceEpoch -
          startTime.millisecondsSinceEpoch,
    );
  }

  /// A method that is used to record activity in the session.
  void recordActivity(RenderState state, double? stateProgression,
      {String? message, String? details}) {
    if (logLevel == LogLevel.none || _notifier.isClosed) return;
    if (_currentState != state) _currentState = state;
    _notifier.add(
      RenderActivity(
        session: this,
        timestamp: currentTimeStamp,
        state: state,
        currentStateProgression: stateProgression ?? 0.5,
        message: message,
        details: details,
      ),
    );
  }

  /// Used to record log messages in the session.
  void recordLog(String message) {
    if (logLevel != LogLevel.debug || _notifier.isClosed) return;
    _notifier.add(
      RenderLog(
        timestamp: currentTimeStamp,
        message: message,
      ),
    );
  }

  /// A method that is used to record errors in the session.
  void recordError(RenderException exception) {
    if (_notifier.isClosed) return;
    _notifier.add(
      RenderError(
        timestamp: currentTimeStamp,
        fatal: exception.fatal,
        exception: exception,
      ),
    );
    if (exception.fatal) {
      dispose();
    }
  }

  /// Recording the result of the render session.
  void recordResult(R output, {String? message, String? details}) {
    if (_notifier.isClosed) return;
    _notifier.add(
      RenderResult(
        session: this,
        format: format,
        timestamp: currentTimeStamp,
        usedSettings: settings as RealRenderSettings,
        output: output,
        message: message,
        details: details,
      ),
    );
    dispose();
  }

  bool _processing = false;

  Future<void> processResult() async {
    if (_processing) {
      throw const RenderException(
          "Cannot start new process, during an active one.");
    }
    _processing = true;
    try {
      final output = await delegate.process(this);
      recordResult(output);
      _processing = false;
    } on RenderException catch (error) {
      recordError(error);
    }
  }

  /// Disposing the current render session.
  Future<void> dispose() async {
    onDispose();
    await _notifier.close();
  }
}
