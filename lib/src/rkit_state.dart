/// Represents the state of a repository operation.
///
/// An [RKitState] is emitted by [RKitRepository.watch] as the repository
/// moves through its lifecycle: loading, serving cached data, delivering
/// fresh data, or reporting a failure.
sealed class RKitState<T> {
  const RKitState();
}

/// The repository has started loading. No data is available yet.
///
/// Always the first emission from [RKitRepository.watch].
final class RKitLoading<T> extends RKitState<T> {
  const RKitLoading();
}

/// Stale data from local storage is available while fresh data is being fetched.
///
/// Emitted after [RKitLoading] when [RKitRepository.load] returns a non-null
/// result. The network request is still in progress.
final class RKitCache<T> extends RKitState<T> {
  const RKitCache(this.data);

  /// The locally cached data.
  final T data;
}

/// Fresh data was successfully fetched from the remote source and persisted.
///
/// The terminal success state. The stream closes after this emission.
final class RKitSuccess<T> extends RKitState<T> {
  const RKitSuccess(this.data);

  /// The fresh, up-to-date data.
  final T data;
}

/// The operation failed. Stale data is preserved when a local cache existed.
///
/// The terminal failure state. The stream closes after this emission.
final class RKitFailure<T> extends RKitState<T> {
  const RKitFailure(this.error, {this.data});

  /// The error that caused the failure.
  final Object error;

  /// The last known cached data, if available before the failure occurred.
  final T? data;
}
