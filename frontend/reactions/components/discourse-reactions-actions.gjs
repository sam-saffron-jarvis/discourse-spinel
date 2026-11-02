import Component from "@glimmer/component";
import DiscourseReactionsCounter from "./discourse-reactions-counter.gjs";

/** Counter-only caller used by the original summary for its left position. */
export default class MinimalReadOnlyReactionsActions extends Component {
  <template>
    {{#if (eq @position "left")}}
      <DiscourseReactionsCounter @post={{@post}} @position={{@position}} />
    {{/if}}
  </template>
}
