## 1.0.0

* Initial release

## 1.0.1

* Added verbose logging option

## 1.0.2

* Added client parameter to createComment and createReply methods

## 1.0.3

* Updated Comment model with unified structure fields
* Added CommentumResponse wrapper with count and nextCursor
* Added Comment extension methods for voting, deleting, and reporting

## 1.0.4
* Added support for initializing the client with a preferred media provider.
* Updated the Comment model to include `media_provider` field.
* Updated `Client.createComment()` to accept a `mediaProvider` parameter.