object GIT [
  import_export_id -> "git",
  import_export_hierarchy -> {"git"}
]
  name: "Git"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  override description = "Read-only Git access. Network operations require a wizard caller. Repository and result flyweights carry data, not authority.";

  method repository owner: ARCH_WIZARD
    "Create a repository descriptor without network access. Args: URL, optional limits, timeout seconds.";
    set_task_perms(caller_perms());
    const {url, ?limits = [], ?timeout = 30.0} = args;
    typeof(url) == TYPE_STR || raise(E_TYPE, "Repository URL must be a string.");
    typeof(limits) == TYPE_MAP || raise(E_TYPE, "Limits must be a map.");
    $git:check_timeout(timeout);
    let normalized = [];
    for key in (mapkeys(limits))
      typeof(key) in {TYPE_STR, TYPE_SYM} || raise(E_TYPE, "Limit names must be strings or symbols.");
      const name = tostr(key);
      name in {"max_entries", "max_file_bytes", "max_total_bytes"} || raise(E_INVARG, "Unknown Git limit.");
      const value = limits[key];
      (typeof(value) == TYPE_INT && value > 0) || raise(E_INVARG, "Git limits must be positive integers.");
      !maphaskey(normalized, name) || raise(E_INVARG, "Duplicate Git limit.");
      normalized[name] = value;
    endfor
    return toflyweight($git_repository, ['url -> url, 'limits -> normalized, 'timeout -> timeout]);
  endmethod

  method capabilities owner: ARCH_WIZARD
    "Return worker capabilities. Wizard only; suspends and commits the current transaction.";
    set_task_perms(caller_perms());
    const {} = args;
    return $git:request('capabilities, []);
  endmethod

  method request owner: ARCH_WIZARD
    "Send a schema-1 request as the incoming wizard. Suspends; returns validated results or raises E_GIT with worker details.";
    const actor = caller_perms();
    (valid(actor) && actor.wizard) || raise(E_PERM, "Git requests require wizard authority.");
    set_task_perms(actor);
    const {operation, fields, ?timeout = 30.0} = args;
    typeof(operation) in {TYPE_STR, TYPE_SYM} || raise(E_TYPE);
    typeof(fields) == TYPE_MAP || raise(E_TYPE);
    const op = tosym(operation);
    op in {'capabilities, 'refs, 'tree, 'read, 'snapshot} || raise(E_INVARG, "Unknown Git operation.");
    $git:check_timeout(timeout);
    let request = [];
    for key in (mapkeys(fields))
      typeof(key) in {TYPE_STR, TYPE_SYM} || raise(E_TYPE, "Request field names must be strings or symbols.");
      const name = tostr(key);
      !maphaskey(request, name) || raise(E_INVARG, "Duplicate Git request field.");
      request[name] = fields[key];
    endfor
    request["schema"] = 1;
    const repository = maphaskey(request, "repository") ? request["repository"] | "";
    const response = $git:_send(op, request, timeout);
    return $git:unpack(op, response, repository);
  endmethod

  method _send owner: ARCH_WIZARD
    "Transport boundary. Direct calls also require a wizard; worker errors propagate unchanged.";
    const actor = caller_perms();
    (valid(actor) && actor.wizard) || raise(E_PERM, "Git requests require wizard authority.");
    set_task_perms(actor);
    const {operation, request, timeout} = args;
    $git:check_timeout(timeout);
    return worker_request('git, {operation, request}, ['timeout_seconds -> timeout]);
  endmethod

  method check_timeout owner: HACKER
    "Validate a finite, positive timeout before passing it to the worker builtin.";
    const {timeout} = args;
    typeof(timeout) == TYPE_FLOAT || raise(E_TYPE, "Git timeout must be a float.");
    (timeout > 0.0 && timeout <= 86400.0) || raise(E_INVARG, "Git timeout must be within (0, 86400] seconds.");
    return timeout;
  endmethod

  method field owner: HACKER
    "Read a required wire field. Malformed worker data raises E_INVARG.";
    const {record, key, expected_type} = args;
    typeof(record) == TYPE_MAP || raise(E_INVARG, "Malformed Git record.");
    maphaskey(record, key) || raise(E_INVARG, "Missing Git field: " + key);
    typeof(record[key]) == expected_type || raise(E_INVARG, "Invalid Git field: " + key);
    return record[key];
  endmethod

  method oid owner: HACKER
    "Validate a schema-1 full SHA-1 object ID without changing its spelling.";
    const {value} = args;
    typeof(value) == TYPE_STR || raise(E_INVARG, "Invalid Git object ID.");
    length(value) == 45 || raise(E_INVARG, "Invalid Git object ID.");
    strcmp(value[1..5], "sha1:") == 0 || raise(E_INVARG, "Invalid Git object ID.");
    match(value[6..$], "^[0-9a-f]+$", 1) || raise(E_INVARG, "Invalid Git object ID.");
    return value;
  endmethod

  method unpack owner: HACKER
    "Decode a worker envelope into local values. Public and pure; supplied data establishes no authority.";
    const {operation, response, ?repository = ""} = args;
    $git:field(response, "schema", TYPE_INT) == 1 || raise(E_INVARG, "Unsupported Git response schema.");
    const ok = $git:field(response, "ok", TYPE_BOOL);
    if (!ok)
      const error = $git:field(response, "error", TYPE_MAP);
      const code = $git:field(error, "code", TYPE_STR);
      const message = $git:field(error, "message", TYPE_STR);
      raise(E_GIT, message, ['code -> code, 'message -> message]);
    endif
    const result = $git:field(response, "result", TYPE_MAP);
    if (operation == 'capabilities)
      for key in ({"operations", "transports", "object_formats"})
        const values = $git:field(result, key, TYPE_LIST);
        for value in (values)
          typeof(value) == TYPE_STR || raise(E_INVARG, "Malformed Git capabilities.");
        endfor
      endfor
      $git:field(result, "limits", TYPE_MAP);
      $git:field(result, "max_concurrent_requests", TYPE_INT);
      $git:field(result, "content_type", TYPE_STR);
      $git:field(result, "path_encoding", TYPE_STR);
      return result;
    elseif (operation == 'refs)
      let refs = {};
      for ref in ($git:field(result, "refs", TYPE_LIST))
        let record = ['name -> $git:field(ref, "name", TYPE_STR),
                      'oid -> $git:oid($git:field(ref, "oid", TYPE_STR))];
        if (maphaskey(ref, "peeled"))
          record['peeled] = $git:oid($git:field(ref, "peeled", TYPE_STR));
        endif
        refs = {@refs, record};
      endfor
      return refs;
    elseif (operation == 'read)
      const commit = $git:oid($git:field(result, "commit", TYPE_STR));
      const entry = $git_entry:mk($git:field(result, "entry", TYPE_MAP), repository, commit, true);
      entry.kind in {'file, 'symlink} || raise(E_INVARG, "Git read returned a non-blob entry.");
      return entry;
    elseif (operation in {'tree, 'snapshot})
      return $git_snapshot:mk(result, repository, operation == 'snapshot);
    endif
    raise(E_INVARG, "Unknown Git operation.");
  endmethod
endobject
