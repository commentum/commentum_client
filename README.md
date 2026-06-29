# Commentum Client

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Dart Platforms](https://img.shields.io/badge/platforms-flutter%20|%20dart-blue)](https://github.com/commentum/commentum_client)

A powerful, beginner-friendly, and stateful Dart & Flutter SDK for integrating community comment threads, nested replies, voting systems, and content moderation into your app.

---

## 🌟 Why Commentum Client?

Building a robust commenting system requires solving complex frontend challenges. **Commentum Client** handles these automatically so you can focus on building a great UI:

1. **Automatic UI State Management**: Managing nested comment trees (replies inside replies) is difficult. When a user posts a reply or votes, our built-in **Discussion Controller** automatically finds the exact node in the tree, inserts the reply, or performs an instant optimistic score update.
2. **Resilient Networking & Auto-Retry**: Mobile connections drop frequently. The client automatically catches timeouts and 5xx server errors, retrying requests with exponential backoff.
3. **Silent Session Recovery (Auto Re-Login)**: Authentication tokens expire over time. Instead of kicking users back to a login screen when their JWT token expires (HTTP 401), the client silently refreshes the token in the background and transparently retries their failed request.
4. **Multi-Account Support**: Users can link multiple identity providers (**AniList**, **MyAnimeList**, **Simkl**) simultaneously and switch commenting personas on the fly.

---

## 📑 Table of Contents

- [1. Installation](#1-installation)
- [2. Quick Start (Beginner Guide)](#2-quick-start-beginner-guide)
- [3. Step-by-Step Guide](#3-step-by-step-guide)
  - [Step 1: Initializing the Client](#step-1-initializing-the-client)
  - [Step 2: Displaying Comments in UI (Recommended)](#step-2-displaying-comments-in-ui-recommended)
  - [Step 3: Authentication & Multi-Account Login](#step-3-authentication--multi-account-login)
  - [Step 4: Persistent Token Storage (Production)](#step-4-persistent-token-storage-production)
- [4. Advanced & Manual Usage](#4-advanced--manual-usage)
  - [Direct API Calls](#direct-api-calls)
  - [Immutable Tree Utilities](#immutable-tree-utilities)
  - [Comment Extension Actions](#comment-extension-actions)
- [5. Error Handling](#5-error-handling)

---

## 1. Installation

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

## 2. Quick Start (Beginner Guide)

Here is the quickest way to get up and running with a complete comment thread in under 15 lines of code:

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

  // 2. Create a discussion controller for a specific anime/manga
  final controller = client.getDiscussionController(
    mediaId: '10123',
    mediaProvider: 'anilist',
  );

  // 3. Load initial comments
  await controller.loadInitial();

  // 4. Post a comment (automatically updates controller state!)
  await controller.postComment('This episode was legendary!');
}
```

---

## 3. Step-by-Step Guide

### Step 1: Initializing the Client

The `CommentumClient` acts as the central gateway to the backend. We configure it with a base URL, retry rules, and a storage engine.

> **Why do we need a Storage engine?**  
> Storage is what saves your users' login tokens across app restarts. For prototyping or tests, use `InMemoryCommentumStorage()`. For production mobile apps, use persistent storage (see [Step 4](#step-4-persistent-token-storage-production)).

```dart
final client = CommentumClient(
  config: const CommentumConfig(
    baseUrl: 'https://api.yourdomain.com/v1',
    appClient: 'my_flutter_app',
    enableLogging: true, // Prints network logs in debug mode
    autoRetry: true,     // Retries failed network requests automatically
    maxRetries: 2,       // Number of retry attempts before throwing error
  ),
  storage: InMemoryCommentumStorage(),
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

### Step 2: Displaying Comments in UI (Recommended)

Instead of manually writing loops to manage pagination cursors or tree insertion algorithms when a user replies to a comment, use `CommentumDiscussionController`. It wraps all UI state management into a clean stream.

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
    _controller.dispose(); // Always dispose controllers
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
                onPressed: () => _controller.vote(comment.id, 1), // Optimistic +1 vote!
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

### Step 3: Authentication & Multi-Account Login

Users must be authenticated to post comments or vote. Commentum relies on third-party OAuth tokens from platforms like **AniList** or **MyAnimeList**.

**Why Multi-Account?**  
Many users track anime on AniList but read manga on MyAnimeList. Commentum allows them to connect both accounts and switch which persona they comment under at any time.

```dart
// 1. Connect an account by passing the platform's OAuth access token
await client.auth.login(CommentumProvider.anilist, 'user_anilist_oauth_token');

// Check who is logged in
print('Logged in as: ${client.auth.loggedInProviders}'); // [CommentumProvider.anilist]

// 2. Connect a second account
await client.auth.login(CommentumProvider.myanimelist, 'user_mal_oauth_token');

// 3. Switch active commenting account
client.auth.switchProvider(CommentumProvider.myanimelist);

// 4. Get profiles for all connected accounts at once
final profiles = await client.auth.getAllLoggedInProfiles();
profiles.forEach((provider, user) {
  print('${provider.displayName}: Avatar URL is ${user.avatarUrl}');
});

// 5. Logout
await client.auth.logout(CommentumProvider.anilist); // Logout single
await client.auth.logoutAll();                        // Logout all
```

---

### Step 4: Persistent Token Storage (Production)

To ensure users stay logged in when they restart your app, implement the `CommentumStorage` interface using a package like `flutter_secure_storage` or `shared_preferences`.

By implementing `saveProviderToken` and `getProviderToken`, the SDK will automatically re-login users in the background if their backend JWT ever expires.

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:commentum_client/commentum_client.dart';

class SecureCommentumStorage implements CommentumStorage {
  final _storage = const FlutterSecureStorage();
  
  String _jwtKey(CommentumProvider p) => 'jwt_${p.name}';
  String _oauthKey(CommentumProvider p) => 'oauth_${p.name}';

  // Save & retrieve JWT session tokens
  @override
  Future<void> saveToken(CommentumProvider provider, String token) =>
      _storage.write(key: _jwtKey(provider), value: token);

  @override
  Future<String?> getToken(CommentumProvider provider) =>
      _storage.read(key: _jwtKey(provider));

  @override
  Future<void> deleteToken(CommentumProvider provider) =>
      _storage.delete(key: _jwtKey(provider));

  // Save & retrieve provider OAuth tokens (enables background auto re-login!)
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

## 4. Advanced & Manual Usage

If you prefer using Riverpod, BLoC, or custom state managers instead of `CommentumDiscussionController`, you can call raw API endpoints directly.

### Direct API Calls

All API endpoints use named parameters to guarantee type safety and prevent argument ordering errors.

```dart
// Fetch raw comments response
final response = await client.comments.listComments(
  mediaId: '10123',
  episodeNumber: 1, // Optional: filter by episode
  limit: 20,
);
List<Comment> rawComments = response.data;
String? nextCursor = response.nextCursor;

// Post comment manually
final comment = await client.comments.createComment(
  mediaId: '10123',
  mediaProvider: 'anilist',
  content: 'Manual comment posting!',
);

// Post reply manually
final reply = await client.comments.createReply(
  parentId: comment.id,
  content: 'Replying directly!',
);

// Cast vote manually (1 for upvote, -1 for downvote)
await client.interactions.voteComment(commentId: comment.id, voteType: 1);
```

### Immutable Tree Utilities

When building custom state reducers, use `CommentTreeUtils` to safely transform deeply nested comment trees without mutating existing arrays:

```dart
// Safely insert a new reply deep into a nested comment tree
final updatedList = CommentTreeUtils.insertReply(currentComments, parentId, newReply);

// Calculate optimistic score adjustments for voting (+1 or -1)
final votedList = CommentTreeUtils.updateVote(currentComments, commentId, 1);

// Remove a deleted comment from the hierarchy
final filteredList = CommentTreeUtils.deleteComment(currentComments, commentId);
```

### Comment Extension Actions

Any `Comment` object has convenience extension methods attached to it:

```dart
final comment = rawComments.first;

await comment.upVote(client);             // Upvote (+1)
await comment.downVote(client);           // Downvote (-1)
await comment.report(client, 'Spoiler');  // Report to moderators
await comment.delete(client);             // Delete comment
```

---

## 5. Error Handling

The SDK throws structured exceptions so you can display precise feedback to your users:

```dart
try {
  await client.comments.createComment(
    mediaId: '101',
    mediaProvider: 'anilist',
    content: '', // Empty content throws validation error
  );
} on CommentumValidationException catch (e) {
  print('Input Error: ${e.message}');
} on CommentumAuthException catch (e) {
  print('Auth Error [${e.statusCode}]: Please log in to comment.');
} on CommentumServerException catch (e) {
  print('Server Error [${e.statusCode}]: ${e.message}');
} on CommentumNetworkException catch (e) {
  print('Network Error: Check your internet connection.');
}
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.