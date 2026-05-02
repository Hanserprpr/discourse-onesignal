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
  "externalIdAuthHash": "hmac-sha256-signature",
  "username": "alice",
  "appId": "onesignal-app-id"
}
```

Enable OneSignal Identity Verification in the OneSignal dashboard. This plugin
uses the existing Discourse site setting `onesignal_rest_api_key` to generate the
legacy `external_id_auth_hash` value for the current user's external id. OneSignal's
current Identity Verification docs describe a JWT-based flow, while the legacy
hash flow used by older SDKs does not expose a separate "identity verification
secret" setting; the HMAC key is the REST API key already configured for sending
notifications.

When this message is received, call OneSignal login with both the external id and
the server-generated auth hash. For SDKs that use the legacy auth-hash API this
looks like `OneSignal.login(externalId, externalIdAuthHash)`; if your SDK version
uses an options object, pass the same value as `external_id_auth_hash`. Do not
construct or accept arbitrary external ids in the mobile client. When the
Discourse user logs out or switches accounts, call `OneSignal.logout()` before
binding a different user.

If `/onesignal/identity.json` fails, the webview sends both
`onesignalIdentityError` (including a best-effort `status` and `message` payload)
and `onesignalLogout` messages so the native app can avoid leaving OneSignal
bound to a stale Discourse user.

Upgrade note: this plugin does not use a separate identity verification secret.
Legacy `external_id_auth_hash` values are signed with `onesignal_rest_api_key`.
If you previously tested a branch that introduced
`onesignal_identity_verification_secret`, that value is now ignored. Verify that
`onesignal_rest_api_key` matches the key expected by OneSignal for legacy HMAC
verification before deploying.

The old `/onesignal/subscribe.json` endpoint is still available for legacy
clients and debug registration. Its JSON response also includes `external_id`
and, when `onesignal_rest_api_key` is configured, `external_id_auth_hash`.
Delivery is now based on the OneSignal external id.

## Huawei notification categories

This plugin sends OneSignal's documented `huawei_category` field. The category is mapped
from Discourse's `notification_type` when available, and falls back to the
`onesignal_huawei_category` site setting. The fallback default is `MARKETING`,
for any notification type the plugin cannot identify. If the fallback setting is
blank and the plugin cannot map the notification type, the field is omitted.

| Huawei major category | Fine category number and type | huawei_category | Discourse notification types | Example |
| --- | --- | --- | --- | --- |
| 服务与通讯 > 社交通讯 | 1 即时聊天 | `IM` | `private_message`, `invited_to_private_message`, `group_message_summary`, `chat_message`, `chat_mention` | `李四 有新私信: 你好，方便看一下这个问题吗？` |
| 服务与通讯 > 服务提醒 | 3 订阅 | `SUBSCRIPTION` | `watching_first_post`, `topic_reminder`, `posted`, `invited_to_topic`, `mentioned`, `replied`, `quoted`, `group_mentioned`, `linked`, `liked`, `liked_consolidated`, `granted_badge`, `invitee_accepted` | `张三 有新回复: 我已经按教程配置好了...` |
| 服务与通讯 > 服务提醒 | 6 工作事项提醒 | `WORK` | `assigned`, `post_approved`, `admin_problems`, `membership_request_accepted` | `有新的审核任务: 用户提交的帖子需要处理` |
| 资讯营销 > 内容资讯 | 12 资讯营销/社交动态 | `MARKETING` | Unknown notification types only, through the fallback setting | `社区活动: 本周问答活动开始了` |

The current plugin does not generate Huawei travel, health, account, express,
finance, device reminder, mail, VoIP, progress, alarm, timer, stopwatch, or
location sharing categories.

Notification text is also formatted by type:

| Discourse notification type | Heading example | Body example |
| --- | --- | --- |
| `private_message` | `来自 李四 的私信` | `你好，方便看一下这个问题吗？` |
| `chat_message` | `来自 李四 的消息` | `我已经看到了` |
| `replied` | `插件安装后无法启动` | `张三 回复了你: 请检查一下配置是否填写正确。` |
| `mentioned` | `插件安装后无法启动` | `张三 提到了你: @alice 可以帮忙看一下吗？` |
| `liked` | `插件安装后无法启动` | `张三 赞了你的内容` |
| `watching_first_post` | `新插件发布` | `你关注的内容有更新: OneSignal 插件已更新。` |
| `assigned` | `待处理举报` | `你有新的待办事项: 用户提交的帖子需要审核。` |
