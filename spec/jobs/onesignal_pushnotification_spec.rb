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
    SiteSetting.orbithy_notify_api_url = "https://notify.example.com"
    SiteSetting.orbithy_notify_app_id = "app-id"
    SiteSetting.orbithy_notify_app_secret = "app-secret"
    SiteSetting.orbithy_notify_push_category = "MARKETING"

    freeze_time Time.zone.at(1_710_000_000)
  end

  it "sends push notifications with Orbithy Notify signed requests and external id aliases" do
    body = nil
    signature = nil

    request =
      stub_request(:post, "https://notify.example.com/api/v1/push/send")
        .with(
          headers: {
            "Content-Type" => "application/json;charset=utf-8",
            "X-App-Id" => "app-id",
            "X-Timestamp" => "1710000000",
          },
        ) do |req|
          body = JSON.parse(req.body)
          signature = req.headers["X-Signature"]
        end
        .to_return(
          status: 200,
          body: { success: true, messageId: "message-id" }.to_json,
          headers: { "Content-Type" => "application/json" },
        )

    expect(Rails.logger).to receive(:info).with(
      /Orbithy Notify push sent message_id=message-id user_id=#{user.id} username=#{user.username} external_id=discourse-user-#{user.id} push_category=MARKETING/,
    )

    described_class.new.execute(
      "payload" => payload,
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(request).to have_been_requested

    expect(body["target_channel"]).to eq("push")
    expect(body["contents"]).to eq("en" => "sender 有新通知: hello from discourse")
    expect(body["push_category"]).to eq("MARKETING")
    expect(body["include_aliases"]).to eq(
      "external_id" => ["discourse-user-#{user.id}"],
    )
    expect(body).not_to have_key("filters")
    expect(signature).to eq(
      ::DiscourseOnesignal.orbithy_signature(
        "POST",
        "/api/v1/push/send",
        "1710000000",
        body.to_json,
      ),
    )
  end

  it "maps private messages to Huawei instant messages" do
    body = nil

    stub_request(:post, "https://notify.example.com/api/v1/push/send")
      .with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: { success: true, messageId: "message-id" }.to_json)

    described_class.new.execute(
      "payload" => payload.merge(notification_type: "private_message"),
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(body["push_category"]).to eq("IM")
  end

  it "omits push category when the configured fallback is blank and the notification type is unknown" do
    body = nil
    SiteSetting.orbithy_notify_push_category = ""

    stub_request(:post, "https://notify.example.com/api/v1/push/send")
      .with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: { success: true, messageId: "message-id" }.to_json)

    described_class.new.execute(
      "payload" => payload.merge(notification_type: "unknown_notification_type"),
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(body).not_to have_key("push_category")
  end

  it "formats private messages without repeating the sender in the body" do
    body = nil

    stub_request(:post, "https://notify.example.com/api/v1/push/send")
      .with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: { success: true, messageId: "message-id" }.to_json)

    described_class.new.execute(
      "payload" => payload.merge(notification_type: "private_message"),
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(body["headings"]).to eq("en" => "来自 sender 的私信")
    expect(body["contents"]).to eq("en" => "hello from discourse")
  end

  it "formats watched topic notifications as followed content updates" do
    body = nil

    stub_request(:post, "https://notify.example.com/api/v1/push/send")
      .with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: { success: true, messageId: "message-id" }.to_json)

    described_class.new.execute(
      "payload" => payload.merge(notification_type: "watching_first_post"),
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(body["push_category"]).to eq("SUBSCRIPTION")
    expect(body["contents"]).to eq("en" => "你关注的内容有更新: hello from discourse")
  end

  it "formats moderation and task notifications as work reminders" do
    body = nil

    stub_request(:post, "https://notify.example.com/api/v1/push/send")
      .with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: { success: true, messageId: "message-id" }.to_json)

    described_class.new.execute(
      "payload" => payload.merge(notification_type: "assigned"),
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(body["push_category"]).to eq("WORK")
    expect(body["contents"]).to eq("en" => "你有新的待办事项: hello from discourse")
  end

  it "formats replies as direct replies" do
    body = nil

    stub_request(:post, "https://notify.example.com/api/v1/push/send")
      .with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: { success: true, messageId: "message-id" }.to_json)

    described_class.new.execute(
      "payload" => payload.merge(notification_type: "replied"),
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(body["push_category"]).to eq("SUBSCRIPTION")
    expect(body["contents"]).to eq("en" => "sender 回复了你: hello from discourse")
  end

  it "formats mentions as mentions" do
    body = nil

    stub_request(:post, "https://notify.example.com/api/v1/push/send")
      .with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: { success: true, messageId: "message-id" }.to_json)

    described_class.new.execute(
      "payload" => payload.merge(notification_type: "mentioned"),
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(body["push_category"]).to eq("SUBSCRIPTION")
    expect(body["contents"]).to eq("en" => "sender 提到了你: hello from discourse")
  end

  it "formats social interaction notifications as subscriptions" do
    body = nil

    stub_request(:post, "https://notify.example.com/api/v1/push/send")
      .with { |req| body = JSON.parse(req.body) }
      .to_return(status: 200, body: { success: true, messageId: "message-id" }.to_json)

    described_class.new.execute(
      "payload" => payload.merge(notification_type: "liked"),
      "user_id" => user.id,
      "username" => user.username,
    )

    expect(body["push_category"]).to eq("SUBSCRIPTION")
    expect(body["contents"]).to eq("en" => "sender 赞了你的内容: hello from discourse")
  end

  it "does not fail when Orbithy Notify accepts the request without a message id" do
    stub_request(:post, "https://notify.example.com/api/v1/push/send")
      .to_return(status: 200, body: {}.to_json, headers: { "Content-Type" => "application/json" })

    expect do
      described_class.new.execute(
        "payload" => payload,
        "user_id" => user.id,
        "username" => user.username,
      )
    end.not_to raise_error
  end

  it "does not log the App Secret on Orbithy Notify errors" do
    stub_request(:post, "https://notify.example.com/api/v1/push/send")
      .to_return(status: 401, body: { errors: ["not authorized"] }.to_json)

    expect(Rails.logger).to receive(:error).with(/Orbithy Notify push failed/)
    expect(Rails.logger).not_to receive(:error).with(/app-secret/)

    described_class.new.execute(
      "payload" => payload,
      "user_id" => user.id,
      "username" => user.username,
    )
  end
end
