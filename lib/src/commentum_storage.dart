import 'dart:async';
import 'commentum_config.dart';

/// Abstract interface for persistence of authentication tokens across multiple providers.
abstract class CommentumStorage {
  /// Saves the JWT [token] for the given identity [provider].
  Future<void> saveToken(CommentumProvider provider, String token);

  /// Retrieves the saved JWT token for [provider], or returns `null` if none exists.
  Future<String?> getToken(CommentumProvider provider);

  /// Deletes any saved JWT token for [provider].
  Future<void> deleteToken(CommentumProvider provider);

  /// Retrieves all persisted provider tokens as a map.
  /// Used during hydration to support multi-account authentication sessions.
  Future<Map<CommentumProvider, String>> getAllTokens();

  /// Clears all saved tokens across all providers.
  Future<void> clearAll();

  /// Saves the third-party access token for [provider] to enable automatic relogin upon JWT expiry.
  Future<void> saveProviderToken(CommentumProvider provider, String token) async {}

  /// Retrieves the third-party access token for [provider].
  Future<String?> getProviderToken(CommentumProvider provider) async => null;

  /// Deletes the third-party access token for [provider].
  Future<void> deleteProviderToken(CommentumProvider provider) async {}
}

/// A ready-to-use in-memory implementation of [CommentumStorage].
/// Ideal for testing, short-lived applications, or fallback scenarios.
class InMemoryCommentumStorage implements CommentumStorage {
  final Map<CommentumProvider, String> _tokens = {};
  final Map<CommentumProvider, String> _providerTokens = {};

  @override
  Future<void> saveToken(CommentumProvider provider, String token) async {
    _tokens[provider] = token;
  }

  @override
  Future<String?> getToken(CommentumProvider provider) async {
    return _tokens[provider];
  }

  @override
  Future<void> deleteToken(CommentumProvider provider) async {
    _tokens.remove(provider);
  }

  @override
  Future<Map<CommentumProvider, String>> getAllTokens() async {
    return Map.from(_tokens);
  }

  @override
  Future<void> clearAll() async {
    _tokens.clear();
    _providerTokens.clear();
  }

  @override
  Future<void> saveProviderToken(CommentumProvider provider, String token) async {
    _providerTokens[provider] = token;
  }

  @override
  Future<String?> getProviderToken(CommentumProvider provider) async {
    return _providerTokens[provider];
  }

  @override
  Future<void> deleteProviderToken(CommentumProvider provider) async {
    _providerTokens.remove(provider);
  }
}
