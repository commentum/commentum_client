# Commentum Client

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Dart Platforms](https://img.shields.io/badge/platforms-flutter%20|%20dart-blue)](https://github.com/commentum/commentum_client)

A Dart and Flutter SDK for integrating comment threads, nested replies, voting systems, and content moderation. Features automatic UI state management, network retries, and multi-account session recovery.

---

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Step-by-Step Guide](#step-by-step-guide)
  - [1. Initializing the Client](#1-initializing-the-client)
  - [2. Displaying Comments in UI](#2-displaying-comments-in-ui)
  - [3. Authentication & Multi-Account Login](#3-authentication--multi-account-login)
  - [4. Persistent Token Storage](#4-persistent-token-storage)
- [Advanced & Manual Usage](#advanced--manual-usage)
  - [Direct API Calls](#direct-api-calls)
  - [Immutable Tree Utilities](#immutable-tree-utilities)
  - [Comment Extension Actions](#comment-extension-actions)
- [Error Handling](#error-handling)

---

## Installation

Add `commentum_client` to your `pubspec.yaml` referencing your Git repository or local package path:

**Using Git URL:**
```yaml
dependencies:
  commentum_client:
    git:
      url: https://github.com/commentum/commentum_client.git
```

**Using Local Submodule Path:**
```yaml
dependencies:
  commentum_client:
    path: packages/commentum_client
```

---

## Quick Start

```dart
import 'package:commentum_client/commentum_client.dart';

// 1. Create client with in-memory storage for quick testing
final client = CommentumClient(
  config: const CommentumConfig(baseUrl: 'https://api.yourdomain.com/v1'),
  storage: InMemoryCommentumStorage(),
  preferredProvider: CommentumProvider.anilist,
);

void main() async {
  await client.init(); // Hydrate sessions

  // 2. Create a discussion controller for a specific media item
  final controller = client.getDiscussionController(
    mediaId: '10123',
    mediaProvider: 'anilist',
  );

  // 3. Load initial comments
  await controller.loadInitial();

  // 4. Post a comment (automatically updates controller state)
  await controller.postComment('Great episode!');
}
```

---

## Step-by-Step Guide

### 1. Initializing the Client

Configure the client with your API base URL, automatic retry options, and token storage engine.

```dart
final client = CommentumClient(
  config: const CommentumConfig(
    baseUrl: 'https://api.yourdomain.com/v1',
    appClient: 'my_flutter_app',
    enableLogging: true, // Prints network logs in debug mode
    autoRetry: true,     // Retries failed network requests automatically
    maxRetries: 2,       // Number of retry attempts before throwing error
  ),
  storage: InMemoryCommentumStorage(), // Use persistent storage for production
  preferredProvider: CommentumProvider.anilist,
  
  // Optional: Callback triggered when a session expires to fetch a fresh token
  onProviderTokenRefreshRequired: (provider) async {
    return await myOAuthService.getFreshToken(provider);
  },
);

// Call init() once at app startup before rendering UI
await client.init();
```

---

### 2. Displaying Comments in UI

The `CommentumDiscussionController` manages loading states, pagination cursors, reply tree insertions, and optimistic vote score updates automatically.

**Controller State Properties:**
* `state.comments`: List of top-level comments (each containing nested `replies`).
* `state.isLoading`: `true` during the initial load.
* `state.isMoreLoading`: `true` while paginating more comments.
* `state.hasMore`: `true` if there are more comments available to load.
* `state.error`: Error message string if a request failed.

**Example Flutter Widget:**

```dart
class CommentsSection extends StatefulWidget {
  final String mediaId;
  const CommentsSection({super.key, required this.mediaId});

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  late final CommentumDiscussionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = client.getDiscussionController(
      mediaId: widget.mediaId,
      mediaProvider: 'anilist',
    );
    _controller.loadInitial(); // Fetch first 20 comments
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CommentumDiscussionState>(
      stream: _controller.stream,
      initialData: _controller.state,
      builder: (context, snapshot) {
        final state = snapshot.data!;

        if (state.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state.error != null && state.comments.isEmpty) {
          return Center(child: Text('Error: ${state.error}'));
        }

        return ListView.builder(
          itemCount: state.comments.length + (state.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == state.comments.length) {
              return TextButton(
                onPressed: () => _controller.loadMore(),
                child: const Text('Load More Comments'),
              );
            }

            final comment = state.comments[index];
            return ListTile(
              title: Text(comment.user?.username ?? 'Anonymous'),
              subtitle: Text(comment.content),
              trailing: IconButton(
                icon: const Icon(Icons.thumb_up),
                onPressed: () => _controller.vote(comment.id, 1),
              ),
            );
          },
        );
      },
    );
  }
}
```

---

### 3. Authentication & Multi-Account Login

Authenticate users using OAuth access tokens from providers like AniList or MyAnimeList. Multiple accounts can be connected simultaneously.

```dart
// Connect an account by passing the platform's OAuth access token
await client.auth.login(CommentumProvider.anilist, 'user_anilist_oauth_token');

// Connect a second account
await client.auth.login(CommentumProvider.myanimelist, 'user_mal_oauth_token');

// Check logged-in providers
print('Logged in as: ${client.auth.loggedInProviders}');

// Switch active commenting account
client.auth.switchProvider(CommentumProvider.myanimelist);

// Get profiles for all connected accounts
final profiles = await client.auth.getAllLoggedInProfiles();
profiles.forEach((provider, user) {
  print('${provider.displayName}: ${user.username}');
});

// Logout
await client.auth.logout(CommentumProvider.anilist); // Logout single
await client.auth.logoutAll();                        // Logout all
```

---

### 4. Persistent Token Storage

To persist sessions across app launches and support background token refresh, implement `CommentumStorage` using secure storage.

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:commentum_client/commentum_client.dart';

class SecureCommentumStorage implements CommentumStorage {
  final _storage = const FlutterSecureStorage();
  
  String _jwtKey(CommentumProvider p) => 'jwt_${p.name}';
  String _oauthKey(CommentumProvider p) => 'oauth_${p.name}';

  @override
  Future<void> saveToken(CommentumProvider provider, String token) =>
      _storage.write(key: _jwtKey(provider), value: token);

  @override
  Future<String?> getToken(CommentumProvider provider) =>
      _storage.read(key: _jwtKey(provider));

  @override
  Future<void> deleteToken(CommentumProvider provider) =>
      _storage.delete(key: _jwtKey(provider));

  @override
  Future<void> saveProviderToken(CommentumProvider provider, String token) =>
      _storage.write(key: _oauthKey(provider), value: token);

  @override
  Future<String?> getProviderToken(CommentumProvider provider) =>
      _storage.read(key: _oauthKey(provider));

  @override
  Future<void> deleteProviderToken(CommentumProvider provider) =>
      _storage.delete(key: _oauthKey(provider));

  @override
  Future<Map<CommentumProvider, String>> getAllTokens() async {
    final map = <CommentumProvider, String>{};
    for (final p in CommentumProvider.values) {
      final t = await getToken(p);
      if (t != null && t.isNotEmpty) map[p] = t;
    }
    return map;
  }

  @override
  Future<void> clearAll() async {
    for (final p in CommentumProvider.values) {
      await deleteToken(p);
      await deleteProviderToken(p);
    }
  }
}
```

---

## Advanced & Manual Usage

If you prefer using custom state managers (like Riverpod or BLoC) instead of `CommentumDiscussionController`, you can call API methods directly.

### Direct API Calls

```dart
// Fetch comments
final response = await client.comments.listComments(
  mediaId: '10123',
  episodeNumber: 1, // Optional filter
  limit: 20,
);
List<Comment> comments = response.data;
String? nextCursor = response.nextCursor;

// Post top-level comment
final comment = await client.comments.createComment(
  mediaId: '10123',
  mediaProvider: 'anilist',
  content: 'Direct API posting!',
);

// Post reply
final reply = await client.comments.createReply(
  parentId: comment.id,
  content: 'Replying directly!',
);

// Vote (1 for upvote, -1 for downvote)
await client.interactions.voteComment(commentId: comment.id, voteType: 1);
```

### Immutable Tree Utilities

Use `CommentTreeUtils` to safely transform nested comment hierarchies without mutating state:

```dart
// Insert reply into nested tree
final updatedList = CommentTreeUtils.insertReply(currentComments, parentId, newReply);

// Optimistically update vote score
final votedList = CommentTreeUtils.updateVote(currentComments, commentId, 1);

// Remove deleted comment from tree
final filteredList = CommentTreeUtils.deleteComment(currentComments, commentId);
```

### Comment Extension Actions

Convenience interaction methods available directly on `Comment` instances:

```dart
final comment = comments.first;

await comment.upVote(client);
await comment.downVote(client);
await comment.report(client, 'Spoiler');
await comment.delete(client);
```

---

## Error Handling

```dart
try {
  await client.comments.createComment(
    mediaId: '101',
    mediaProvider: 'anilist',
    content: '',
  );
} on CommentumValidationException catch (e) {
  print('Validation Error: ${e.message}');
} on CommentumAuthException catch (e) {
  print('Auth Error [${e.statusCode}]: Please log in.');
} on CommentumServerException catch (e) {
  print('Server Error [${e.statusCode}]: ${e.message}');
} on CommentumNetworkException catch (e) {
  print('Network Error: Check internet connection.');
}
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.