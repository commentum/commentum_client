enum CommentumProvider {
  anilist,
  myanimelist,
  simkl,
}

extension CommentumProviderExt on CommentumProvider {
  /// The string identifier sent to or received from the Commentum API backend.
  String get apiValue {
    switch (this) {
      case CommentumProvider.anilist:
        return 'anilist';
      case CommentumProvider.myanimelist:
        return 'mal';
      case CommentumProvider.simkl:
        return 'simkl';
    }
  }

  /// Human-readable display name suitable for UI display.
  String get displayName {
    switch (this) {
      case CommentumProvider.anilist:
        return 'AniList';
      case CommentumProvider.myanimelist:
        return 'MyAnimeList';
      case CommentumProvider.simkl:
        return 'Simkl';
    }
  }

  /// Resolves a [CommentumProvider] from its backend [apiValue] or enum name.
  static CommentumProvider? fromString(String value) {
    final lower = value.toLowerCase();
    for (final provider in CommentumProvider.values) {
      if (provider.apiValue == lower || provider.name.toLowerCase() == lower) {
        return provider;
      }
    }
    return null;
  }
}

class CommentumConfig {
  /// Base URL of the backend Commentum API server.
  final String baseUrl;

  /// Identifier of the client app (e.g., 'web', 'android', 'ios', 'shonenx').
  final String? appClient;

  /// Timeout duration for connecting to the API server.
  final Duration connectTimeout;

  /// Timeout duration for receiving HTTP responses.
  final Duration receiveTimeout;

  /// Whether basic request/response URL logging is enabled.
  final bool enableLogging;

  /// Whether verbose JSON headers & body structured logging is enabled.
  final bool verboseLogging;

  /// Whether automatic retries on network/server errors and token re-login on expiry are enabled.
  final bool autoRetry;

  /// Maximum number of retry attempts for failed network requests.
  final int maxRetries;

  /// Base delay between retry attempts.
  final Duration retryDelay;

  const CommentumConfig({
    required this.baseUrl,
    this.appClient,
    this.connectTimeout = const Duration(seconds: 10),
    this.receiveTimeout = const Duration(seconds: 10),
    this.enableLogging = false,
    this.verboseLogging = false,
    this.autoRetry = true,
    this.maxRetries = 2,
    this.retryDelay = const Duration(seconds: 1),
  });
}
