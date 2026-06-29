import 'dart:async';
import '../commentum_config.dart';
import '../commentum_storage.dart';
import '../models/error.dart';
import '../models/user.dart';
import '../network/commentum_http_client.dart';

/// Manages authentication state, multi-account tokens, and user profile operations.
class CommentumAuthManager {
  final CommentumStorage storage;
  final CommentumHttpClient _network;
  final CommentumProvider defaultProvider;

  final Map<CommentumProvider, String> _tokenCache = {};
  final Map<CommentumProvider, String> _providerTokenCache = {};
  CommentumProvider? _activeProvider;

  /// Optional callback to retrieve a fresh third-party access token if not cached locally.
  Future<String?> Function(CommentumProvider provider)? onProviderTokenRefreshRequired;

  CommentumAuthManager({
    required this.storage,
    required CommentumHttpClient network,
    required this.defaultProvider,
    this.onProviderTokenRefreshRequired,
  }) : _network = network {
    _network.getAuthToken = () {
      if (_activeProvider != null) {
        return _tokenCache[_activeProvider!];
      }
      return null;
    };
    _network.onTokenExpired = () async {
      final provider = _activeProvider;
      if (provider == null) return false;

      String? providerToken = _providerTokenCache[provider] ?? await storage.getProviderToken(provider);
      if (providerToken == null && onProviderTokenRefreshRequired != null) {
        providerToken = await onProviderTokenRefreshRequired!(provider);
      }

      if (providerToken != null && providerToken.isNotEmpty) {
        try {
          await login(provider, providerToken);
          return true;
        } catch (_) {
          // Fallthrough to clear expired token if silent re-login fails
        }
      }

      await _clearExpiredToken(provider);
      return false;
    };
  }

  /// Hydrates authentication state by loading all persisted tokens from [storage].
  /// Sets the active provider to [defaultProvider] if available, or any other logged-in provider.
  Future<void> init() async {
    final allTokens = await storage.getAllTokens();
    _tokenCache.clear();
    _tokenCache.addAll(allTokens);

    _providerTokenCache.clear();
    for (final p in CommentumProvider.values) {
      final pToken = await storage.getProviderToken(p);
      if (pToken != null) _providerTokenCache[p] = pToken;
    }

    if (_tokenCache.containsKey(defaultProvider)) {
      _activeProvider = defaultProvider;
    } else if (_tokenCache.isNotEmpty) {
      _activeProvider = _tokenCache.keys.first;
    } else {
      _activeProvider = defaultProvider;
    }
  }

  /// The currently active authentication provider.
  CommentumProvider? get activeProvider => _activeProvider;

  /// Sets the active authentication provider context without checking login status.
  void setActiveProvider(CommentumProvider? provider) {
    _activeProvider = provider;
  }

  /// Switches the active provider to [provider].
  /// Throws [CommentumAuthException] if no token is cached for [provider].
  void switchProvider(CommentumProvider provider) {
    if (!_tokenCache.containsKey(provider)) {
      throw CommentumAuthException(
        'Cannot switch to ${provider.displayName}: Account not logged in.',
      );
    }
    _activeProvider = provider;
  }

  /// Whether the currently active provider has a valid cached token.
  bool get isLoggedIn =>
      _activeProvider != null && _tokenCache.containsKey(_activeProvider!);

  /// List of all providers that currently have active sessions / tokens.
  List<CommentumProvider> get loggedInProviders => _tokenCache.keys.toList();

  /// Checks if a specific [provider] currently has an active login session.
  bool isProviderLoggedIn(CommentumProvider provider) =>
      _tokenCache.containsKey(provider);

  /// Retrieves the cached token for a specific [provider].
  String? getToken(CommentumProvider provider) => _tokenCache[provider];

  /// Exchanges a third-party [providerAccessToken] for a Commentum JWT.
  /// Automatically caches the token and sets [provider] as active.
  Future<void> login(
      CommentumProvider provider, String providerAccessToken) async {
    final data = await _network.request(
      '/auth',
      method: 'POST',
      body: {
        'provider': provider.apiValue,
        'access_token': providerAccessToken,
      },
      useAuth: false,
    );

    final jwt = data['token']?.toString();
    if (jwt == null || jwt.isEmpty) {
      throw const CommentumAuthException(
          'Backend did not return a valid token upon login.');
    }

    _tokenCache[provider] = jwt;
    _providerTokenCache[provider] = providerAccessToken;
    await storage.saveToken(provider, jwt);
    await storage.saveProviderToken(provider, providerAccessToken);
    _activeProvider = provider;
  }

  /// Logs out the specified [provider] (or the currently active provider).
  /// Clears token from both memory cache and persistent [storage].
  Future<void> logout([CommentumProvider? provider]) async {
    final targetProvider = provider ?? _activeProvider;
    if (targetProvider == null) return;

    try {
      if (_tokenCache.containsKey(targetProvider)) {
        final prevActive = _activeProvider;
        _activeProvider = targetProvider;
        await _network.request('/auth', method: 'DELETE');
        _activeProvider = prevActive;
      }
    } catch (_) {
      // Suppress network errors during logout to guarantee local token cleanup.
    }

    _tokenCache.remove(targetProvider);
    _providerTokenCache.remove(targetProvider);
    await storage.deleteToken(targetProvider);
    await storage.deleteProviderToken(targetProvider);

    if (_activeProvider == targetProvider) {
      _activeProvider =
          _tokenCache.isNotEmpty ? _tokenCache.keys.first : defaultProvider;
    }
  }

  /// Logs out all currently authenticated accounts and clears persistent storage.
  Future<void> logoutAll() async {
    final providers = loggedInProviders;
    for (final p in providers) {
      await logout(p);
    }
    await storage.clearAll();
    _tokenCache.clear();
    _providerTokenCache.clear();
    _activeProvider = defaultProvider;
  }

  /// Fetches the profile of the currently authenticated user.
  /// Throws [CommentumAuthException] if not logged in.
  Future<User> getMe() async {
    _ensureLoggedIn();
    final data = await _network.request('/me');
    return User.fromJson(data['user']);
  }

  /// Fetches profiles for all currently logged-in accounts concurrently.
  /// Returns a map of [CommentumProvider] to their respective [User] profile.
  Future<Map<CommentumProvider, User>> getAllLoggedInProfiles() async {
    final result = <CommentumProvider, User>{};
    final originalActive = _activeProvider;

    for (final provider in _tokenCache.keys) {
      try {
        _activeProvider = provider;
        final data = await _network.request('/me');
        result[provider] = User.fromJson(data['user']);
      } catch (_) {
        // Ignore individual profile fetch errors for multi-account summary.
      }
    }

    _activeProvider = originalActive;
    return result;
  }

  Future<void> _clearExpiredToken(CommentumProvider provider) async {
    _tokenCache.remove(provider);
    _providerTokenCache.remove(provider);
    await storage.deleteToken(provider);
    await storage.deleteProviderToken(provider);
    if (_activeProvider == provider) {
      _activeProvider =
          _tokenCache.isNotEmpty ? _tokenCache.keys.first : defaultProvider;
    }
  }

  void _ensureLoggedIn() {
    if (!isLoggedIn) {
      throw const CommentumAuthException(
        'Authentication required. Please login before performing this action.',
      );
    }
  }
}
