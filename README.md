# Commentum Client

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Dart Platforms](https://img.shields.io/badge/platforms-flutter%20|%20dart-blue)](https://pub.dev/packages/commentum_client)

A robust, type-safe, and modular Dart client for the **Commentum API**.

This package provides a complete interface for integrating comment threads, voting systems, and moderation tools into Dart and Flutter applications. It features a storage-agnostic architecture, enabling seamless integration with `flutter_secure_storage`, `hive`, or `shared_preferences`.

---

## 📑 Table of Contents

- [Features](#-features)
- [Installation](#-installation)
- [Getting Started](#-getting-started)
  - [1. Implement Storage](#1-implement-storage)
  - [2. Initialize Client](#2-initialize-client)
- [Usage](#-usage)
  - [Authentication](#authentication)
  - [Comments & Threads](#comments--threads)
  - [Interactions (Votes & Reports)](#interactions-votes--reports)
  - [Extensions](#-extensions)
- [Error Handling](#-error-handling)
- [Advanced Configuration](#-advanced-configuration)

---

## ✨ Features

* **Multi-Provider Authentication**: Native support for **AniList**, **MyAnimeList**, and **Simkl** OAuth flows.
* **Automatic Token Management**: Handles JWT storage, injection, and session lifecycle automatically.
* **Type-Safe Models**: Fully typed responses for `Comment`, `User`, and `Reply` objects.
* **Cursor Pagination**: Built-in support for efficient, infinite-scroll pagination.
* **Optimistic UI Ready**: Returns standardized objects that make optimistic UI updates easy to implement.
* **Platform Agnostic**: Works in Flutter, AngularDart, or pure Dart CLIs.

---

## 📦 Installation

Add `commentum_client` to your `pubspec.yaml`:

```yaml
dependencies:
  commentum_client:
    path: ../packages/commentum_client # or git url
```

---

## 🚀 Getting Started

### 1. Implement Storage

To keep the package platform-agnostic, you must provide a storage implementation for persisting authentication tokens.

*Example using `flutter_secure_storage`:*

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:commentum_client/commentum_client.dart';

class SecureTokenStorage implements CommentumStorage {
  final _storage = const FlutterSecureStorage();
  
  String _key(CommentumProvider p) => 'commentum_token_${p.name}';

  @override
  Future<void> saveToken(CommentumProvider provider, String token) =>
      _storage.write(key: _key(provider), value: token);

  @override
  Future<String?> getToken(CommentumProvider provider) =>
      _storage.read(key: _key(provider));

  @override
  Future<void> deleteToken(CommentumProvider provider) =>
      _storage.delete(key: _key(provider));
}
```

### 2. Initialize Client

Create a global instance of the client (using Riverpod, GetIt, or Provider) and initialize it at app startup.

```dart
final client = CommentumClient(
  config: const CommentumConfig(
    baseUrl: 'https://<SUPABASE_API>.supabase.co/functions/v1',
    enableLogging: true, // Disable in production
  ),
  storage: SecureTokenStorage(),
  preferredProvider: CommentumProvider.anilist
);

void main() async {
  // Hydrate authentication state from storage
  await client.init();
  runApp(MyApp());
}
```

---

## 💻 Usage

### Authentication

Exchange a third-party access token (e.g., from Simkl OAuth) for a Commentum session. The client caches the result automatically.

```dart
try {
  // Login with Simkl
  await client.login(CommentumProvider.simkl, 'simkl_access_token');
  
  print('Logged in successfully!');
} on CommentumError catch (e) {
  print('Login failed: ${e.message}');
}

// Check login status
if (client.isLoggedIn) {
  final user = await client.getMe();
}

// Logout
await client.logout();
```

### Comments & Threads

**Fetching Comments (Root Level)**
```dart
final response = await client.listComments(
  'media_id_101', 
  limit: 20,
);

final comments = response.data;
final totalCount = response.count;
final nextCursor = response.nextCursor; // Use for infinite scroll
```

**Fetching Replies (Threaded)**
```dart
final response = await client.listReplies(
  'root_comment_id',
  limit: 10,
);

final replies = response.data;
```

**Posting a Comment**
```dart
final newComment = await client.createComment(
  'media_id_101', 
  'anilist',
  'This episode was a masterpiece!',
  client: 'my_app_v1',
);
```

**Replying to a Comment**
```dart
final reply = await client.createReply(
  'parent_comment_id',
  'I completely agree.',
  client: 'my_app_v1',
);
```

### Interactions (Votes & Reports)

You can interact with comments directly using the extension methods:

```dart
// Vote
await comment.upVote(client);
await comment.downVote(client);
await comment.removeVote(client);

// Delete
await comment.delete(client);

// Report
await comment.report(client, 'Contains unmarked spoilers');
```

Alternatively, use the client methods directly:

**Voting**
```dart
// Upvote
await client.voteComment('comment_id', 1);

// Downvote
await client.voteComment('comment_id', -1);

// Remove Vote
await client.voteComment('comment_id', 0);
```

**Reporting Content**
```dart
await client.reportComment(
  commentId: 'comment_id',
  reason: 'Contains unmarked spoilers',
);
```

---

## 🧩 Extensions

The package includes helpful extensions on the `Comment` model to simplify interactions.

### CommentActions

Methods available on `Comment` instances:

*   `upVote(CommentumClient client)`: Upvote the comment.
*   `downVote(CommentumClient client)`: Downvote the comment.
*   `removeVote(CommentumClient client)`: Remove your vote.
*   `report(CommentumClient client, String reason)`: Report the comment.
*   `delete(CommentumClient client)`: Delete the comment.

**Example:**

```dart
final comment = response.data.first;

// Easy interaction
await comment.upVote(client);
```

---

## ⚠️ Error Handling

All API methods throw a `CommentumError` when operations fail.

```dart
try {
  await client.createComment('101', 'Hello');
} on CommentumError catch (e) {
  switch (e.status) {
    case 401:
      // Handle session expiry
      break;
    case 429:
      // Handle rate limiting
      break;
    default:
      // Handle generic errors
      print('Error: ${e.message}');
  }
} catch (e) {
  // Handle network/connection errors
}
```

---

## 🛠 Advanced Configuration

You can customize the underlying HTTP client for testing or interceptors (e.g., using `http.Client` wrappers or `MockClient`).

```dart
final client = CommentumClient(
  config: CommentumConfig(
    baseUrl: '...',
    connectTimeout: Duration(seconds: 30),
  ),
  storage: storage,
  httpClient: CustomHttpClient(), // Inject custom client here
);
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.