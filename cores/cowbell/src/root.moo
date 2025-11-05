object ROOT
  name: "Root Prototype"
  location: FIRST_ROOM
  owner: HACKER
  fertile: true
  readable: true

  property aliases (owner: HACKER, flags: "rc") = {};
  property description (owner: HACKER, flags: "rc") = "Root prototype object from which all other objects inherit.";
  property import_export_id (owner: HACKER, flags: "r") = "root";

  verb accept (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(caller_perms());
    return this:acceptable(@args);
  endverb

  verb acceptable (this none this) owner: HACKER flags: "rxd"
    "Returns true if the object can accept items. Called by :accept (runtime-initiated) but can also be called elsewhere in scenarios where we are just checking in-advance.";
    return false;
  endverb

  verb moveto (this none this) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(this.owner);
    return `move(this, args[1]) ! ANY';
  endverb

  verb all_contents (this none this) owner: HACKER flags: "rxd"
    "Return a list of all objects contained (at some level) by this object.";
    res = {};
    for y in (this.contents)
      res = {@res, y, y:all_contents()};
    endfor
    return res;
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

  verb contents (this none this) owner: HACKER flags: "rxd"
    "Returns a list of the objects that are apparently inside this one.  Don't confuse this with .contents, which is a property kept consistent with .location by the server.  This verb should be used in `VR' situations, for instance when looking in a room, and does not necessarily have anything to do with the value of .contents (although the default implementation does).  `Non-VR' commands (like @contents) should look directly at .contents.";
    return this.contents;
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

  verb look_self (this none this) owner: HACKER flags: "rxd"
    return $look:mk(this, @this.contents);
  endverb

  verb name (this none this) owner: HACKER flags: "rxd"
    "Returns the presentation name of the object.";
    return this.name;
  endverb

  verb test_all_verbs (this none this) owner: HACKER flags: "rx"
    all_verbs = this:all_verbs();
    !("all_verbs" in all_verbs) || (!("test_all_verbs" in all_verbs) && return E_ASSERT);
    return true;
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
    {target, cap_list, ?expiration, ?run_as} = args;
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
    token = paseto_make_local(claims);
    return <target, [token -> token]>;
  endverb

  verb challenge_for (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Validate a capability and verify it grants the required permissions.";
    "";
    "Called on a capability flyweight to check if it grants specific capabilities.";
    "Performs cryptographic verification of the PASETO token, validates expiration,";
    "checks target binding, and optionally elevates task permissions via run_as.";
    "";
    "Args: Variable number of capability symbols to require (e.g., 'read, 'write)";
    "";
    "Returns: Decoded claims map containing:";
    "  target      - Literal string of target object (e.g., \"#123\")";
    "  caps        - List of granted capability literal strings (e.g., {\"'read\"})";
    "  iat         - Issued-at timestamp";
    "  granted_by  - Literal string of issuing object";
    "  jti         - Unique token identifier (UUID)";
    "  exp         - Expiration timestamp (if present)";
    "  run_as      - Authority elevation target (if present)";
    "";
    "Raises: E_PERM if:";
    "  - this is not a flyweight";
    "  - token signature is invalid or tampered";
    "  - token has expired";
    "  - target binding doesn't match flyweight delegate";
    "  - any required capability is not granted";
    "";
    "Side effects:";
    "  - If run_as claim present, calls set_task_perms() to elevate authority";
    "";
    "Example:";
    "  key:challenge_for('enter);  # Raises E_PERM if key doesn't grant 'enter";
    "  claims = door:challenge_for('open, 'lock);  # Check for multiple caps";
    required_caps = args;
    "Type check - this must be a flyweight";
    typeof(this) == FLYWEIGHT || raise(E_PERM);
    "Structure check - must have token slot";
    maphaskey(slots(this), 'token) || raise(E_PERM);
    "Verify PASETO signature and decode";
    claims = 0;
    try
      claims = paseto_verify_local(this.token);
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
    "Authority elevation if capability grants it - run_as is encoded as literal";
    if (maphaskey(claims, "run_as"))
      "Parse run_as from literal string back to object - simple objnum parse";
      let run_as_str = claims["run_as"];
      if (run_as_str[1] == "#")
        let objnum = tonum(run_as_str[2..length(run_as_str)]);
        set_task_perms(toobj(objnum));
      endif
    endif
    return claims;
  endverb

  verb test_capabilities (this none this) owner: ARCH_WIZARD flags: "rxd"
    "Test capability issuance and challenge with custom test key";
    test_key = "dGVzdHRlc3R0ZXN0dGVzdHRlc3R0ZXN0dGVzdHRlc3Q=";
    "Test 1: Basic token creation and verification";
    claims = ['target -> toliteral(this), 'caps -> {toliteral('read)}, 'iat -> time(), 'jti -> uuid()];
    token = paseto_make_local(claims, test_key);
    decoded = paseto_verify_local(token, test_key);
    typeof(decoded) == MAP || raise(E_ASSERT);
    decoded["target"] == toliteral(this) || raise(E_ASSERT);
    toliteral('read) in decoded["caps"] || raise(E_ASSERT);
    "Test 2: Flyweight capability structure";
    cap = <this, [token -> token]>;
    typeof(cap) == FLYWEIGHT || raise(E_ASSERT);
    cap.delegate == this || raise(E_ASSERT);
    maphaskey(slots(cap), 'token) || raise(E_ASSERT);
    "Test 3: Expiration check";
    expired_claims = ['target -> toliteral(this), 'caps -> {toliteral('read)}, 'exp -> time() - 1, 'iat -> time(), 'jti -> uuid()];
    expired_token = paseto_make_local(expired_claims, test_key);
    exp_decoded = paseto_verify_local(expired_token, test_key);
    time() > exp_decoded["exp"] || raise(E_ASSERT);
    return true;
  endverb
endobject