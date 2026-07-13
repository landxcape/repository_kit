/// Controls when [RKitRepository.watch] performs a remote fetch.
///
/// Pass an [RKitCachePolicy] via [RKitRepository.cachePolicy] to configure the
/// fetch behaviour for a repository.
sealed class RKitCachePolicy {
  const RKitCachePolicy();

  /// Always fetch from the remote source, regardless of cache state.
  ///
  /// This is the default policy.
  static const RKitCachePolicy always = _AlwaysPolicy();

  /// Only fetch from the remote source if no local data exists.
  ///
  /// If [RKitRepository.load] returns a non-null value, the stream emits
  /// [RKitSuccess] with the cached data and closes without a
  /// network request.
  static const RKitCachePolicy ifEmpty = _IfEmptyPolicy();

  /// Never fetch from the remote source. Serve local data only.
  ///
  /// If [RKitRepository.load] returns null, the stream emits
  /// [RKitFailure] with an [RKitException] and closes.
  static const RKitCachePolicy never = _NeverPolicy();

  /// Whether a remote fetch should be performed given the current [cached] data.
  bool shouldFetch<T>(T? cached);
}

final class _AlwaysPolicy extends RKitCachePolicy {
  const _AlwaysPolicy();

  @override
  bool shouldFetch<T>(T? cached) => true;
}

final class _IfEmptyPolicy extends RKitCachePolicy {
  const _IfEmptyPolicy();

  @override
  bool shouldFetch<T>(T? cached) => cached == null;
}

final class _NeverPolicy extends RKitCachePolicy {
  const _NeverPolicy();

  @override
  bool shouldFetch<T>(T? cached) => false;
}
