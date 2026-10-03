## 0.1.4

- Added `.pubignore` to prevent bundling build artifacts and temporary files.
- Upgraded `lints` dev dependency to `^6.0.0`.

## 0.1.3

- **State Semantics Refinement:**
  - `RKitSuccess` is now strictly emitted only when a remote fetch succeeds and its response is successfully persisted.
  - `RKitCache` is now emitted whenever cached data is available, acting as the terminal state for sequential strategies (`ifEmpty`, `never`, `staleIf`) when the cache policy decides to skip the remote fetch.
- **Docs:** Added mixin usage documentation and corrected emission tables in the README.

## 0.1.2

- `RKitCachePolicy.always` now runs `load()` and `fetch()` in parallel. The first to complete determines the emission sequence: if `fetch()` wins, `RKitSuccess` is emitted directly and `RKitCache` is never shown; if `load()` wins, `RKitCache` is emitted first, followed by `RKitSuccess` when `fetch()` completes. Total time to `RKitSuccess` is now `max(load, fetch)` instead of `load + fetch`. All other policies are sequential and unchanged.

## 0.1.1

- `RKitRepository` is now declared as `abstract mixin class`. It can be used with `extends` (unchanged from 0.1.0) or with `with` when the consuming class already has a base class. No breaking changes.

## 0.1.0

Initial release.

- `RKitRepository<ResultType, RemoteType>` — abstract base class with a two-shot `watch()` stream engine.
- `RKitState<T>` — sealed state hierarchy with four subtypes: `RKitLoading`, `RKitCache`, `RKitSuccess`, `RKitFailure`.
- `RKitCachePolicy` — controls when the remote fetch is performed. Supports `always`, `ifEmpty`, `never`, and `staleIf` (closure-based dynamic cache freshness check).
- `RKitRetryPolicy` — controls retry behaviour on request failure. Supports `none` and `exponential` backoff.
- `RKitException` — exception type representing infrastructure failures, wrapping the underlying error and stacktrace.
