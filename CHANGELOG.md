## 1.2.0

* **Automatic Retries & Token Relogin**: Added `autoRetry`, `maxRetries`, and `retryDelay` to `CommentumConfig` for automatic network error retries.
* Added silent token re-login loop upon receiving HTTP 401 expiration responses via `onProviderTokenRefreshRequired` callback and provider token storage.
* **Stateful Discussion Controller**: Added `CommentumDiscussionController` and `CommentTreeUtils` to automatically manage loading, pagination, tree insertions for replies, optimistic voting updates, and deletions.
* Added `saveProviderToken`, `getProviderToken`, and `deleteProviderToken` to `CommentumStorage` interface.
