/// A pure Dart toolkit for implementing clean, offline-first repositories.
///
/// Eliminates repetitive data-layer boilerplate by owning cache-vs-remote
/// strategy decisions inside the repository. The presentation layer simply
/// consumes a stream of [RKitState] events.
library;

export 'src/rkit_cache_policy.dart' show RKitCachePolicy;
export 'src/rkit_repository.dart' show RKitRepository;
export 'src/rkit_exception.dart' show RKitException;
export 'src/rkit_state.dart'
    show RKitState, RKitLoading, RKitCache, RKitSuccess, RKitFailure;
export 'src/rkit_retry_policy.dart' show RKitRetryPolicy;
