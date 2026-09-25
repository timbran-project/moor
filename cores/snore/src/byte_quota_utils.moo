object BYTE_QUOTA_UTILS [
  import_export_id -> "byte_quota_utils"
]
  name: "Byte Quota Utilities"
  parent: GENERIC_UTILS
  owner: HACKER
  readable: true

  property byte_based (owner: HACKER, flags: "rc") = true;
  property cycle_days (owner: HACKER, flags: "rc") = 5;
  property default_quota (owner: HACKER, flags: "rc") = {20000, 0, 0, 1};
  property exempted (owner: HACKER, flags: "rc") = {};
  property large_negative_number (owner: HACKER, flags: "rc") = -10000;
  property large_objects (owner: HACKER, flags: "rc") = {SPELL};
  property max_unmeasured (owner: HACKER, flags: "rc") = 10;
  property measurement_task_running (owner: HACKER, flags: "rc") = false;
  property repeat_cycle (owner: HACKER, flags: "rc") = false;
  property report_recipients (owner: HACKER, flags: "rc") = {#2};
  property task_time_limit (owner: HACKER, flags: "rc") = 500;
  property too_large (owner: HACKER, flags: "rc") = 1000000;
  property unmeasured_multiplier (owner: HACKER, flags: "rc") = 100;
  property working (owner: HACKER, flags: "rc") = #2;

  override aliases (owner: HACKER, flags: "rc") = {"Byte Quota Utilities"};
  override description (owner: HACKER, flags: "rc") = {
    "This is the Byte Quota Utilities utility package.  See `help $quota_utils' for more details."
  };
  override help_msg (owner: HACKER, flags: "rc") = {
    "Verbs a user might want to call from a program:",
    " :bi_create -- built-in create() call, takes same args.",
    "",
    " :get_quota(who) -- just get the raw size_quota property",
    " :display_quota(who) -- prints to player the quota of who.  If caller_perms() controls who, include any secondary characters.  Called by @quota.",
    " :get_size_quota(who [allchars]) -- return the quota of who, if allchars flag set, add info from all secondary chars, if caller_perms() permits.",
    "",
    " :value_bytes(value) -- computes the size of the value.",
    " :object_bytes(object) -- computes the size of the object and caches it.",
    " :recent_object_bytes(object, days) -- computes and caches the size of object only if cached value more than days old.  Returns cached value.",
    " :do_summary(user) -- prints out the results of summarize-one-user.",
    " :summarize_one_user(user) -- summarizes and caches space usage for user.  See verb help for details.",
    "",
    "Verbs the system calls:",
    " :\"creation_permitted verb_addition_permitted property_addition_permitted\"(who) -- returns true if who is permitted to build.",
    " :initialize_quota(who) -- sets quota for newly created players",
    " :adjust_quota_for_programmer(who) -- empty; might add more quota to newly @progged player.",
    " :enable_create(who) -- sets .ownership_quota to 1",
    " :disable_create(who) -- sets .ownership_quota back to -1000 to prohibit create()",
    " :charge_quota(who, object) -- subtract the size of object from who's quota.  Manipulates the #-unmeasured if what is not currently measured.  Called by $wiz_utils:set_owner.",
    " :reimburse_quota(who, object) -- add the size of object to who's quota.  Ditto.",
    " :set_quota(who, howmuch)",
    " :quota_remaining(who) ",
    " :display_quota_summary -- internal, called by display quota",
    "",
    "The measurement task:",
    " :schedule_measurement_task() schedules a single worker at 08:00 UTC.",
    " :measurement_task([seconds]) runs a bounded pass and sends the configured report.",
    " :measurement_task_nofork([seconds]) is a one-shot alias.",
    " .measurement_task_running holds its task ID, or false when not scheduled.",
    " .task_time_limit sets the duration of a pass. Work commits between complete owners.",
    " .cycle_days sets the maximum cached measurement age.",
    " .repeat_cycle permits additional passes with fresher measurements within that time.",
    " .exempted lists objects whose existing cached sizes should be retained.",
    " .report_recipients receives the report; an empty list disables reports.",
    "Measurements are estimates. Custom measurement hooks must preserve the no-suspend contract.",
    "The object-count quota alternative requires native ownership_quota support."
  };
  override object_size (owner: HACKER, flags: "r") = {32429, 1084848672};

  method initialize_quota owner: HACKER
    "Initialize private byte-quota counters for a player. Wizard callers only.";
    !caller_perms().wizard && return E_PERM;
    args[1].size_quota = this.default_quota;
    args[1].ownership_quota = this.large_negative_number;
  endmethod

  method init_for_core owner: #2
    "Reset this object for an extracted core. Wizard callers only.";
    !caller_perms().wizard && return E_PERM;
    pass(@args);
    this.exempted = {};
    this.working = #2;
    this.measurement_task_running = false;
    this.task_time_limit = 500;
    this.repeat_cycle = false;
    this.large_objects = {};
    this.report_recipients = {#2};
    this.default_quota = {100000, 0, 0, 1};
    $quota_utils = this;
  endmethod

  method adjust_quota_for_programmer owner: HACKER
    "Leave byte quota unchanged on programmer promotion.";
    return 0;
  endmethod

  method bi_create owner: #2
    "Create with caller authority after checking byte quota; charge a successful creation.";
    set_task_perms(caller_perms());
    const who = this:parse_create_args(@args);
    typeof(who) == TYPE_ERR && return who;
    !this:creation_permitted(who) && return E_QUOTA;
    this:enable_create(who);
    const value = `create(@args) ! ANY';
    this:disable_create(who);
    if (typeof(value) != TYPE_ERR)
      this:charge_quota(who, value);
      if (typeof(who.owned_objects) == TYPE_LIST && !(value in who.owned_objects))
        this:add_owned_object(who, value);
      endif
    endif
    return value;
  endmethod

  method enable_create owner: #2
    "Permit a creation through this package or a wizard caller.";
    caller != this && !caller_perms().wizard && return E_PERM;
    args[1].ownership_quota = 1;
  endmethod

  method disable_create owner: #2
    "Restore the native quota sentinel after a creation attempt.";
    caller != this && !caller_perms().wizard && return E_PERM;
    args[1].ownership_quota = this.large_negative_number;
  endmethod

  method parse_create_args owner: HACKER
    "This figures out who is gonna own the stuff @create does.  If one arg, return caller_perms().  If two args, then if caller_perms().wizard, args[2].";
    const {what, ?who = #-1} = args;
    !valid(who) && return caller_perms();
    $perm_utils:controls(caller_perms(), who) && return who;
    return E_INVARG;
  endmethod

  method "creation_permitted verb_addition_permitted property_addition_permitted" owner: HACKER
    "Return whether cached byte allowance and unmeasured-object limits permit building.";
    const who = args[1];
    if (who.wizard || who == $hacker)
      return true;
    endif
    if (!$object_utils:has_property(who, "size_quota") || is_clear_property(who, "size_quota"))
      return false;
    endif
    $recycler:check_quota_scam(who);
    const allwho = this:all_characters(who);
    let quota = 0;
    let usage = 0;
    let unmeasured = 0;
    for x in (allwho)
      quota = quota + x.size_quota[1];
      usage = usage + x.size_quota[2];
      unmeasured = unmeasured + x.size_quota[4];
    endfor
    usage >= quota && return false;
    unmeasured >= this.max_unmeasured && return false;
    return true;
  endmethod

  method all_characters owner: HACKER
    "Return a permitted player's linked characters, or just that player.";
    const {who} = args;
    caller != this && !this:can_peek(caller_perms(), who) && return E_PERM;
    if ($object_utils:has_property($local, "second_char_registry"))
      const seconds = $local.second_char_registry:all_second_chars(who);
      seconds == E_INVARG && return {who};
      return seconds;
    else
      return {who};
    endif
  endmethod

  method display_quota owner: HACKER
    "Print cached quota and usage, including linked characters when permitted.";
    let tquota;
    let tusage;
    let ttime;
    let tunmeasured;
    let tunmeasurable;
    let quota;
    let usage;
    let timestamp;
    let unmeasured;
    let unmeasurable;
    const who = args[1];
    const all = this:can_peek(caller_perms(), who) ? this:all_characters(who) | {who};
    const many = length(all) > 1;
    if (many)
      tquota = 0;
      tusage = 0;
      ttime = $maxint;
      tunmeasured = 0;
      tunmeasurable = 0;
    endif
    for x in (all)
      {quota, usage, timestamp, unmeasured} = x.size_quota;
      unmeasurable = 0;
      if (unmeasured >= 100)
        unmeasurable = unmeasured / 100;
        unmeasured = unmeasured % 100;
      endif
      if (many)
        player:tell(x.name, " quota: ", $string_utils:group_number(quota), "; usage: ", $string_utils:group_number(usage), "; unmeasured: ", unmeasured, "; no .object_size: ", unmeasurable, ".");
        tquota = tquota + quota;
        tusage = tusage + usage;
        ttime = min(ttime, timestamp);
        tunmeasured = tunmeasured + unmeasured;
        tunmeasurable = tunmeasurable + unmeasurable;
      endif
    endfor
    if (many)
      this:display_quota_summary(who, tquota, tusage, ttime, tunmeasured, tunmeasurable);
    else
      this:display_quota_summary(who, quota, usage, timestamp, unmeasured, unmeasurable);
    endif
  endmethod

  method get_quota owner: HACKER
    "Return the player's configured byte allowance.";
    return args[1].size_quota[1];
  endmethod

  method charge_quota owner: HACKER
    "Charge args[1] for the quota required to own args[2]";
    let {who, what} = args;
    if (caller == this || caller_perms().wizard)
      const usage_index = 2;
      const unmeasured_index = 4;
      const object_size = $object_utils:has_property(what, "object_size") ? what.object_size[1] | -1;
      if (object_size <= 0)
        who.size_quota[unmeasured_index] = who.size_quota[unmeasured_index] + 1;
      else
        who.size_quota[usage_index] = who.size_quota[usage_index] + object_size;
      endif
    else
      return E_PERM;
    endif
  endmethod

  method reimburse_quota owner: HACKER
    "reimburse args[1] for the quota required to own args[2]";
    "If it is a $garbage, then if who = $hacker, then we mostly ignore everything.  Who cares what $hacker's quota looks like.";
    let {who, what} = args;
    if (caller == this || caller_perms().wizard)
      const usage_index = 2;
      const unmeasured_index = 4;
      parent(what) == $garbage && return 0;
      if (valid(who) && is_player(who) && $object_utils:has_property(what, "object_size") && !is_clear_property(who, "size_quota"))
        const object_size = what.object_size[1];
        if (object_size <= 0)
          who.size_quota[unmeasured_index] = who.size_quota[unmeasured_index] - 1;
        else
          who.size_quota[usage_index] = who.size_quota[usage_index] - object_size;
        endif
      endif
    else
      return E_PERM;
    endif
  endmethod

  method set_quota owner: HACKER
    "Set args[1]'s quota to args[2]";
    if (caller_perms().wizard || caller == this || this:can_touch(caller_perms()))
      "Size_quota[1] is the total quota permitted.";
      return args[1].size_quota[1] = args[2];
    else
      return E_PERM;
    endif
  endmethod

  method get_size_quota owner: HACKER
    "Return args[1]'s quotas.  second arg of 1 means add all second chars.";
    let who;
    let all;
    {who, ?all = 0} = args;
    if (all && (caller == this || this:can_peek(caller_perms(), who)))
      all = this:all_characters(who);
    else
      all = {who};
    endif
    const baseline = {0, 0, 0, 0};
    for x in (all)
      baseline[1] = baseline[1] + x.size_quota[1];
      baseline[2] = baseline[2] + x.size_quota[2];
      baseline[3] = min(baseline[3], x.size_quota[3]) || x.size_quota[3];
      baseline[4] = baseline[4] + x.size_quota[4];
    endfor
    return baseline;
  endmethod

  method display_quota_summary owner: HACKER
    "Print the supplied usage totals and unmeasured-object counts.";
    let plural;
    const {who, quota, usage, timestamp, unmeasured, unmeasurable} = args;
    player:tell(who.name, " has a total building quota of ", $string_utils:group_number(quota), " bytes.");
    player:tell($gender_utils:get_pronoun("P", who), " total usage was ", $string_utils:group_number(usage), " as of ", player:ctime(timestamp), ".");
    if (usage > quota)
      player:tell(who.name, " is over quota by ", $string_utils:group_number(usage - quota), " bytes.");
    else
      player:tell(who.name, " may create up to ", $string_utils:group_number(quota - usage), " more bytes of objects, properties, or verbs.");
    endif
    if (unmeasured)
      plural = unmeasured != 1;
      player:tell("There ", plural ? tostr("are ", unmeasured, " objects") | "is 1 object", " which ", plural ? "are" | "is", " not yet included in the tally; this tally may thus be inaccurate.");
      if (unmeasured >= this.max_unmeasured)
        player:tell("The number of unmeasured objects is too large; no objects may be created until @measure new is used.");
      endif
    endif
    if (unmeasurable)
      plural = unmeasurable != 1;
      player:tell("There ", plural ? tostr("are ", unmeasurable, " objects") | "is 1 object", " which do", plural ? "" | "es", " not have a .object_size property and will thus prevent additional building.", who == player ? "  Contact a wizard for assistance in having this situation repaired." | "");
    endif
  endmethod

  method quota_remaining owner: HACKER
    "This wants to only be called by a wizard cuz I'm lazy.  This is just for @second-char anyway.";
    if (caller_perms().wizard)
      const q = this:get_size_quota(args[1], 1);
      return q[1] - q[2];
    endif
  endmethod

  method value_bytes owner: #2
    "Return mooR's byte estimate for a value.";
    return value_bytes(args[1]);
  endmethod

  method "object_bytes object_size" owner: #2
    "Measure and cache an object; update its owner accounting in the same transaction.";
    this:can_peek(caller_perms(), args[1].owner) || return E_PERM;
    let o = args[1];
    if ($object_utils:has_property(o, "object_size") && o.object_size[1] > this.too_large && !caller_perms().wizard && caller_perms() != this.owner && caller_perms() != $hacker)
      return o.object_size[1];
    endif
    const b = object_bytes(o);
    if ($object_utils:has_property(o, "object_size"))
      const oldsize = is_clear_property(o, "object_size") ? 0 | o.object_size[1];
      if ($object_utils:has_property(o.owner, "size_quota"))
        "Update quota cache.";
        if (oldsize)
          o.owner.size_quota[2] = o.owner.size_quota[2] + (b - oldsize);
        else
          o.owner.size_quota[2] = o.owner.size_quota[2] + b;
          if (o.owner.size_quota[4] > 0)
            o.owner.size_quota[4] = o.owner.size_quota[4] - 1;
          endif
        endif
      endif
      o.object_size = {b, time()};
    endif
    if (b > this.too_large)
      this.large_objects = setadd(this.large_objects, o);
    endif
    return b;
  endmethod

  verb do_summary (any with this) owner: HACKER flags: "rxd"
    "Summarize a permitted player's objects and print the accounting result.";
    const who = args[1];
    const results = this:summarize_one_user(who);
    const {total, nuncounted, nzeros, oldest, eldest} = results;
    player:tell(who.name, " statistics:");
    player:tell("  ", $string_utils:group_number(total), " bytes of storage measured.");
    player:tell("  Oldest measurement date ", ctime(oldest), " (", $string_utils:from_seconds(time() - oldest), " ago) of object ", eldest, " (", valid(eldest) ? eldest.name | "$nothing", ")");
    if (nzeros || nuncounted)
      player:tell("  Number of objects with no statistics recorded:  ");
      player:tell("      ", nzeros, " recently created, ", nuncounted, " not descendents of #1");
    endif
  endverb

  method summarize_one_user owner: HACKER
    "Return {bytes, unmeasurable, unmeasured, oldest_time, oldest_object} and cache totals.";
    "An optional age in seconds remeasures older objects; a negative age measures new objects.";
    "The standard measurement path does not suspend within one owner's accounting update.";
    const {who, ?age = false} = args;
    this:can_peek(caller_perms(), who) || return E_PERM;
    const earliest = typeof(age) == TYPE_INT ? age < 0 ? 1 | time() - age | 0;
    let unmeasured = 0;
    let oldest = time();
    let oldest_object = $nothing;
    let unmeasurable = 0;
    let total = 0;
    for object in (typeof(who.owned_objects) == TYPE_LIST ? who.owned_objects | {})
      if (!valid(object) || object.owner != who)
        continue;
      endif
      if (!$object_utils:has_property(object, "object_size"))
        unmeasurable = unmeasurable + 1;
        continue;
      endif
      if (object.object_size[2] < earliest && !(object in this.exempted))
        this:object_bytes(object);
      endif
      const {size, timestamp} = object.object_size;
      if (!timestamp)
        unmeasured = unmeasured + 1;
      elseif (timestamp <= oldest)
        oldest = timestamp;
        oldest_object = object;
      endif
      total = total + max(0, size);
    endfor
    if (!is_clear_property(who, "size_quota"))
      who.size_quota[2] = total;
      who.size_quota[3] = oldest;
      who.size_quota[4] = unmeasurable * this.unmeasured_multiplier + unmeasured;
    endif
    return {total, unmeasurable, unmeasured, oldest, oldest_object};
  endmethod

  method recent_object_bytes owner: #2
    ":recent_object_bytes(x, n) -- return object size of x, guaranteed to be no more than n days old.  N defaults to this.cycle_days.";
    const {object, ?since = this.cycle_days} = args;
    !valid(object) && return 0;
    if (`object.object_size[2] ! ANY => 0' > time() - since * 24 * 60 * 60)
      "Trap error when doesn't have .object_size for some oddball reason ($garbage). Ho_Yan 11/19/96";
      return object.object_size[1];
    else
      return this:object_bytes(object);
    endif
  endmethod

  method measurement_task owner: #2
    "Run a bounded measurement pass and optionally mail its report. Wizard callers only.";
    caller_perms().wizard || return E_PERM;
    const start = time();
    const result = this:measurement_task_body(@args);
    typeof(result) == TYPE_ERR && return result;
    if (this.report_recipients)
      $mail_agent:send_message(this.owner, this.report_recipients, "Quota measurement report", {tostr("Measured ", result[1], " owners in ", time() - start, " seconds.")});
    endif
    return result;
  endmethod

  method can_peek owner: HACKER
    "Return whether a principal may inspect another player's accounting.";
    return args[1] == this.owner || $perm_utils:controls(args[1], args[2]);
  endmethod

  method can_touch owner: HACKER
    "Return whether a principal may change quota allowances.";
    return args[1].wizard;
  endmethod

  method do_breakdown owner: #2
    "Return native size estimates and readable property/source payloads for a controlled object.";
    "Payload totals are diagnostic and do not add up to on-disk storage.";
    const {object} = args;
    this:can_peek(caller_perms(), object.owner) || return E_PERM;
    set_task_perms(caller_perms());
    const measured = object_bytes(object);
    let properties = {};
    for prop in ($object_utils:all_properties(object))
      if (!is_clear_property(object, prop))
        properties = {@properties, {prop, value_bytes(object.(prop))}};
      endif
    endfor
    properties = $list_utils:sort_by(properties, {item} => item[2], false, true);
    let lines = {tostr("Object size estimate: ", measured, " bytes."), "Property value payloads (excluding clear inherited values):"};
    for item in (properties)
      lines = {@lines, tostr("  ", item[1], ": ", item[2])};
    endfor
    lines = {@lines, "Verb source payloads (not compiled program sizes):"};
    for number in [1..length(verbs(object))]
      lines = {@lines, tostr("  ", verb_info(object, number)[3], ": ", value_bytes(verb_code(object, number)))};
    endfor
    return {@lines, "Payloads and native object estimates use different accounting; do not add them."};
  endmethod

  method object_overhead_bytes owner: HACKER
    "Return the inherited object-overhead estimate; this is not a storage measurement.";
    const object = args[1];
    return 13 * 4 + length(object.name) + 1;
  endmethod

  method property_overhead_bytes owner: #2
    "Return the inherited property-overhead estimate; this is not a storage measurement.";
    const {o, ?ps = $object_utils:all_properties_suspended(o)} = args;
    return value_bytes(properties(o)) - 4 + length(ps) * 4 * 4;
  endmethod

  method verb_overhead_bytes owner: #2
    "Return the inherited verb-overhead estimate; this is not a storage measurement.";
    const o = args[1];
    const vs = verbs(o);
    return length(vs) * 5 * 4;
  endmethod

  method add_owned_object owner: #2
    "Record an owned object after creation for a controlled owner or an internal call.";
    $perm_utils:controls(caller_perms(), args[1]) || caller == this || return E_PERM;
    const {who, what} = args;
    if (typeof(who.owned_objects) == TYPE_LIST && what.owner == who)
      who.owned_objects = setadd(who.owned_objects, what);
    endif
  endmethod

  method measurement_task_nofork owner: #2
    "Run one bounded measurement pass without scheduling another task. Wizard callers only.";
    caller_perms().wizard || return E_PERM;
    return this:measurement_task(@args);
  endmethod

  method measurement_task_body owner: #2
    "Measure complete owners until the time limit; commit only between owners.";
    "Return {owners_processed, repeated_cycles}. Wizard callers only.";
    caller_perms().wizard || return E_PERM;
    const {?timeout = this.task_time_limit} = args;
    typeof(timeout) == TYPE_INT && timeout >= 0 || return E_INVARG;
    const candidates = setremove(players(), $hacker);
    !candidates && return {0, 0};
    const stop = time() + timeout;
    let position = this.working in candidates || 1;
    let processed = 0;
    let cycles = 0;
    let age = this.cycle_days * 86400;
    while (time() < stop)
      caller_perms().wizard || return E_PERM;
      const who = candidates[position];
      if (valid(who) && is_player(who) && $object_utils:has_property(who, "size_quota"))
        this:summarize_one_user(who, age);
      endif
      if (valid(who) && $object_utils:has_callable_verb($local, "per_player_daily_scan"))
        $local:per_player_daily_scan(who);
      endif
      processed = processed + 1;
      position = position % length(candidates) + 1;
      this.working = candidates[position];
      if (processed % length(candidates) == 0)
        if (!this.repeat_cycle || age <= 0)
          break;
        endif
        cycles = cycles + 1;
        age = max(0, age - 86400);
      endif
      "A complete owner's totals are published before another owner is considered.";
      suspend(0);
    endwhile
    return {processed, cycles};
  endmethod

  method schedule_measurement_task owner: #2
    "Schedule one daily measurement worker at 08:00 UTC. Wizard callers only.";
    caller_perms().wizard || return E_PERM;
    if ($code_utils:task_valid(this.measurement_task_running))
      return this.measurement_task_running;
    endif
    let worker;
    fork worker ((8 * 3600 - time() % 86400 + 86400) % 86400 || 86400)
      while (this.measurement_task_running == task_id())
        try
          this:measurement_task(this.task_time_limit);
        except error (ANY)
          server_log(tostr("Quota measurement failed: ", error));
        endtry
        suspend(86400);
      endwhile
    endfork
    this.measurement_task_running = worker;
    return worker;
  endmethod

  method task_perms owner: #2
    "Put all your wizards in $byte_quota_utils.wizards.  Then various long-running tasks will cycle among the permissions, spreading out the scheduler-induced personal lag.";
    $wiz_utils.old_task_perms_user = setadd($wiz_utils.old_task_perms_user, caller);
    return $wiz_utils:random_wizard();
  endmethod

  method property_exists owner: #2
    "this:property_exists(object, property)";
    " => does the specified property exist?";
    return !!(`property_info(@args) ! ANY');
  endmethod

  method reimburse_recycled_object owner: #2
    "Refund the cached size of a successfully recycled object. System recycle hook only.";
    caller == #0 || raise(E_PERM);
    const {owner, size} = args;
    is_clear_property(owner, "size_quota") && return false;
    if (size > 0)
      owner.size_quota[2] = max(0, owner.size_quota[2] - size);
    else
      owner.size_quota[4] = max(0, owner.size_quota[4] - 1);
    endif
    return true;
  endmethod
endobject
