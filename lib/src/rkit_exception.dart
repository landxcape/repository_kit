/// Base class for exceptions thrown by the [RKitRepository] framework itself.
///
/// Errors thrown by user-implemented methods ([RKitRepository.load],
/// [RKitRepository.request], [RKitRepository.persist]) are surfaced directly
/// via [RKitFailure.error] and are not wrapped in this type.
///
/// [RKitException] is reserved for infrastructure-level failures
/// within the [RKitRepository.watch] engine, such as when [RKitCachePolicy.never]
/// is active and no local data is available.
final class RKitException implements Exception {
  const RKitException(
    this.message, {
    this.error,
    this.stackTrace,
  });

  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  @override
  String toString() {
    final buffer = StringBuffer('RKitException: $message');
    if (error != null) {
      buffer.write('\nCaused by: $error');
    }
    if (stackTrace != null) {
      buffer.write('\n$stackTrace');
    }
    return buffer.toString();
  }
}
