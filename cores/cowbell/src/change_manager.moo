object CHANGE_MANAGER [import_export_id -> "change_manager"]
  name: "Change Manager"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: false

  property default_package (owner: ARCH_WIZARD, flags: "") = "cowbell";
  // These bindings are core data. Keep them aligned with the distributed source objects.
  property packages (owner: ARCH_WIZARD, flags: "") = ["cowbell" -> [
    "schema" -> 1,
    "generation" -> 1,
    "objects" -> {
      ACTOR, AGENTIC, AGENTIC_AGENT, AGENTIC_CODING_ROOM, AGENTIC_EVENT_QUEUE, AGENTIC_LOOP,
      AGENTIC_ROOM_OBSERVER, AGENTIC_RUNNER, AGENTIC_TOOL, ARCH_WIZARD, LOGIN, PASSWORD,
      CHANGE_MANAGER, EVENT, EVENT_RECEIVER, MSG_BAG, SUB, SUB_UTILS,
      EXAMINATION, ADMIN_FEATURES, BUILDER_FEATURES, MAIL_FEATURES, PROG_FEATURES, SOCIAL_FEATURES,
      WIZ_FEATURES, ANSI, FORMAT, FORMAT_ANNOTATION, FORMAT_BLOCK, FORMAT_CODE,
      FORMAT_DEFLIST, FORMAT_LINK, FORMAT_LIST, FORMAT_PARAGRAPH, FORMAT_TABLE, FORMAT_TITLE,
      GIT, GIT_REPOSITORY, GIT_SNAPSHOT, GIT_ENTRY,
      HTML, HACKER, ADMIN_HELP_TOPICS, BUILDER_HELP_TOPICS, HELP, HELP_SOURCE,
      HELP_TOPICS, HELP_UTILS, PROG_HELP_TOPICS, WIZARD_HELP_TOPICS, ARCH_WIZARD_MAILBOX, BRASS_KEY,
      CAT_KIBBLE, COUCH, FIRST_AREA, FIRST_AREA_PASSAGES, FIRST_ROOM, HENRI,
      HOUSEKEEPING, HOUSEKEEPING_SWEEP_MSGS, KIBBLE_CAN_1, KIBBLE_CAN_2, KIBBLE_CAN_3, KIBBLE_CUPBOARD,
      MAIL_ROOM, PROTOTYPE_BOX, TEST_PLAYER, CONSUMABLE, CONTAINER, DRINK,
      FOOD, NOTE, SITTABLE, THING, WEARABLE, AGENT_BUILDING_TOOLS,
      AGENT_ROOM, ARCHITECTS_COMPASS, DATA_VISOR, LLM_AGENT, LLM_AGENT_TOOL, LLM_CHAT_OPTS,
      LLM_CLIENT, LLM_RESPONSE, LLM_ROOM_OBSERVER, LLM_TASK, LLM_WEARABLE, MR_WELCOME,
      RLM_AGENT, LOOK, DM, LETTER, MAILBOX, PLAYER,
      PLAYER_ACTIVITY, PRONOUNS, RELATION, ROOT, REACTION, RULE,
      RULE_ENGINE, RULE_TEST, SERVER_OPTIONS, SYSOBJ, INT_PROTO, LIST_PROTO,
      PROPERTY, STR_PROTO, SYM_PROTO, VERB, GRANT_UTILS, MATCH,
      OBJ_UTILS, PROG_UTILS, TEST_UTILS, URL_UTILS, AREA, PASSAGE,
      ROOM
    },
    "fields" -> {"program"},
    "trusted_owners" -> {HACKER},
    "constants" -> [
      "SYSOBJ" -> #0,
      "ROOT" -> #1,
      "ARCH_WIZARD" -> #2,
      "ACTOR" -> #3,
      "PLAYER" -> #5,
      "HACKER" -> #6,
      "LOOK" -> #20,
      "PRONOUNS" -> #22,
      "SERVER_OPTIONS" -> #52,
      "EXAMINATION" -> #56,
      "PLAYER_ACTIVITY" -> #113,
      "AGENTIC" -> #119,
      "AGENTIC_TOOL" -> #120,
      "AGENTIC_LOOP" -> #121,
      "AGENTIC_AGENT" -> #122,
      "AGENTIC_EVENT_QUEUE" -> #123,
      "AGENTIC_RUNNER" -> #124,
      "AGENTIC_ROOM_OBSERVER" -> #125,
      "AGENTIC_CODING_ROOM" -> #126,
      "PASSWORD" -> #16,
      "LOGIN" -> #17,
      "EVENT_RECEIVER" -> #4,
      "EVENT" -> #18,
      "SUB" -> #19,
      "SUB_UTILS" -> #59,
      "MSG_BAG" -> #60,
      "SOCIAL_FEATURES" -> #36,
      "BUILDER_FEATURES" -> #37,
      "PROG_FEATURES" -> #38,
      "WIZ_FEATURES" -> #39,
      "ADMIN_FEATURES" -> #87,
      "MAIL_FEATURES" -> #97,
      "ANSI" -> #26,
      "FORMAT" -> #29,
      "FORMAT_BLOCK" -> #30,
      "FORMAT_TITLE" -> #31,
      "FORMAT_LIST" -> #32,
      "FORMAT_TABLE" -> #33,
      "FORMAT_CODE" -> #34,
      "HTML" -> #35,
      "FORMAT_DEFLIST" -> #72,
      "FORMAT_ANNOTATION" -> #134,
      "FORMAT_LINK" -> #82,
      "FORMAT_PARAGRAPH" -> #114,
      "HELP_UTILS" -> #58,
      "HELP" -> #75,
      "HELP_TOPICS" -> #76,
      "HELP_SOURCE" -> #88,
      "PROG_HELP_TOPICS" -> #89,
      "BUILDER_HELP_TOPICS" -> #90,
      "ADMIN_HELP_TOPICS" -> #91,
      "WIZARD_HELP_TOPICS" -> #92,
      "PROTOTYPE_BOX" -> #48,
      "FIRST_ROOM" -> #49,
      "FIRST_AREA" -> #50,
      "FIRST_AREA_PASSAGES" -> #51,
      "BRASS_KEY" -> #65,
      "KIBBLE_CUPBOARD" -> #66,
      "CAT_KIBBLE" -> #67,
      "TEST_PLAYER" -> #74,
      "HOUSEKEEPING" -> #79,
      "HOUSEKEEPING_SWEEP_MSGS" -> #80,
      "COUCH" -> #107,
      "HENRI" -> #111,
      "MAIL_ROOM" -> #112,
      "ARCH_WIZARD_MAILBOX" -> #115,
      "KIBBLE_CAN_1" -> #116,
      "KIBBLE_CAN_2" -> #117,
      "KIBBLE_CAN_3" -> #118,
      "THING" -> #8,
      "WEARABLE" -> #9,
      "CONTAINER" -> #10,
      "SITTABLE" -> #70,
      "NOTE" -> #71,
      "CONSUMABLE" -> #93,
      "FOOD" -> #94,
      "DRINK" -> #95,
      "LLM_CLIENT" -> #40,
      "LLM_AGENT" -> #41,
      "LLM_AGENT_TOOL" -> #42,
      "LLM_ROOM_OBSERVER" -> #43,
      "LLM_WEARABLE" -> #44,
      "MR_WELCOME" -> #45,
      "DATA_VISOR" -> #46,
      "ARCHITECTS_COMPASS" -> #47,
      "LLM_TASK" -> #61,
      "LLM_CHAT_OPTS" -> #68,
      "AGENT_BUILDING_TOOLS" -> #81,
      "AGENT_ROOM" -> #86,
      "LLM_RESPONSE" -> #99,
      "RLM_AGENT" -> #100,
      "MAILBOX" -> #73,
      "LETTER" -> #77,
      "DM" -> #78,
      "RELATION" -> #23,
      "RULE_ENGINE" -> #62,
      "RULE" -> #63,
      "RULE_TEST" -> #64,
      "REACTION" -> #69,
      "STR_PROTO" -> #13,
      "LIST_PROTO" -> #14,
      "INT_PROTO" -> #15,
      "VERB" -> #54,
      "PROPERTY" -> #55,
      "SYM_PROTO" -> #133,
      "MATCH" -> #21,
      "GRANT_UTILS" -> #25,
      "PROG_UTILS" -> #53,
      "OBJ_UTILS" -> #57,
      "URL_UTILS" -> #96,
      "TEST_UTILS" -> #127,
      "ROOM" -> #7,
      "AREA" -> #11,
      "PASSAGE" -> #12,
      "GIT" -> GIT,
      "GIT_REPOSITORY" -> GIT_REPOSITORY,
      "GIT_SNAPSHOT" -> GIT_SNAPSHOT,
      "GIT_ENTRY" -> GIT_ENTRY,
      "CHANGE_MANAGER" -> #2000
    ],
    "upstream" -> ["transport" -> "git",
      "repository" -> "https://github.com/timbran-project/moor.git",
      "revision" -> ["ref" -> "refs/heads/main"], "path" -> "cores/cowbell/src"],
    "active" -> 0
  ]];
  property pending (owner: ARCH_WIZARD, flags: "") = [];
  property receipts (owner: ARCH_WIZARD, flags: "") = [];
  property next_review (owner: ARCH_WIZARD, flags: "") = 1;

  method _error owner: ARCH_WIZARD
    "Raise a versioned service error.";
    caller == this || raise(E_PERM);
    const {code, message} = args;
    raise(E_INVARG, message, ["schema" -> 1, "code" -> code]);
  endmethod

  method _entry owner: ARCH_WIZARD
    "Authorize the invoking administrator without treating this verb's owner as the caller.";
    caller == this && this == $change_manager || raise(E_PERM);
    const {origin} = args;
    const actor = player;
    valid(actor) && valid(origin) || raise(E_PERM);
    let authority = actor;
    if (!actor.wizard)
      $admin_features in actor.admin_features || raise(E_PERM);
      authority = $admin_features:_resolve_delegate(actor);
      $admin_features:_is_allowed_verb(actor, $wiz_features, "@changes") || raise(E_PERM);
    endif
    origin in {actor, authority} && valid(authority) && authority.wizard || raise(E_PERM);
    return {actor, authority};
  endmethod

  method _authorized owner: ARCH_WIZARD
    "Recheck persisted actor and authority after suspension or restart.";
    caller == this && this == $change_manager || raise(E_PERM);
    const {actor, authority} = args;
    valid(actor) && valid(authority) && authority.wizard || raise(E_PERM);
    if (!actor.wizard)
      $admin_features in actor.admin_features || raise(E_PERM);
      $admin_features:_resolve_delegate(actor) == authority || raise(E_PERM);
      $admin_features:_is_allowed_verb(actor, $wiz_features, "@changes") || raise(E_PERM);
    else
      actor == authority || raise(E_PERM);
    endif
    return true;
  endmethod

  method _get owner: ARCH_WIZARD
    "Read a pending record with owner and generation guards.";
    caller == this || raise(E_PERM);
    const {auth, id, ?generation = -1} = args;
    maphaskey(this.pending, id) || this:_error("missing_review", "No pending review with that ID.");
    const record = this.pending[id];
    auth[1] == record["actor"] || auth[1].wizard || raise(E_PERM);
    generation == -1 || generation == record["generation"] || this:_error("stale_generation", "Review changed; reload its status.");
    this:_authorized(@auth);
    return record;
  endmethod

  method _summary owner: ARCH_WIZARD
    "Return status without source, drafts, or program bodies.";
    caller == this || raise(E_PERM);
    const {record} = args;
    return ["schema" -> 1, "review_id" -> record["id"], "generation" -> record["generation"], "package" -> record["package"], "status" -> record["status"], "task" -> record["task"], "error" -> record["error"], "provenance" -> record["provenance"]];
  endmethod

  method capabilities owner: ARCH_WIZARD
    "Describe the versioned review API and its limits.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    return ["schema" -> 1, "operations" -> {"packages", "configure", "upstream", "stage", "status", "review", "diagnostics", "details", "resolve", "apply", "refresh", "discard"}, "fields" -> {"program"}, "choices" -> {"incoming", "local", "edited", "defer"}, "transports" -> {"upload", "http", "git"}, "git_authorization" -> "wizard", "authorization" -> "administrator", "default_package" -> this.default_package, "max_source_bytes" -> 4194304, "max_pending_bytes" -> 33554432, "max_packages" -> 32, "page_rows" -> 50, "max_detail_bytes" -> 524288, "max_page_bytes" -> 262144, "receipt_decisions" -> 50];
  endmethod

  method packages owner: ARCH_WIZARD
    "Return package bindings, policy, upstream settings, and active review IDs.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    return ["schema" -> 1, "packages" -> this.packages];
  endmethod

  method configure owner: ARCH_WIZARD
    "Create or conditionally replace explicit package bindings and program-only policy.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    const {name, objects, constants, ?url = "", ?expected = 0, ?trusted_owners = {}} = args;
    typeof(name) == TYPE_STR && length(name) > 0 && length(name) <= 64 || raise(E_INVARG);
    typeof(objects) == TYPE_LIST && length(objects) > 0 && length(objects) <= 4096 || raise(E_INVARG);
    typeof(constants) == TYPE_MAP && value_bytes(constants) <= 1048576 || raise(E_INVARG);
    typeof(trusted_owners) == TYPE_LIST && length(trusted_owners) <= 128 || raise(E_INVARG);
    let owner_set = {};
    for owner in (trusted_owners)
      typeof(owner) == TYPE_OBJ && valid(owner) && !(owner in owner_set) || raise(E_INVARG);
      owner_set = {@owner_set, owner};
    endfor
    const upstream = this:_upstream(url);
    let seen = {};
    for object in (objects)
      typeof(object) == TYPE_OBJ && valid(object) && !(object in seen) || raise(E_INVARG);
      seen = {@seen, object};
    endfor
    for other_name in (mapkeys(this.packages))
      if (other_name != name)
        for object in (this.packages[other_name]["objects"])
          !(object in seen) || this:_error("overlapping_package", "Another package already manages one of these objects.");
        endfor
      endif
    endfor
    let generation = 0;
    if (maphaskey(this.packages, name))
      const previous = this.packages[name];
      generation = previous["generation"];
      previous["active"] == 0 || this:_error("active_review", "Discard the active review before changing package settings.");
    else
      length(this.packages) < 32 || raise(E_QUOTA);
    endif
    generation == expected || this:_error("stale_generation", "Package settings changed.");
    const package = ["schema" -> 1, "generation" -> generation + 1, "objects" -> objects, "fields" -> {"program"}, "constants" -> constants, "trusted_owners" -> trusted_owners, "upstream" -> upstream, "active" -> 0];
    this.packages[name] = package;
    return package;
  endmethod

  method _url owner: ARCH_WIZARD
    "Accept a single HTTP text-bundle URL without embedded credentials.";
    caller == this || raise(E_PERM);
    const {url} = args;
    typeof(url) == TYPE_STR && length(url) <= 2048 || raise(E_INVARG);
    if (url != "")
      (index(url, "http://") == 1 || index(url, "https://") == 1) && !index(url, "@") || raise(E_INVARG, "Expected an HTTP bundle URL without credentials.");
    endif
  endmethod

  method upstream owner: ARCH_WIZARD
    "Conditionally set an HTTP bundle URL or a Git repository source map.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    const {name, url, expected} = args;
    maphaskey(this.packages, name) || raise(E_INVARG);
    const package = this.packages[name];
    return this:configure(name, package["objects"], package["constants"], url, expected, package["trusted_owners"]);
  endmethod

  method _keys owner: ARCH_WIZARD
    "Normalize source-setting keys and reject duplicates or unknown fields.";
    caller == this || raise(E_PERM);
    const {input, allowed} = args;
    typeof(input) == TYPE_MAP || raise(E_TYPE);
    let result = [];
    for key in (mapkeys(input))
      typeof(key) in {TYPE_STR, TYPE_SYM} || raise(E_TYPE);
      const name = tostr(key);
      name in allowed && !maphaskey(result, name) || raise(E_INVARG, "Unknown or duplicate upstream field.");
      result[name] = input[key];
    endfor
    return result;
  endmethod

  method _upstream owner: ARCH_WIZARD
    "Validate HTTP bundle URLs and Git source descriptors without network access.";
    caller == this || raise(E_PERM);
    const {source} = args;
    if (typeof(source) == TYPE_STR)
      this:_url(source);
      return source;
    endif
    const spec = this:_keys(source, {"transport", "repository", "revision", "path"});
    for key in ({"transport", "repository", "revision"})
      maphaskey(spec, key) || raise(E_INVARG, "Missing upstream field: " + key);
    endfor
    spec["transport"] == "git" || raise(E_INVARG, "Unknown upstream transport.");
    const url = spec["repository"];
    this:_url(url);
    url != "" && !index(url, "?") && !index(url, "#") || raise(E_INVARG, "Expected a Git HTTP(S) URL without a query or fragment.");
    const revision = this:_keys(spec["revision"], {"ref", "commit"});
    length(revision) == 1 || raise(E_INVARG, "Specify one full Git ref or commit.");
    if (maphaskey(revision, "commit"))
      $git:oid(revision["commit"]);
    else
      const ref = revision["ref"];
      typeof(ref) == TYPE_STR || raise(E_TYPE);
      index(ref, "refs/", 1) == 1 && length(ref) > 5 && length(ref) <= 1024 || raise(E_INVARG, "Use a full Git ref, such as refs/heads/main.");
    endif
    const path = `spec["path"] ! E_RANGE => ""';
    typeof(path) == TYPE_STR && length(path) <= 4096 || raise(E_INVARG);
    !index(path, "\\") || raise(E_INVARG, "Git paths use forward slashes.");
    if (path != "")
      for part in (explode(path, "/", true))
        !(part in {"", ".", ".."}) || raise(E_INVARG, "Git paths must be relative without dot segments.");
      endfor
    endif
    return ["transport" -> "git", "repository" -> url, "revision" -> revision, "path" -> path];
  endmethod

  method _git_sources owner: ARCH_WIZARD
    "Convert local snapshot files to objdef units. Package constants remain the authoritative bindings.";
    caller == this || raise(E_PERM);
    const {snapshot} = args;
    snapshot.complete || raise(E_INVARG, "Git staging requires a complete snapshot.");
    let sources = {};
    let bytes = 0;
    for entry in (snapshot.entries)
      if (entry.kind in {'symlink, 'submodule})
        this:_error("unsupported_git_entry", "Git source trees cannot contain symlinks or submodules: " + entry.path);
      endif
      if (entry.kind != 'file || length(entry.path) < 4)
        continue;
      endif
      if (strcmp(entry.path[length(entry.path) - 3..$], ".moo") != 0)
        continue;
      endif
      const parts = explode(entry.path, "/", true);
      // Source addresses must not replace the package's live object bindings.
      if (strcmp(parts[$], "constants.moo") == 0)
        continue;
      endif
      let text = "";
      try
        text = binary_to_str(entry.content);
      except failure (E_INVARG)
        this:_error("invalid_git_utf8", "Git objdef source is not UTF-8: " + entry.path);
      endtry
      const unit = ["label" -> entry.path, "text" -> text];
      bytes = bytes + value_bytes(unit);
      bytes <= 4194304 || raise(E_QUOTA, "Source exceeds the service limit.");
      sources = {@sources, unit};
    endfor
    length(sources) > 0 || this:_error("missing_source", "Git subtree contains no objdef object files.");
    return sources;
  endmethod

  method _save_ready owner: ARCH_WIZARD
    "Validate exact staged input and save original evidence without applying changes.";
    caller == this || raise(E_PERM);
    let {record, sources, provenance} = args;
    value_bytes(sources) <= 4194304 || raise(E_QUOTA, "Source exceeds the service limit.");
    this:_authorized(record["actor"], record["authority"]);
    set_task_perms(record["authority"]);
    const package = this.packages[record["package"]];
    package["generation"] == record["package_generation"] && package["active"] == record["id"] || this:_error("stale_package", "Package settings changed during staging.");
    const report = preview_objdef_changes(sources, record["request"]);
    provenance["digest"] = report["source_digest"];
    record["sources"] = sources;
    record["report"] = report;
    record["provenance"] = provenance;
    record["status"] = "ready";
    record["error"] = [];
    record["task"] = 0;
    value_bytes(this.pending) + value_bytes(record) <= 33554432 || raise(E_QUOTA, "Pending review storage is full.");
    this.pending[record["id"]] = record;
    return this:_summary(record);
  endmethod

  method stage owner: ARCH_WIZARD
    "Stage uploaded source, or fetch the configured upstream. Git fetches require an actual wizard.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    const {name, ?sources = {}, ?operation = "update"} = args;
    operation in {"adopt", "update"} || raise(E_INVARG);
    maphaskey(this.packages, name) || this:_error("missing_package", "Configure package bindings first.");
    const package = this.packages[name];
    package["active"] == 0 || this:_error("active_review", "A review already exists. Refresh or discard it explicitly.");
    length(this.pending) < 8 || raise(E_QUOTA);
    typeof(sources) == TYPE_LIST || raise(E_TYPE);
    if (!sources && !package["upstream"])
      this:_error("missing_source", "Upload source units or configure an upstream.");
    endif
    if (!sources && typeof(package["upstream"]) == TYPE_MAP)
      auth[1].wizard || raise(E_PERM, "Git staging requires wizard authority.");
    endif
    const id = this.next_review;
    this.next_review = id + 1;
    let record = ["id" -> id, "generation" -> 1, "actor" -> auth[1], "authority" -> auth[2], "package" -> name, "package_generation" -> package["generation"], "upstream" -> package["upstream"], "status" -> "fetching", "task" -> 0, "error" -> [], "sources" -> {}, "report" -> [], "choices" -> [], "provenance" -> [], "request" -> ["schema" -> 1, "operation" -> operation, "objects" -> package["objects"], "fields" -> package["fields"], "constants" -> package["constants"], "trusted_owners" -> package["trusted_owners"]]];
    this.packages[name]["active"] = id;
    this.pending[id] = record;
    if (sources)
      try
        return this:_save_ready(record, sources, ["transport" -> "upload"]);
      except failure (ANY)
        record["status"] = "failed";
        record["error"] = typeof(failure[3]) == TYPE_MAP ? failure[3] | ["schema" -> 1, "code" -> "compile_failure", "message" -> tostr(failure[2])];
        this.pending[id] = record;
        return this:_summary(record);
      endtry
    endif
    const parent_task = task_id();
    fork fetch_task (0)
      this:_await_job(id, 1, parent_task);
      this:_fetch(id, 1);
    endfork
    record["task"] = fetch_task;
    this.pending[id] = record;
    return this:_summary(record);
  endmethod

  method _await_job owner: ARCH_WIZARD
    "Forks can start before the parent commits; wait for this job's persisted identity.";
    caller == this && this == $change_manager || raise(E_PERM);
    const {id, generation, parent_task} = args;
    let parent_ended = false;
    for attempt in [1..1000]
      if (maphaskey(this.pending, id))
        const record = this.pending[id];
        if (record["generation"] == generation && record["task"] == task_id())
          return;
        endif
      endif
      !parent_ended || raise(E_INVARG, "Job was not committed by its parent.");
      parent_ended = !valid_task(parent_task);
      suspend(0.01);
    endfor
    raise(E_QUOTA, "Timed out waiting for the saved job.");
  endmethod

  method _job owner: ARCH_WIZARD
    "Validate a background task's saved identity, generation, package, and authority.";
    caller == this && this == $change_manager || raise(E_PERM);
    const {id, generation, status} = args;
    maphaskey(this.pending, id) || raise(E_INVARG);
    const record = this.pending[id];
    record["generation"] == generation && record["status"] == status && record["task"] == task_id() || raise(E_PERM);
    this:_authorized(record["actor"], record["authority"]);
    set_task_perms(record["authority"]);
    const package = this.packages[record["package"]];
    package["active"] == id && package["generation"] == record["package_generation"] || raise(E_INVARG);
    return record;
  endmethod

  method _fetch owner: ARCH_WIZARD
    "Fetch saved upstream settings; recheck authority and job identity before saving any source.";
    caller == this || raise(E_PERM);
    const {id, generation} = args;
    let record = this:_job(id, generation, "fetching");
    set_task_perms(record["authority"]);
    try
      const upstream = `record["upstream"] ! E_RANGE => this.packages[record["package"]]["upstream"]';
      if (typeof(upstream) == TYPE_MAP)
        record["actor"].wizard || raise(E_PERM, "Git staging requires wizard authority.");
        const repository = $git:repository(upstream["repository"],
          ['max_entries -> 4096, 'max_file_bytes -> 4194304, 'max_total_bytes -> 4194304]);
        const snapshot = repository:snapshot(upstream["revision"], upstream["path"]);
        record = this:_job(id, generation, "fetching");
        record["actor"].wizard || raise(E_PERM, "Git staging requires wizard authority.");
        const sources = this:_git_sources(snapshot);
        this:_save_ready(record, sources, ["transport" -> "git", "repository" -> upstream["repository"],
          "revision" -> upstream["revision"], "commit" -> snapshot.commit,
          "tree" -> snapshot.tree, "path" -> snapshot.path]);
        return;
      endif
      const url = upstream;
      const response = worker_request("curl", {"GET", url, "", {}, ["max_bytes" -> 4194304, "strict_utf8" -> true, "include_url" -> true]}, ["timeout_seconds" -> 30.0]);
      record = this:_job(id, generation, "fetching");
      length(response) == 4 && response[1] == 200 || this:_error("http_failure", "HTTP bundle fetch did not return status 200.");
      let etag = "";
      for header in (response[2])
        if (header[1] == "etag")
          etag = header[2];
        endif
      endfor
      this:_save_ready(record, {["label" -> "http-bundle.moo", "text" -> response[3]]}, ["transport" -> "http", "url" -> response[4], "etag" -> etag]);
    except failure (ANY)
      if (maphaskey(this.pending, id) && this.pending[id]["generation"] == generation && this.pending[id]["task"] == task_id())
        record = this.pending[id];
        record["status"] = "failed";
        record["task"] = 0;
        record["error"] = typeof(failure[3]) == TYPE_MAP ? failure[3] | ["schema" -> 1, "code" -> "fetch_failed", "message" -> tostr(failure[2])];
        this.pending[id] = record;
      endif
    endtry
  endmethod

  method status owner: ARCH_WIZARD
    "Return committed status and detect an interrupted fetch or apply task.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    const {id} = args;
    if (maphaskey(this.receipts, id))
      const receipt = this.receipts[id];
      receipt["actor"] == auth[1] || auth[1].wizard || raise(E_PERM);
      return receipt;
    endif
    let record = this:_get(auth, id);
    if (record["status"] in {"fetching", "applying"} && !valid_task(record["task"]))
      const fetching = record["status"] == "fetching";
      record["status"] = fetching ? "failed" | "interrupted";
      record["task"] = 0;
      record["generation"] = record["generation"] + 1;
      record["error"] = ["schema" -> 1, "code" -> fetching ? "fetch_interrupted" | "interrupted", "message" -> fetching ? "Fetch ended without a result. Check worker availability, discard, and stage again." | "Task ended without a receipt. Refresh or discard this review."];
      this.pending[id] = record;
    endif
    let summary = this:_summary(record);
    if (maphaskey(record, "last_receipt"))
      summary["last_receipt"] = record["last_receipt"];
    endif
    return summary;
  endmethod

  method review owner: ARCH_WIZARD
    "Return a bounded row page; the cursor binds review ID, generation, and offset.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    const {id, generation, ?cursor = {}, ?classification = ""} = args;
    const record = this:_get(auth, id, generation);
    record["status"] in {"ready", "partial", "rejected"} || this:_error("not_ready", "Review is not ready.");
    let offset = 1;
    if (cursor)
      length(cursor) == 3 && cursor[1] == id && cursor[2] == generation || this:_error("stale_cursor", "Cursor belongs to another review generation.");
      offset = cursor[3];
    endif
    typeof(offset) == TYPE_INT && offset >= 1 || raise(E_INVARG);
    const rows = record["report"]["rows"];
    let page = {};
    let next_offset = offset;
    for i in [offset..length(rows)]
      next_offset = i + 1;
      let row = rows[i];
      if (classification != "" && row["classification"] != classification)
        continue;
      endif
      const choice = `record["choices"][row["id"]] ! E_RANGE => []';
      row["choice"] = choice ? ["choice" -> choice["choice"], "validated" -> maphaskey(choice, "validation")] | [];
      if (value_bytes(page) + value_bytes(row) > 262144)
        length(page) > 0 || raise(E_QUOTA, "Row exceeds the page limit.");
        next_offset = i;
        break;
      endif
      page = {@page, row};
      if (length(page) == 50)
        break;
      endif
    endfor
    const next_cursor = next_offset <= length(rows) ? {id, generation, next_offset} | {};
    return ["schema" -> 1, "review_id" -> id, "generation" -> generation, "total" -> length(rows), "rows" -> page, "cursor" -> next_cursor, "counts" -> record["report"]["counts"], "diagnostic_count" -> length(record["report"]["diagnostics"]), "diagnostics" -> record["report"]["diagnostics"][1..min(50, length(record["report"]["diagnostics"]))], "provenance" -> record["provenance"]];
  endmethod

  method diagnostics owner: ARCH_WIZARD
    "Return a bounded diagnostic page bound to the saved review generation.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    const {id, generation, ?offset = 1} = args;
    const record = this:_get(auth, id, generation);
    record["status"] in {"ready", "partial", "rejected"} || this:_error("not_ready", "Review is not ready.");
    typeof(offset) == TYPE_INT && offset >= 1 || raise(E_INVARG);
    const all = record["report"]["diagnostics"];
    const page = all[offset..min(offset + 49, length(all))];
    value_bytes(page) <= 262144 || raise(E_QUOTA, "Diagnostic page exceeds the service limit.");
    return ["schema" -> 1, "review_id" -> id, "generation" -> generation, "total" -> length(all), "diagnostics" -> page, "next" -> offset + length(page) <= length(all) ? offset + length(page) | 0];
  endmethod

  method details owner: ARCH_WIZARD
    "Return selected live/incoming text only while original review evidence still matches.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    const {id, generation, row_id} = args;
    const record = this:_get(auth, id, generation);
    let request = record["request"];
    request["details"] = {row_id};
    const current = preview_objdef_changes(record["sources"], request);
    current["evidence"] == record["report"]["evidence"] || this:_error("stale_review", "Live state changed. Refresh before reading details.");
    for selected in (current["rows"])
      let row = selected;
      if (row["id"] == row_id)
        row["choice"] = `record["choices"][row_id] ! E_RANGE => []';
        value_bytes(row) <= 524288 || raise(E_QUOTA, "Selected details exceed the service limit.");
        return ["schema" -> 1, "review_id" -> id, "generation" -> generation, "row" -> row];
      endif
    endfor
    this:_error("missing_row", "No such review row.");
  endmethod

  method resolve owner: ARCH_WIZARD
    "Save a conditional choice or edited draft, with native result validation.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    const {id, generation, row_id, kind, ?program = ""} = args;
    let record = this:_get(auth, id, generation);
    record["status"] in {"ready", "partial", "rejected"} || this:_error("not_ready", "Review is not ready.");
    let choice = ["choice" -> kind];
    if (kind == "edited")
      value_bytes(program) <= 524288 || raise(E_QUOTA);
      choice["program"] = program;
    endif
    record["choices"][row_id] = choice;
    const current = preview_objdef_changes(record["sources"], record["request"], record["choices"]);
    current["evidence"] == record["report"]["evidence"] || this:_error("stale_review", "Live state changed. Refresh before choosing.");
    for validation in (current["validation"])
      if (validation["id"] == row_id && validation["valid"])
        record["choices"][row_id]["validation"] = validation["validation"];
      endif
    endfor
    record["generation"] = generation + 1;
    record["status"] = "ready";
    record["error"] = [];
    value_bytes(this.pending) + value_bytes(record) <= 33554432 || raise(E_QUOTA);
    this.pending[id] = record;
    return ["schema" -> 1, "review_id" -> id, "generation" -> record["generation"], "validation" -> current["validation"]];
  endmethod

  method refresh owner: ARCH_WIZARD
    "Create new evidence from saved input and discard all earlier choices.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    const {id, generation} = args;
    let record = this:_get(auth, id, generation);
    !(record["status"] in {"fetching", "applying"}) || this:_error("busy", "Task is still running.");
    length(record["sources"]) > 0 || this:_error("missing_source", "Discard this failed fetch and stage again.");
    record["choices"] = [];
    record["generation"] = generation + 1;
    return this:_save_ready(record, record["sources"], record["provenance"]);
  endmethod

  method apply owner: ARCH_WIZARD
    "Start one dedicated application task; success is reported only by a committed receipt.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    const {id, generation} = args;
    if (maphaskey(this.receipts, id))
      return this:status(id);
    endif
    let record = this:_get(auth, id);
    if (record["status"] == "applying")
      return this:_summary(record);
    endif
    record["generation"] == generation || this:_error("stale_generation", "Review choices changed.");
    record["status"] in {"ready", "partial"} || this:_error("not_ready", "Review is not ready.");
    record["generation"] = generation + 1;
    record["status"] = "applying";
    record["error"] = [];
    const parent_task = task_id();
    fork apply_task (0)
      this:_await_job(id, generation + 1, parent_task);
      this:_apply(id, generation + 1);
    endfork
    record["task"] = apply_task;
    this.pending[id] = record;
    return this:_summary(record);
  endmethod

  method _apply owner: ARCH_WIZARD
    "Commit content, baselines, and a source-free receipt together, or abort the task.";
    caller == this || raise(E_PERM);
    const {id, generation} = args;
    let record = this:_job(id, generation, "applying");
    set_task_perms(record["authority"]);
    let wrote = false;
    try
      const result = apply_objdef_changes(record["sources"], record["request"], record["report"]["evidence"], record["choices"]);
      wrote = true;
      let deferred = false;
      for diagnostic in (record["report"]["diagnostics"])
        if (diagnostic["code"] in {"missing_source", "unsupported_creation", "unsupported_or_ambiguous_definition"})
          deferred = true;
        endif
      endfor
      for row in (record["report"]["rows"])
        const kind = `record["choices"][row["id"]]["choice"] ! E_RANGE => row["default"]';
        if (kind == "defer" && (record["request"]["operation"] == "adopt" || row["classification"] in {"upstream", "conflict", "unbased"}))
          deferred = true;
        endif
      endfor
      record["generation"] = generation + 1;
      record["task"] = 0;
      record["choices"] = [];
      record["error"] = [];
      if (deferred)
        record["status"] = "partial";
        record["report"] = preview_objdef_changes(record["sources"], record["request"]);
        this.pending[id] = record;
      else
        record["status"] = "complete";
        this.pending = mapdelete(this.pending, id);
        this.packages[record["package"]]["active"] = 0;
      endif
      // Do not call MOO helpers after installation: this package may have updated their code.
      let receipt = ["schema" -> 1, "review_id" -> id, "generation" -> record["generation"], "package" -> record["package"], "status" -> record["status"], "task" -> 0, "error" -> []];
      receipt["actor"] = record["actor"];
      receipt["provenance"] = record["provenance"];
      receipt["decision_count"] = length(result["decisions"]);
      receipt["decisions"] = result["decisions"][1..min(50, length(result["decisions"]))];
      receipt["source_digest"] = record["report"]["source_digest"];
      receipt["completed_at"] = time();
      if (deferred)
        this.pending[id]["last_receipt"] = receipt;
      else
        this.receipts[id] = receipt;
        if (length(this.receipts) > 64)
          this.receipts = mapdelete(this.receipts, mapkeys(this.receipts)[1]);
        endif
      endif
    except failure (ANY)
      if (wrote)
        rollback();
      endif
      record["status"] = "rejected";
      record["task"] = 0;
      record["generation"] = generation + 1;
      record["error"] = ["schema" -> 1, "code" -> "apply_rejected", "message" -> tostr(failure[2])];
      this.pending[id] = record;
    endtry
  endmethod

  method discard owner: ARCH_WIZARD
    "Remove pending source and drafts with a generation check.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    const {id, generation} = args;
    const record = this:_get(auth, id, generation);
    record["status"] != "applying" || this:_error("busy", "Apply is running. Query status before discarding.");
    this.pending = mapdelete(this.pending, id);
    this.packages[record["package"]]["active"] = 0;
    return ["schema" -> 1, "review_id" -> id, "status" -> "discarded"];
  endmethod
  method command owner: ARCH_WIZARD
    "Terminal wrapper for the versioned review service; writes require a displayed generation.";
    const auth = this:_entry(caller_perms());
    set_task_perms(auth[2]);
    let {words} = args;
    const usage = {"@changes packages", "@changes package NAME #OBJECT ...", "@changes upstream [NAME] HTTP-BUNDLE-URL", "@changes upstream [NAME] git REPOSITORY FULL-REF-OR-COMMIT [PATH]", "@changes stage [NAME] | adopt [NAME]", "@changes status ID", "@changes diff ID [OFFSET]", "@changes source ID GENERATION ROW live|incoming [OFFSET]", "@changes resolve ID GENERATION ROW incoming|local|defer", "@changes resolve ID GENERATION ROW edited PROGRAM", "@changes apply ID GENERATION | refresh ID GENERATION | discard ID GENERATION", "Uploads: $change_manager:stage(NAME, {[\"label\" -> \"file.moo\", \"text\" -> LINES]})."};
    if (!words || words[1] == "help")
      return usage;
    endif
    const action = words[1];
    if (action == "upstream" && length(words) >= 2)
      const git_index = words[2] == "git" ? 2 | 3;
      if (length(words) >= git_index && words[git_index] == "git")
        length(words) in {git_index + 2, git_index + 3} || raise(E_INVARG, "Expected Git repository, full ref or commit, and optional path.");
        const name = git_index == 2 ? this.default_package | words[2];
        const revision = words[git_index + 2];
        const key = index(revision, "sha1:", 1) == 1 ? "commit" | "ref";
        const path = length(words) == git_index + 3 ? words[git_index + 3] | "";
        this:upstream(name, ["transport" -> "git", "repository" -> words[git_index + 1],
          "revision" -> [key -> revision], "path" -> path], this.packages[name]["generation"]);
        return {"Git upstream configured."};
      endif
    endif
    if (action in {"stage", "adopt"} && length(words) == 1)
      words = {@words, this.default_package};
    elseif (action == "upstream" && length(words) == 2)
      words = {action, this.default_package, words[2]};
    endif
    if (action == "packages")
      let output = {"Change packages:"};
      for name in (mapkeys(this.packages))
        const package = this.packages[name];
        output = {@output, tostr(name, " generation=", package["generation"], " objects=", length(package["objects"]), " active=", package["active"], " upstream=", toliteral(package["upstream"]))};
      endfor
      return output;
    endif
    if (action == "package" && length(words) >= 3)
      let objects = {};
      let constants = [];
      for i in [3..length(words)]
        const object = toobj(words[i]);
        valid(object) || raise(E_INVARG, "Package targets must be valid object addresses.");
        objects = {@objects, object};
        const name = object_metadata(object, "import_export_id");
        if (typeof(name) == TYPE_STR && name != "")
          constants[name] = object;
        endif
      endfor
      const previous = `this.packages[words[2]]["generation"] ! E_RANGE => 0';
      const owners = `this.packages[words[2]]["trusted_owners"] ! E_RANGE => {}';
      const result = this:configure(words[2], objects, constants, "", previous, owners);
      return {tostr("Package ", words[2], " configured at generation ", result["generation"], ".")};
    endif
    if (action == "upstream" && length(words) == 3)
      const package = this.packages[words[2]];
      this:upstream(words[2], words[3], package["generation"]);
      return {"HTTP upstream configured."};
    endif
    if (action in {"stage", "adopt"} && length(words) == 2)
      const result = this:stage(words[2], {}, action == "adopt" ? "adopt" | "update");
      return {toliteral(result)};
    endif
    if (length(words) < 2)
      return usage;
    endif
    const id = toint(words[2]);
    if (action == "status")
      return {toliteral(this:status(id))};
    endif
    if (action == "diff")
      const status = this:status(id);
      const offset = length(words) == 3 ? toint(words[3]) | 1;
      const page = this:review(id, status["generation"], {id, status["generation"], offset});
      let output = {tostr("Review ", id, " generation ", status["generation"], " (", page["total"], " rows)"), tostr("Source: ", toliteral(page["provenance"]))};
      for row in (page["rows"])
        output = {@output, tostr(row["id"], " ", row["classification"], " eligible=", row["eligible"], " default=", row["default"], " choice=", toliteral(row["choice"]), " blockers=", toliteral(row["blockers"]))};
      endfor
      if (page["cursor"])
        output = {@output, tostr("Next: @changes diff ", id, " ", page["cursor"][3])};
      endif
      return output;
    endif
    if (length(words) < 3)
      return usage;
    endif
    const generation = toint(words[3]);
    if (action == "source" && length(words) in {5, 6})
      const detail = this:details(id, generation, words[4]);
      words[5] in {"live", "incoming"} || raise(E_INVARG);
      const lines = explode(detail["row"][tostr(words[5], "_text")], "\n", true);
      const offset = length(words) == 6 ? toint(words[6]) | 1;
      offset >= 1 && offset <= length(lines) || raise(E_INVARG);
      let output = {tostr(words[5], " decompiled program; base text unavailable")};
      for i in [offset..min(offset + 49, length(lines))]
        value_bytes(output) + value_bytes(lines[i]) <= 65536 || raise(E_QUOTA, "Source page exceeds the terminal limit. Use the details API.");
        output = {@output, tostr(i, ": ", lines[i])};
      endfor
      return output;
    endif
    if (action == "apply" && length(words) == 3)
      return {toliteral(this:apply(id, generation))};
    elseif (action == "refresh" && length(words) == 3)
      return {toliteral(this:refresh(id, generation))};
    elseif (action == "discard" && length(words) == 3)
      return {toliteral(this:discard(id, generation))};
    elseif (action == "resolve" && length(words) >= 5)
      let program = "";
      for i in [6..length(words)]
        program = tostr(program, i == 6 ? "" | " ", words[i]);
      endfor
      return {toliteral(this:resolve(id, generation, words[4], words[5], program))};
    endif
    return usage;
  endmethod
endobject
