# repository_kit

A Dart utility for implementing offline-first repositories without repeating the same data-layer boilerplate across every feature.

---

## The Problem

In most Flutter applications, every repository method that needs to serve cached data while fetching fresh data ends up looking like this:

```dart
Future<User?> getUser(String id) async {
  // Check cache
  final cached = await _db.findUser(id);
  if (cached != null) return cached;

  // Fetch from network
  try {
    final response = await _api.getUser(id);
    final user = User.fromJson(response);
    await _db.saveUser(user);
    return user;
  } catch (e) {
    return cached; // stale fallback
  }
}
```

This works, but it forces the presentation layer to make decisions it should not need to make: when to show cached data, when to show a loading indicator, and when to show an error alongside stale data. The same orchestration is duplicated across every repository method.

The deeper issue is that this pattern uses a `Future`, which can only return one value. An offline-first data layer naturally produces multiple values over time: first the local cache, then fresh data from the network. A `Future` cannot express that.

---

## What This Package Does

`repository_kit` provides a base class and state wrapper that replaces this orchestration with a two-shot `Stream`. Instead of returning a single `Future<T>`, a repository returns `Stream<RKitState<T>>`. The stream emits up to three events:

1. `RKitLoading` — immediately, before any async work begins.
2. `RKitCache` — the local data, if it exists, while the network call is in progress.
3. `RKitSuccess` or `RKitFailure` — the result of the network call.

The presentation layer subscribes to the stream and reacts to each state. It never decides where data comes from. All generic types are prefixed with `RKit` to prevent naming conflicts with existing packages in the Flutter/Dart ecosystem.

---

## When to Use This

This package is useful when:

- Your app needs to show cached data immediately while refreshing from a remote source.
- You want the repository to own the cache-vs-network decision entirely.
- You are building an offline-first feature and want a consistent pattern across all repositories.

This package is not useful when:

- Your repository only fetches from the network with no local storage.
- You only need a one-shot `Future<T>` with no caching.
- You want a state management solution — this is not one.

---

## Installation

```yaml
dependencies:
  repository_kit: ^0.1.2
```

---

## Usage

### 1. Extend `RKitRepository`

Implement three methods. The framework handles the rest.

```dart
class UserRepository extends RKitRepository<User, Map<String, dynamic>> {
  UserRepository(this._api, this._db, this._userId);

  final UserApi _api;
  final UserDao _db;
  final String _userId;

  /// Load from local storage. Return null if nothing is cached.
  @override
  Future<User?> load() => _db.findUser(_userId);

  /// Make the network request.
  @override
  Future<Map<String, dynamic>> fetch() => _api.getUser(_userId);

  /// Persist the network response and return the domain model.
  /// Both saving and returning are required.
  @override
  Future<User> persist(Map<String, dynamic> response) async {
    final user = User.fromJson(response);
    await _db.saveUser(user);
    return user;
  }
}
```

### 2. Consume the Stream

The state sealed class is exhaustive, so a `switch` expression covers all cases at compile time.

```dart
userRepository.watch().listen((state) {
  switch (state) {
    case RKitLoading():
      showSpinner();
    case RKitCache(:final data):
      showUser(data, isStale: true);
    case RKitSuccess(:final data):
      showUser(data);
    case RKitFailure(:final error, :final data):
      showError(error, stale: data);
  }
});
```

With a `StreamBuilder` in Flutter:

```dart
StreamBuilder<RKitState<User>>(
  stream: userRepository.watch(),
  builder: (context, snapshot) {
    return switch (snapshot.data) {
      null || RKitLoading() => const CircularProgressIndicator(),
      RKitCache(:final data) => UserCard(user: data, isStale: true),
      RKitSuccess(:final data) => UserCard(user: data),
      RKitFailure(:final data?, :final error) => Column(
          children: [ErrorBanner(error: error), UserCard(user: data)],
        ),
      RKitFailure(:final error) => ErrorView(error: error),
    };
  },
)
```

---

## Cache Policy

Control whether and when the network request is made. Set via `cachePolicy` on your repository.

### `RKitCachePolicy.always` (default) — Parallel

`load()` and `fetch()` run simultaneously. The first to complete controls what the stream emits.

```dart
@override
RKitCachePolicy get cachePolicy => RKitCachePolicy.always;
```

| Scenario | Emission sequence |
|---|---|
| `fetch()` wins the race | `RKitLoading` → `RKitSuccess` |
| `load()` wins the race | `RKitLoading` → `RKitCache` → `RKitSuccess` |
| `fetch()` fails | `RKitLoading` → `RKitCache` (if available) → `RKitFailure` |

