# discourse-onesignal

Discourse push notifications through [Orbithy Notify](https://github.com/Hanserprpr/orbithy-notify).

The plugin keeps the historical `/onesignal/*` routes and `DiscourseOnesignal`
JavaScript object for mobile-app compatibility, but the backend now talks to
Orbithy Notify.

## Settings

Enable the plugin with:

- `orbithy_notify_enabled`
- `orbithy_notify_api_url`, for example `http://localhost:8080`
- `orbithy_notify_app_id`
- `orbithy_notify_app_secret`
- `orbithy_notify_push_category`, fallback category for unknown notification types

Orbithy Notify signs external API requests with:

```text
METHOD
/path
timestamp
sha256(body)
```

The plugin sends `X-App-Id`, `X-Timestamp`, and `X-Signature` headers for both
device registration and push delivery.

## Mobile WebView Bridge

When a logged-in user opens Discourse inside the app, the plugin posts an
`orbithyNotifyIdentity` message:

```json
{
  "externalId": "discourse-user-123",
  "externalIdAuthHash": "hmac-sha256-signature",
  "userId": 123,
  "username": "alice",
  "appId": "app_dev",
  "apiUrl": "https://notify.example.com"
}
```

For legacy app builds, the same payload is also sent as `onesignalIdentity`.
Logout/error compatibility messages are also preserved:

- `orbithyNotifyLogout` and `onesignalLogout`
- `orbithyNotifyIdentityError` and `onesignalIdentityError`

Native apps can register push tokens through either bridge:

```js
window.DiscourseOrbithyNotify.registerDevice(
  token,
  "android",
  "My App",
  null,
  "hms",
  "Mate 60",
  "1.0.0"
);
```

The legacy call still works:

```js
window.DiscourseOnesignal.subscribeDeviceToken(token, platform, applicationName);
```

Both call `/onesignal/subscribe.json`, store the local legacy subscription
record, and register the device with Orbithy Notify at
`/api/v1/device/register`.

## Push Delivery

Discourse notification jobs call Orbithy Notify at `/api/v1/push/send` using its
OneSignal-compatible request shape:

```json
{
  "target_channel": "push",
  "include_aliases": {
    "external_id": ["discourse-user-123"]
  },
  "headings": {
    "en": "插件安装后无法启动"
  },
  "contents": {
    "en": "张三 回复了你: 请检查一下配置是否填写正确。"
  },
  "data": {
    "discourse_url": "/t/topic/123"
  },
  "notification_type": "replied",
  "push_category": "SUBSCRIPTION",
  "ios_badgeType": "Increase",
  "ios_badgeCount": "1"
}
```

Orbithy accepts `discourse-user-{id}` external IDs directly.

## Notification Categories

The plugin maps Discourse notification types to Orbithy `push_category`.
Orbithy applies the vendor-specific HMS/HONOR category behavior.

| Category | Discourse notification types |
| --- | --- |
| `IM` | `private_message`, `invited_to_private_message`, `group_message_summary`, `chat_message`, `chat_mention` |
| `SUBSCRIPTION` | `watching_first_post`, `topic_reminder`, `posted`, `invited_to_topic`, `mentioned`, `replied`, `quoted`, `group_mentioned`, `linked`, `liked`, `liked_consolidated`, `granted_badge`, `invitee_accepted` |
| `WORK` | `assigned`, `post_approved`, `admin_problems`, `membership_request_accepted` |
| `MARKETING` | Unknown notification types, through the fallback setting |

Notification text is also formatted by type:

| Discourse notification type | Heading example | Body example |
| --- | --- | --- |
| `private_message` | `来自 李四 的私信` | `你好，方便看一下这个问题吗？` |
| `chat_message` | `来自 李四 的消息` | `我已经看到了` |
| `replied` | `插件安装后无法启动` | `张三 回复了你: 请检查一下配置是否填写正确。` |
| `mentioned` | `插件安装后无法启动` | `张三 提到了你: @alice 可以帮忙看一下吗？` |
| `liked` | `插件安装后无法启动` | `张三 赞了你的内容` |
| `watching_first_post` | `新插件发布` | `你关注的内容有更新: Orbithy Notify 插件已更新。` |
| `assigned` | `待处理举报` | `你有新的待办事项: 用户提交的帖子需要审核。` |
