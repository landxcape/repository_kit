/// Controls how [RKitRepository.watch] handles remote request failures.
///
/// Pass an [RKitRetryPolicy] via [RKitRepository.retryPolicy] to configure retry
/// behaviour for a repository.
sealed class RKitRetryPolicy {
  const RKitRetryPolicy();

  /// No retries. Emit [RKitFailure] immediately on the first error.
  ///
  /// This is the default policy.
  static const RKitRetryPolicy none = _NoRetryPolicy();

  /// Retry the remote request with exponential backoff.
  ///
  /// Retries up to [maxAttempts] times, doubling the delay starting from
  /// [initialDelay] on each attempt.
  static RKitRetryPolicy exponential({
    int maxAttempts = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) =>
      _ExponentialRetryPolicy(
        maxAttempts: maxAttempts,
        initialDelay: initialDelay,
      );

  /// Executes [operation], retrying according to this policy on failure.
  ///
  /// Returns the result of the first successful attempt, or rethrows the
  /// last error if all attempts are exhausted.
  Future<T> execute<T>(Future<T> Function() operation);
}

final class _NoRetryPolicy extends RKitRetryPolicy {
  const _NoRetryPolicy();

  @override
  Future<T> execute<T>(Future<T> Function() operation) => operation();
}

final class _ExponentialRetryPolicy extends RKitRetryPolicy {
  const _ExponentialRetryPolicy({
    required this.maxAttempts,
    required this.initialDelay,
  });

  final int maxAttempts;
  final Duration initialDelay;

  @override
  Future<T> execute<T>(Future<T> Function() operation) async {
    var delay = initialDelay;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(delay);
          delay *= 2;
        }
      }
    }

    throw lastError!;
  }
}
