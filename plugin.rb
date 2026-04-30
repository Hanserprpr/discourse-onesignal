# name: discourse-onesignal
# about: Push notifications via the OneSignal API.
# version: 2.0
# authors: pmusaraj
# url: https://github.com/pmusaraj/discourse-onesignal

require "net/http"
require "json"

enabled_site_setting :onesignal_push_enabled

register_asset 'stylesheets/common/app-login.scss'
register_asset 'stylesheets/mobile/app-login.scss', :mobile

load File.expand_path('lib/discourse-onesignal/engine.rb', __dir__)

module ::DiscourseOnesignal
  ONESIGNAL_NOTIFICATIONS_API = "https://api.onesignal.com/notifications"

  def self.external_id_for(user_id)
    "discourse-user-#{user_id}"
  end
end

after_initialize do

  User.class_eval do
    has_many :onesignal_subscriptions, dependent: :delete_all
  end

  DiscourseEvent.on(:post_notification_alert) do |user, payload|
    if SiteSetting.onesignal_app_id.blank?
      Rails.logger.warn('OneSignal App ID is missing')
      next
    end

    if SiteSetting.onesignal_rest_api_key.blank?
      Rails.logger.warn('OneSignal REST API Key is missing')
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
          Rails.logger.warn("OneSignal push skipped: missing user_id")
          return
        end

        username = payload["username"] || payload[:username]
        excerpt = payload["excerpt"] || payload[:excerpt]
        topic_title = payload["topic_title"] || payload[:topic_title]
        post_url = payload["post_url"] || payload[:post_url]

        params = {
          "app_id" => SiteSetting.onesignal_app_id,
          "target_channel" => "push",
          "include_aliases" => {
            "external_id" => [::DiscourseOnesignal.external_id_for(user_id)],
          },
          "contents" => {"en" => "#{username}: #{excerpt}"},
          "headings" => {"en" => topic_title},
          "data" => {"discourse_url" => post_url},
          "ios_badgeType" => "Increase",
          "ios_badgeCount" => "1",
        }

        uri = URI.parse(::DiscourseOnesignal::ONESIGNAL_NOTIFICATIONS_API)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true if uri.scheme == 'https'

        request = Net::HTTP::Post.new(uri.request_uri,
            'Content-Type'  => 'application/json;charset=utf-8',
            'Authorization' => "Key #{SiteSetting.onesignal_rest_api_key}")
        request.body = params.as_json.to_json
        response = http.request(request)

        case response
        when Net::HTTPSuccess
          response_body = JSON.parse(response.body.presence || "{}") rescue {}

          if response_body["id"].present?
            Rails.logger.info("Push notification sent via OneSignal to #{args['username']}.")
          else
            Rails.logger.info("OneSignal accepted the push request for #{args['username']}, but no subscribed device was returned.")
          end
        else
          Rails.logger.error("OneSignal error when sending a push notification to #{args['username']}: HTTP #{response.code} #{response.body}")
        end

      end
    end
  end
end
