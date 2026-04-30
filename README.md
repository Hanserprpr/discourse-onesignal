# discourse-onesignal

See https://meta.discourse.org/t/whiltelisted-discourse-app-with-push-notifications-via-onesignal/58247 

## Current OneSignal integration

This plugin targets the current OneSignal user model. Discourse sends push
notifications through `https://api.onesignal.com/notifications` using
`include_aliases.external_id`.

The mobile app should initialize the OneSignal SDK and listen for the webview
message named `onesignalIdentity`. Its payload is:

```json
{
  "externalId": "discourse-user-123",
  "username": "alice",
  "appId": "onesignal-app-id"
}
```

When this message is received, call `OneSignal.login(externalId)`. When the
Discourse user logs out or switches accounts, call `OneSignal.logout()` before
binding a different user. The old `/onesignal/subscribe.json` endpoint is still
available for legacy clients and debug registration, but delivery is now based
on the OneSignal external id.
