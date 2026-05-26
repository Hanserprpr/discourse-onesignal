import { ajax } from "discourse/lib/ajax";
import { apiInitializer } from "discourse/lib/api";
import { postRNWebviewMessage } from "discourse/lib/utilities";

function identityErrorPayload(error) {
  return {
    status: error?.jqXHR?.status || error?.status,
    message:
      error?.message || error?.errorThrown || error?.jqXHR?.statusText || "identity_fetch_failed",
  };
}

export default apiInitializer("1.0.0", (api) => {
  const container = api.container;
  const currentUser = api.getCurrentUser();
  const capabilities = container.lookup("service:capabilities");

  if (capabilities.isAppWebview && currentUser) {
    postRNWebviewMessage("currentUsername", currentUser.username);

    ajax("/onesignal/identity.json")
      .then((identity) => {
        const orbithyIdentity = {
          externalId: identity.external_id,
          externalIdAuthHash: identity.external_id_auth_hash,
          userId: identity.user_id,
          username: currentUser.username,
          appId: identity.app_id,
          apiUrl: identity.api_url,
        };

        postRNWebviewMessage("orbithyNotifyIdentity", orbithyIdentity);
        postRNWebviewMessage("onesignalIdentity", orbithyIdentity);
      })
      .catch((error) => {
        const payload = identityErrorPayload(error);
        postRNWebviewMessage("orbithyNotifyIdentityError", payload);
        postRNWebviewMessage("onesignalIdentityError", payload);
        postRNWebviewMessage("orbithyNotifyLogout", true);
        postRNWebviewMessage("onesignalLogout", true);
      });
  } else if (capabilities.isAppWebview) {
    postRNWebviewMessage("orbithyNotifyLogout", true);
    postRNWebviewMessage("onesignalLogout", true);
  }

  // called by legacy webview clients
  const subscribeDeviceToken = (
    token,
    platform,
    applicationName,
    subscriptionId,
    vendor,
    deviceName,
    appVersion
  ) => {
    ajax("/onesignal/subscribe.json", {
      type: "POST",
      data: {
        token,
        platform,
        application_name: applicationName,
        subscription_id: subscriptionId,
        vendor,
        device_name: deviceName,
        app_version: appVersion,
      },
    }).then((result) => {
      postRNWebviewMessage("orbithyNotifySubscribedToken", result);
      postRNWebviewMessage("subscribedToken", result);
    });
  };

  window.DiscourseOrbithyNotify = {
    subscribeDeviceToken,
    registerDevice: subscribeDeviceToken,
  };

  window.DiscourseOnesignal = {
    subscribeDeviceToken,
  };
});
