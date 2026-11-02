import { withPluginApi } from "discourse/lib/plugin-api";
import ReactionsActionSummary from "../components/discourse-reactions-actions-summary.gjs";

/**
 * Bounded native adapter: retain the upstream read-only summary/counter path,
 * while deliberately removing the upstream toggle action from the post menu.
 */
function registerReadOnlyReactionSummary(api) {
  api.registerValueTransformer(
    "post-menu-buttons",
    ({ value: dag, context: { buttonKeys } }) => {
      dag.delete(buttonKeys.LIKE);
      dag.add("discourse-reactions-actions", ReactionsActionSummary, {
        before: buttonKeys.REPLIES,
      });
    }
  );
  api.addTrackedPostProperties(
    "current_user_used_main_reaction",
    "reaction_users_count",
    "current_user_reaction",
    "reactions"
  );
}

export default {
  name: "minimal-read-only-reactions",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    if (siteSettings.discourse_reactions_enabled) {
      withPluginApi(registerReadOnlyReactionSummary);
    }
  },
};
