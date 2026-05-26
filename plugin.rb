# name: discourse-onesignal
# about: Push notifications via the Orbithy Notify API.
# version: 2.0
# authors: pmusaraj
# url: https://github.com/pmusaraj/discourse-onesignal

require "digest"
require "net/http"
require "json"
require "openssl"
require "set"

enabled_site_setting :orbithy_notify_enabled

register_asset 'stylesheets/common/app-login.scss'
register_asset 'stylesheets/mobile/app-login.scss', :mobile

load File.expand_path('lib/discourse-onesignal/engine.rb', __dir__)

module ::DiscourseOnesignal
  ORBITHY_PUSH_SEND_PATH = "/api/v1/push/send"
  ORBITHY_DEVICE_REGISTER_PATH = "/api/v1/device/register"

  HUAWEI_CATEGORY_BY_NOTIFICATION_TYPE = {
    "private_message" => "IM",
    "invited_to_private_message" => "IM",
    "group_message_summary" => "IM",
    "chat_message" => "IM",
    "chat_mention" => "IM",
    "watching_first_post" => "SUBSCRIPTION",
    "topic_reminder" => "SUBSCRIPTION",
    "posted" => "SUBSCRIPTION",
    "invited_to_topic" => "SUBSCRIPTION",
    "mentioned" => "SUBSCRIPTION",
    "replied" => "SUBSCRIPTION",
    "quoted" => "SUBSCRIPTION",
    "group_mentioned" => "SUBSCRIPTION",
    "linked" => "SUBSCRIPTION",
    "liked" => "SUBSCRIPTION",
    "liked_consolidated" => "SUBSCRIPTION",
    "granted_badge" => "SUBSCRIPTION",
    "invitee_accepted" => "SUBSCRIPTION",
    "assigned" => "WORK",
    "post_approved" => "WORK",
    "admin_problems" => "WORK",
    "membership_request_accepted" => "WORK",
  }

  PRIVATE_MESSAGE_NOTIFICATION_TYPES = Set.new(
    %w[
      private_message
      invited_to_private_message
      group_message_summary
      chat_message
      chat_mention
    ],
  )

  DIRECT_MESSAGE_NOTIFICATION_TYPES = Set.new(
    %w[
      private_message
      invited_to_private_message
    ],
  )

  CHAT_NOTIFICATION_TYPES = Set.new(
    %w[
      chat_message
      chat_mention
    ],
  )

  def self.external_id_for(user_id)
    "discourse-user-#{user_id}"
  end

  def self.external_id_auth_hash_for(user_id)
    secret = SiteSetting.orbithy_notify_app_secret
    return if secret.blank?

    OpenSSL::HMAC.hexdigest("SHA256", secret, external_id_for(user_id))
  end

  def self.push_heading_for(payload)
    username = payload["username"] || payload[:username]
    topic_title = payload["topic_title"] || payload[:topic_title]
    notification_type = notification_type_name(payload)

    if DIRECT_MESSAGE_NOTIFICATION_TYPES.include?(notification_type) && username.present?
      "来自 #{username} 的私信"
    elsif CHAT_NOTIFICATION_TYPES.include?(notification_type) && username.present?
      "来自 #{username} 的消息"
    elsif notification_type == "group_message_summary"
      "群组有新消息"
    else
      topic_title
    end
  end

  def self.push_content_for(payload)
    username = payload["username"] || payload[:username]
    excerpt = payload["excerpt"] || payload[:excerpt]
    notification_type = notification_type_name(payload)

    if private_message_notification?(payload)
      excerpt
    else
      case notification_type
      when "mentioned", "group_mentioned"
        push_sentence(username, "提到了你", excerpt)
      when "replied"
        push_sentence(username, "回复了你", excerpt)
      when "quoted"
        push_sentence(username, "引用了你的内容", excerpt)
      when "linked"
        push_sentence(username, "链接了你的内容", excerpt)
      when "liked", "liked_consolidated"
        push_sentence(username, "赞了你的内容", excerpt)
      when "watching_first_post", "posted"
        push_sentence(nil, "你关注的内容有更新", excerpt)
      when "topic_reminder"
        push_sentence(nil, "话题提醒", excerpt)
      when "invited_to_topic"
        push_sentence(username, "邀请你查看话题", excerpt)
      when "assigned"
        push_sentence(nil, "你有新的待办事项", excerpt)
      when "post_approved"
        push_sentence(nil, "你的内容已通过审核", excerpt)
      when "admin_problems"
        push_sentence(nil, "站点有新的管理提醒", excerpt)
      when "membership_request_accepted"
        push_sentence(nil, "你的加入申请已通过", excerpt)
      when "granted_badge"
        push_sentence(nil, "你获得了新徽章", excerpt)
      when "invitee_accepted"
        push_sentence(username, "接受了你的邀请", excerpt)
      else
        push_sentence(username, "有新通知", excerpt)
      end
    end
  end

  def self.push_sentence(username, action, excerpt)
    subject = username.present? ? "#{username} #{action}" : action
    excerpt.present? ? "#{subject}: #{excerpt}" : subject
  end

  def self.push_category_for(payload)
    notification_type = notification_type_name(payload)

    HUAWEI_CATEGORY_BY_NOTIFICATION_TYPE.fetch(
      notification_type,
      SiteSetting.orbithy_notify_push_category,
    )
  end

  def self.add_push_category!(params, payload)
    push_category = push_category_for(payload)
    return if push_category.blank?

    params["push_category"] = push_category
  end

  def self.notification_type_name(payload)
    notification_type =
      payload["notification_type"] ||
      payload[:notification_type] ||
      payload["notification_type_name"] ||
      payload[:notification_type_name]

    return if notification_type.blank?

    if notification_type.to_s.match?(/\A\d+\z/) && defined?(::Notification)
      notification_type_id = notification_type.to_i
      return ::Notification.types.key(notification_type_id).to_s if ::Notification.respond_to?(:types)
    end

    notification_type.to_s
  end

  def self.private_message_notification?(payload)
    PRIVATE_MESSAGE_NOTIFICATION_TYPES.include?(notification_type_name(payload))
  end

  def self.orbithy_api_base_url
    SiteSetting.orbithy_notify_api_url.to_s.sub(%r{/*\z}, "")
  end

  def self.orbithy_uri_for(path)
    URI.parse("#{orbithy_api_base_url}#{path}")
  end

  def self.orbithy_signature(method, path, timestamp, body)
    body_hash = Digest::SHA256.hexdigest(body)
    canonical = [method.upcase, path, timestamp, body_hash].join("\n")
    OpenSSL::HMAC.hexdigest("SHA256", SiteSetting.orbithy_notify_app_secret, canonical)
  end

  def self.orbithy_json_request(method, path, body)
    uri = orbithy_uri_for(path)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == "https"

    body_json = body.as_json.to_json
    timestamp = Time.now.to_i.to_s
    signature = orbithy_signature(method, uri.path, timestamp, body_json)

    request_class = method.to_s.upcase == "POST" ? Net::HTTP::Post : Net::HTTP::Get
    request =
      request_class.new(
        uri.request_uri,
        "Content-Type" => "application/json;charset=utf-8",
        "X-App-Id" => SiteSetting.orbithy_notify_app_id,
        "X-Timestamp" => timestamp,
        "X-Signature" => signature,
      )
    request.body = body_json

    http.request(request)
  end
end

after_initialize do

  User.class_eval do
    has_many :onesignal_subscriptions, dependent: :delete_all
  end

  DiscourseEvent.on(:post_notification_alert) do |user, payload|
    if SiteSetting.orbithy_notify_api_url.blank?
      Rails.logger.warn("Orbithy Notify API URL is missing")
      next
    end

    if SiteSetting.orbithy_notify_app_id.blank?
      Rails.logger.warn("Orbithy Notify App ID is missing")
      next
    end

    if SiteSetting.orbithy_notify_app_secret.blank?
      Rails.logger.warn("Orbithy Notify App Secret is missing")
      next
    end

    Jobs.enqueue(
      :onesignal_pushnotification,
      payload: payload,
      user_id: user.id,
      username: user.username,
    )
  end

  module ::Jobs
    class OnesignalPushnotification < ::Jobs::Base
      def execute(args)
        payload = args["payload"]
        user_id = args["user_id"]

        if user_id.blank?
          Rails.logger.warn("Orbithy Notify push skipped: missing user_id")
          return
        end

        post_url = payload["post_url"] || payload[:post_url]
        external_id = ::DiscourseOnesignal.external_id_for(user_id)

        params = {
          "target_channel" => "push",
          "include_aliases" => {
            "external_id" => [external_id],
          },
          "contents" => {"en" => ::DiscourseOnesignal.push_content_for(payload)},
          "headings" => {"en" => ::DiscourseOnesignal.push_heading_for(payload)},
          "data" => {"discourse_url" => post_url},
          "notification_type" => ::DiscourseOnesignal.notification_type_name(payload),
          "ios_badgeType" => "Increase",
          "ios_badgeCount" => "1",
        }

        ::DiscourseOnesignal.add_push_category!(params, payload)
        params.compact!
        push_category = params["push_category"]

        response =
          ::DiscourseOnesignal.orbithy_json_request(
            "POST",
            ::DiscourseOnesignal::ORBITHY_PUSH_SEND_PATH,
            params,
          )

        case response
        when Net::HTTPSuccess
          response_body = JSON.parse(response.body.presence || "{}") rescue {}

          if response_body["messageId"].present?
            Rails.logger.info(
              "Orbithy Notify push sent message_id=#{response_body["messageId"]} user_id=#{user_id} username=#{args['username']} external_id=#{external_id} push_category=#{push_category || 'none'}",
            )
          else
            Rails.logger.info(
              "Orbithy Notify accepted push request without message_id user_id=#{user_id} username=#{args['username']} external_id=#{external_id} push_category=#{push_category || 'none'}",
            )
          end
        else
          Rails.logger.error(
            "Orbithy Notify push failed user_id=#{user_id} username=#{args['username']} external_id=#{external_id} push_category=#{push_category || 'none'} http_status=#{response.code} response_body=#{response.body}",
          )
        end

      end
    end
  end
end
