import 'package:flutter/material.dart';
import 'package:repository_kit/repository_kit.dart';

// -----------------------------------------------------------------------------
// 1. Models and Services (Infrastructure)
// -----------------------------------------------------------------------------
class User {
  const User({required this.id, required this.name, required this.email});
  final String id;
  final String name;
  final String email;
}

class UserDao {
  final Map<String, User> _db = {};

  Future<User?> findUser(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return _db[id];
  }

  Future<void> saveUser(User user) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _db[user.id] = user;
  }

  void clear() {
    _db.clear();
  }
}

class UserApi {
  int _requestCount = 0;
  bool _shouldFail = false;

  void setShouldFail(bool value) {
    _shouldFail = value;
    _requestCount = 0;
  }

  Future<Map<String, dynamic>> getUser(String id) async {
    _requestCount++;
    await Future<void>.delayed(const Duration(milliseconds: 800));

    if (_shouldFail) {
      // Exponential retry will attempt to recover from this
      if (_requestCount < 3) {
        throw Exception('Server Timeout (Attempt $_requestCount of 3)');
      }
    }

    return {
      'id': id,
      'name': 'Jane Doe',
      'email': 'jane@example.com',
    };
  }
}

// -----------------------------------------------------------------------------
// 2. Repository Definition
// -----------------------------------------------------------------------------
class UserRepository extends RKitRepository<User, Map<String, dynamic>> {
  UserRepository({
    required UserDao db,
    required UserApi api,
    required this.userId,
    required RKitCachePolicy cachePolicy,
    required RKitRetryPolicy retryPolicy,
  })  : _db = db,
        _api = api,
        _cachePolicy = cachePolicy,
        _retryPolicy = retryPolicy;

  final UserDao _db;
  final UserApi _api;
  final String userId;
  final RKitCachePolicy _cachePolicy;
  final RKitRetryPolicy _retryPolicy;

  @override
  RKitCachePolicy get cachePolicy => _cachePolicy;

  @override
  RKitRetryPolicy get retryPolicy => _retryPolicy;

  @override
  Future<User?> load() => _db.findUser(userId);

  @override
  Future<Map<String, dynamic>> fetch() => _api.getUser(userId);

  @override
  Future<User> persist(Map<String, dynamic> response) async {
    final user = User(
      id: response['id'] as String,
      name: response['name'] as String,
      email: response['email'] as String,
    );
    await _db.saveUser(user);
    return user;
  }
}

// -----------------------------------------------------------------------------
// 3. Presentation Layer
// -----------------------------------------------------------------------------
void main() {
  runApp(const RepositoryKitExampleApp());
}

