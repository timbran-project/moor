object ROOT
  name: "Root Prototype"
  location: FIRST_ROOM
  owner: HACKER
  fertile: true
  readable: true

  property aliases (owner: HACKER, flags: "rc") = {};
  property description (owner: HACKER, flags: "rc") = "Root prototype object from which all other objects inherit.";
  property import_export_id (owner: HACKER, flags: "r") = "root";
  property object_documentation (owner: HACKER, flags: "rc") = {
    "# $sub - Event Substitution System",
    "",
    "## Overview",
    "",
    "The `$sub` system provides template-based text substitution for events in the MOO. It allows you to write narrative",
    "descriptions that automatically adapt based on perspective (first-person vs third-person) and grammatical context.",
    "",
    "Substitutions are created as lightweight flyweight objects that get evaluated when events are rendered to players. This",
    "means the same event can produce different text for different viewers.",
    "",
    "## Basic Concept",
    "",
    "When you create an event, you build content using substitution flyweights:",
    "",
    "```moo",
    "content = {$sub:nc(), \" picks up \", $sub:d(), \".\"};",
    "```",
    "",
    "When this event is rendered:",
    "",
    "- **To the actor**: \"You pick up the sword.\"",
    "- **To others**: \"Alice picks up the sword.\"",
    "",
    "## Name Substitutions",
    "",
    "These substitute names of objects and participants in the event.",
    "",
    "### Actor Names",
    "",
    "| Verb        | Output                 | Example (actor is Alice) |",
    "|-------------|------------------------|--------------------------|",
    "| `$sub:n()`  | Actor name             | \"Alice\" / \"you\"          |",
    "| `$sub:nc()` | Capitalized actor name | \"Alice\" / \"You\"          |",
    "",
    "### Object Names",
    "",
    "| Verb        | Description          | Example               |",
    "|-------------|----------------------|-----------------------|",
    "| `$sub:d()`  | Direct object        | \"the sword\" / \"you\"   |",
    "| `$sub:dc()` | Capitalized dobj     | \"The sword\" / \"You\"   |",
    "| `$sub:i()`  | Indirect object      | \"the chest\" / \"you\"   |",
    "| `$sub:ic()` | Capitalized iobj     | \"The chest\" / \"You\"   |",
    "| `$sub:t()`  | This object          | \"the door\" / \"you\"    |",
    "| `$sub:tc()` | Capitalized this     | \"The door\" / \"You\"    |",
    "| `$sub:l()`  | Location             | \"the tavern\" / \"here\" |",
    "| `$sub:lc()` | Capitalized location | \"The tavern\" / \"Here\" |",
    "",
    "## Pronoun Substitutions",
    "",
    "These substitute pronouns based on the actor's or object's gender settings.",
    "",
    "### Actor Pronouns",
    "",
    "| Verb       | Type                 | Example (he/him)       | Example (they/them)       |",
    "|------------|----------------------|------------------------|---------------------------|",
    "| `$sub:s()` | Subject              | \"he\" / \"you\"           | \"they\" / \"you\"            |",
    "| `$sub:o()` | Object               | \"him\" / \"you\"          | \"them\" / \"you\"            |",
    "| `$sub:p()` | Possessive adjective | \"his\" / \"your\"         | \"their\" / \"your\"          |",
    "| `$sub:q()` | Possessive noun      | \"his\" / \"yours\"        | \"theirs\" / \"yours\"        |",
    "| `$sub:r()` | Reflexive            | \"himself\" / \"yourself\" | \"themselves\" / \"yourself\" |",
    "",
    "Add `c` for capitalized versions: `$sub:sc()`, `$sub:oc()`, etc.",
    "",
    "### Direct Object Pronouns",
    "",
    "| Verb            | Type            | Example              |",
    "|-----------------|-----------------|----------------------|",
    "| `$sub:s_dobj()` | Subject         | \"he\" / \"it\"          |",
    "| `$sub:o_dobj()` | Object          | \"him\" / \"it\"         |",
    "| `$sub:p_dobj()` | Possessive adj  | \"his\" / \"its\"        |",
    "| `$sub:q_dobj()` | Possessive noun | \"his\" / \"its\"        |",
    "| `$sub:r_dobj()` | Reflexive       | \"himself\" / \"itself\" |",
    "",
    "Also available with capitalization: `$sub:sc_dobj()`, etc.",
    "",
    "### Indirect Object Pronouns",
    "",
    "Same pattern as dobj, but using `_iobj` suffix:",
    "",
    "- `$sub:s_iobj()`, `$sub:o_iobj()`, `$sub:p_iobj()`, etc.",
    "- Capitalized: `$sub:sc_iobj()`, `$sub:oc_iobj()`, etc.",
    "",
    "## Verb Conjugation",
    "",
    "These conjugate verbs based on person and number.",
    "",
    "### Actor Verb Conjugation",
    "",
    "| Verb               | 2nd person (you) | 3rd person (he/she/it) |",
    "|--------------------|------------------|------------------------|",
    "| `$sub:verb_be()`   | \"are\"            | \"is\"                   |",
    "| `$sub:verb_have()` | \"have\"           | \"has\"                  |",
    "| `$sub:verb_look()` | \"look\"           | \"looks\"                |",
    "",
    "### Object Verb Conjugation",
    "",
    "Same verbs available with `_dobj` or `_iobj` suffix:",
    "",
    "- `$sub:verb_be_dobj()`, `$sub:verb_have_iobj()`, etc.",
    "",
    "## Self-Alternation",
    "",
    "The `self_alt()` method chooses between two alternatives based on whether the viewer is the actor.",
    "",
    "```moo",
    "$sub:self_alt(for_self, for_others)",
    "```",
    "",
    "### Basic Usage",
    "",
    "```moo",
    "content = {$sub:nc(), \" \", $sub:self_alt(\"feel\", \"feels\"), \" tired.\"};",
    "```",
    "",
    "- **To actor**: \"You feel tired.\"",
    "- **To others**: \"Alice feels tired.\"",
    "",
    "### Nested Substitutions",
    "",
    "You can nest substitutions inside `self_alt()`:",
    "",
    "```moo",
    "content = {",
    "    $sub:nc(), \" \", $sub:self_alt(\"try\", \"tries\"),",
    "    \" to pet the cat, but it swats \",",
    "    $sub:self_alt(\"your\", $sub:p()), \" hand away.\"",
    "};",
    "```",
    "",
    "- **To actor**: \"You try to pet the cat, but it swats **your** hand away.\"",
    "- **To others**: \"Alice tries to pet the cat, but it swats **her** hand away.\"",
    "",
    "The nested `$sub:p()` is only evaluated when the viewer is not the actor.",
    "",
    "### Capitalization",
    "",
    "Use `$sub:self_altc()` to capitalize the result:",
    "",
    "```moo",
    "$sub:self_altc(\"you're\", \"they're\")",
    "```",
    "",
    "## Complete Example",
    "",
    "Here's a full example of building event content:",
    "",
    "```moo",
    "verb pet (this none this)",
    "    dobj = args[1];",
    "",
    "    if (!dobj:allows_petting())",
    "        \"Build content for failed petting attempt\";",
    "        content = {",
    "            $sub:nc(), \" \", $sub:self_alt(\"try\", \"tries\"),",
    "            \" to pet \", $sub:d(), \", but \", $sub:d(),",
    "            \" hisses and swats \", $sub:self_alt(\"your\", $sub:p()),",
    "            \" hand away.\"",
    "        };",
    "",
    "        event = $event:mk(player, #-1, this, dobj, #-1, content, {});",
    "        event:send_to_location();",
    "",
    "        \"Tell actor they failed\";",
    "        notify(player, \"The cat doesn't want to be petted right now.\");",
    "        return;",
    "    endif",
    "",
    "    \"Build content for successful petting\";",
    "    content = {",
    "        $sub:nc(), \" \", $sub:self_alt(\"pet\", \"pets\"), \" \", $sub:d(),",
    "        \" gently, and \", $sub:d(), \" purrs contentedly.\"",
    "    };",
    "",
    "    event = $event:mk(player, #-1, this, dobj, #-1, content, {});",
    "    event:send_to_location();",
    "endverb",
    "```",
    "",
    "When Alice pets the friendly cat:",
    "",
    "- **Alice sees**: \"You pet the friendly cat gently, and the friendly cat purrs contentedly.\"",
    "- **Bob sees**: \"Alice pets the friendly cat gently, and the friendly cat purrs contentedly.\"",
    "",
    "When Alice tries to pet the grumpy cat:",
    "",
    "- **Alice sees**: \"You try to pet the grumpy cat, but the grumpy cat hisses and swats your hand away.\"",
    "- **Bob sees**: \"Alice tries to pet the grumpy cat, but the grumpy cat hisses and swats her hand away.\"",
    "",
    "## Implementation Notes",
    "",
    "- All substitution verbs return flyweight objects with a `.type` property",
    "- The actual substitution happens when the event is rendered via `:render_as()` or `:compose()`",
    "- Substitutions check if `event.actor == render_for` to determine perspective",
    "- The `name_sub()` method handles the \"you\" vs object name logic",
    "- Nested substitutions are evaluated recursively during rendering",
    "- If a dobj/iobj is missing, placeholder text like `\"<no-dobj>\"` is returned",
    "",
    "## Phrase Utilities",
    "",
    "The `$sub:phrase()` verb provides text manipulation:",
    "",
    "```moo",
    "$sub:phrase(text, options)",
    "```",
    "",
    "Options:",
    "",
    "- `'strip_period` - Remove trailing period",
    "- `'initial_lowercase` - Lowercase first character",
    "",
    "Example:",
    "",
    "```moo",
    "result = $sub:phrase(\"Hello world.\", {'strip_period, 'initial_lowercase});",
    "\"Result: hello world\";",
    "```",
    "",
    "## Technical Details",
    "",
    "- All substitution verbs use wildcard matching (e.g., `\"n* nc*\"`) to handle variations",
    "- Capitalization is controlled by checking for `\"c\"` in the verb name",
    "- The flyweight's `.capitalize` property is checked during rendering",
    "- Events are composed of lists that may contain strings, flyweights, or other content",
    "- The system recurses through content, evaluating each substitution flyweight it encounters",
    ""
  };
  property test_number (owner: ARCH_WIZARD, flags: "rc") = 42;
  property test_property (owner: ARCH_WIZARD, flags: "rc") = "test value";

  verb create (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Create a child of this object.";
    "";
    "Permission is granted if any of:";
    "  - Object is fertile";
    "  - Caller is wizard";
    "  - Caller is object owner";
    "  - this is a capability flyweight granting 'create_child";
    "";
    "Normal usage (fertile object):";
    "  new_obj = parent:create();";
    "";
    "Capability usage (non-fertile object):";
    "  cap = parent:issue_capability(parent, {'create_child}, ?exp, parent.owner);";
    "  new_obj = cap:create();  # Flyweight delegates to parent, validates cap";
    "";
    "Returns: New child object with caller_perms() as owner (or run_as from capability)";
    "Check fertility first - object-creation specific permission";
    target = typeof(this) == FLYWEIGHT ? this.delegate | this;
    is_fertile = `target.fertile ! E_PROPNF => false';
    if (!is_fertile)
      {_, perms} = this:check_permissions('create_child);
    endif
    new_obj = create(target, caller_perms());
    return new_obj;
  endverb

  verb destroy (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Destroy this object. Permission: wizard, owner, or capability.";
    this:check_permissions('recycle);
    recycle(this);
  endverb

  verb accept (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    return this:acceptable(@args);
  endverb

  verb acceptable (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Returns true if the object can accept items. Called by :accept (runtime-initiated) but can also be called elsewhere in scenarios where we are just checking in-advance.";
    set_task_perms(caller_perms());
    return false;
  endverb

  verb moveto (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Move this object to destination. Permission: wizard, owner, or capability.";
    {destination} = args;
    {this, perms} = this:check_permissions('move);
    set_task_perms(perms);
    return `move(this, destination) ! ANY';
  endverb

  verb set_owner (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set this object's owner. Permission: wizard or 'set_owner capability.";
    {target, perms} = this:check_permissions('set_owner);
    set_task_perms(perms);
    {new_owner} = args;
    target.owner = new_owner;
  endverb

  verb set_name_aliases (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set this object's name and aliases. Permission: wizard, owner, or 'set_name_aliases capability.";
    {target, perms} = this:check_permissions('set_name_aliases);
    set_task_perms(perms);
    {new_name, new_aliases} = args;
    target.name = new_name;
    target.aliases = new_aliases;
  endverb

  verb contents (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Returns a list of the objects that are apparently inside this one.  Don't confuse this with .contents, which is a property kept consistent with .location by the server.  This verb should be used in `VR' situations, for instance when looking in a room, and does not necessarily have anything to do with the value of .contents (although the default implementation does).  `Non-VR' commands (like @contents) should look directly at .contents.";
    set_task_perms(caller_perms());
    return this.contents;
  endverb

  verb all_contents (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return a list of all objects contained (at some level) by this object.";
    set_task_perms(caller_perms());
    res = {};
    for y in (this.contents)
      res = {@res, y, y:all_contents()};
    endfor
    return res;
  endverb

  verb description (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Returns the external description of the object.";
    return this.description;
  endverb

  verb set_description (this none this) owner: ARCH_WIZARD flags: "rxd"
    {target, perms} = this:check_permissions('set_description);
    set_task_perms(perms);
    {description} = args;
    this.description = description;
  endverb

  verb name (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    "Returns the presentation name of the object.";
    return this.name;
  endverb

  verb aliases (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    "Returns the aliases of the object.";
    return this.aliases;
  endverb

  verb look_self (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    return $look:mk(this, @this.contents);
  endverb

  verb all_verbs (this none this) owner: ARCH_WIZARD flags: "rx"
    set_task_perms(caller_perms());
    "Recurse up the inheritance hierarchy, getting a list of all verbs.";
    if (this.owner != caller_perms())
      set_task_perms(caller_perms());
    endif
    what = this;
    verbs = {};
    while (valid(what))
      verbs = {@verbs(what) || {}, @verbs};
      what = parent(what);
    endwhile
    return verbs;
  endverb

  verb all_command_verbs (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Get all command verbs (readable, not 'this none this') from this object and ancestors.";
    "Returns list of {verb_name, definer_object, dobj, prep, iobj} for each command verb.";
    set_task_perms(caller_perms());
    if (this.owner != caller_perms())
      set_task_perms(caller_perms());
    endif
    result = {};
    "Walk inheritance chain";
    for definer in ({this, @ancestors(this)})
      "Get verbs defined on this specific object";
      for verb_name in (verbs(definer))
        "Get verb info to check flags";
        {verb_owner, verb_flags, verb_names} = verb_info(definer, verb_name);
        "Skip non-readable verbs";
        if (!index(verb_flags, "r"))
          continue;
        endif
        "Get verb args to check if it's a command verb";
        {dobj, prep, iobj} = verb_args(definer, verb_name);
        "Skip internal 'this none this' verbs";
        if (dobj == "this" && prep == "none" && iobj == "this")
          continue;
        endif
        "Add to result list";
        result = {@result, {verb_name, definer, dobj, prep, iobj}};
      endfor
    endfor
    return result;
  endverb

  verb branches (this none this) owner: ARCH_WIZARD flags: "rxd"
    ":branches(object) => list of all descendants of this object which have children.";
    set_task_perms(caller_perms());
    if (kids = children(object = this))
      s = {object};
      for k in (kids)
        s = {@s, @k:branches()};
      endfor
      return s;
    else
      return {};
    endif
  endverb

  verb find_verb_definer (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Find verb on object or its ancestors, returning the object that actually defines the verb.";
    "Uses ancestors() builtin and verb_info() to handle aliases, wildcards, and inheritance.";
    "Usage: obj:find_verb_definer(verb_name)";
    set_task_perms(caller_perms());
    {verb_name} = args;
    "Check this object first";
    try
      verb_info(this, verb_name);
      return this;
    except (E_VERBNF)
    endtry
    "Then check ancestors";
    ancestor_list = ancestors(this);
    for ancestor in (ancestor_list)
      try
        verb_info(ancestor, verb_name);
        return ancestor;
      except (E_VERBNF)
        continue;
      endtry
    endfor
    return #-1;
  endverb

  verb estimated_size_bytes (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Return a spitball estimate of the in-memory size / on-disk size of this object.";
    "No guarantee of accuracy and this computation is relatively expensive so use sparingly.";
    "Caller must own the object or have the arcane powers of a wizard.";
    caller == this.owner || caller.wizard || raise(E_PERM);
    return object_bytes(this);
  endverb

  verb issue_capability (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Issue an unforgeable capability flyweight for delegating specific permissions.";
    "";
    "Capabilities implement object-capability security (E-rights model) where possession";
    "of the flyweight grants authority. The capability is cryptographically signed using";
    "PASETO V4.Local tokens, making them unforgeable and tamper-proof.";
    "";
    "Args:";
    "  target        - Object the capability grants access to (becomes flyweight delegate)";
    "  cap_list      - List of capability symbols (e.g., {'read, 'write, 'enter})";
    "  ?expiration   - Optional Unix timestamp when capability expires";
    "  ?run_as       - Optional object to elevate permissions to (caller or player only)";
    "  ?key          - Optional custom signing key (for testing; default uses server key)";
    "";
    "Returns: Flyweight <target, [token -> paseto_token]>";
    "";
    "Security:";
    "  - Only object owner or wizard can issue capabilities for an object";
    "  - Tokens are signed with server's symmetric key (wizard-only access)";
    "  - Token includes: target, caps, issued_at, granted_by, unique_id, optional exp/run_as";
    "  - Possession of flyweight grants bearer authority (protect like passwords)";
    "";
    "Example:";
    "  key = room:issue_capability(locked_room, {'enter), time() + 3600);";
    "  move(key, player);  # Give player a 1-hour access key";
    "  ";
    "  setup_cap = $root:issue_capability(new_player, {'set_owner, 'set_password});";
    "  setup_cap:set_owner(new_player);  # Capability-protected setup";
    {target, cap_list, ?expiration = 0, ?run_as = 0, ?key = 0} = args;
    "Only owner or wizard can issue";
    !caller_perms().wizard && caller_perms() != target.owner && raise(E_PERM);
    "Build claims map - PASETO handles symbols/objects natively via __type_* tags";
    claims = ['target -> target, 'caps -> cap_list, 'iat -> time(), 'granted_by -> caller_perms(), 'jti -> uuid()];
    "Add optional expiration";
    if (expiration)
      claims['exp] = expiration;
    endif
    "Add run_as if provided - issuer can grant run_as for self or player";
    "Note: Check run_as != 0, not truthiness, because objects are falsy in MOO";
    if (run_as != 0)
      run_as == caller_perms() || run_as == player || raise(E_PERM);
      claims['run_as] = run_as;
    endif
    "Create server authority PASETO token (wizard-only builtin)";
    token = key ? paseto_make_local(claims, key) | paseto_make_local(claims);
    return <target, .token = token>;
  endverb

  verb merge_capability (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Merge two capability flyweights for the same target into one with combined permissions.";
    caller_perms().wizard || raise(E_PERM);
    {cap1, cap2, ?key = 0} = args;
    "Both must be flyweights with tokens";
    typeof(cap1) == FLYWEIGHT && typeof(cap2) == FLYWEIGHT || raise(E_TYPE);
    maphaskey(flyslots(cap1), 'token) && maphaskey(flyslots(cap2), 'token) || raise(E_INVARG);
    "Both must be for the same target";
    cap1.delegate == cap2.delegate || raise(E_INVARG, "Capabilities must be for same target");
    target = cap1.delegate;
    "Decode both tokens";
    claims1 = key ? paseto_verify_local(cap1.token, key) | paseto_verify_local(cap1.token);
    claims2 = key ? paseto_verify_local(cap2.token, key) | paseto_verify_local(cap2.token);
    "Combine capability lists (remove duplicates)";
    all_caps = {@claims1["caps"], @claims2["caps"]};
    unique_caps = {};
    for cap in (all_caps)
      !(cap in unique_caps) && (unique_caps = {@unique_caps, cap});
    endfor
    "Take the later expiration if any";
    exp = 0;
    maphaskey(claims1, "exp") && (exp = claims1["exp"]);
    maphaskey(claims2, "exp") && claims2["exp"] > exp && (exp = claims2["exp"]);
    "Take run_as if either has it (prefer cap1) - comes back as object";
    run_as = 0;
    if (maphaskey(claims1, "run_as"))
      run_as = claims1["run_as"];
    elseif (maphaskey(claims2, "run_as"))
      run_as = claims2["run_as"];
    endif
    "Caps come back as symbols directly - unique_caps is already a list of symbols";
    "Issue new merged capability";
    return this:issue_capability(target, unique_caps, exp, run_as, key);
  endverb

  verb grant_capability (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Grant capabilities for target_obj to grantee, storing in specified category.";
    {target_obj, cap_list, grantee, category, ?key = 0} = args;
    "Permission: wizard, owner of target_obj, or TODO: 'grant capability";
    caller_perms().wizard || caller_perms() == target_obj.owner || raise(E_PERM);
    "Validate category is a symbol";
    typeof(category) == SYM || raise(E_TYPE);
    "Construct property name from category";
    prop_name = "grants_" + tostr(category);
    "Check that grantee has this grants bucket";
    grants_map = 0;
    try
      grants_map = grantee.(prop_name);
    except (E_PROPNF)
      raise(E_INVARG, tostr(grantee) + " cannot accept grants of category " + tostr(category) + " (missing property: " + prop_name + ")");
    endtry
    typeof(grants_map) == MAP || raise(E_INVARG, tostr(grantee) + "." + prop_name + " must be a map");
    "Issue new capability";
    new_cap = target_obj:issue_capability(target_obj, cap_list, 0, 0, key);
    "Check if grantee already has a grant for this object";
    if (maphaskey(grants_map, target_obj))
      "Merge with existing grant";
      old_cap = grants_map[target_obj];
      new_cap = $root:merge_capability(old_cap, new_cap, key);
    endif
    "Store the grant";
    grants_map[target_obj] = new_cap;
    grantee.(prop_name) = grants_map;
    "Notify the grantee if they're a player";
    if (is_player(grantee))
      grant_display = $grant_utils:format_grant_with_name(target_obj, category, cap_list);
      message = "You have been granted " + grant_display + ".";
      notify(grantee, message);
    endif
    return new_cap;
  endverb

  verb challenge_for (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Validate a capability and verify it grants the required permissions.";
    "";
    "Called on a capability flyweight to check if it grants specific capabilities.";
    "Performs cryptographic verification of the PASETO token, validates expiration,";
    "and checks target binding.";
    "";
    "Args: Variable number of capability symbols to require (e.g., 'read, 'write)";
    "";
    "Returns: {delegate, run_as_object} where run_as is from token or $hacker";
    "";
    "Raises: E_PERM if:";
    "  - this is not a flyweight";
    "  - token signature is invalid or tampered";
    "  - token has expired";
    "  - target binding doesn't match flyweight delegate";
    "  - any required capability is not granted";
    "";
    "Example:";
    "  {target, perms} = this:challenge_for('enter);";
    "  set_task_perms(perms);";
    return this:_capability_challenge(args, 0);
  endverb

  verb challenge_for_with_key (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Validate a capability using a custom signing key (for testing).";
    "";
    "Like challenge_for() but accepts a custom PASETO signing key instead of";
    "using the server's symmetric key. Primarily for testing scenarios.";
    "";
    "Args:";
    "  caps_list  - List of capability symbols (e.g., {'read, 'write})";
    "  key        - Custom PASETO signing key (base64-encoded 32-byte string)";
    "";
    "Returns: {delegate, run_as_object} where run_as is from token or $hacker";
    "";
    "Example:";
    "  test_key = \"dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q=\";";
    "  {target, perms} = cap:challenge_for_with_key({'read}, test_key);";
    {caps_list, key} = args;
    return this:_capability_challenge(caps_list, key);
  endverb

  verb require_caller (this none this) owner: HACKER flags: "rxd"
    "Verify that caller is the expected object (or a flyweight with that object as delegate).";
    "Raises E_PERM if check fails, otherwise returns normally.";
    "Usage: $root:require_caller(this);";
    {expected} = args;
    if (caller == expected)
      return;
    endif
    if (typeof(caller) == FLYWEIGHT && caller.delegate == expected)
      return;
    endif
    raise(E_PERM);
  endverb

  verb check_permissions (this none this) owner: HACKER flags: "rxd"
    "Check wizard, owner, or capability permission. Returns {target, perms_object}.";
    "Anyone can call this - authorization is checked internally based on caller_perms()";
    target = typeof(this) == FLYWEIGHT ? this.delegate | this;
    if (caller_perms().wizard)
      return {target, caller_perms()};
    endif
    if (caller_perms() == target.owner)
      return {target, caller_perms()};
    endif
    return this:challenge_for(@args);
  endverb

  verb _capability_challenge (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Internal: Validate capability with optional custom signing key.";
    if (!(caller == this || (typeof(this) == FLYWEIGHT && caller == this.delegate)))
      raise(E_PERM);
    endif
    {required_caps, key} = args;
    "Type check - this must be a flyweight";
    if (typeof(this) != FLYWEIGHT)
      raise(E_PERM);
    endif
    "Structure check - must have token slot";
    if (!maphaskey(flyslots(this), 'token))
      raise(E_PERM);
    endif
    "Verify PASETO signature and decode";
    claims = 0;
    try
      claims = key ? paseto_verify_local(this.token, key) | paseto_verify_local(this.token);
    except (E_INVARG)
      raise(E_PERM);
    endtry
    "Target binding - token must match this flyweight's delegate";
    if (this.delegate != claims["target"])
      raise(E_PERM);
    endif
    "Expiration check";
    if (maphaskey(claims, "exp") && time() > claims["exp"])
      raise(E_PERM);
    endif
    "Capability subset check - symbols round-trip directly";
    for required in (required_caps)
      if (!(required in claims["caps"]))
        raise(E_PERM);
      endif
    endfor
    "Determine run_as object - comes back as object directly via __type_obj";
    run_as = $hacker;
    if (maphaskey(claims, "run_as"))
      run_as = claims["run_as"];
    endif
    return {this.delegate, run_as};
  endverb

  verb test_all_verbs (this none this) owner: HACKER flags: "rx"
    all_verbs = this:all_verbs();
    !("all_verbs" in all_verbs) || (!("test_all_verbs" in all_verbs) && return E_ASSERT);
    return true;
  endverb

  verb test_capabilities (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test capability issuance and challenge with custom test key";
    test_key = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q=";
    "Test 1: Issue capability with custom key";
    cap = this:issue_capability(this, {'read}, 0, 0, test_key);
    typeof(cap) == FLYWEIGHT || raise(E_ASSERT, "Cap should be flyweight");
    cap.delegate == this || raise(E_ASSERT, "Cap delegate should be this");
    maphaskey(flyslots(cap), 'token) || raise(E_ASSERT, "Cap should have token slot");
    "Test 2: Challenge returns {delegate, run_as}";
    {target, run_as} = cap:challenge_for_with_key({'read}, test_key);
    typeof(target) == OBJ || raise(E_ASSERT, "Target should be OBJ");
    target == this || raise(E_ASSERT, "Target should be this");
    typeof(run_as) == OBJ || raise(E_ASSERT, "run_as should be OBJ");
    run_as == $hacker || raise(E_ASSERT, "run_as should be $hacker");
    "Test 3: Multiple capabilities";
    multi_cap = this:issue_capability(this, {'read, 'write, 'execute}, 0, 0, test_key);
    multi_cap:challenge_for_with_key({'read, 'write}, test_key);
    "Should succeed - all required caps present";
    "Test 4: Expiration check";
    expired_cap = this:issue_capability(this, {'read}, time() - 1, 0, test_key);
    expired_valid = false;
    try
      expired_cap:challenge_for_with_key({'read}, test_key);
      expired_valid = true;
    except (E_PERM)
    endtry
    !expired_valid || raise(E_ASSERT("Expired capability should have raised E_PERM"));
    "Test 5: Missing capability";
    read_cap = this:issue_capability(this, {'read}, 0, 0, test_key);
    write_denied = false;
    try
      read_cap:challenge_for_with_key({'write}, test_key);
      write_denied = true;
    except (E_PERM)
    endtry
    !write_denied || raise(E_ASSERT("Missing capability should have raised E_PERM"));
    "Test 6: run_as claim";
    run_as_cap = this:issue_capability(this, {'read}, 0, $arch_wizard, test_key);
    {target2, run_as_obj} = run_as_cap:challenge_for_with_key({'read}, test_key);
    target2 == this || raise(E_ASSERT, "run_as cap target should be this");
    run_as_obj == $arch_wizard || raise(E_ASSERT, "run_as_obj should be $arch_wizard");
    return true;
  endverb

  verb test_merge_capability (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test merging two capabilities for the same target";
    test_key = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q=";
    "Test 1: Merge two capabilities with different permissions";
    cap1 = this:issue_capability(this, {'read, 'write}, 0, 0, test_key);
    cap2 = this:issue_capability(this, {'execute, 'delete}, 0, 0, test_key);
    merged = $root:merge_capability(cap1, cap2, test_key);
    typeof(merged) == FLYWEIGHT || raise(E_ASSERT("Merged result should be a flyweight"));
    merged.delegate == this || raise(E_ASSERT("Merged delegate should match original"));
    "Test 2: Verify merged capability contains all permissions";
    {target, perms} = merged:challenge_for_with_key({'read, 'write, 'execute, 'delete}, test_key);
    target == this || raise(E_ASSERT("Merged capability should validate all permissions"));
    "Test 3: Merge with overlapping permissions";
    cap3 = this:issue_capability(this, {'read, 'write}, 0, 0, test_key);
    cap4 = this:issue_capability(this, {'write, 'execute}, 0, 0, test_key);
    merged2 = $root:merge_capability(cap3, cap4, test_key);
    {target2, perms2} = merged2:challenge_for_with_key({'read, 'write, 'execute}, test_key);
    target2 == this || raise(E_ASSERT("Merged overlapping should contain all unique permissions"));
    "Test 4: Merge with expiration - should take later expiration";
    future = time() + 3600;
    cap5 = this:issue_capability(this, {'read}, 0, 0, test_key);
    cap6 = this:issue_capability(this, {'write}, future, 0, test_key);
    merged3 = $root:merge_capability(cap5, cap6, test_key);
    claims = paseto_verify_local(merged3.token, test_key);
    maphaskey(claims, "exp") || raise(E_ASSERT("Merged should have expiration from cap6"));
    claims["exp"] == future || raise(E_ASSERT("Merged expiration should be later time"));
    "Test 5: Cannot merge capabilities for different targets";
    other_obj = create(this);
    cap7 = this:issue_capability(this, {'read}, 0, 0, test_key);
    cap8 = other_obj:issue_capability(other_obj, {'write}, 0, 0, test_key);
    merge_failed = false;
    try
      $root:merge_capability(cap7, cap8, test_key);
      merge_failed = true;
    except (E_INVARG)
    endtry
    other_obj:destroy();
    !merge_failed || raise(E_ASSERT("Should not be able to merge caps for different targets"));
    return true;
  endverb

  verb test_grant_capability (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test granting capabilities to players with auto-merge";
    test_key = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q=";
    "Create test objects";
    test_area = create($area);
    test_player = create($player);
    "Initialize grants properties";
    add_property(test_player, "grants_area", [], {test_player.owner, "rw"});
    add_property(test_player, "grants_room", [], {test_player.owner, "rw"});
    "Test 1: Grant initial capability";
    cap1 = $root:grant_capability(test_area, {'add_room}, test_player, 'area, test_key);
    typeof(cap1) == FLYWEIGHT || raise(E_ASSERT("Should return capability flyweight"));
    cap1.delegate == test_area || raise(E_ASSERT("Capability should be for test_area"));
    "Test 2: Verify capability was stored in grants_area";
    typeof(test_player.grants_area) == MAP || raise(E_ASSERT("grants_area should be a map"));
    maphaskey(test_player.grants_area, test_area) || raise(E_ASSERT("Should have grant for test_area"));
    stored_cap = test_player.grants_area[test_area];
    stored_cap == cap1 || raise(E_ASSERT("Stored capability should match returned one"));
    "Test 3: Grant additional capability - should auto-merge";
    cap2 = $root:grant_capability(test_area, {'create_passage}, test_player, 'area, test_key);
    typeof(cap2) == FLYWEIGHT || raise(E_ASSERT("Second grant should return flyweight"));
    "Test 4: Verify merged capability has both permissions";
    merged_cap = test_player.grants_area[test_area];
    {target, perms} = merged_cap:challenge_for_with_key({'add_room, 'create_passage}, test_key);
    target == test_area || raise(E_ASSERT("Merged cap should grant both permissions"));
    "Test 5: find_capability_for retrieves the grant";
    found_cap = test_player:find_capability_for(test_area, 'area);
    found_cap == merged_cap || raise(E_ASSERT("find_capability_for should return stored grant"));
    "Test 6: Different category (room grants)";
    test_room = create($room);
    room_cap = $root:grant_capability(test_room, {'dig_from}, test_player, 'room, test_key);
    typeof(test_player.grants_room) == MAP || raise(E_ASSERT("grants_room should be created"));
    maphaskey(test_player.grants_room, test_room) || raise(E_ASSERT("Should have grant for test_room"));
    found_room_cap = test_player:find_capability_for(test_room, 'room);
    found_room_cap == room_cap || raise(E_ASSERT("Should find room grant"));
    "Cleanup";
    test_area:destroy();
    test_player:destroy();
    test_room:destroy();
    return true;
  endverb

  verb is_actor (this none this) owner: HACKER flags: "rxd"
    "Return whether this object is an actor (player or NPC). Override in descendants.";
    return false;
  endverb

  verb display_name (this none this) owner: HACKER flags: "rxd"
    "Return the display name for this object. Defaults to :name() but can be overridden for richer descriptions.";
    return this:name();
  endverb
endobject