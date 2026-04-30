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

## Huawei notification categories

This plugin sends OneSignal's `Huawei_category` field. The category is mapped
from Discourse's `notification_type` when available, and falls back to the
`onesignal_huawei_category` site setting. The fallback default is `MARKETING`,
for any notification type the plugin cannot identify.

| Huawei major category | Fine category number and type | Huawei_category | Discourse notification types | Example |
| --- | --- | --- | --- | --- |
| 服务与通讯 > 社交通讯 | 1 即时聊天 | `IM` | `private_message`, `invited_to_private_message`, `group_message_summary`, `chat_message`, `chat_mention` | `李四 有新私信: 你好，方便看一下这个问题吗？` |
| 服务与通讯 > 服务提醒 | 3 订阅 | `SUBSCRIPTION` | `watching_first_post`, `topic_reminder`, `posted`, `invited_to_topic`, `mentioned`, `replied`, `quoted`, `group_mentioned`, `linked`, `liked`, `liked_consolidated`, `granted_badge`, `invitee_accepted` | `张三 有新回复: 我已经按教程配置好了...` |
| 服务与通讯 > 服务提醒 | 6 工作事项提醒 | `WORK` | `assigned`, `post_approved`, `admin_problems`, `membership_request_accepted` | `有新的审核任务: 用户提交的帖子需要处理` |
| 资讯营销 > 内容资讯 | 12 资讯营销/社交动态 | `MARKETING` | Unknown notification types only, through the fallback setting | `社区活动: 本周问答活动开始了` |

The current plugin does not generate Huawei travel, health, account, express,
finance, device reminder, mail, VoIP, progress, alarm, timer, stopwatch, or
location sharing categories.
