import 'dart:async';
import 'package:http/http.dart' as http;
import 'commentum_config.dart';
import 'commentum_storage.dart';
import 'models/comment.dart';
import 'models/response.dart';
import 'models/user.dart';
import 'modules/auth_manager.dart';
import 'modules/comment_manager.dart';
import 'modules/discussion_controller.dart';
import 'modules/interaction_manager.dart';
import 'network/commentum_http_client.dart';

/// Client for interacting with the Commentum API.
///
/// Designed with a modular architecture:
/// * [auth]: Manages multi-account logins, token hydration, active provider switching, and profile lookups.
/// * [comments]: Handles creation, listing, editing, and deletion of comments and replies.
/// * [interactions]: Handles community voting and moderation reporting.
class CommentumClient {
  final CommentumConfig config;
  final CommentumStorage storage;
  final CommentumProvider preferredProvider;
  final CommentumHttpClient _network;

  late final CommentumAuthManager auth;
  late final CommentumCommentManager comments;
  late final CommentumInteractionManager interactions;

  /// Creates a new [CommentumClient] instance.
  ///
  /// * [config]: Configuration for base URL, timeouts, and logging.
  /// * [storage]: Persistence strategy for tokens (e.g., [InMemoryCommentumStorage] or secure storage).
  /// * [preferredProvider]: Initial default provider to activate upon hydration.
  /// * [onProviderTokenRefreshRequired]: Optional callback triggered when JWT expires to retrieve fresh provider token.
  /// * [httpClient]: Optional custom [http.Client] for interception or testing.
  CommentumClient({
    required this.config,
    required this.storage,
    required this.preferredProvider,
    Future<String?> Function(CommentumProvider provider)? onProviderTokenRefreshRequired,
    http.Client? httpClient,
  }) : _network = CommentumHttpClient(config: config, httpClient: httpClient) {
    auth = CommentumAuthManager(
      storage: storage,
      network: _network,
      defaultProvider: preferredProvider,
      onProviderTokenRefreshRequired: onProviderTokenRefreshRequired,
    );
    comments = CommentumCommentManager(
      config: config,
      network: _network,
      auth: auth,
    );
    interactions = CommentumInteractionManager(
      network: _network,
      auth: auth,
    );
  }

  /// Hydrates the client state by loading persisted tokens across all accounts from [storage].
  /// Call this immediately after instantiating the client.
  Future<void> init() => auth.init();

  /// The currently active authentication provider.
  CommentumProvider? get activeProvider => auth.activeProvider;

  /// Sets the active provider context without validating login status.
  void setActiveProvider(CommentumProvider? provider) =>
      auth.setActiveProvider(provider);

  /// Switches the active provider to [provider]. Throws an exception if not logged in.
  void switchProvider(CommentumProvider provider) =>
      auth.switchProvider(provider);

  /// Whether the [activeProvider] has a valid cached token.
  bool get isLoggedIn => auth.isLoggedIn;

  /// List of all providers currently authenticated in session cache.
  List<CommentumProvider> get loggedInProviders => auth.loggedInProviders;

  // ---------------------------------------------------------------------------
  // AUTH FACADE
  // ---------------------------------------------------------------------------

  /// Exchanges a third-party [providerAccessToken] for a Commentum JWT.
  Future<void> login(CommentumProvider provider, String providerAccessToken) =>
      auth.login(provider, providerAccessToken);

  /// Logs out the specified [provider] (or the active one).
  Future<void> logout([CommentumProvider? provider]) => auth.logout(provider);

  /// Logs out all currently authenticated providers.
  Future<void> logoutAll() => auth.logoutAll();

  /// Fetches the profile of the currently authenticated user.
  Future<User> getMe() => auth.getMe();

  /// Fetches user profiles for all currently authenticated accounts concurrently.
  Future<Map<CommentumProvider, User>> getAllLoggedInProfiles() =>
      auth.getAllLoggedInProfiles();

  // ---------------------------------------------------------------------------
  // COMMENTS FACADE
  // ---------------------------------------------------------------------------

  /// Creates a new root-level comment on a media item.
  Future<Comment> createComment({
    required String mediaId,
    required String mediaProvider,
    required String content,
    int? episodeNumber,
  }) =>
      comments.createComment(
        mediaId: mediaId,
        mediaProvider: mediaProvider,
        content: content,
        episodeNumber: episodeNumber,
      );

  /// Creates a reply to an existing comment.
  Future<Comment> createReply({
    required String parentId,
    required String content,
  }) =>
      comments.createReply(parentId: parentId, content: content);

  /// Retrieves a paginated list of root comments for [mediaId].
  Future<CommentumResponse> listComments({
    required String mediaId,
    int limit = 20,
    String? cursor,
    int? episodeNumber,
  }) =>
      comments.listComments(
        mediaId: mediaId,
        limit: limit,
        cursor: cursor,
        episodeNumber: episodeNumber,
      );

  /// Retrieves a paginated list of replies under [rootId].
  Future<CommentumResponse> listReplies({
    required String rootId,
    String? parentId,
    int limit = 20,
    String? cursor,
  }) =>
      comments.listReplies(
        rootId: rootId,
        parentId: parentId,
        limit: limit,
        cursor: cursor,
      );

  /// Updates the text content of a comment.
  Future<Comment> updateComment({
    required String commentId,
    required String content,
  }) =>
      comments.updateComment(commentId: commentId, content: content);

  /// Deletes a comment by [commentId].
  Future<void> deleteComment({required String commentId}) =>
      comments.deleteComment(commentId: commentId);

  // ---------------------------------------------------------------------------
  // INTERACTIONS FACADE
  // ---------------------------------------------------------------------------

  /// Casts or toggles a vote on a comment (`1` up, `-1` down). Sending twice toggles/removes it.
  Future<void> voteComment({
    required String commentId,
    required int voteType,
  }) =>
      interactions.voteComment(commentId: commentId, voteType: voteType);

  /// Upvotes a comment (+1). Sending twice toggles/removes upvote.
  Future<void> upvote({required String commentId}) =>
      interactions.upvote(commentId: commentId);

  /// Downvotes a comment (-1). Sending twice toggles/removes downvote.
  Future<void> downvote({required String commentId}) =>
      interactions.downvote(commentId: commentId);

  /// Reports a comment for moderation.
  Future<void> reportComment({
    required String commentId,
    required String reason,
  }) =>
      interactions.reportComment(commentId: commentId, reason: reason);

  /// Creates a self-contained [CommentumDiscussionController] that manages discussion state,
  /// pagination, optimistic voting, replies insertion, and deletion automatically.
  CommentumDiscussionController getDiscussionController({
    required String mediaId,
    required String mediaProvider,
  }) =>
      CommentumDiscussionController(
        client: this,
        mediaId: mediaId,
        mediaProvider: mediaProvider,
      );

  /// Closes the underlying HTTP client resources.
  void dispose() {
    _network.dispose();
  }
}
