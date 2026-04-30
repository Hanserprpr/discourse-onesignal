import { ajax } from "discourse/lib/ajax";
import { apiInitializer } from "discourse/lib/api";
import { postRNWebviewMessage } from "discourse/lib/utilities";

function externalIdFor(userId) {
  return `discourse-user-${userId}`;
}

export default apiInitializer("1.0.0", (api) => {
  const container = api.container;
  const currentUser = api.getCurrentUser();
  const capabilities = container.lookup("service:capabilities");
  const siteSettings = container.lookup("service:site-settings");

  if (capabilities.isAppWebview && currentUser) {
    const externalId = externalIdFor(currentUser.id);

    postRNWebviewMessage("currentUsername", currentUser.username);
    postRNWebviewMessage("onesignalIdentity", {
      externalId,
      username: currentUser.username,
      appId: siteSettings.onesignal_app_id,
    });
  } else if (capabilities.isAppWebview) {
    postRNWebviewMessage("onesignalLogout", true);
  }

  // called by legacy webview clients
  window.DiscourseOnesignal = {
    subscribeDeviceToken(token, platform, applicationName, subscriptionId) {
      ajax("/onesignal/subscribe.json", {
        type: "POST",
        data: {
          token,
          platform,
          application_name: applicationName,
          subscription_id: subscriptionId,
        },
      }).then((result) => {
        postRNWebviewMessage("subscribedToken", result);
      });
    },
  };
});