Total time to `RKitSuccess` is `max(load, fetch)` instead of `load + fetch`.

---

### `RKitCachePolicy.ifEmpty` — Sequential

`load()` runs first. `fetch()` is only called if `load()` returns `null`. Saves network bandwidth when data is already cached.

```dart
@override
RKitCachePolicy get cachePolicy => RKitCachePolicy.ifEmpty;
```

| Scenario | Emission sequence |
|---|---|
| Cache is empty (`load()` returns `null`) | `RKitLoading` → `RKitSuccess` |
| Cache has data (`load()` returns non-null) | `RKitLoading` → `RKitSuccess` (cached, no network call) |
| Cache empty and `fetch()` fails | `RKitLoading` → `RKitFailure` |

---

### `RKitCachePolicy.never` — Local only

`load()` runs. `fetch()` is never called. Useful for fully offline features or reference data that does not change.

```dart
@override
RKitCachePolicy get cachePolicy => RKitCachePolicy.never;
```

| Scenario | Emission sequence |
|---|---|
| Cache has data | `RKitLoading` → `RKitSuccess` (cached) |
| Cache is empty | `RKitLoading` → `RKitFailure` |

---

### `RKitCachePolicy.staleIf` — Sequential, conditional

`load()` runs first. Your closure inspects the cached object and decides whether it is stale. If stale, `fetch()` proceeds. If fresh, `fetch()` is skipped.

```dart
@override
RKitCachePolicy get cachePolicy => RKitCachePolicy.staleIf<User>((cachedUser) {
  final age = DateTime.now().difference(cachedUser.updatedAt);
  return age > const Duration(minutes: 5); // true = stale, fetch needed
});
```

| Scenario | Emission sequence |
|---|---|
| Cache is empty | `RKitLoading` → `RKitSuccess` (fresh) |
| Cache is stale (closure returns `true`) | `RKitLoading` → `RKitCache` → `RKitSuccess` |
| Cache is fresh (closure returns `false`) | `RKitLoading` → `RKitSuccess` (cached, no network call) |
| Cache stale and `fetch()` fails | `RKitLoading` → `RKitCache` → `RKitFailure` |



---

## Retry Policy

Control retry behaviour when `fetch()` fails.

### `RKitRetryPolicy.none` (default)

No retries. A single failure immediately emits `RKitFailure`.

```dart
@override
RKitRetryPolicy get retryPolicy => RKitRetryPolicy.none;
```

### `RKitRetryPolicy.exponential`

Retries `fetch()` up to `maxAttempts` times with exponentially increasing delays between attempts. If all attempts fail, `RKitFailure` is emitted.

```dart
@override
RKitRetryPolicy get retryPolicy => RKitRetryPolicy.exponential(
  maxAttempts: 3,
  initialDelay: const Duration(seconds: 1),
  // Delays: 1s, 2s, 4s — then failure
);
```

| Attempt | Delay before attempt |
|---|---|
| 1 | `initialDelay` |
| 2 | `initialDelay * 2` |
| 3 | `initialDelay * 4` |
| … | … |


---

## Error Handling

| Scenario | Behaviour |
|---|---|
| `load()` throws | Treated as a cache miss. The network fetch proceeds normally. |
| `fetch()` throws | Emits `RKitFailure` with stale data if cache was available. The original exception is wrapped in `RKitException` to preserve error/stacktrace context. |
| `persist()` throws | Emits `RKitFailure` with stale data if cache was available. |
| `RKitCachePolicy.never`, no local data | Emits `RKitFailure` with an `RKitException`. |

---

## API Reference

### `RKitRepository<ResultType, RemoteType>`

| Member | Description |
|---|---|
| `Future<ResultType?> load()` | Load from local storage. Return `null` if nothing is cached. |
| `Future<RemoteType> fetch()` | Make the remote request. |
| `Future<ResultType> persist(RemoteType)` | Save the remote response and return the domain model. |
| `RKitCachePolicy get cachePolicy` | When to fetch from remote. Defaults to `RKitCachePolicy.always`. |
| `RKitRetryPolicy get retryPolicy` | How to handle request failures. Defaults to `RKitRetryPolicy.none`. |
| `Stream<RKitState<ResultType>> watch()` | The two-shot stream. |

### `RKitState<T>`

| Subtype | When emitted |
|---|---|
| `RKitLoading` | Always, immediately. |
| `RKitCache(data)` | When `load()` returns non-null before `fetch()` completes (`always` policy only). |
| `RKitSuccess(data)` | When the network fetch and persist succeed. |
| `RKitFailure(error, {data?})` | When the network fetch or persist fails. Holds an `RKitException`. |

---

## License

MIT
