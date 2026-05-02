# frozen_string_literal: true

require 'rails_helper'

describe DiscourseOnesignal::OnesignalController do

  it 'returns the current user OneSignal identity with an auth hash' do
    user = Fabricate(:user)
    sign_in(user)
    SiteSetting.onesignal_identity_verification_secret = "identity-secret"

    get "/onesignal/identity.json"

    expect(response.status).to eq(200)
    body = JSON.parse(response.body)
    external_id = "discourse-user-#{user.id}"

    expect(body["external_id"]).to eq(external_id)
    expect(body["external_id_auth_hash"]).to eq(
      OpenSSL::HMAC.hexdigest("SHA256", "identity-secret", external_id),
    )
  end

  it 'does not expose another user OneSignal identity from request params' do
    user = Fabricate(:user)
    other_user = Fabricate(:user)
    sign_in(user)
    SiteSetting.onesignal_identity_verification_secret = "identity-secret"

    get "/onesignal/identity.json", params: { user_id: other_user.id }

    body = JSON.parse(response.body)

    expect(body["external_id"]).to eq("discourse-user-#{user.id}")
    expect(body["external_id"]).not_to eq("discourse-user-#{other_user.id}")
  end

  it 'requires params' do
    sign_in(Fabricate(:user))

    post "/onesignal/subscribe.json", params: {
      token: "atoken"
    }

    expect(response.status).to eq(400)
    expect(response.body).to include('param is missing')
  end

  it 'works!' do
    user = Fabricate(:user)
    sign_in(user)

    post "/onesignal/subscribe.json", params: {
      token: "a token",
      application_name: "My App",
      platform: "ios",
      subscription_id: "subscription-id",
    }

    expect(response.status).to eq(200)
    expect(OnesignalSubscription.last.device_token).to eq('a token')
    expect(OnesignalSubscription.last.subscription_id).to eq('subscription-id')
    expect(JSON.parse(response.body)["external_id"]).to eq("discourse-user-#{user.id}")
  end

  it 'includes OneSignal identity auth hash when subscribing' do
    user = Fabricate(:user)
    sign_in(user)
    SiteSetting.onesignal_identity_verification_secret = "identity-secret"

    post "/onesignal/subscribe.json", params: {
      token: "a token",
      application_name: "My App",
      platform: "ios",
    }

    external_id = "discourse-user-#{user.id}"
    body = JSON.parse(response.body)

    expect(body["external_id"]).to eq(external_id)
    expect(body["external_id_auth_hash"]).to eq(
      OpenSSL::HMAC.hexdigest("SHA256", "identity-secret", external_id),
    )
  end

  it 'replaces record when switching users on device' do
    prevuser = Fabricate(:user)
    current_user = Fabricate(:user)
    token = "sometoken"

    OnesignalSubscription.find_or_create_by(
      user_id: prevuser.id,
      device_token: token,
      application_name: "My App",
      platform: "android",
    )

    sign_in(current_user)

    post "/onesignal/subscribe.json", params: {
      token: token,
      application_name: "My App",
      platform: "ios"
    }

    expect(response.status).to eq(200)
    expect(OnesignalSubscription.last.device_token).to eq(token)
    expect(OnesignalSubscription.last.user_id).to eq(current_user.id)
  end
end
