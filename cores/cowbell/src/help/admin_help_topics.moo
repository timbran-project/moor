object ADMIN_HELP_TOPICS
  name: "Admin Help Topics"
  parent: HELP_SOURCE
  location: PROTOTYPE_BOX
  owner: ARCH_WIZARD
  readable: true

  property topic_administration_dump_database (owner: ARCH_WIZARD, flags: "rc") = <HELP, .name = "@dump-database", .aliases = {"dump", "checkpoint", "save"}, .content = "Usage: `@dump-database`\n\nManually triggers a database dump to disk.\n\nOnly admins can use this command.", .category = 'administration, .summary = "Trigger database dump", .see_also = {}>;
  property topic_administration_overview (owner: ARCH_WIZARD, flags: "rc") = {
    "administration",
    "Administration commands",
    "Commands for delegated administration and auditing:\n\n`@sudo`, `@sudo-grant`, `@sudo-allow`, `@sudo-revoke`, `@sudo-show`, `@sudo-who`, `@sudo-log`, `@dump-database`\n\nTypical flow: `@sudo-grant` -> `@sudo-allow` -> validate with `@sudo-show` -> audit with `@sudo-log`.\n\nImportant: `@sudo` is an allowlisted command-dispatch facility, not a universal permission elevator. Some privileged operations still require dedicated admin verbs.",
    {"admin", "sudo", "management"},
    'administration,
    {"@sudo", "@sudo-grant", "@sudo-allow", "@sudo-show", "@sudo-log"}
  };
  property topic_administration_sudo (owner: ARCH_WIZARD, flags: "rc") = {
    "@sudo",
    "Run an allowlisted delegated admin command",
    "Usage: `@sudo <command>`\n\nRuns an allowlisted command through delegated admin dispatch.\n\nImportant limitations:\n- This is not universal command elevation.\n- `set_task_perms()` scope does not make arbitrary downstream command execution fully transitive.\n- Some operations (for example direct property/verb mutation commands) may still fail unless exposed as dedicated admin verbs.\n\nAllowlist entries can be plain verb names (for example `@llm-budget`) or object-scoped tokens (`#11::@dig`).\n\nTroubleshooting:\n- `@sudo @rmprop ...` returning permission denied usually means that operation is outside current delegated-dispatch guarantees.\n- Check your grant and allowlist with `@sudo-show <player>`.\n- Check active entries with `@sudo-who` and recent audit events with `@sudo-log`.",
    {"sudo", "@sudo", "sudo-cmd"},
    'administration,
    {"@sudo-grant", "@sudo-allow", "@sudo-show", "@sudo-who", "@sudo-log"}
  };
  property topic_administration_sudo_allow (owner: ARCH_WIZARD, flags: "rc") = {
    "@sudo-allow",
    "Set sudo allowlist",
    "Usage: `@sudo-allow <player> to <verb|obj::verb,...>`\n\nSets the list of command verbs a player may run via `@sudo`.\n\nExamples:\n- `@sudo-allow Ryan to @llm-budget,@dump-database`\n- `@sudo-allow Ryan to #11::@dig`\n- `@sudo-allow Ryan to *`\n\nLeast-privilege guidance:\n- Prefer `obj::verb` entries over plain verb names.\n- Avoid `*` except for tightly controlled temporary situations.\n- Keep lists focused on commands with expected delegated behavior.",
    {"sudo-allow", "allow sudo"},
    'administration,
    {"@sudo-grant", "@sudo-revoke", "@sudo-show", "@sudo-log"}
  };
  property topic_administration_sudo_grant (owner: ARCH_WIZARD, flags: "rc") = <HELP, .name = "@sudo-grant", .aliases = {"sudo-grant", "grant sudo", "sudo-grant"}, .content = "Usage: `@sudo-grant <player> as <wizard_player>`\n\nConfigures a player to execute commands as a specified wizard delegate via `@sudo`. If the player has no allowlist yet, a default seed is created.", .category = 'administration, .summary = "Grant sudo delegation", .see_also = {"@sudo-revoke", "@sudo-allow"}>;
  property topic_administration_sudo_log (owner: ARCH_WIZARD, flags: "rc") = <HELP, .name = "@sudo-log", .aliases = {"sudo-log", "sudo audit", "sudo-audit"}, .content = "Usage: `@sudo-log [N]`\n\nShows the most recent N sudo audit entries (default 20).", .category = 'administration, .summary = "Show sudo audit log", .see_also = {"@sudo-who"}>;
  property topic_administration_sudo_revoke (owner: ARCH_WIZARD, flags: "rc") = <HELP, .name = "@sudo-revoke", .aliases = {"sudo-revoke", "revoke sudo", "sudo-revoke"}, .content = "Usage: `@sudo-revoke <player>`\n\nRemoves sudo delegation, allowlist entries, and clears active sudo task markers for that player.", .category = 'administration, .summary = "Revoke sudo delegation", .see_also = {"@sudo-grant", "@sudo-allow"}>;
  property topic_administration_sudo_show (owner: ARCH_WIZARD, flags: "rc") = <HELP, .name = "@sudo-show", .aliases = {"sudo-show", "show sudo", "sudo-show"}, .content = "Usage: `@sudo-show <player>`\n\nShows delegate mapping, allowlist, and active sudo task entries for a player.", .category = 'administration, .summary = "Show sudo state for a player", .see_also = {"@sudo-who", "@sudo-allow"}>;
  property topic_administration_sudo_who (owner: ARCH_WIZARD, flags: "rc") = <HELP, .name = "@sudo-who", .aliases = {"sudo-who", "sudo active", "sudo-active"}, .content = "Usage: `@sudo-who`\n\nLists active sudo tasks and recent sudo audit log entries.", .category = 'administration, .summary = "Show active sudo and recent audit", .see_also = {"@sudo-show", "@sudo-log"}>;

  override import_export_hierarchy = {"help"};
  override import_export_id = "admin_help_topics";
  override topic_order = {
    "topic_administration_overview",
    "topic_administration_sudo",
    "topic_administration_sudo_grant",
    "topic_administration_sudo_allow",
    "topic_administration_sudo_revoke",
    "topic_administration_sudo_show",
    "topic_administration_sudo_who",
    "topic_administration_sudo_log",
    "topic_administration_dump_database"
  };
endobject
