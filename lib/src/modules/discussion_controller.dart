import 'dart:async';
import '../commentum_client.dart';
import '../models/comment.dart';

/// Utilities for immutable comment tree mutations (inserting replies, voting, deleting).
class CommentTreeUtils {
  /// Recursively inserts a [reply] under the comment matching [parentId].
  static List<Comment> insertReply(List<Comment> list, String parentId, Comment reply) {
    return list.map((c) {
      if (c.id == parentId) {
        return c.copyWith(
          replies: [...c.replies, reply],
          repliesCount: c.repliesCount + 1,
        );
      }
      if (c.replies.isNotEmpty) {
        return c.copyWith(
          replies: insertReply(c.replies, parentId, reply),
        );
      }
      return c;
    }).toList();
  }

  /// Recursively updates a comment's score and user vote optimistically.
  static List<Comment> updateVote(List<Comment> list, String targetId, int newVote) {
    return list.map((c) {
      if (c.id == targetId) {
        final oldVote = c.userVote ?? 0;
        final finalVote = (oldVote == newVote) ? null : newVote;
        final scoreDiff = (finalVote ?? 0) - oldVote;
        return c.copyWith(score: c.score + scoreDiff, userVote: finalVote);
      }
      if (c.replies.isNotEmpty) {
        return c.copyWith(
          replies: updateVote(c.replies, targetId, newVote),
        );
      }
      return c;
    }).toList();
  }

  /// Recursively removes a comment matching [targetId] from the tree.
  static List<Comment> deleteComment(List<Comment> list, String targetId) {
    return list.where((c) => c.id != targetId).map((c) {
      if (c.replies.isNotEmpty) {
        return c.copyWith(replies: deleteComment(c.replies, targetId));
      }
      return c;
    }).toList();
  }
}

/// Represents the immutable snapshot state of a comment discussion.
class CommentumDiscussionState {
  final List<Comment> comments;
  final bool isLoading;
  final bool isMoreLoading;
  final String? nextCursor;
  final String? error;

  const CommentumDiscussionState({
    this.comments = const [],
    this.isLoading = false,
    this.isMoreLoading = false,
    this.nextCursor,
    this.error,
  });

  /// Whether more comments can be paginated from the server.
  bool get hasMore => nextCursor != null;

  CommentumDiscussionState copyWith({
    List<Comment>? comments,
    bool? isLoading,
    bool? isMoreLoading,
    String? nextCursor,
    String? error,
    bool clearError = false,
  }) {
    return CommentumDiscussionState(
      comments: comments ?? this.comments,
      isLoading: isLoading ?? this.isLoading,
      isMoreLoading: isMoreLoading ?? this.isMoreLoading,
      nextCursor: nextCursor ?? this.nextCursor,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Self-contained controller that manages state, pagination, optimistic UI updates, and tree mutations
/// for a media item's comment discussion.
class CommentumDiscussionController {
  final CommentumClient client;
  final String mediaId;
  final String mediaProvider;

  CommentumDiscussionState _state = const CommentumDiscussionState();
  final _stateController = StreamController<CommentumDiscussionState>.broadcast();

  CommentumDiscussionController({
    required this.client,
    required this.mediaId,
    required this.mediaProvider,
  });

  /// The current snapshot state of the discussion.
  CommentumDiscussionState get state => _state;

  /// Stream of state updates for UI binding.
  Stream<CommentumDiscussionState> get stream => _stateController.stream;

  void _updateState(CommentumDiscussionState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  /// Loads the initial list of comments.
  Future<void> loadInitial({int limit = 20, int? episodeNumber}) async {
    _updateState(_state.copyWith(isLoading: true, clearError: true));
    try {
      await client.init();
      final response = await client.listComments(
        mediaId: mediaId,
        limit: limit,
        episodeNumber: episodeNumber,
      );
      _updateState(_state.copyWith(
        comments: response.data,
        isLoading: false,
        nextCursor: response.nextCursor,
      ));
    } catch (e) {
      _updateState(_state.copyWith(
        isLoading: false,
        error: e.toString(),
      ));
    }
  }

  /// Paginates and appends more comments to the list.
  Future<void> loadMore({int limit = 20, int? episodeNumber}) async {
    if (_state.isLoading || _state.isMoreLoading || _state.nextCursor == null) return;

    _updateState(_state.copyWith(isMoreLoading: true, clearError: true));
    try {
      final response = await client.listComments(
        mediaId: mediaId,
        limit: limit,
        cursor: _state.nextCursor,
        episodeNumber: episodeNumber,
      );
      _updateState(_state.copyWith(
        comments: [..._state.comments, ...response.data],
        isMoreLoading: false,
        nextCursor: response.nextCursor,
      ));
    } catch (e) {
      _updateState(_state.copyWith(
        isMoreLoading: false,
        error: 'Failed to load more comments: $e',
      ));
    }
  }

  /// Posts a top-level comment and prepends it to the discussion state.
  Future<Comment> postComment(String content, {int? episodeNumber}) async {
    final comment = await client.createComment(
      mediaId: mediaId,
      mediaProvider: mediaProvider,
      content: content,
      episodeNumber: episodeNumber,
    );
    _updateState(_state.copyWith(
      comments: [comment, ..._state.comments],
      clearError: true,
    ));
    return comment;
  }

  /// Posts a reply and inserts it into the correct location in the comment tree.
  Future<Comment> postReply(String parentId, String content) async {
    final reply = await client.createReply(parentId: parentId, content: content);
    final updated = CommentTreeUtils.insertReply(_state.comments, parentId, reply);
    _updateState(_state.copyWith(comments: updated, clearError: true));
    return reply;
  }

  /// Votes on a comment with immediate optimistic UI update and rollback on failure.
  Future<void> vote(String commentId, int voteType) async {
    final previousComments = _state.comments;
    final updated = CommentTreeUtils.updateVote(previousComments, commentId, voteType);
    _updateState(_state.copyWith(comments: updated));

    try {
      await client.voteComment(commentId: commentId, voteType: voteType);
    } catch (e) {
      // Rollback on failure
      _updateState(_state.copyWith(comments: previousComments, error: e.toString()));
      rethrow;
    }
  }

  /// Deletes a comment and removes it from the comment tree.
  Future<void> deleteComment(String commentId) async {
    await client.deleteComment(commentId: commentId);
    final updated = CommentTreeUtils.deleteComment(_state.comments, commentId);
    _updateState(_state.copyWith(comments: updated));
  }

  /// Closes the state stream.
  void dispose() {
    _stateController.close();
  }
}
