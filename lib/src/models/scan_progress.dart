/// Snapshot of scan progress, emitted via [ScanProgressCallback]
class ScanProgress {
  /// Total number of files discovered (known so far)
  /// Android: Full MediaStore count
  /// Desktop: Count from dir listing
  final int total;

  /// Number of files fully processed (metadata read + filters applied)
  final int completed;

  /// Path of file currently being processed => if available
  final String? currentPath;

  /// Which phase the scanner is in
  final ScanPhase phase;

  const ScanProgress({
    required this.total,
    required this.completed,
    this.currentPath,
    this.phase = ScanPhase.reading,
  });

  /// Progress as 0.0 - 1.0 fraction
  double get progress => total > 0 ? completed / total : 0.0;

  @override
  String toString() =>
      'ScanProgress($completed/$total), phase: ${phase.name}'
      '${currentPath != null ? ', current: $currentPath' : ''})';
}

/// Phases of scan operation
enum ScanPhase {
  /// Discovering files
  discovering,

  /// Reading metadata from discovered files
  reading,

  /// Scan completed
  done,
}

/// Callback that receives [ScanProgress] snapshots during scanning
typedef ScanProgressCallback = void Function(ScanProgress progress);
