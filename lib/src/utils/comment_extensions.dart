import '../commentum_client.dart';
import '../models/comment.dart';

extension CommentActions on Comment {
  /// Upvotes this comment (+1). Sending twice toggles/removes upvote.
  Future<void> upVote(CommentumClient client) async {
    await client.interactions.upvote(commentId: id);
  }

  /// Downvotes this comment (-1). Sending twice toggles/removes downvote.
  Future<void> downVote(CommentumClient client) async {
    await client.interactions.downvote(commentId: id);
  }

  /// Permanently deletes this comment.
  Future<void> delete(CommentumClient client) async {
    await client.comments.deleteComment(commentId: id);
  }

  /// Reports this comment to moderators.
  Future<void> report(CommentumClient client, String reason) async {
    await client.interactions.reportComment(commentId: id, reason: reason);
  }
}