class RepositoryKitExampleApp extends StatelessWidget {
  const RepositoryKitExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Repository Kit Example',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Deep Slate
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1), // Indigo Accent
          surface: Color(0xFF1E293B), // Card Slate
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final UserDao _db = UserDao();
  final UserApi _api = UserApi();

  RKitCachePolicy _cachePolicy = RKitCachePolicy.always;
  final RKitCachePolicy _staleIfPolicy = RKitCachePolicy.staleIf<User>((user) {
    // If the name is already correct, say it is NOT stale (skip API fetch)
    return user.name != 'Jane Doe';
  });
  bool _useRetryPolicy = true;
  bool _simulateNetworkError = false;

  Stream<RKitState<User>>? _repositoryStream;
  final List<String> _consoleLogs = [];

  void _runWatch() {
    setState(() {
      _consoleLogs.clear();
      _api.setShouldFail(_simulateNetworkError);

      final retryPolicy = _useRetryPolicy
          ? RKitRetryPolicy.exponential(
              maxAttempts: 3,
              initialDelay: const Duration(milliseconds: 300),
            )
          : RKitRetryPolicy.none;

      final repository = UserRepository(
        db: _db,
        api: _api,
        userId: 'user_456',
        cachePolicy: _cachePolicy,
        retryPolicy: retryPolicy,
      );

      // Listen to the stream to print to our visual logs
      _repositoryStream = repository.watch().asBroadcastStream();
      _repositoryStream!.listen(
        (state) {
          setState(() {
            _consoleLogs.add(_getStateLog(state));
          });
        },
        onError: (Object error) {
          setState(() {
            _consoleLogs.add('[Stream Error] $error');
          });
        },
      );
    });
  }

  void _clearDatabase() {
    _db.clear();
    setState(() {
      _consoleLogs.add('[DB] Local database cleared');
      _repositoryStream = null;
    });
  }

  String _getStateLog(RKitState<User> state) {
    return switch (state) {
      RKitLoading() => '[RKitState] Loading: Starting fetch lifecycle',
      RKitCache(:final data) =>
        '[RKitState] Cache: Serving stale data (User: ${data.name})',
      RKitSuccess(:final data) =>
        '[RKitState] Success: Fresh data saved (User: ${data.name})',
      RKitFailure(:final error, :final data) =>
        '[RKitState] Failure: error="$error", staleData=${data?.name ?? "null"}',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Repository Kit Dashboard'),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Controls Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configuration Settings',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF818CF8),
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    // Cache Policy Selector
                    DropdownButtonFormField<RKitCachePolicy>(
                      initialValue: _cachePolicy,
                      decoration: const InputDecoration(
                        labelText: 'Cache Policy',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: RKitCachePolicy.always,
                          child: Text('always (Fetch every time)'),
                        ),
                        const DropdownMenuItem(
                          value: RKitCachePolicy.ifEmpty,
                          child: Text('ifEmpty (Only fetch if cache empty)'),
                        ),
                        const DropdownMenuItem(
                          value: RKitCachePolicy.never,
                          child: Text('never (Serve from cache only)'),
                        ),
                        DropdownMenuItem(
                          value: _staleIfPolicy,
                          child: const Text(
                              'staleIf (Fetch only if name NOT Jane)'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _cachePolicy = val);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    // Checkboxes
                    SwitchListTile(
                      title: const Text('Exponential Retry (3 Attempts)'),
                      subtitle:
                          const Text('Recover from simulated network issues'),
                      value: _useRetryPolicy,
                      onChanged: (val) => setState(() => _useRetryPolicy = val),
                    ),
                    SwitchListTile(
                      title: const Text('Simulate Network Timeout'),
                      subtitle:
                          const Text('First 2 attempts fail. Succeeds on 3rd.'),
                      value: _simulateNetworkError,
                      onChanged: (val) =>
                          setState(() => _simulateNetworkError = val),
                    ),
                    const SizedBox(height: 12),
                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('Watch Repository'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: _runWatch,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_sweep),
                          label: const Text('Clear DB'),
                          onPressed: _clearDatabase,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Live Output UI State
            Text(
              'UI State Result',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(16),
                child: _repositoryStream == null
                    ? const Text('Click "Watch Repository" to start stream')
                    : StreamBuilder<RKitState<User>>(
                        stream: _repositoryStream,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const CircularProgressIndicator();
                          }
                          final state = snapshot.data!;
                          return _buildStateCard(context, state);
                        },
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Console Logs Console
            Text(
              'Stream Lifecycle Log Output',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                padding: const EdgeInsets.all(12),
                child: _consoleLogs.isEmpty
                    ? const Text(
                        'No emissions yet...',
                        style: TextStyle(
                            color: Colors.grey, fontFamily: 'monospace'),
                      )
                    : ListView.builder(
                        itemCount: _consoleLogs.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Text(
                              _consoleLogs[index],
                              style: const TextStyle(
                                color:
                                    Color(0xFF34D399), // Emerald terminal green
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStateCard(BuildContext context, RKitState<User> state) {
    return switch (state) {
      RKitLoading() => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Starting Repository Fetch...'),
          ],
        ),
      RKitCache(:final data) => _UserCardView(
          user: data,
          statusText: 'Serving Stale Cache Data...',
          borderColor: Colors.amber,
          badgeColor: Colors.amber.withValues(alpha: 0.2),
          badgeText: 'STALE CACHE',
        ),
      RKitSuccess(:final data) => _UserCardView(
          user: data,
          statusText: 'Data Fetched & Synced Successfully',
          borderColor: Colors.green,
          badgeColor: Colors.green.withValues(alpha: 0.2),
          badgeText: 'SYNCHRONIZED',
        ),
      RKitFailure(:final error, :final data) => data == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Operation Failed',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.red),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            )
          : _UserCardView(
              user: data,
              statusText: 'Fetch Failed: Showing Stale Backup Data',
              borderColor: Colors.redAccent,
              badgeColor: Colors.red.withValues(alpha: 0.2),
              badgeText: 'ERROR FALLBACK',
            ),
    };
  }
}

class _UserCardView extends StatelessWidget {
  const _UserCardView({
    required this.user,
    required this.statusText,
    required this.borderColor,
    required this.badgeColor,
    required this.badgeText,
  });

  final User user;
  final String statusText;
  final Color borderColor;
  final Color badgeColor;
  final String badgeText;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: borderColor.withValues(alpha: 0.5), width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'USER INFORMATION',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: borderColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            user.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            user.email,
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),
          Text(
            statusText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: borderColor,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
