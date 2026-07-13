import 'package:repository_kit/src/rkit_cache_policy.dart';
import 'package:repository_kit/src/rkit_exception.dart';
import 'package:repository_kit/src/rkit_state.dart';
import 'package:repository_kit/src/rkit_retry_policy.dart';

/// Mixin class for implementing offline-first repositories.
///
/// Use [RKitRepository] by extending it directly or mixing it into an existing
/// base class. Implement [load], [fetch], and [persist] to describe *what*
/// should happen. The [watch] engine handles *how* it happens.
///
/// ## Type Parameters
///
/// - [ResultType] — the domain model type exposed to callers.
/// - [RemoteType] — the raw type returned by the remote source (e.g. a JSON map
///   or a DTO). This type is only visible inside [persist]; it never leaves
///   the repository.
///
/// ## Example (extends)
///
/// ```dart
/// class UserRepository extends RKitRepository<User, UserDto> {
///   UserRepository(this._api, this._db);
///
///   final UserApi _api;
///   final UserDao _db;
///   final String userId;
///
///   @override
///   Future<User?> load() => _db.findUser(userId);
///
///   @override
///   Future<UserDto> fetch() => _api.getUser(userId);
///
///   @override
///   Future<User> persist(UserDto response) async {
///     final user = User.fromDto(response);
///     await _db.saveUser(user);
///     return user;
///   }
///
///   @override
///   RKitCachePolicy get cachePolicy => RKitCachePolicy.ifEmpty;
/// }
/// ```
///
/// ## Example (mixin — when you already have a base class)
///
/// ```dart
/// class UserRepository extends BaseRepository
///     with RKitRepository<User, UserDto> {
///   // same implementation as above
/// }
/// ```
///
/// ## Consumption
///
/// ```dart
/// userRepository.watch().listen((state) {
///   switch (state) {
///     case RKitLoading():  // show spinner
///     case RKitCache(:final data):  // show stale data
///     case RKitSuccess(:final data):  // show fresh data
///     case RKitFailure(:final error, :final data):  // show error
///   }
/// });
/// ```
abstract mixin class RKitRepository<ResultType, RemoteType> {
  /// Loads the most recent data from local storage.
  ///
  /// Return `null` if no local data is available.
  /// If this method throws, the error is silently swallowed and treated as
  /// a cache miss — the remote fetch proceeds normally.
  Future<ResultType?> load();

  /// Performs the remote data request.
  ///
  /// Throw any exception to trigger [RKitFailure]. The [retryPolicy]
  /// controls how many times this is attempted before failing.
  Future<RemoteType> fetch();

  /// Persists the remote [response] to local storage and returns the
  /// domain representation.
  ///
  /// Both saving and returning are required. The returned [ResultType] is what
  /// the stream emits as [RKitSuccess.data].
  ///
  /// If this method throws, [RKitFailure] is emitted with the stale
  /// cached data if available.
  Future<ResultType> persist(RemoteType response);

  /// Controls when a remote fetch is performed.
  ///
  /// Defaults to [RKitCachePolicy.always].
  RKitCachePolicy get cachePolicy => RKitCachePolicy.always;

  /// Controls retry behaviour when [fetch] fails.
  ///
  /// Defaults to [RKitRetryPolicy.none].
  RKitRetryPolicy get retryPolicy => RKitRetryPolicy.none;

  /// Returns a stream of [RKitState] events representing the full
  /// data-fetch lifecycle.
  ///
  /// ## Emission order
  ///
  /// 1. [RKitLoading] — emitted immediately, before any async work.
  /// 2. [RKitCache] — emitted if [load] returns a non-null value. This state can
  ///    be intermediate (before [RKitSuccess] / [RKitFailure]) or terminal (if the
  ///    cache policy determines that no remote fetch is required).
  /// 3. [RKitSuccess] or [RKitFailure] — the terminal state if a remote fetch
  ///    was performed. [RKitSuccess] is strictly emitted only when the remote
  ///    fetch completes successfully and its response is persisted.
  ///
  /// ## Parallel execution ([RKitCachePolicy.always])
  ///
  /// [load] and [fetch] are started simultaneously. Whichever completes first
  /// determines the emission sequence:
  ///
  /// - **[fetch] wins** — [persist] is called, [RKitSuccess] is emitted.
  ///   The [load] result is discarded; [RKitCache] is never emitted.
  /// - **[load] wins** — [RKitCache] is emitted with the cached data.
  ///   When [fetch] subsequently completes, [persist] is called and
  ///   [RKitSuccess] is emitted.
  ///
  /// All other policies ([RKitCachePolicy.ifEmpty], [RKitCachePolicy.never],
  /// [RKitCachePolicy.staleIf]) execute [load] first, then conditionally
  /// execute [fetch] based on the cached result. If no fetch is executed,
  /// the stream terminates at [RKitCache] (or [RKitFailure] if the cache is null).
  ///
  /// The stream closes after the terminal emission.
  Stream<RKitState<ResultType>> watch() {
    if (cachePolicy == RKitCachePolicy.always) {
      return _watchParallel();
    }
    return _watchSequential();
  }

  Stream<RKitState<ResultType>> _watchParallel() async* {
    yield const RKitLoading();

    // Start both concurrently. The first to complete controls the emission path.
    final localFuture = Future<ResultType?>(() async {
      try {
        return await load();
      } catch (_) {
        return null;
      }
    });

    final remoteFuture = Future<RemoteType>(() => retryPolicy.execute(fetch));

    // Race local vs remote.
    bool remoteWon = false;
    RemoteType? remoteResponse;
    Object? remoteError;
    StackTrace? remoteStackTrace;

    final remoteTracked = remoteFuture.then(
      (r) {
        remoteWon = true;
        remoteResponse = r;
      },
      onError: (Object e, StackTrace st) {
        remoteWon = true; // finished, but with error
        remoteError = e;
        remoteStackTrace = st;
      },
    );

    final cached = await localFuture;

    if (!remoteWon) {
      // Cache won the race — show stale data while remote is in flight.
      if (cached != null) yield RKitCache(cached);
      await remoteTracked;
    }

    // Remote has now completed (either it won the race or we just awaited it).
    if (remoteError != null) {
      yield RKitFailure(
        remoteError is RKitException
            ? remoteError! as RKitException
            : RKitException(
                'Repository operation failed.',
                error: remoteError,
                stackTrace: remoteStackTrace,
              ),
        data: cached,
      );
      return;
    }

    try {
      final result = await persist(remoteResponse as RemoteType);
      yield RKitSuccess(result);
    } catch (error, stackTrace) {
      yield RKitFailure(
        error is RKitException
            ? error
            : RKitException(
                'Repository operation failed.',
                error: error,
                stackTrace: stackTrace,
              ),
        data: cached,
      );
    }
  }

  Stream<RKitState<ResultType>> _watchSequential() async* {
    yield const RKitLoading();

    ResultType? cached;
    try {
      cached = await load();
    } catch (_) {
      // Treat a load failure as a cache miss. Remote fetch will proceed.
    }

    // Always deliver cached data if present. The data layer's contract is to
    // emit data as it becomes available — what the presentation layer does with
    // it is not this layer's concern.
    if (cached != null) yield RKitCache(cached);

    if (!cachePolicy.shouldFetch(cached)) {
      // Policy decided no fetch is needed. If cache was available it was
      // already emitted above and the stream ends there.
      // The only failure case is never policy with no local data at all.
      if (cached == null) {
        yield RKitFailure(
          const RKitException(
            'RKitCachePolicy.never is active but no local data is available.',
          ),
        );
      }
      return;
    }

    // Fetch is proceeding. RKitSuccess is strictly emitted when the API
    // returns and data has been persisted.
    try {
      final response = await retryPolicy.execute(fetch);
      final result = await persist(response);
      yield RKitSuccess(result);
    } catch (error, stackTrace) {
      yield RKitFailure(
        error is RKitException
            ? error
            : RKitException(
                'Repository operation failed.',
                error: error,
                stackTrace: stackTrace,
              ),
        data: cached,
      );
    }
  }
}
