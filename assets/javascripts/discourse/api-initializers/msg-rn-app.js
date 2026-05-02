import { ajax } from "discourse/lib/ajax";
import { apiInitializer } from "discourse/lib/api";
import { postRNWebviewMessage } from "discourse/lib/utilities";

export default apiInitializer("1.0.0", (api) => {
  const container = api.container;
  const currentUser = api.getCurrentUser();
  const capabilities = container.lookup("service:capabilities");
  const siteSettings = container.lookup("service:site-settings");

  if (capabilities.isAppWebview && currentUser) {
    postRNWebviewMessage("currentUsername", currentUser.username);

    ajax("/onesignal/identity.json")
      .then((identity) => {
        postRNWebviewMessage("onesignalIdentity", {
          externalId: identity.external_id,
          externalIdAuthHash: identity.external_id_auth_hash,
          username: currentUser.username,
          appId: siteSettings.onesignal_app_id,
        });
      })
      .catch(() => {
        postRNWebviewMessage("onesignalIdentityError", true);
        postRNWebviewMessage("onesignalLogout", true);
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
