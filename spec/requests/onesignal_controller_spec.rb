# frozen_string_literal: true

require 'rails_helper'

describe DiscourseOnesignal::OnesignalController do
  before do
    SiteSetting.orbithy_notify_api_url = "https://notify.example.com"
    SiteSetting.orbithy_notify_app_id = "app-id"
    SiteSetting.orbithy_notify_app_secret = "app-secret"
    freeze_time Time.zone.at(1_710_000_000)
  end

  it 'returns the current user Orbithy Notify identity with an auth hash signed by the app secret' do
    user = Fabricate(:user)
    sign_in(user)

    get "/onesignal/identity.json"

    expect(response.status).to eq(200)
    body = JSON.parse(response.body)
    external_id = "discourse-user-#{user.id}"

    expect(body["external_id"]).to eq(external_id)
    expect(body["user_id"]).to eq(user.id)
    expect(body["app_id"]).to eq("app-id")
    expect(body["api_url"]).to eq("https://notify.example.com")
    expect(body["external_id_auth_hash"]).to eq(
      OpenSSL::HMAC.hexdigest("SHA256", "app-secret", external_id),
    )
  end

  it 'does not expose another user Orbithy Notify identity from request params' do
    user = Fabricate(:user)
    other_user = Fabricate(:user)
    sign_in(user)

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

  it 'registers a device with Orbithy Notify and stores the legacy subscription record' do
    user = Fabricate(:user)
    sign_in(user)
    request_body = nil
    signature = nil

    request =
      stub_request(:post, "https://notify.example.com/api/v1/device/register")
        .with(
          headers: {
            "Content-Type" => "application/json;charset=utf-8",
            "X-App-Id" => "app-id",
            "X-Timestamp" => "1710000000",
          },
        ) do |req|
          request_body = JSON.parse(req.body)
          signature = req.headers["X-Signature"]
        end
        .to_return(
          status: 200,
          body: { success: true, device: { userId: user.id } }.to_json,
          headers: { "Content-Type" => "application/json" },
        )

    post "/onesignal/subscribe.json", params: {
      token: "a token",
      application_name: "My App",
      platform: "ios",
      vendor: "apns",
      device_name: "iPhone",
      app_version: "1.0.0",
      subscription_id: "subscription-id",
    }

    expect(response.status).to eq(200)
    expect(request).to have_been_requested
    expect(request_body).to eq(
      "userId" => user.id,
      "platform" => "ios",
      "vendor" => "apns",
      "token" => "a token",
      "deviceName" => "iPhone",
      "appVersion" => "1.0.0",
      "online" => false,
    )
    expect(signature).to eq(
      ::DiscourseOnesignal.orbithy_signature(
        "POST",
        "/api/v1/device/register",
        "1710000000",
        request_body.to_json,
      ),
    )
    expect(OnesignalSubscription.last.device_token).to eq('a token')
    expect(OnesignalSubscription.last.subscription_id).to eq('subscription-id')
    body = JSON.parse(response.body)
    expect(body["external_id"]).to eq("discourse-user-#{user.id}")
    expect(body["orbithy_response"]["success"]).to eq(true)
  end

  it 'includes Orbithy Notify identity auth hash when subscribing' do
    user = Fabricate(:user)
    sign_in(user)

    stub_request(:post, "https://notify.example.com/api/v1/device/register")
      .to_return(status: 200, body: { success: true }.to_json)

    post "/onesignal/subscribe.json", params: {
      token: "a token",
      application_name: "My App",
      platform: "ios",
    }

    external_id = "discourse-user-#{user.id}"
    body = JSON.parse(response.body)

    expect(body["external_id"]).to eq(external_id)
    expect(body["external_id_auth_hash"]).to eq(
      OpenSSL::HMAC.hexdigest("SHA256", "app-secret", external_id),
    )
  end

  it 'does not store a subscription when Orbithy Notify rejects device registration' do
    user = Fabricate(:user)
    sign_in(user)

    stub_request(:post, "https://notify.example.com/api/v1/device/register")
      .to_return(status: 401, body: { success: false }.to_json)

    post "/onesignal/subscribe.json", params: {
      token: "a token",
      application_name: "My App",
      platform: "ios",
    }

    expect(response.status).to eq(401)
    expect(OnesignalSubscription.where(device_token: "a token")).to be_blank
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

    stub_request(:post, "https://notify.example.com/api/v1/device/register")
      .to_return(status: 200, body: { success: true }.to_json)

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
