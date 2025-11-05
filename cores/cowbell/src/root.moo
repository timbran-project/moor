object ROOT
  name: "Root Prototype"
  location: FIRST_ROOM
  owner: HACKER
  fertile: true
  readable: true

  property aliases (owner: HACKER, flags: "rc") = {};
  property description (owner: HACKER, flags: "rc") = "Root prototype object from which all other objects inherit.";
  property import_export_id (owner: HACKER, flags: "r") = "root";

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
      {target, perms} = this:_perms_challenge('create_child);
      set_task_perms(perms);
    endif
    new_obj = create(target, caller_perms());
    return new_obj;
  endverb

  verb recycle (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Recycle this object. Permission: wizard, owner, or capability.";
    this:_perms_challenge('recycle);
    recycle(this);
  endverb

  verb accept (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    return this:acceptable(@args);
  endverb

  verb acceptable (this none this) owner: HACKER flags: "rxd"
    "Returns true if the object can accept items. Called by :accept (runtime-initiated) but can also be called elsewhere in scenarios where we are just checking in-advance.";
    return false;
  endverb

  verb moveto (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Move this object to destination. Permission: wizard, owner, or capability.";
    {destination} = args;
    {this, perms} = this:_perms_challenge('move);
    set_task_perms(perms);
    return `move(this, destination) ! ANY';
  endverb

  verb set_owner (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set this object's owner. Permission: wizard or 'set_owner capability.";
    {target, perms} = this:_perms_challenge('set_owner);
    set_task_perms(perms);
    {new_owner} = args;
    target.owner = new_owner;
  endverb

  verb set_name_aliases (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Set this object's name and aliases. Permission: wizard, owner, or 'set_name_aliases capability.";
    {target, perms} = this:_perms_challenge('set_name_aliases);
    set_task_perms(perms);
    {new_name, new_aliases} = args;
    target.name = new_name;
    target.aliases = new_aliases;
  endverb

  verb contents (this none this) owner: HACKER flags: "rxd"
    "Returns a list of the objects that are apparently inside this one.  Don't confuse this with .contents, which is a property kept consistent with .location by the server.  This verb should be used in `VR' situations, for instance when looking in a room, and does not necessarily have anything to do with the value of .contents (although the default implementation does).  `Non-VR' commands (like @contents) should look directly at .contents.";
    return this.contents;
  endverb

  verb all_contents (this none this) owner: HACKER flags: "rxd"
    "Return a list of all objects contained (at some level) by this object.";
    res = {};
    for y in (this.contents)
      res = {@res, y, y:all_contents()};
    endfor
    return res;
  endverb

  verb description (this none this) owner: HACKER flags: "rxd"
    "Returns the external description of the object.";
    return this.description;
  endverb

  verb set_description (this none this) owner: ARCH_WIZARD flags: "rxd"
    caller == #-1 || caller == this || caller.wizard || raise(E_PERM);
    set_task_perms(this);
    {description} = args;
    this.description = description;
  endverb

  verb name (this none this) owner: HACKER flags: "rxd"
    "Returns the presentation name of the object.";
    return this.name;
  endverb

  verb look_self (this none this) owner: HACKER flags: "rxd"
    return $look:mk(this, @this.contents);
  endverb

  verb all_verbs (this none this) owner: HACKER flags: "rx"
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

  verb branches (this none this) owner: FORMAT flags: "rxd"
    ":branches(object) => list of all descendants of this object which have children.";
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

  verb find_verb_definer (this none this) owner: HACKER flags: "rxd"
    "Find verb on object or its ancestors, returning the object that actually defines the verb.";
    "Uses ancestors() builtin and verb_info() to handle aliases, wildcards, and inheritance.";
    "Usage: obj:find_verb_definer(verb_name)";
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
    "Convert caps to literal strings for JSON encoding";
    cap_strings = { toliteral(c) for c in (cap_list) };
    "Build claims map";
    claims = ['target -> toliteral(target), 'caps -> cap_strings, 'iat -> time(), 'granted_by -> toliteral(caller_perms()), 'jti -> uuid()];
    "Add optional expiration";
    if (expiration)
      claims['exp] = expiration;
    endif
    "Add run_as if provided - issuer can grant run_as for self or player";
    if (run_as)
      run_as == caller_perms() || run_as == player || raise(E_PERM);
      claims['run_as] = toliteral(run_as);
    endif
    "Create server authority PASETO token (wizard-only builtin)";
    token = key ? paseto_make_local(claims, key) | paseto_make_local(claims);
    return <target, [token -> token]>;
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

  verb _perms_challenge (this none this) owner: HACKER flags: "rxd"
    "Check wizard, owner, or capability permission. Returns {target, perms_object}.";
    caller == this || raise(E_PERM);
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
    caller == this || raise(E_PERM);
    {required_caps, key} = args;
    "Type check - this must be a flyweight";
    typeof(this) == FLYWEIGHT || raise(E_PERM);
    "Structure check - must have token slot";
    maphaskey(slots(this), 'token) || raise(E_PERM);
    "Verify PASETO signature and decode";
    claims = 0;
    try
      claims = key ? paseto_verify_local(this.token, key) | paseto_verify_local(this.token);
    except (E_INVARG)
      raise(E_PERM);
    endtry
    "Target binding - token must match this flyweight's delegate";
    toliteral(this.delegate) == claims["target"] || raise(E_PERM);
    "Expiration check";
    maphaskey(claims, "exp") && time() > claims["exp"] && raise(E_PERM);
    "Capability subset check - convert required caps to literal strings";
    for required in (required_caps)
      toliteral(required) in claims["caps"] || raise(E_PERM);
    endfor
    "Determine run_as object";
    run_as = $hacker;
    if (maphaskey(claims, "run_as"))
      run_as_str = claims["run_as"];
      if (run_as_str[1] == "#")
        objnum = tonum(run_as_str[2..length(run_as_str)]);
        run_as = toobj(objnum);
      endif
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
    typeof(cap) == FLYWEIGHT || raise(E_ASSERT);
    cap.delegate == this || raise(E_ASSERT);
    maphaskey(slots(cap), 'token) || raise(E_ASSERT);
    "Test 2: Challenge returns {delegate, run_as}";
    {target, run_as} = cap:challenge_for_with_key({'read}, test_key);
    typeof(target) == OBJ || raise(E_ASSERT);
    target == this || raise(E_ASSERT);
    typeof(run_as) == OBJ || raise(E_ASSERT);
    run_as == $hacker || raise(E_ASSERT);
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
    target2 == this || raise(E_ASSERT);
    run_as_obj == $arch_wizard || raise(E_ASSERT);
    return true;
  endverb
endobject