import { apiInitializer } from "discourse/lib/api";

export default apiInitializer("1.0.0", (api) => {
  api.modifyClass("component:d-modal", {
    pluginId: "discourse-onesignal",

    init() {
      this._super(...arguments);

      if (document.body.classList.contains("mobile-app-login-modal")) {
        this.set("dismissable", false);
      }
    },

    mouseDown() {
      if (document.body.classList.contains("mobile-app-login-modal")) {
        return;
      }

      this._super(...arguments);
    },
  });
});
