import 'package:repository_kit/src/rkit_cache_policy.dart';
import 'package:repository_kit/src/rkit_exception.dart';
import 'package:repository_kit/src/rkit_state.dart';
import 'package:repository_kit/src/rkit_retry_policy.dart';

/// Abstract base class for implementing offline-first repositories.
///
/// Extend [RKitRepository] and implement [load], [fetch], and [persist] to
/// describe *what* should happen. The [watch] engine handles *how* it happens.
///
/// ## Type Parameters
///
/// - [ResultType] — the domain model type exposed to callers.
/// - [RemoteType] — the raw type returned by the remote source (e.g. a JSON map
///   or a DTO). This type is only visible inside [persist]; it never leaves
///   the repository.
///
/// ## Example
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
///   RKitCachePolicy get cachePolicy =>
///       RKitCachePolicy.ifEmpty;
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
abstract class RKitRepository<ResultType, RemoteType> {
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
  /// 2. [RKitCache] — emitted if [load] returns a non-null value.
  /// 3. [RKitSuccess] or [RKitFailure] — the terminal state.
  ///
  /// The stream closes after the terminal emission.
  Stream<RKitState<ResultType>> watch() async* {
    yield const RKitLoading();

    ResultType? cached;
    try {
      cached = await load();
    } catch (_) {
      // Treat a load failure as a cache miss. Remote fetch will proceed.
    }

    if (cached != null) {
      yield RKitCache(cached);
    }

    if (!cachePolicy.shouldFetch(cached)) {
      if (cached != null) {
        yield RKitSuccess(cached);
      } else {
        yield RKitFailure(
          const RKitException(
            'RKitCachePolicy.never is active but no local data is available.',
          ),
        );
      }
      return;
    }

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

    return;
  }
}
