object RELATION [
  import_export_id -> "relation",
  import_export_hierarchy -> {"relations"}
]
  name: "Generic Relation"
  parent: ROOT
  owner: HACKER
  fertile: true
  readable: true

  property fact_schema (owner: HACKER, flags: "rc") = ['columns -> {}, 'types -> []];
  property set_version (owner: HACKER, flags: "rc") = 0;
  property watchers (owner: ARCH_WIZARD, flags: "r") = {};
  property fact_lifetimes (owner: ARCH_WIZARD, flags: "r") = false;
  property keeps_provenance (owner: ARCH_WIZARD, flags: "r") = false;
  property sweep_schedule (owner: ARCH_WIZARD, flags: "r") = 0;
  property listener (owner: ARCH_WIZARD, flags: "r") = 0;
  property starter (owner: ARCH_WIZARD, flags: "r") = 0;
  property backlog (owner: ARCH_WIZARD, flags: "r") = {};
  property sweep_at (owner: ARCH_WIZARD, flags: "r") = 0;
  property meta_fields (owner: HACKER, flags: "r") = ['recorded_by -> 'object, 'recorded_at -> 'integer, 'expires_at -> 'integer];

  override description (owner: HACKER, flags: "rc") = "N-ary persistent data relation.";

  method define_fields owner: ARCH_WIZARD
    "Define ordered, named fields on an owned relation. Existing tuples must fit before any change.";
    const {relation, columns, types} = args;
    const principal = caller_perms();
    typeof(relation) == TYPE_OBJ && valid(relation) && isa(relation, $relation) || raise(E_INVARG, "The relation no longer exists, or is not a relation.");
    principal == relation.owner || principal.wizard || raise(E_PERM, "You do not own this relation.");
    set_task_perms(principal);
    $behavior_schema:_types(types, "relation fields");
    typeof(columns) == TYPE_LIST && length(columns) > 0 && length(columns) == length(types) || raise(E_INVARG, "Declare each relation field once, in tuple order.");
    let seen = {};
    for field in (columns)
      maphaskey(types, field) && !(field in seen) || raise(E_INVARG, "Declare each relation field once, in tuple order.");
      !maphaskey($relation.meta_fields, field) || raise(E_INVARG, tostr(field) + " is reserved for when and by whom a fact was recorded.");
      seen = {@seen, field};
    endfor
    const schema = ['columns -> columns, 'types -> types];
    for tuple in ($relation:tuples(relation))
      $relation:_check_tuple(tuple, schema);
    endfor
    relation.fact_schema = schema;
    return schema;
  endmethod

  method schema owner: ARCH_WIZARD
    "Read a relation's field definitions and check an optional required shape and write authority.";
    const {relation, ?expected = 0, ?write = false} = args;
    const principal = caller_perms();
    typeof(relation) == TYPE_OBJ && valid(relation) && isa(relation, $relation) || raise(E_INVARG, "The relation no longer exists, or is not a relation.");
    principal == relation.owner || principal.wizard || (relation.r && !write) || raise(E_PERM, write ? "You cannot write to this relation." | "You cannot read this relation.");
    set_task_perms(principal);
    const schema = relation.fact_schema;
    length(schema['columns]) > 0 || raise(E_INVARG, "Define this relation's fields with @facts OBJECT define FIELD:TYPE.");
    if (typeof(expected) == TYPE_MAP)
      let own = expected;
      for field in (mapkeys($relation.meta_fields))
        maphaskey(own, field) && (own = mapdelete(own, field));
      endfor
      equal(schema['types], own) || raise(E_INVARG, "This relation has different field names or types from those required by the condition or step.");
    endif
    return schema;
  endmethod

  method _check_tuple owner: HACKER
    "Check tuple arity and types against optional named fields. Untyped relations keep their tuple API.";
    const {tuple, schema} = args;
    length(schema['columns]) == 0 && return;
    length(tuple) == length(schema['columns]) || raise(E_INVARG, "Fact has the wrong number of fields.");
    for i in [1..length(tuple)]
      const field = schema['columns][i];
      $behavior_schema:_type(tuple[i], schema['types][field], "fact field " + tostr(field));
    endfor
  endmethod

  method change_fact owner: ARCH_WIZARD
    "Record or forget one complete named fact under the caller's relation write authority.";
    set_task_perms(caller_perms());
    const {relation, fields, values, operation, ?options = []} = args;
    operation in {'record, 'forget} || raise(E_INVARG, "Expected record or forget.");
    $behavior_schema:_fields(options, {}, {'lasts, 'chain}, "fact options");
    const lasts = `options['lasts] ! E_RANGE => 0';
    const chain = `options['chain] ! E_RANGE => {}';
    const schema = $relation:schema(relation, fields, true);
    $behavior_schema:bindings(values, schema['types], "fact fields");
    const tuple = { values[field] for field in (schema['columns]) };
    return operation == 'record ? $relation:assert(tuple, relation, lasts, chain) | $relation:retract(tuple, relation, chain);
  endmethod

  method assert owner: ARCH_WIZARD
    "Store a tuple once and return its identity. With a lifetime in seconds, the fact expires; recording it again replaces its lifetime.";
    const {tuple, ?relation = this, ?lasts = 0, ?chain = {}} = args;
    isa(relation, $relation) || raise(E_INVARG, "Expected a relation.");
    const principal = caller_perms();
    principal == relation.owner || principal.wizard || raise(E_PERM);
    set_task_perms(principal);
    typeof(tuple) == TYPE_LIST || raise(E_TYPE);
    length(tuple) > 0 || raise(E_INVARG);
    typeof(lasts) == TYPE_INT && lasts >= 0 || raise(E_INVARG, "A fact's lifetime must be zero or more seconds.");
    typeof(chain) == TYPE_LIST || raise(E_INVARG, "Invalid reaction chain.");
    $relation:_check_tuple(tuple, relation.fact_schema);
    relation.set_version != 1 && $relation:repair(relation);
    const recorded = $relation:_record(relation, tuple, lasts, principal);
    recorded['appeared] && length(relation.watchers) > 0 && $relation:_announce(relation, 'recorded, tuple, principal, chain);
    return recorded['identity];
  endmethod

  method _record owner: ARCH_WIZARD
    "Store or renew one checked tuple. Report whether it was absent or expired before.";
    callers()[1][4] == $relation || raise(E_PERM);
    const {relation, tuple, lasts, principal} = args;
    let identity = $relation:_find_tuple_id(relation, tuple);
    let appeared = true;
    if (identity != 0)
      appeared = relation.fact_lifetimes && length($relation:_live(relation, {identity})) == 0;
    else
      identity = uuid();
      add_property(relation, "tuple_" + identity, tuple, {relation.owner, "r"});
      $relation:_index_tuple(relation, identity, tuple);
    endif
    let meta = [];
    if (relation.keeps_provenance)
      meta = ['by -> principal, 'at -> time()];
    endif
    if (lasts > 0)
      meta['expires] = time() + lasts;
      relation.fact_lifetimes || (relation.fact_lifetimes = true);
      $relation:_plan_sweep(relation, meta['expires]);
    endif
    const name = "meta_" + identity;
    if (length(meta) > 0)
      try
        relation.(name) = meta;
      except (E_PROPNF)
        add_property(relation, name, meta, {$arch_wizard, "r"});
      endtry
    elseif (relation.fact_lifetimes || relation.keeps_provenance)
      `delete_property(relation, name) ! E_PROPNF';
    endif
    return ['identity -> identity, 'appeared -> appeared];
  endmethod

  method _remove owner: ARCH_WIZARD
    "Delete one stored tuple, its indexes, and its lifetime and provenance.";
    callers()[1][4] == $relation || raise(E_PERM);
    const {relation, identity, tuple} = args;
    for element in (tuple)
      if (typeof(element) in {TYPE_FLYWEIGHT, TYPE_LIST, TYPE_MAP})
        continue;
      endif
      const name = $relation:_index_key(element);
      const previous = `relation.(name) ! E_PROPNF => {}';
      if (length(previous) == 0)
        continue;
      endif
      const identities = setremove(previous, identity);
      if (length(identities) > 0)
        relation.(name) = identities;
      else
        delete_property(relation, name);
      endif
    endfor
    delete_property(relation, "tuple_" + identity);
    `delete_property(relation, "meta_" + identity) ! E_PROPNF';
  endmethod

  method _live owner: ARCH_WIZARD
    "Keep the identities of facts that have not expired. Relations that never held an expiring fact skip the check.";
    const {relation, identities} = args;
    relation.fact_lifetimes || return identities;
    const now = time();
    let live = {};
    for identity in (identities)
      const meta = `relation.("meta_" + identity) ! E_PROPNF => []';
      if (!maphaskey(meta, 'expires) || meta['expires] > now)
        live = {@live, identity};
      endif
    endfor
    return live;
  endmethod

  method _announce owner: ARCH_WIZARD
    "Send a fact change to the relation's listener once the recording task commits. A rolled-back task sends nothing.";
    callers()[1][4] == $relation || raise(E_PERM);
    const {relation, operation, tuple, actor, ?chain = {}} = args;
    length(relation.watchers) > 0 || return;
    const change = {operation, tuple, actor, chain};
    if (relation.listener != 0)
      try
        task_send(relation.listener, change);
        return;
      except (E_INVARG, E_QUOTA)
      endtry
    endif
    "No listener is taking messages: keep the change for the next one, and start one once.";
    relation.backlog = {@relation.backlog, change};
    if (!schedule_valid(relation.starter))
      relation.starter = schedule_at($relation, "_listen", ftime(), {relation}, ['pass_elapsed -> 0]);
    endif
  endmethod

  method _listen owner: ARCH_WIZARD
    "Deliver a relation's changes in order, one transaction each, while anyone watches it. One listener runs per relation.";
    caller_perms().wizard || raise(E_PERM);
    const {relation} = args;
    valid(relation) && isa(relation, $relation) || return 0;
    if (relation.listener != 0 && relation.listener != task_id())
      try
        task_send(relation.listener, 'backlog);
        return 0;
      except (E_QUOTA)
        "The listener is busy; it reads the backlog once its mailbox drains. Check again in a second.";
        return 1;
      except (E_INVARG)
      endtry
    endif
    relation.listener = task_id();
    relation.starter = 0;
    let queue = {};
    while (true)
      if (length(relation.backlog) > 0)
        queue = {@queue, @relation.backlog};
        relation.backlog = {};
      endif
      while (length(queue) > 0)
        const change = queue[1];
        queue = queue[2..$];
        typeof(change) == TYPE_LIST && $relation:_deliver(relation, @change);
        queue = {@queue, @task_recv()};
      endwhile
      if (!valid(relation) || length(relation.watchers) == 0)
        break;
      endif
      queue = task_recv(3600);
    endwhile
    if (valid(relation) && relation.listener == task_id())
      relation.listener = 0;
    endif
    return 0;
  endmethod

  method _deliver owner: ARCH_WIZARD
    "Run the fact reactions of each watcher for one change.";
    callers()[1][4] == $relation || raise(E_PERM);
    const {relation, operation, tuple, actor, chain} = args;
    valid(relation) && isa(relation, $relation) || return;
    let context = ['Relation -> relation, 'Actor -> actor, '_reaction_chain -> chain];
    const columns = relation.fact_schema['columns];
    if (length(columns) == length(tuple))
      for i in [1..length(columns)]
        context[columns[i]] = tuple[i];
      endfor
    endif
    const trigger = {'fact, relation, operation};
    let stale = {};
    for host in (relation.watchers)
      if (!valid(host) || !$relation:_watches(host, relation))
        stale = {@stale, host};
        continue;
      endif
      try
        $reaction:_dispatch(host, trigger, context);
      except error (ANY)
        server_log("Fact reaction on " + toliteral(host) + " failed: " + error[2]);
      endtry
    endfor
    if (length(stale) > 0)
      relation.watchers = { host for host in (relation.watchers) if !(host in stale) };
    endif
  endmethod

  method _watches owner: ARCH_WIZARD
    "Whether a host has a reaction to changes in this relation.";
    const {host, relation} = args;
    for reaction in ($root:_get_reactions_for(host, $arch_wizard))
      const trigger = reaction.trigger;
      if (typeof(trigger) == TYPE_LIST && length(trigger) == 3 && trigger[1] == 'fact && trigger[2] == relation)
        return true;
      endif
    endfor
    return false;
  endmethod

  method watch owner: ARCH_WIZARD
    "Have a relation tell an owned host's fact reactions about its changes. The caller must be able to read the relation.";
    const {relation, host} = args;
    const principal = caller_perms();
    typeof(relation) == TYPE_OBJ && valid(relation) && isa(relation, $relation) || raise(E_INVARG, "The relation no longer exists, or is not a relation.");
    typeof(host) == TYPE_OBJ && valid(host) || raise(E_INVARG);
    principal == host.owner || principal.wizard || raise(E_PERM);
    principal == relation.owner || principal.wizard || relation.r || raise(E_PERM, "You cannot read this relation.");
    host in relation.watchers || (relation.watchers = {@relation.watchers, host});
    return true;
  endmethod

  method keep_provenance owner: ARCH_WIZARD
    "Choose whether an owned relation records who recorded each fact and when.";
    const {relation, keep} = args;
    const principal = caller_perms();
    typeof(relation) == TYPE_OBJ && valid(relation) && isa(relation, $relation) || raise(E_INVARG, "The relation no longer exists, or is not a relation.");
    principal == relation.owner || principal.wizard || raise(E_PERM);
    typeof(keep) == TYPE_BOOL || raise(E_TYPE);
    relation.keeps_provenance = keep;
    return keep;
  endmethod

  method _plan_sweep owner: ARCH_WIZARD
    "Make sure the relation's sweep runs by the given time.";
    callers()[1][4] == $relation || raise(E_PERM);
    const {relation, due} = args;
    if (schedule_valid(relation.sweep_schedule) && relation.sweep_at <= due)
      return;
    endif
    schedule_valid(relation.sweep_schedule) && schedule_stop(relation.sweep_schedule);
    relation.sweep_schedule = schedule_at($relation, "_sweep", due, {relation}, ['pass_elapsed -> 0]);
    relation.sweep_at = due;
  endmethod

  method _sweep owner: ARCH_WIZARD
    "Remove expired facts, telling watchers, and wait for the next expiry.";
    caller_perms().wizard || raise(E_PERM);
    const {relation} = args;
    valid(relation) && isa(relation, $relation) || return 0;
    let next = 0;
    for property in (properties(relation))
      const name = tostr(property);
      if (!name:starts_with("meta_"))
        continue;
      endif
      const meta = `relation.(name) ! E_PROPNF => []';
      if (!maphaskey(meta, 'expires))
        continue;
      endif
      if (meta['expires] <= time())
        const identity = name[6..$];
        const tuple = `relation.("tuple_" + identity) ! E_PROPNF => 0';
        if (typeof(tuple) == TYPE_LIST)
          $relation:_remove(relation, identity, tuple);
          $relation:_announce(relation, 'forgotten, tuple, #-1);
        else
          delete_property(relation, name);
        endif
      elseif (next == 0 || meta['expires] < next)
        next = meta['expires];
      endif
      suspend_if_needed();
    endfor
    relation.sweep_at = next;
    return next == 0 ? 0 | max(1, next - time());
  endmethod

  method _index_key owner: HACKER
    "Hash an exact scalar value, treating both floating-point zero signs as the same value.";
    let {value} = args;
    if (typeof(value) == TYPE_FLOAT && value == 0.0)
      value = 0.0;
    endif
    return "index_" + value_hash(value);
  endmethod

  method _index_tuple owner: ARCH_WIZARD
    "Add one stored identity to each scalar index under the caller's write permissions.";
    const {relation, identity, tuple} = args;
    const principal = caller_perms();
    principal == relation.owner || principal.wizard || raise(E_PERM);
    set_task_perms(principal);
    for element in (tuple)
      if (typeof(element) in {TYPE_FLYWEIGHT, TYPE_LIST, TYPE_MAP})
        continue;
      endif
      const name = $relation:_index_key(element);
      const identities = `relation.(name) ! E_PROPNF => 0';
      if (typeof(identities) == TYPE_LIST)
        relation.(name) = setadd(identities, identity);
      else
        add_property(relation, name, {identity}, {relation.owner, "r"});
      endif
    endfor
  endmethod

  method repair owner: ARCH_WIZARD
    "Collapse legacy duplicates and rebuild indexes, retaining one original identity per tuple.";
    "Requires relation ownership or wizard authority. No suspension or partial batch commits.";
    const {?relation = this} = args;
    const principal = caller_perms();
    principal == relation.owner || principal.wizard || raise(E_PERM);
    set_task_perms(principal);
    const names = properties(relation);
    let kept = [];
    let duplicates = {};
    for property in (names)
      const name = tostr(property);
      if (!name:starts_with("tuple_"))
        continue;
      endif
      const tuple = relation.(property);
      typeof(tuple) == TYPE_LIST && length(tuple) > 0 || raise(E_INVARG, "Invalid stored relation tuple: " + name);
      let duplicate = false;
      for original in (mapvalues(kept))
        if (equal(original, tuple))
          duplicate = true;
          break;
        endif
      endfor
      if (duplicate)
        duplicates = {@duplicates, property};
      else
        kept[name[7..$]] = tuple;
      endif
    endfor
    for property in (names)
      if (tostr(property):starts_with("index_") || property in duplicates)
        delete_property(relation, property);
        property in duplicates && `delete_property(relation, "meta_" + tostr(property)[7..$]) ! E_PROPNF';
      endif
    endfor
    for identity in (mapkeys(kept))
      $relation:_index_tuple(relation, identity, kept[identity]);
    endfor
    relation.set_version = 1;
    return length(duplicates);
  endmethod

  method retract owner: ARCH_WIZARD
    "Remove a fact once. Return false when absent or expired; repair legacy duplicates before removal.";
    const {tuple, ?relation = this, ?chain = {}} = args;
    isa(relation, $relation) || raise(E_INVARG, "Expected a relation.");
    const principal = caller_perms();
    principal == relation.owner || principal.wizard || raise(E_PERM);
    set_task_perms(principal);
    typeof(tuple) == TYPE_LIST || raise(E_TYPE);
    typeof(chain) == TYPE_LIST || raise(E_INVARG, "Invalid reaction chain.");
    relation.set_version != 1 && $relation:repair(relation);
    const identity = $relation:_find_tuple_id(relation, tuple);
    identity == 0 && return false;
    const live = !relation.fact_lifetimes || length($relation:_live(relation, {identity})) > 0;
    $relation:_remove(relation, identity, tuple);
    length(relation.watchers) > 0 && $relation:_announce(relation, 'forgotten, tuple, principal, chain);
    return live;
  endmethod

  method member owner: ARCH_WIZARD
    "Check exact tuple membership under the caller's read permissions.";
    set_task_perms(caller_perms());
    const {tuple} = args;
    typeof(tuple) == TYPE_LIST || raise(E_TYPE);
    const identity = $relation:_find_tuple_id(this, tuple);
    return identity != 0 && (!this.fact_lifetimes || length($relation:_live(this, {identity})) > 0);
  endmethod

  method select owner: ARCH_WIZARD
    "Return distinct tuples with an exact value at a one-based position.";
    set_task_perms(caller_perms());
    const {position, value} = args;
    typeof(position) == TYPE_INT || raise(E_TYPE);
    position > 0 || raise(E_INVARG);
    return { tuple for tuple in ($relation:select_containing(value, this)) if length(tuple) >= position && equal(tuple[position], value) };
  endmethod

  method select_containing owner: ARCH_WIZARD
    "Return distinct tuples containing an exact value, using scalar indexes when available.";
    set_task_perms(caller_perms());
    const {value, ?relation = this} = args;
    if (typeof(value) in {TYPE_FLYWEIGHT, TYPE_LIST, TYPE_MAP} || relation.set_version != 1)
      let selected = {};
      for tuple in ($relation:tuples(relation))
        for element in (tuple)
          if (equal(element, value))
            selected = {@selected, tuple};
            break;
          endif
        endfor
      endfor
      return selected;
    endif
    let identities = `relation.($relation:_index_key(value)) ! E_PROPNF => {}';
    relation.fact_lifetimes && (identities = $relation:_live(relation, identities));
    let result = {};
    for identity in (identities)
      const tuple = relation.("tuple_" + identity);
      for element in (tuple)
        if (equal(element, value))
          result = {@result, tuple};
          break;
        endif
      endfor
    endfor
    return result;
  endmethod

  method tuples owner: ARCH_WIZARD
    "Return distinct stored facts, including before legacy storage has been repaired.";
    const {?relation = this} = args;
    set_task_perms(caller_perms());
    let tuples;
    if (relation.fact_lifetimes)
      const identities = { tostr(name)[7..$] for name in (properties(relation)) if tostr(name):starts_with("tuple_") };
      tuples = { relation.("tuple_" + identity) for identity in ($relation:_live(relation, identities)) };
    else
      tuples = { relation.(name) for name in (properties(relation)) if tostr(name):starts_with("tuple_") };
    endif
    const matched = term_match({'var, 'Tuple}, tuples, [], ['case_sensitive -> true, 'dedupe -> true, 'max_solutions -> max(1, length(tuples)), 'max_steps -> max(1, length(tuples))]);
    return { row['Tuple] for row in (matched) };
  endmethod

  method replace_snapshot owner: ARCH_WIZARD
    "Replace a captured tuple set atomically. Return false if another writer changed it.";
    const principal = caller_perms();
    const {relation, snapshot, replacement} = args;
    typeof(relation) == TYPE_OBJ && valid(relation) && isa(relation, $relation) || raise(E_TYPE);
    principal == relation.owner || principal.wizard || raise(E_PERM);
    set_task_perms(principal);
    typeof(snapshot) == TYPE_LIST && typeof(replacement) == TYPE_LIST || raise(E_TYPE);
    length(replacement) <= 1000 || raise(E_QUOTA, "Too many replacement facts");
    for tuple in (replacement)
      typeof(tuple) == TYPE_LIST && length(tuple) > 0 || raise(E_TYPE);
      $relation:_check_tuple(tuple, relation.fact_schema);
    endfor
    const current = $relation:tuples(relation);
    strcmp(toliteral(current), toliteral(snapshot)) == 0 || return false;
    "No callbacks or suspension between removing old tuples and installing validated replacements.";
    for property in (properties(relation))
      const name = tostr(property);
      if (name:starts_with("tuple_") || name:starts_with("index_") || name:starts_with("meta_"))
        delete_property(relation, property);
      endif
    endfor
    relation.set_version = 1;
    for tuple in (replacement)
      $relation:_record(relation, tuple, 0, principal);
    endfor
    if (length(relation.watchers) > 0)
      for tuple in (current)
        tuple in replacement || $relation:_announce(relation, 'forgotten, tuple, principal);
      endfor
      for tuple in (replacement)
        tuple in current || $relation:_announce(relation, 'recorded, tuple, principal);
      endfor
    endif
    return true;
  endmethod

  method clear owner: ARCH_WIZARD
    "Remove all tuples and indexes under the caller's write permissions.";
    const principal = caller_perms();
    principal == this.owner || principal.wizard || raise(E_PERM);
    set_task_perms(principal);
    const forgotten = length(this.watchers) > 0 ? $relation:tuples(this) | {};
    for property in (properties(this))
      const name = tostr(property);
      if (name:starts_with("tuple_") || name:starts_with("index_") || name:starts_with("meta_"))
        delete_property(this, property);
      endif
    endfor
    this.set_version = 1;
    for tuple in (forgotten)
      $relation:_announce(this, 'forgotten, tuple, principal);
    endfor
    return true;
  endmethod

  method _find_tuple_id owner: ARCH_WIZARD
    "Find an exact tuple's stored identity. Composite-only tuples require a scan.";
    set_task_perms(caller_perms());
    const {relation, tuple} = args;
    let identities = 0;
    if (relation.set_version == 1)
      for element in (tuple)
        if (typeof(element) in {TYPE_FLYWEIGHT, TYPE_LIST, TYPE_MAP})
          continue;
        endif
        identities = `relation.($relation:_index_key(element)) ! E_PROPNF => {}';
        break;
      endfor
    endif
    if (typeof(identities) != TYPE_LIST)
      const names = properties(relation);
      identities = { tostr(name)[7..length(tostr(name))] for name in (names) if tostr(name):starts_with("tuple_") };
    endif
    for identity in (identities)
      equal(relation.("tuple_" + identity), tuple) && return identity;
    endfor
    return 0;
  endmethod

  method test_assert_and_member owner: HACKER
    "Test basic assertion and membership checking";
    const rel = $relation:create(true);
    "Test binary relation";
    rel:assert({#990001, #990002});
    !rel:member({#990001, #990002}) && raise(E_ASSERT, "Binary tuple not found after assert");
    rel:member({#990002, #990001}) && raise(E_ASSERT, "Element position within tuple should matter");
    "Test ternary relation";
    rel:assert({#990012, #990039, "passage1"});
    !rel:member({#990012, #990039, "passage1"}) && raise(E_ASSERT, "Ternary tuple not found");
    rel:member({#990012, #990039}) && raise(E_ASSERT, "Partial tuple should not match");
    "Test different arities in same relation";
    rel:assert({#990005, #990006, #990007, #990008});
    !rel:member({#990005, #990006, #990007, #990008}) && raise(E_ASSERT, "Quaternary tuple not found");
  endmethod

  method test_retract owner: HACKER
    "Test tuple removal";
    const rel = $relation:create(true);
    rel:assert({#990001, #990002, "edge1"});
    rel:assert({#990001, #990003, "edge2"});
    rel:assert({#990002, #990003, "edge3"});
    "Verify all present";
    !rel:member({#990001, #990002, "edge1"}) && raise(E_ASSERT, "Setup failed");
    "Retract one tuple";
    !rel:retract({#990001, #990002, "edge1"}) && raise(E_ASSERT, "Retract should return true");
    rel:member({#990001, #990002, "edge1"}) && raise(E_ASSERT, "Tuple still present after retract");
    "Other tuples should remain";
    !rel:member({#990001, #990003, "edge2"}) && raise(E_ASSERT, "Other tuple incorrectly removed");
    !rel:member({#990002, #990003, "edge3"}) && raise(E_ASSERT, "Other tuple incorrectly removed");
    "Retracting non-existent tuple should return false";
    rel:retract({#990099, #990100, "none"}) && raise(E_ASSERT, "Retract of missing tuple should be false");
  endmethod

  method test_select owner: HACKER
    "Test position-based selection";
    const rel = $relation:create(true);
    "Setup passage-like data";
    rel:assert({#990012, #990039, "north"});
    rel:assert({#990012, #990040, "east"});
    rel:assert({#990039, #990040, "south"});
    "Select by first position";
    let results = rel:select(1, #990012);
    length(results) != 2 && raise(E_ASSERT, "Expected 2 results from position 1");
    {#990012, #990039, "north"} in results || raise(E_ASSERT, "Missing expected tuple");
    {#990012, #990040, "east"} in results || raise(E_ASSERT, "Missing expected tuple");
    "Select by second position";
    results = rel:select(2, #990039);
    length(results) != 1 && raise(E_ASSERT, "Expected 1 result from position 2");
    {#990012, #990039, "north"} in results || raise(E_ASSERT, "Missing expected tuple");
    "Select by third position";
    results = rel:select(3, "south");
    length(results) != 1 && raise(E_ASSERT, "Expected 1 result from position 3");
    {#990039, #990040, "south"} in results || raise(E_ASSERT, "Missing expected tuple");
    "Select non-existent value";
    results = rel:select(1, #990099);
    length(results) != 0 && raise(E_ASSERT, "Expected empty results for non-existent value");
  endmethod

  method test_tuples owner: HACKER
    "Test retrieving all tuples";
    const rel = $relation:create(true);
    "Empty relation";
    length(rel:tuples()) != 0 && raise(E_ASSERT, "Empty relation should have no tuples");
    "Add some tuples";
    rel:assert({#990001, #990002});
    rel:assert({#990003, #990004});
    rel:assert({#990005, #990006, #990007});
    const all_tuples = rel:tuples();
    length(all_tuples) != 3 && raise(E_ASSERT, "Expected 3 tuples");
    {#990001, #990002} in all_tuples || raise(E_ASSERT, "Missing tuple");
    {#990003, #990004} in all_tuples || raise(E_ASSERT, "Missing tuple");
    {#990005, #990006, #990007} in all_tuples || raise(E_ASSERT, "Missing tuple");
  endmethod

  method test_clear owner: HACKER
    "Test clearing all tuples";
    const rel = $relation:create(true);
    "Add several tuples";
    rel:assert({#990001, #990002, "a"});
    rel:assert({#990003, #990004, "b"});
    rel:assert({#990005, #990006, "c"});
    length(rel:tuples()) != 3 && raise(E_ASSERT, "Setup failed");
    "Clear the relation";
    !rel:clear() && raise(E_ASSERT, "Clear should return true");
    "Verify empty";
    length(rel:tuples()) != 0 && raise(E_ASSERT, "Relation should be empty after clear");
    rel:member({#990001, #990002, "a"}) && raise(E_ASSERT, "Tuple still present after clear");
  endmethod

  method test_duplicate_assert owner: HACKER
    "Repeated assertion keeps one identity, one fact, and one query answer.";
    const relation = $relation:create(true);
    const first = relation:assert({#990001, #990002, "edge"});
    const again = relation:assert({#990001, #990002, "edge"});
    $test_utils:assert_eq(first, again, "Assertion is idempotent");
    $test_utils:assert_eq(relation:count(), 1, "One stored fact");
    $test_utils:assert_eq(relation:query({#990001, {'var, 'To}, {'var, 'Label}}), {['To -> #990002, 'Label -> "edge"]}, "One binding map");
    $test_utils:assert_true(relation:retract({#990001, #990002, "edge"}), "One retraction removes the fact");
    $test_utils:assert_false(relation:member({#990001, #990002, "edge"}), "No duplicate remains");
    return true;
  endmethod

  method test_bidirectional_indexing owner: HACKER
    "Test that a single tuple is indexed under all its values.";
    const rel = $relation:create(true);
    "Assert a passage-like tuple";
    rel:assert({#990012, #990039, "north"});
    "Find tuples containing #990012";
    const results_from_12 = rel:select_containing(#990012);
    length(results_from_12) != 1 && raise(E_ASSERT, "Should find 1 tuple via #990012");
    {#990012, #990039, "north"} in results_from_12 || raise(E_ASSERT, "Wrong tuple via #990012");
    "Find tuples containing #990039";
    const results_from_39 = rel:select_containing(#990039);
    length(results_from_39) != 1 && raise(E_ASSERT, "Should find 1 tuple via #990039");
    {#990012, #990039, "north"} in results_from_39 || raise(E_ASSERT, "Wrong tuple via #990039");
    "Find tuples containing 'north'";
    const results_from_north = rel:select_containing("north");
    length(results_from_north) != 1 && raise(E_ASSERT, "Should find 1 tuple via 'north'");
    {#990012, #990039, "north"} in results_from_north || raise(E_ASSERT, "Wrong tuple via 'north'");
    "Verify it's the SAME tuple found three different ways";
    results_from_12 == results_from_39 || raise(E_ASSERT, "Results should be identical");
    results_from_39 == results_from_north || raise(E_ASSERT, "Results should be identical");
    "Test with multiple passages";
    rel:assert({#990012, #990040, "east"});
    rel:assert({#990039, #990040, "south"});
    "Find all passages from #990012";
    const from_12 = rel:select_containing(#990012);
    length(from_12) != 2 && raise(E_ASSERT, "Room #990012 should have 2 passages");
    {#990012, #990039, "north"} in from_12 || raise(E_ASSERT, "Missing north passage");
    {#990012, #990040, "east"} in from_12 || raise(E_ASSERT, "Missing east passage");
    "Find all passages from #990040";
    const from_40 = rel:select_containing(#990040);
    length(from_40) != 2 && raise(E_ASSERT, "Room #990040 should have 2 passages");
    {#990012, #990040, "east"} in from_40 || raise(E_ASSERT, "Missing east passage");
    {#990039, #990040, "south"} in from_40 || raise(E_ASSERT, "Missing south passage");
    "Room #990039 appears in different positions but both found";
    const from_39 = rel:select_containing(#990039);
    length(from_39) != 2 && raise(E_ASSERT, "Room #990039 should have 2 passages");
    {#990012, #990039, "north"} in from_39 || raise(E_ASSERT, "Missing north passage (pos 2)");
    {#990039, #990040, "south"} in from_39 || raise(E_ASSERT, "Missing south passage (pos 1)");
  endmethod

  method test_fact_lifetimes owner: ARCH_WIZARD
    "An expired fact leaves every read at once; recording it again renews it, and the sweep removes it.";
    const rel = $relation:create(true);
    $relation:define_fields(rel, {'site}, ['site -> 'string]);
    const identity = rel:assert({"north"}, rel, 60);
    $test_utils:assert_true(rel:member({"north"}), "A fact with a lifetime is there until it expires");
    $test_utils:assert_true(schedule_valid(rel.sweep_schedule), "Recording a lifetime plans a sweep");
    rel.("meta_" + identity) = ['expires -> time() - 1];
    $test_utils:assert_false(rel:member({"north"}), "An expired fact is not a member");
    $test_utils:assert_eq(rel:tuples(), {}, "An expired fact is not listed");
    $test_utils:assert_eq(rel:select(1, "north"), {}, "An expired fact is not selected");
    $test_utils:assert_eq($relation:query_rows(rel, ['site -> 'string], [], 10)['rows], {}, "An expired fact does not match");
    $test_utils:assert_eq(rel:assert({"north"}), identity, "Recording an expired fact again keeps its identity");
    $test_utils:assert_true(rel:member({"north"}), "Recording without a lifetime makes the fact permanent");
    $test_utils:assert_eq(`rel.("meta_" + identity) ! E_PROPNF => 0', 0, "A permanent fact keeps no lifetime");
    const south = rel:assert({"south"}, rel, 60);
    rel.("meta_" + south) = ['expires -> time() - 1];
    $test_utils:assert_false(rel:retract({"south"}), "Forgetting an expired fact reports it absent");
    rel:assert({"east"}, rel, 60);
    const west = rel:assert({"west"}, rel, 60);
    rel.("meta_" + west) = ['expires -> time() - 1];
    $test_utils:assert_true($relation:_sweep(rel) > 0, "The sweep waits for the next expiry");
    $test_utils:assert_eq(length(rel:tuples()), 2, "The sweep removes only expired facts");
    $test_utils:assert_eq(`rel.("tuple_" + west) ! E_PROPNF => 0', 0, "The sweep deletes the expired fact");
    return true;
  endmethod

  method test_fact_provenance owner: HACKER
    "A relation that keeps provenance answers who recorded each fact and when.";
    const rel = $relation:create(0);
    try
      $relation:define_fields(rel, {'site}, ['site -> 'string]);
      $test_utils:assert_raises(E_INVARG, $relation, "define_fields", {rel, {'recorded_at}, ['recorded_at -> 'integer]}, "Provenance field names are reserved");
      const fields = ['site -> 'string, 'recorded_by -> 'object, 'recorded_at -> 'integer];
      $test_utils:assert_raises(E_INVARG, $relation, "query_rows", {rel, fields, [], 10}, "A relation without provenance has no recorder");
      $relation:keep_provenance(rel, true);
      const before = time();
      rel:assert({"north"});
      const rows = $relation:query_rows(rel, fields, [], 10)['rows];
      $test_utils:assert_eq(rows[1]['recorded_by], task_perms()[1], "The recorder is the recording task's principal");
      $test_utils:assert_true(rows[1]['recorded_at] >= before, "The recording time is kept");
      const fresh = $rule_engine:parse_expression("relation(" + tostr(rel) + ") -> (site: S, recorded_at: T) AND binding.T >= " + tostr(before));
      $test_utils:assert_true($rule_engine:evaluate(fresh)['success], "A rule can ask how fresh a fact is");
      const stale = $rule_engine:parse_expression("relation(" + tostr(rel) + ") -> (site: S, recorded_at: T) AND binding.T < " + tostr(before));
      $test_utils:assert_false($rule_engine:evaluate(stale)['success], "A rule can tell a fresh fact from a stale one");
    finally
      $test_utils:destroy_if_valid(rel);
    endtry
    return true;
  endmethod

  method test_fact_triggers owner: ARCH_WIZARD
    "Installing a fact reaction watches its relation; only the relation's own tasks deliver changes.";
    const rel = $relation:create(true);
    $relation:define_fields(rel, {'item}, ['item -> 'string]);
    const host = $test_utils:anonymous($thing);
    add_property(host, "seen", 0, {host.owner, "r"});
    $test_utils:assert_raises(E_INVARG, $reaction, "mk", {{'fact, rel, 'changed}}, "A fact trigger watches recorded or forgotten facts");
    const clash = $relation:create(true);
    $relation:define_fields(clash, {'Actor}, ['Actor -> 'object]);
    $test_utils:assert_raises(E_INVARG, $reaction, "mk", {{'fact, clash, 'recorded}}, "A field cannot take an event value's name");
    $reaction:install(host, "fact_reaction", $reaction:mk({'fact, rel, 'recorded}, "input.item == \"apple\"", {{'increment, 'seen}}));
    $test_utils:assert_eq(rel.watchers, {host}, "Installing a fact reaction watches the relation");
    $test_utils:assert_raises(E_PERM, $relation, "_listen", {rel}, "Other code cannot deliver facts");
    $test_utils:assert_raises(E_PERM, $relation, "_deliver", {rel, 'recorded, {"apple"}, player, {}}, "Other code cannot run fact reactions");
    $test_utils:assert_raises(E_PERM, $relation, "_sweep", {rel}, "Other code cannot sweep a relation");
    return true;
  endmethod

  method query_result owner: ARCH_WIZARD
    "Return distinct binding maps and whether the requested scope was searched completely.";
    set_task_perms(caller_perms());
    return $relation:_query_result(this, @args);
  endmethod

  method query_rows owner: ARCH_WIZARD
    "Query explicit relation fields; each call chooses its bound columns. Preserve completeness.";
    set_task_perms(caller_perms());
    const {relation, fields, values, limit} = args;
    const schema = $relation:schema(relation, fields);
    $behavior_schema:_fields(values, {}, mapkeys(fields), "relation inputs");
    for field in (mapkeys(values))
      $behavior_schema:_type(values[field], fields[field], "relation input " + tostr(field));
    endfor
    const meta = { field for field in (mapkeys($relation.meta_fields)) if maphaskey(fields, field) };
    length(meta) == 0 || relation.keeps_provenance || raise(E_INVARG, "This relation does not record who recorded its facts.");
    const columns = {@schema['columns], @meta};
    const pattern = { {'var, column} for column in (columns) };
    const types = { fields[field_name] for field_name in (columns) };
    return $relation:_query_result(relation, pattern, values, ['max_solutions -> limit], types, meta);
  endmethod

  method _query_result owner: ARCH_WIZARD
    "Match stored facts with explicit result completeness. This method does not mutate or suspend.";
    set_task_perms(caller_perms());
    let {relation, pattern, ?bindings = [], ?options = [], ?types = {}, ?meta = {}} = args;
    isa(relation, $relation) || raise(E_INVARG, "Expected a relation");
    typeof(pattern) == TYPE_LIST || raise(E_TYPE);
    typeof(bindings) == TYPE_MAP || raise(E_TYPE);
    typeof(options) == TYPE_MAP || raise(E_TYPE);
    const limit = `options['max_solutions] ! E_RANGE => 256';
    typeof(limit) == TYPE_INT && limit > 0 && limit <= 4096 || raise(E_INVARG, "Relation result limit must be between 1 and 4096");
    options['case_sensitive] = true;
    options['dedupe] = true;
    options['max_solutions] = limit + 1;
    term_variables(pattern);
    let identities = 0;
    if (relation.set_version == 1)
      for value in (pattern[1..length(pattern) - length(meta)])
        let bound = value;
        if (typeof(value) == TYPE_LIST && length(value) == 2 && value[1] == 'var)
          bound = `bindings[value[2]] ! E_RANGE => {}';
        endif
        if (!(typeof(bound) in {TYPE_LIST, TYPE_MAP, TYPE_FLYWEIGHT}))
          identities = `relation.($relation:_index_key(bound)) ! E_PROPNF => {}';
          break;
        endif
      endfor
    endif
    if (typeof(identities) != TYPE_LIST)
      const names = properties(relation);
      identities = { tostr(name)[7..length(tostr(name))] for name in (names) if tostr(name):starts_with("tuple_") };
    endif
    relation.fact_lifetimes && (identities = $relation:_live(relation, identities));
    length(identities) <= 4096 || raise(E_QUOTA, "Relation query needs a narrower input scope");
    let candidates = { relation.("tuple_" + identity) for identity in (identities) };
    if (length(meta) > 0)
      const keys = ['recorded_by -> 'by, 'recorded_at -> 'at, 'expires_at -> 'expires];
      const defaults = ['by -> #-1, 'at -> 0, 'expires -> 0];
      for i in [1..length(identities)]
        const recorded = mapmerge(defaults, `relation.("meta_" + identities[i]) ! E_PROPNF => []');
        candidates[i] = {@candidates[i], @{ recorded[keys[field]] for field in (meta) }};
      endfor
    endif
    for tuple in (candidates)
      typeof(tuple) == TYPE_LIST && length(tuple) > 0 || raise(E_INVARG, "Invalid stored relation fact");
      if (length(types) > 0)
        length(tuple) == length(types) || raise(E_INVARG, "Stored fact has the wrong number of fields");
        for i in [1..length(types)]
          $behavior_schema:_type(tuple[i], types[i], "relation field " + tostr(i));
        endfor
      endif
    endfor
    const rows = term_match(pattern, candidates, bindings, options);
    return ['rows -> rows[1..min(length(rows), limit)], 'complete -> length(rows) <= limit];
  endmethod

  method query owner: ARCH_WIZARD
    "Return distinct complete query answers. Raise E_QUOTA instead of returning a silent prefix.";
    set_task_perms(caller_perms());
    const result = $relation:_query_result(this, @args);
    result['complete] || raise(E_QUOTA, "Relation query exceeded its result limit");
    return result['rows];
  endmethod

  method reachable_from owner: ARCH_WIZARD
    "Find all values reachable via transitive closure from start value. Assumes binary relation.";
    "Read and mutation authority is the calling principal; this method does not suspend.";
    set_task_perms(caller_perms());
    const {start} = args;
    let visited = [start -> true];
    let frontier = {start};
    while (length(frontier) > 0)
      const current = frontier[1];
      frontier = listdelete(frontier, 1);
      for tuple in ($relation:select_containing(current, this))
        length(tuple) != 2 && raise(E_INVARG, "reachable_from requires binary relation");
        const {val_a, val_b} = tuple;
        const other = val_a == current ? val_b | val_a;
        !maphaskey(visited, other) && (visited[other] = true) && (frontier = {@frontier, other});
      endfor
    endwhile
    return mapkeys(visited);
  endmethod

  method test_query_basic owner: HACKER
    "Test basic pattern matching with variables";
    const rel = $relation:create(true);
    rel:assert({#990012, #990039, "north"});
    rel:assert({#990012, #990040, "east"});
    rel:assert({#990039, #990040, "south"});
    "Query for all passages from #990012";
    let results = rel:query({#990012, {'var, 'dest}, {'var, 'label}});
    length(results) != 2 && raise(E_ASSERT, "Expected 2 results from #990012");
    ['dest -> #990039, 'label -> "north"] in results || raise(E_ASSERT, "Missing north binding");
    ['dest -> #990040, 'label -> "east"] in results || raise(E_ASSERT, "Missing east binding");
    "Query for passages to #990039";
    results = rel:query({{'var, 'src}, #990039, {'var, 'label}});
    length(results) != 1 && raise(E_ASSERT, "Expected 1 result to #990039");
    ['src -> #990012, 'label -> "north"] in results || raise(E_ASSERT, "Missing binding");
    "Query all tuples";
    results = rel:query({{'var, 'a}, {'var, 'b}, {'var, 'c}});
    length(results) != 3 && raise(E_ASSERT, "Expected 3 results for all tuples");
  endmethod

  method test_reachable owner: HACKER
    "Test transitive closure - note: relation is bidirectional";
    const rel = $relation:create(true);
    "Build a chain: 1 <-> 2 <-> 3 <-> 4";
    rel:assert({#990001, #990002});
    rel:assert({#990002, #990003});
    rel:assert({#990003, #990004});
    "Add a branch: 2 <-> 5";
    rel:assert({#990002, #990005});
    let reachable = rel:reachable_from(#990001);
    length(reachable) != 5 && raise(E_ASSERT, "Should reach 5 nodes from #990001");
    #990001 in reachable || raise(E_ASSERT, "Should include start node");
    #990002 in reachable || raise(E_ASSERT, "Should reach #990002");
    #990003 in reachable || raise(E_ASSERT, "Should reach #990003");
    #990004 in reachable || raise(E_ASSERT, "Should reach #990004");
    #990005 in reachable || raise(E_ASSERT, "Should reach #990005");
    "From #990003 reaches all nodes (bidirectional graph)";
    reachable = rel:reachable_from(#990003);
    length(reachable) != 5 && raise(E_ASSERT, "Should reach all 5 nodes from #990003");
    #990001 in reachable || raise(E_ASSERT, "Should reach #990001 via bidirectional edges");
    #990002 in reachable || raise(E_ASSERT, "Should reach #990002");
    #990004 in reachable || raise(E_ASSERT, "Should reach #990004");
    #990005 in reachable || raise(E_ASSERT, "Should reach #990005 via #990002");
  endmethod

  method count owner: ARCH_WIZARD
    "Count distinct facts under the caller's read permissions, including legacy storage.";
    set_task_perms(caller_perms());
    return length($relation:tuples(this));
  endmethod
endobject
