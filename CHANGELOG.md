## 0.1.1

- `RKitRepository` is now declared as `abstract mixin class`. It can be used with `extends` (unchanged from 0.1.0) or with `with` when the consuming class already has a base class. No breaking changes.

## 0.1.0

Initial release.

- `RKitRepository<ResultType, RemoteType>` — abstract base class with a two-shot `watch()` stream engine.
- `RKitState<T>` — sealed state hierarchy with four subtypes: `RKitLoading`, `RKitCache`, `RKitSuccess`, `RKitFailure`.
- `RKitCachePolicy` — controls when the remote fetch is performed. Supports `always`, `ifEmpty`, `never`, and `staleIf` (closure-based dynamic cache freshness check).
- `RKitRetryPolicy` — controls retry behaviour on request failure. Supports `none` and `exponential` backoff.
- `RKitException` — exception type representing infrastructure failures, wrapping the underlying error and stacktrace.
