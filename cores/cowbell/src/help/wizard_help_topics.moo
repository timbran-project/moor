object WIZARD_HELP_TOPICS
  name: "Wizard Help Topics"
  parent: HELP_SOURCE
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  property topic_wizard_announce (owner: ARCH_WIZARD, flags: "rc") = <HELP, .content = "Usage: `@announce <message>`\n\nBroadcasts a message to all connected players.", .name = "@announce", .summary = "Broadcast announcement", .category = 'administration, .aliases = {"announce", "broadcast"}, .see_also = {"@shutdown"}>;
  property topic_wizard_builder (owner: ARCH_WIZARD, flags: "rc") = <HELP, .content = "Usage: `@builder <player>`\n\nGrants builder privileges (or downgrades programmer to builder).", .name = "@builder", .summary = "Grant builder status", .category = 'administration, .aliases = {"builder", "grant builder"}, .see_also = {"@programmer"}>;
  property topic_wizard_chown (owner: ARCH_WIZARD, flags: "rc") = <HELP, .content = "Usage:\n- `@chown <object> to <owner>`\n- `@chown <object>.<property> to <owner>`\n- `@chown <object>:<verb> to <owner>`", .name = "@chown", .summary = "Change ownership", .category = 'administration, .aliases = {"chown", "owner"}, .see_also = {}>;
  property topic_wizard_llm_budget (owner: ARCH_WIZARD, flags: "rc") = <HELP, .content = "Usage: `@llm-budget <player>`\n\nShows token budget and usage data for a player.", .name = "@llm-budget", .summary = "Show LLM budget", .category = 'administration, .aliases = {"llm-budget", "token budget"}, .see_also = {"@llm-set-budget", "@llm-reset-usage"}>;
  property topic_wizard_llm_config (owner: ARCH_WIZARD, flags: "rc") = <HELP, .content = "Usage:\n- `@llm-config`\n- `@llm-config endpoint <url>`\n- `@llm-config model <name>`\n- `@llm-config key`", .name = "@llm-config", .summary = "Configure LLM client", .category = 'administration, .aliases = {"llm-config", "llm settings"}, .see_also = {"@llm-reset-agents"}>;
  property topic_wizard_llm_reset_agents (owner: ARCH_WIZARD, flags: "rc") = <HELP, .content = "Usage: `@llm-reset-agents`\n\nReconfigures wearable and observer LLM agent instances.", .name = "@llm-reset-agents", .summary = "Reconfigure LLM agents", .category = 'administration, .aliases = {"llm-reset-agents", "llm agents"}, .see_also = {"@llm-config"}>;
  property topic_wizard_llm_reset_usage (owner: ARCH_WIZARD, flags: "rc") = <HELP, .content = "Usage: `@llm-reset-usage <player>`\n\nResets token usage counter and usage log for a player.", .name = "@llm-reset-usage", .summary = "Reset LLM usage", .category = 'administration, .aliases = {"llm-reset-usage", "reset token usage"}, .see_also = {"@llm-budget"}>;
  property topic_wizard_llm_set_budget (owner: ARCH_WIZARD, flags: "rc") = <HELP, .content = "Usage: `@llm-set-budget <player> to <budget>`\n\nSets token budget for a player.", .name = "@llm-set-budget", .summary = "Set LLM budget", .category = 'administration, .aliases = {"llm-set-budget", "set token budget"}, .see_also = {"@llm-budget"}>;
  property topic_wizard_overview (owner: ARCH_WIZARD, flags: "rc") = <HELP, .content = "Wizard/admin command surface:\n\n`@announce`, `@programmer`, `@builder`, `@chown`, `@shutdown`, `@reconfigure-tools`, `@reissue-tools`, `@llm-budget`, `@llm-set-budget`, `@llm-reset-usage`, `@llm-config`, `@llm-reset-agents`\n\nUse `help <command>` for details.", .name = "wizard", .summary = "Wizard administration commands", .category = 'administration, .aliases = {"wizard", "admin"}, .see_also = {"administration"}>;
  property topic_wizard_programmer (owner: ARCH_WIZARD, flags: "rc") = <HELP, .content = "Usage: `@programmer <player>`\n\nGrants programmer privileges (or upgrades builder to programmer) and issues required tools.", .name = "@programmer", .summary = "Grant programmer status", .category = 'administration, .aliases = {"programmer", "grant programmer"}, .see_also = {"@builder"}>;
  property topic_wizard_reconfigure_tools (owner: ARCH_WIZARD, flags: "rc") = <HELP, .content = "Usage: `@reconfigure-tools`\n\nReconfigures all Architect's Compass and Data Visor instances.", .name = "@reconfigure-tools", .summary = "Reconfigure tool instances", .category = 'administration, .aliases = {"reconfigure-tools", "tool reconfigure"}, .see_also = {"@reissue-tools"}>;
  property topic_wizard_reissue_tools (owner: ARCH_WIZARD, flags: "rc") = <HELP, .content = "Usage: `@reissue-tools`\n\nDestroys existing tool instances and reissues them to qualified players.", .name = "@reissue-tools", .summary = "Reissue tool instances", .category = 'administration, .aliases = {"reissue-tools", "tool reissue"}, .see_also = {"@reconfigure-tools"}>;
  property topic_wizard_shutdown (owner: ARCH_WIZARD, flags: "rc") = <HELP, .content = "Usage: `@shutdown [in <minutes>] [message]`\n\nSends countdown announcements, dumps database, and shuts down server.", .name = "@shutdown", .summary = "Shutdown server", .category = 'administration, .aliases = {"shutdown", "reboot"}, .see_also = {"@announce"}>;

  override import_export_hierarchy = {"help"};
  override import_export_id = "wizard_help_topics";
  override topic_order = {
    'topic_wizard_overview,
    'topic_wizard_announce,
    'topic_wizard_programmer,
    'topic_wizard_builder,
    'topic_wizard_chown,
    'topic_wizard_shutdown,
    'topic_wizard_reconfigure_tools,
    'topic_wizard_reissue_tools,
    'topic_wizard_llm_budget,
    'topic_wizard_llm_set_budget,
    'topic_wizard_llm_reset_usage,
    'topic_wizard_llm_config,
    'topic_wizard_llm_reset_agents
  };
endobject
