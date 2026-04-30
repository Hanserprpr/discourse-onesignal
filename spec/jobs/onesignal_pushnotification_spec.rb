# frozen_string_literal: true

require "rails_helper"

describe Jobs::OnesignalPushnotification do
  fab!(:user)

  let(:payload) do
    {
      username: "sender",
      excerpt: "hello from discourse",
      topic_title: "A topic",
      post_url: "https://forum.example.com/t/a-topic/1/2",
    }
  end

  before do
    SiteSetting.onesignal_app_id = "app-id"
    SiteSetting.onesignal_rest_api_key = "rest-api-key"
    SiteSetting.onesignal_huawei_category = "MARKETING"
  end

  it "sends push notifications with OneSignal external id aliases" do
    body = nil

    request =
      stub_request(:post, "https://api.onesignal.com/notifications")
        .with(
          headers: {
            "Authorization" => "Key rest-api-key",
            "Content-Type" => "application/json;charset=utf-8",
          },
        ) { |req| body = JSON.parse(req.body) }
        .to_return(
          status: 200,
          body: { id: "notification-id" }.to_json,
          headers: { "Content-Type" => "application/json" },
        )

    described_class.new.execute(
      "payload" => payload,
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(request).to have_been_requested

    expect(body["app_id"]).to eq("app-id")
    expect(body["target_channel"]).to eq("push")
    expect(body["contents"]).to eq("en" => "sender 有新回复: hello from discourse")
    expect(body["Huawei_category"]).to eq("MARKETING")
    expect(body["include_aliases"]).to eq(
      "external_id" => ["discourse-user-#{user.id}"],
    )
    expect(body).not_to have_key("filters")
  end

  it "maps private messages to Huawei instant messages" do
    body = nil

    stub_request(:post, "https://api.onesignal.com/notifications")
      .with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: { id: "notification-id" }.to_json)

    described_class.new.execute(
      "payload" => payload.merge(notification_type: "private_message"),
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(body["Huawei_category"]).to eq("IM")
  end

  it "maps watched topic notifications to Huawei subscriptions" do
    body = nil

    stub_request(:post, "https://api.onesignal.com/notifications")
      .with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: { id: "notification-id" }.to_json)

    described_class.new.execute(
      "payload" => payload.merge(notification_type: "watching_first_post"),
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(body["Huawei_category"]).to eq("SUBSCRIPTION")
  end

  it "maps moderation and task notifications to Huawei work reminders" do
    body = nil

    stub_request(:post, "https://api.onesignal.com/notifications")
      .with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: { id: "notification-id" }.to_json)

    described_class.new.execute(
      "payload" => payload.merge(notification_type: "assigned"),
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(body["Huawei_category"]).to eq("WORK")
  end

  it "maps replies and mentions to Huawei subscriptions" do
    body = nil

    stub_request(:post, "https://api.onesignal.com/notifications")
      .with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: { id: "notification-id" }.to_json)

    described_class.new.execute(
      "payload" => payload.merge(notification_type: "replied"),
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(body["Huawei_category"]).to eq("SUBSCRIPTION")
  end

  it "maps social interaction notifications to Huawei subscriptions" do
    body = nil

    stub_request(:post, "https://api.onesignal.com/notifications")
      .with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: { id: "notification-id" }.to_json)

    described_class.new.execute(
      "payload" => payload.merge(notification_type: "liked"),
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(body["Huawei_category"]).to eq("SUBSCRIPTION")
  end

  it "does not fail when OneSignal accepts the request without a notification id" do
    stub_request(:post, "https://api.onesignal.com/notifications")
      .to_return(status: 200, body: {}.to_json, headers: { "Content-Type" => "application/json" })

    expect do
      described_class.new.execute(
        "payload" => payload,
        "user_id" => user.id,
        "username" => user.username,
      )
    end.not_to raise_error
  end

  it "does not log the REST API key on OneSignal errors" do
    stub_request(:post, "https://api.onesignal.com/notifications")
      .to_return(status: 401, body: { errors: ["not authorized"] }.to_json)

    expect(Rails.logger).to receive(:error).with(/OneSignal error/)
    expect(Rails.logger).not_to receive(:error).with(/rest-api-key/)

    described_class.new.execute(
      "payload" => payload,
      "user_id" => user.id,
      "username" => user.username,
    )
  end
end
