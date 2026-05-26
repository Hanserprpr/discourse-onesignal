# frozen_string_literal: true

module DiscourseOnesignal
  class OnesignalController < ::ApplicationController
    requires_plugin "discourse-onesignal"

    before_action :ensure_logged_in, except: [:app_login]

    def subscribe
      token = params.require(:token)
      application_name = params.require(:application_name)
      platform = params.require(:platform)
      vendor = params[:vendor].presence || platform
      subscription_id = params[:subscription_id].presence

      if ["ios", "android"].exclude?(platform)
        raise Discourse::InvalidParameters, "Platform parameter should be ios or android."
      end

      # clear any records of this device linked to other users
      OnesignalSubscription.where(device_token: token).where.not(user_id: current_user.id).destroy_all

      record = OnesignalSubscription.find_or_initialize_by(device_token: token)
      record.user_id = current_user.id
      record.application_name = application_name
      record.platform = platform
      record.subscription_id = subscription_id if record.respond_to?(:subscription_id=)

      response =
        ::DiscourseOnesignal.orbithy_json_request(
          "POST",
          ::DiscourseOnesignal::ORBITHY_DEVICE_REGISTER_PATH,
          {
            userId: current_user.id,
            platform: platform,
            vendor: vendor,
            token: token,
            deviceName: params[:device_name].presence || application_name,
            appVersion: params[:app_version].presence,
            online: false,
          }.compact,
        )

      if !response.is_a?(Net::HTTPSuccess)
        Rails.logger.error(
          "Orbithy Notify device register failed request_id=#{request.request_id} user_id=#{current_user.id} platform=#{platform} vendor=#{vendor} http_status=#{response.code} response_body=#{response.body}",
        )
        render json: failed_json.merge(error: "device_register_failed"), status: response.code.to_i
        return
      end

      record.save!

      Rails.logger.info(
        "Orbithy Notify subscription updated request_id=#{request.request_id} user_id=#{current_user.id} platform=#{platform} vendor=#{vendor}",
      )

      register_body = JSON.parse(response.body.presence || "{}") rescue {}
      render json: record.as_json.merge(onesignal_identity_json).merge(orbithy_response: register_body)
    end

    def identity
      Rails.logger.info(
        "Orbithy Notify identity requested request_id=#{request.request_id} user_id=#{current_user.id}",
      )

      render json: onesignal_identity_json
    end

    def app_login
      render json: success_json
    end

    private

    def onesignal_identity_json
      identity = {
        external_id: ::DiscourseOnesignal.external_id_for(current_user.id),
        user_id: current_user.id,
        app_id: SiteSetting.orbithy_notify_app_id,
        api_url: ::DiscourseOnesignal.orbithy_api_base_url,
      }

      external_id_auth_hash = ::DiscourseOnesignal.external_id_auth_hash_for(current_user.id)
      identity[:external_id_auth_hash] = external_id_auth_hash if external_id_auth_hash.present?

      identity
    end
  end
end
