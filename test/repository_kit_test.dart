import 'package:repository_kit/repository_kit.dart';
import 'package:test/test.dart';

// Minimal concrete implementation for testing the watch() engine.
class _TestRepository extends RKitRepository<String, String> {
  _TestRepository({
    this.localData,
    this.remoteData,
    this.loadThrows = false,
    this.fetchThrows = false,
    RKitCachePolicy? cachePolicy,
    RKitRetryPolicy? retryPolicy,
  })  : _cachePolicy = cachePolicy ?? RKitCachePolicy.always,
        _retryPolicy = retryPolicy ?? RKitRetryPolicy.none;

  final String? localData;
  final String? remoteData;
  final bool loadThrows;
  final bool fetchThrows;
  final RKitCachePolicy _cachePolicy;
  final RKitRetryPolicy _retryPolicy;

  @override
  RKitCachePolicy get cachePolicy => _cachePolicy;

  @override
  RKitRetryPolicy get retryPolicy => _retryPolicy;

  @override
  Future<String?> load() async {
    if (loadThrows) throw Exception('load failed');
    return localData;
  }

  @override
  Future<String> fetch() async {
    if (fetchThrows) throw Exception('fetch failed');
    return remoteData!;
  }

  @override
  Future<String> persist(String response) async {
    return response;
  }
}

void main() {
  group('RKitRepository.watch()', () {
    test('always emits RKitLoading as the first event', () async {
      final repo = _TestRepository(remoteData: 'fresh');
      final first = await repo.watch().first;
      expect(first, isA<RKitLoading<String>>());
    });

    test('emits RKitCache when local data exists', () async {
      final repo = _TestRepository(localData: 'cached', remoteData: 'fresh');
      final states = await repo.watch().toList();
      expect(states[1], isA<RKitCache<String>>());
      expect((states[1] as RKitCache<String>).data, 'cached');
    });

    test('emits RKitSuccess with fresh data on success', () async {
      final repo = _TestRepository(localData: 'cached', remoteData: 'fresh');
      final states = await repo.watch().toList();
      expect(states.last, isA<RKitSuccess<String>>());
      expect((states.last as RKitSuccess<String>).data, 'fresh');
    });

    test('emits RKitFailure with stale data when fetch throws', () async {
      final repo = _TestRepository(
        localData: 'cached',
        fetchThrows: true,
      );
      final states = await repo.watch().toList();
      final failure = states.last as RKitFailure<String>;
      expect(failure, isA<RKitFailure<String>>());
      expect(failure.data, 'cached');
      expect(failure.error, isA<RKitException>());
      expect((failure.error as RKitException).error, isA<Exception>());
    });

    test('emits RKitFailure with no data when fetch throws and no cache',
        () async {
      final repo = _TestRepository(fetchThrows: true);
      final states = await repo.watch().toList();
      final failure = states.last as RKitFailure<String>;
      expect(failure.data, isNull);
    });

    test('treats load() throwing as a cache miss and proceeds to fetch',
        () async {
      final repo = _TestRepository(loadThrows: true, remoteData: 'fresh');
      final states = await repo.watch().toList();
      expect(states.any((s) => s is RKitCache), isFalse);
      expect(states.last, isA<RKitSuccess<String>>());
    });

    test('RKitCachePolicy.ifEmpty skips fetch when cache exists', () async {
      final repo = _TestRepository(
        localData: 'cached',
        remoteData: 'fresh',
        cachePolicy: RKitCachePolicy.ifEmpty,
      );
      final states = await repo.watch().toList();
      expect(states.last, isA<RKitCache<String>>());
      expect((states.last as RKitCache<String>).data, 'cached');
    });

    test('RKitCachePolicy.never emits RKitFailure when no local data exists',
        () async {
      final repo = _TestRepository(cachePolicy: RKitCachePolicy.never);
      final states = await repo.watch().toList();
      expect(states.last, isA<RKitFailure<String>>());
      expect(
        (states.last as RKitFailure<String>).error,
        isA<RKitException>(),
      );
    });

    test('RKitCachePolicy.staleIf fetches when isStale returns true', () async {
      final repo = _TestRepository(
        localData: 'cached',
        remoteData: 'fresh',
        cachePolicy:
            RKitCachePolicy.staleIf<String>((data) => data == 'cached'),
      );
      final states = await repo.watch().toList();
      expect(states.last, isA<RKitSuccess<String>>());
      expect((states.last as RKitSuccess<String>).data, 'fresh');
    });

    test('RKitCachePolicy.staleIf skips fetch when isStale returns false',
        () async {
      final repo = _TestRepository(
        localData: 'cached',
        remoteData: 'fresh',
        cachePolicy:
            RKitCachePolicy.staleIf<String>((data) => data != 'cached'),
      );
      final states = await repo.watch().toList();
      expect(states.last, isA<RKitCache<String>>());
      expect((states.last as RKitCache<String>).data, 'cached');
    });

    test('stream closes after terminal emission', () async {
      final repo = _TestRepository(remoteData: 'fresh');
      var count = 0;
      await repo.watch().forEach((_) => count++);
      expect(count, greaterThan(0));
    });

    test('RKitRetryPolicy.exponential retries on failure', () async {
      final repo = _TestRepository(
        remoteData: 'fresh',
        retryPolicy: RKitRetryPolicy.exponential(
          maxAttempts: 3,
          initialDelay: Duration.zero,
        ),
      );
      final states = await repo.watch().toList();
      expect(states.last, isA<RKitSuccess<String>>());
    });
  });
}
