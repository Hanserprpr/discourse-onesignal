# frozen_string_literal: true

class AddSubscriptionIdToOnesignalSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :onesignal_subscriptions, :subscription_id, :string, if_not_exists: true
  end
end
