## 0.1.0

Initial release.

- `RKitRepository<ResultType, RemoteType>` — abstract base class with a two-shot `watch()` stream engine.
- `RKitState<T>` — sealed state hierarchy with four subtypes: `RKitLoading`, `RKitCache`, `RKitSuccess`, `RKitFailure`.
- `RKitCachePolicy` — controls when the remote fetch is performed. Supports `always`, `ifEmpty`, and `never`.
- `RKitRetryPolicy` — controls retry behaviour on request failure. Supports `none` and `exponential` backoff.
- `RKitException` — exception type representing infrastructure failures, wrapping the underlying error and stacktrace.
