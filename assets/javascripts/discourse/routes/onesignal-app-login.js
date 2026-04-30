import { later, next } from "@ember/runloop";
import Route from "@ember/routing/route";

export default Route.extend({
  afterModel(_model, transition) {
    if (!this.currentUser) {
      next(() => transition.send("showLogin"));
    } else {
      next(() => this.transitionTo("discovery.latest"));
    }
  },

  activate() {
    this._super(...arguments);

    if (!this.currentUser) {
      document.body.classList.add("mobile-app-login-modal");
    }
  },

  deactivate() {
    this._super(...arguments);

    if (!this.currentUser) {
      later(
        () => document.body.classList.remove("mobile-app-login-modal"),
        300
      );
    }
  },
});
