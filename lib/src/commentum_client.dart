import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import './models/comment.dart';
import './models/error.dart';
import './models/response.dart';
import './models/user.dart';
import 'commentum_storage.dart';
import 'commentum_config.dart';

/// Client for interacting with the Commentum API.
///
/// Handles authentication state, token management, and all CRUD operations
/// for comments, replies, and votes across multiple providers (AniList, MAL, Simkl).
class CommentumClient {
  final CommentumConfig config;
  final CommentumStorage storage;
  final http.Client _httpClient;

  /// In-memory cache of JWTs to minimize async storage reads.
  final Map<CommentumProvider, String> _tokenCache = {};

  CommentumProvider? _activeProvider;

  /// Creates a new [CommentumClient] instance.
  ///
  /// * [config]: Configuration for base URL, timeouts, and logging.
  /// * [storage]: Persistence strategy for tokens (e.g., SecureStorage, Hive).
  /// * [httpClient]: Optional custom http client for testing or interception.
  CommentumClient({
    required this.config,
    required this.storage,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Hydrates the client state by loading persisted tokens from [storage].
  ///
  /// Call this immediately after instantiating the client.
  Future<void> init() async {
    for (final provider in CommentumProvider.values) {
      final token = await storage.getToken(provider);
      if (token != null) {
        _tokenCache[provider] = token;
      }
    }
  }

  /// Sets the active provider context (e.g., [CommentumProvider.anilist]).
  ///
  /// Subsequent requests will use the cached token for this provider.
  void setActiveProvider(CommentumProvider? provider) {
    _activeProvider = provider;
  }

  /// The currently active authentication provider.
  CommentumProvider? get activeProvider => _activeProvider;

  /// Whether the [activeProvider] has a valid cached token.
  bool get isLoggedIn =>
      _activeProvider != null && _tokenCache.containsKey(_activeProvider);

  // ---------------------------------------------------------------------------
  // AUTHENTICATION
  // ---------------------------------------------------------------------------

  /// Exchanges a third-party [providerAccessToken] for a Commentum JWT.
  ///
  /// * [provider]: The identity provider (e.g., MAL, Simkl).
  /// * [providerAccessToken]: The access token received from the provider's OAuth flow.
  ///
  /// Automatically caches the resulting JWT and sets the provider as active.
  Future<void> login(
      CommentumProvider provider, String providerAccessToken) async {
    final data = await _request(
      '/auth',
      method: 'POST',
      body: {
        'provider': provider.apiValue,
        'access_token': providerAccessToken,
      },
      useAuth: false,
    );

    final jwt = data['token'];
    _tokenCache[provider] = jwt;
    await storage.saveToken(provider, jwt);

    setActiveProvider(provider);
  }

  /// Logs out the specified [provider] (or the currently active one).
  ///
  /// Clears the token from both memory and [storage].
  /// Attempts to notify the server to invalidate the session (best-effort).
  Future<void> logout([CommentumProvider? provider]) async {
    final targetProvider = provider ?? _activeProvider;
    if (targetProvider == null) return;

    try {
      if (_tokenCache.containsKey(targetProvider)) {
        final prevActive = _activeProvider;
        _activeProvider = targetProvider;
        await _request('/auth', method: 'DELETE');
        _activeProvider = prevActive;
      }
    } catch (_) {
      // Suppress network errors during logout to ensure local cleanup proceeds.
    }

    _tokenCache.remove(targetProvider);
    await storage.deleteToken(targetProvider);

    if (_activeProvider == targetProvider) {
      _activeProvider = null;
    }
  }

  /// Fetches the profile of the currently authenticated user.
  ///
  /// Throws [CommentumError] if not logged in.
  Future<User> getMe() async {
    final data = await _request('/me');
    return User.fromJson(data['user']);
  }

  // ---------------------------------------------------------------------------
  // COMMENTS & REPLIES
  // ---------------------------------------------------------------------------

  /// Creates a new root-level comment on a media item.
  ///
  /// * [mediaId]: The ID of the media (anime/manga) in the external database.
  /// * [content]: The text body of the comment.
  Future<Comment> createComment(String mediaId, String content, { required String? client }) async {
    final data = await _request(
      '/posts',
      method: 'POST',
      body: {'media_id': mediaId, 'content': content, 'client': client},
    );
    return Comment.fromJson(data['post']);
  }

  /// Creates a reply to an existing comment.
  ///
  /// * [parentId]: The ID of the comment being replied to.
  /// * [content]: The text body of the reply.
  Future<Comment> createReply(String parentId, String content, { required String? client }) async {
    final data = await _request(
      '/posts',
      method: 'POST',
      body: {'parent_id': parentId, 'content': content, 'client': client},
    );
    return Comment.fromJson(data['post']);
  }

  /// Retrieves a paginated list of root comments for [mediaId].
  ///
  /// * [limit]: Max items to return (default: 20).
  /// * [cursor]: Pagination cursor from a previous [CommentumResponse] result.
  Future<CommentumResponse> listComments(
    String mediaId, {
    int limit = 20,
    String? cursor,
  }) async {
    final params = {'media_id': mediaId, 'limit': limit.toString()};
    if (cursor != null) params['cursor'] = cursor;

    final data = await _request('/posts', params: params);
    return CommentumResponse.fromJson(data, isReply: false);
  }

  /// Retrieves a paginated list of replies.
  ///
  /// * [rootId]: The ID of the top-level ancestor comment.
  /// * [parentId]: (Optional) Filter by direct parent ID.
  Future<CommentumResponse> listReplies(
    String rootId, {
    int limit = 20,
    String? cursor,
    String? parentId,
  }) async {
    final params = {'root_id': rootId, 'limit': limit.toString()};
    if (parentId != null) params['parent_id'] = parentId;
    if (cursor != null) params['cursor'] = cursor;

    final data = await _request('/posts', params: params);
    return CommentumResponse.fromJson(data, isReply: true);
  }

  /// Updates the text content of a comment.
  ///
  /// * [commentId]: ID of the comment to edit.
  /// * [content]: The new text content.
  Future<Comment> updateComment(String commentId, String content) async {
    final data = await _request(
      '/posts',
      method: 'PATCH',
      body: {'id': commentId, 'content': content},
    );
    return Comment.fromJson(data['post']);
  }

  /// Deletes a comment by [commentId].
  ///
  /// This action is typically irreversible.
  Future<void> deleteComment(String commentId) async {
    await _request('/posts?id=$commentId', method: 'DELETE');
  }

  // ---------------------------------------------------------------------------
  // INTERACTION
  // ---------------------------------------------------------------------------

  /// Casts or updates a vote on a comment.
  ///
  /// * [commentId]: The target comment ID.
  /// * [voteType]: `1` (Upvote), `-1` (Downvote), or `0` (Remove vote).
  Future<void> voteComment(String commentId, int voteType) async {
    await _request(
      '/votes',
      method: 'POST',
      body: {'post_id': commentId, 'vote_type': voteType},
    );
  }

  /// Reports a comment for moderation.
  ///
  /// * [commentId]: The ID of the offending comment.
  /// * [reason]: A short string describing the violation (e.g. "Spam", "Spoiler").
  Future<void> reportComment({
    required String commentId,
    required String reason,
  }) async {
    await _request(
      '/reports',
      method: 'POST',
      body: {'comment_id': commentId, 'reason': reason},
    );
  }

  // ---------------------------------------------------------------------------
  // INTERNAL NETWORKING
  // ---------------------------------------------------------------------------

  /// Performs the HTTP request, handles auth headers, and parses errors.
  ///
  /// Wraps [http.Client] calls with:
  /// 1. Auth header injection
  /// 2. Request/Response Logging (if enabled)
  /// 3. Error handling and wrapping into [CommentumError]
  Future<dynamic> _request(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? params,
    bool useAuth = true,
    bool isRetry = false,
  }) async {
    final url = Uri.parse('${config.baseUrl}$endpoint').replace(
      queryParameters: params,
    );

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (useAuth && _activeProvider != null) {
      final token = _tokenCache[_activeProvider];
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    // -- Simple Logging --
    if (config.enableLogging && !config.verboseLogging) {
      print('[Commentum] $method $url');
    }

    // -- Verbose Request Logging --
    if (config.verboseLogging) {
      _logRequest(method, url, headers, body);
    }

    final stopwatch = Stopwatch()..start();

    try {
      http.Response response;
      final encodedBody = body != null ? jsonEncode(body) : null;

      switch (method.toUpperCase()) {
        case 'POST':
          response =
              await _httpClient.post(url, headers: headers, body: encodedBody);
          break;
        case 'PUT':
          response =
              await _httpClient.put(url, headers: headers, body: encodedBody);
          break;
        case 'PATCH':
          response =
              await _httpClient.patch(url, headers: headers, body: encodedBody);
          break;
        case 'DELETE':
          response = await _httpClient.delete(url,
              headers: headers, body: encodedBody);
          break;
        default:
          response = await _httpClient.get(url, headers: headers);
      }

      stopwatch.stop();

      // -- Verbose Response Logging --
      if (config.verboseLogging) {
        _logResponse(response, stopwatch.elapsedMilliseconds);
      }

      // Handle 401 Unauthorized
      if (response.statusCode == 401 &&
          !isRetry &&
          useAuth &&
          _activeProvider != null) {
        throw CommentumError('Unauthorized: Token expired or invalid', 401);
      }

      final dynamic responseBody;
      try {
        responseBody = jsonDecode(response.body);
      } catch (e) {
        throw CommentumError(
            'Invalid JSON response from server', response.statusCode);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CommentumError(
          responseBody['error'] ?? 'Unknown Server Error',
          response.statusCode,
        );
      }

      return responseBody;
    } on http.ClientException catch (e, stackTrace) {
      stopwatch.stop();
      if (config.verboseLogging) {
        _logError(e, stopwatch.elapsedMilliseconds, stackTrace);
      }
      throw CommentumError('Network Error: ${e.message}', 0);
    } catch (e, stackTrace) {
      stopwatch.stop();
      if (config.verboseLogging) {
        _logError(e, stopwatch.elapsedMilliseconds, stackTrace);
      }
      if (e is CommentumError) rethrow;
      throw CommentumError('Unexpected Error: $e', 0);
    }
  }

  // ---------------------------------------------------------------------------
  // LOGGING UTILITIES
  // ---------------------------------------------------------------------------

  /// Logs outgoing requests in a structured, box-drawing format.
  void _logRequest(
      String method, Uri url, Map<String, String> headers, dynamic body) {
    final buffer = StringBuffer();
    buffer.writeln(
        '╔══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║ ↗️ REQUEST');
    buffer.writeln(
        '╠══════════════════════════════════════════════════════════════');
    buffer.writeln('║ URL: $method $url');
    buffer.writeln('║ Headers:');
    headers.forEach((k, v) => buffer.writeln('║   $k: $v'));
    if (body != null) {
      buffer.writeln('║ Body:');
      _prettyPrintJson(body, buffer);
    }
    buffer.writeln(
        '╚══════════════════════════════════════════════════════════════╝');
    dev.log(buffer.toString(), name: 'Commentum');
  }

  /// Logs incoming responses, including latency and formatted JSON body.
  void _logResponse(http.Response response, int latencyMs) {
    final buffer = StringBuffer();
    buffer.writeln(
        '╔══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║ ↘️ RESPONSE [${response.statusCode}] (${latencyMs}ms)');
    buffer.writeln(
        '╠══════════════════════════════════════════════════════════════');
    buffer.writeln('║ Headers:');
    response.headers.forEach((k, v) => buffer.writeln('║   $k: $v'));
    buffer.writeln('║ Body:');
    try {
      final json = jsonDecode(response.body);
      _prettyPrintJson(json, buffer);
    } catch (_) {
      // If body isn't JSON, just print raw
      buffer.writeln('║   ${response.body}');
    }
    buffer.writeln(
        '╚══════════════════════════════════════════════════════════════╝');
    dev.log(buffer.toString(), name: 'Commentum');
  }

  /// Logs errors and exceptions, including stack traces if available.
  void _logError(dynamic error, int latencyMs, [StackTrace? stackTrace]) {
    final buffer = StringBuffer();
    buffer.writeln(
        '╔══════════════════════════════════════════════════════════════╗');
    buffer.writeln('║ ❌ ERROR (${latencyMs}ms)');
    buffer.writeln(
        '╠══════════════════════════════════════════════════════════════');
    buffer.writeln('║ Error: $error');
    if (stackTrace != null) {
      buffer.writeln('║ StackTrace:');
      final traceLines =
          stackTrace.toString().split('\n').take(5); // Limit to top 5 lines
      for (var line in traceLines) {
        if (line.isNotEmpty) buffer.writeln('║   $line');
      }
    }
    buffer.writeln(
        '╚══════════════════════════════════════════════════════════════╝');
    dev.log(buffer.toString(), name: 'Commentum', error: error);
  }

  /// Helper to indent and format JSON for readability in logs.
  void _prettyPrintJson(dynamic json, StringBuffer buffer) {
    var spaces = '║   ';
    var encoder = JsonEncoder.withIndent('  ');
    var prettyString = encoder.convert(json);
    // Indent each line to align with the log box
    prettyString
        .split('\n')
        .forEach((element) => buffer.writeln('$spaces$element'));
  }

  /// Closes the underlying HTTP client.
  void dispose() {
    _httpClient.close();
  }
}


