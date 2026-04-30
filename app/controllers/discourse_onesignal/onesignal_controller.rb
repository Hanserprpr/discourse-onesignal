# frozen_string_literal: true

module DiscourseOnesignal
  class OnesignalController < ::ApplicationController
    requires_plugin DiscourseOnesignal

    before_action :ensure_logged_in, except: [:app_login]

    def subscribe
      token = params.require(:token)
      application_name = params.require(:application_name)
      platform = params.require(:platform)
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
      record.save!

      render json: record.as_json.merge(
        external_id: ::DiscourseOnesignal.external_id_for(current_user.id),
      )
    end

    def app_login
      render json: success_json
    end
  end
end
