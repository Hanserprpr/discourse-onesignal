import RouteTemplate from "ember-route-template";
import { i18n } from "discourse-i18n";

export default RouteTemplate(<template>
  <div class="mobile-app-login-intro">
    {{i18n "onesignal.intro"}}
  </div>
</template>);
