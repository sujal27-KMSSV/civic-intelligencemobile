import 'dart:developer' as developer;

/// Lightweight performance instrumentation, disabled by default.
///
/// Enable at build time with `--dart-define=PERF_TIMING=true`. All calls to
/// [perfLog] become no-ops otherwise, so there is zero overhead in normal
/// builds and no dependency on debug logging.
const bool perfTimingEnabled = bool.fromEnvironment('PERF_TIMING');

/// Emits a `[perf:<tag>]` log line when [perfTimingEnabled] is set.
void perfLog(String tag, String message, [int? elapsedMs]) {
  if (!perfTimingEnabled) return;
  final suffix = elapsedMs == null ? '' : ' (${elapsedMs}ms)';
  developer.log('[perf:$tag] $message$suffix');
}