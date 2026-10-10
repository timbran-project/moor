object GIT_SCENARIOS
  name: "Git Wrapper Scenarios"
  parent: ROOT
  owner: #90100
  readable: true
  override import_export_id = "git_scenarios";
  override import_export_hierarchy = {"tests", "baseline"};

  method call_as owner: #90100
    "Invoke a wrapper with the specified incoming principal and preserve the exception tuple.";
    const {actor, target, method, parameters} = args;
    set_task_perms(actor);
    try
      return {true, target:(method)(@parameters)};
    except error (ANY)
      return {false, error};
    endtry
  endmethod

  method file_record owner: HACKER
    "Return a small wire-format blob record.";
    const {path, content} = args;
    return ["path" -> path, "kind" -> "file", "oid" -> "sha1:0123456789abcdef0123456789abcdef01234567",
      "size" -> length(content), "executable" -> false, "content" -> content];
  endmethod

  method snapshot_response owner: HACKER
    "Return a worker envelope with two case-distinct paths.";
    const oid = "sha1:0123456789abcdef0123456789abcdef01234567";
    return ["schema" -> 1, "ok" -> true, "result" -> ["commit" -> oid, "tree" -> oid,
      "path" -> "src", "entries" -> {
        this:file_record("Readme", binary_from_str("Upper\r\n")),
        this:file_record("README", binary_from_str("UPPER\n"))}]];
  endmethod

  method test_git_network_requires_incoming_wizard owner: #90100
    "All network boundaries reject ordinary callers, including forged and inherited descriptors.";
    const repo = $git:repository("https://example.invalid/repo.git");
    const forged = toflyweight($git_repository, ['url -> repo.url, 'limits -> [],
      'timeout -> 30.0, 'wizard -> true, 'owner -> #90100]);
    const child = create($git_repository, #90101, 2);
    add_property(child, "url", repo.url, {#90101, "r"});
    add_property(child, "limits", [], {#90101, "r"});
    add_property(child, "timeout", 30.0, {#90101, "r"});
    try
      for actor in ({#90101, #90102})
        for target in ({repo, forged, child})
          for invocation in ({ {"refs", {}}, {"tree", {['ref -> "refs/heads/main"]}},
            {"read", {['ref -> "refs/heads/main"], "README"}},
            {"snapshot", {['ref -> "refs/heads/main"]}} })
            const result = this:call_as(actor, target, invocation[1], invocation[2]);
            $test_utils:assert_false(result[1], "non-wizard request must fail");
            $test_utils:assert_eq(result[2][1], E_PERM, "descriptor grants no authority");
          endfor
        endfor
        for invocation in ({ {"capabilities", {}}, {"request", {'capabilities, []}},
          {"_send", {'capabilities, ["schema" -> 1], 30.0}} })
          const result = this:call_as(actor, $git, invocation[1], invocation[2]);
          $test_utils:assert_false(result[1], "direct helper must fail");
          $test_utils:assert_eq(result[2][1], E_PERM, "helper preserves incoming authority");
        endfor
      endfor
    finally
      recycle(child);
    endtry
    return true;
  endmethod

  method test_git_local_values_need_no_wizard owner: #90100
    "Ordinary callers can build descriptors and inspect fetched results without a worker.";
    const response = this:snapshot_response();
    const snapshot = $git:unpack('snapshot, response, "https://example.invalid/repo.git");
    for actor in ({#90101, #90102})
      const descriptor = this:call_as(actor, $git, "repository", {snapshot.repository});
      $test_utils:assert_true(descriptor[1], "descriptor creation requires no privilege");
      const wrapped = this:call_as(actor, $git, "unpack", {'snapshot, response, snapshot.repository});
      $test_utils:assert_true(wrapped[1], "pure decoding requires no privilege");
      const upper = this:call_as(actor, snapshot, "entry", {"Readme"});
      $test_utils:assert_true(upper[1], "lookup requires no privilege");
      const text = this:call_as(actor, upper[2], "text", {});
      $test_utils:assert_eq(text, {true, "Upper\r\n"}, "text preserves line endings");
      const other = snapshot:entry("README");
      $test_utils:assert_eq(other:text(), "UPPER\n", "case-distinct paths remain distinct");
      const absent = this:call_as(actor, snapshot, "entry", {"readme"});
      $test_utils:assert_eq(absent[2][1], E_RANGE, "lookup is case sensitive and never fetches");
    endfor
    $test_utils:assert_true(snapshot.complete, "snapshot contains recursive content");
    $test_utils:assert_eq(snapshot.path, "src", "subtree path is retained");
    $test_utils:assert_eq(snapshot:entry("README").commit, snapshot.commit, "entry retains commit");
    return true;
  endmethod

  method test_git_binary_and_entry_kinds owner: #90100
    "Binary and symlink data stay exact; metadata-only entries never pretend to have contents.";
    const oid = "sha1:0123456789abcdef0123456789abcdef01234567";
    const binary = decode_base64("AP8NCg==");
    const blob = $git_entry:mk(this:file_record("bytes", binary), "repo", oid, true);
    $test_utils:assert_eq(blob:bytes(), binary, "NUL and non-UTF-8 bytes survive");
    $test_utils:assert_true(blob:has_content(), "blob has content");
    const invalid = this:call_as(#90102, blob, "text", {});
    $test_utils:assert_eq(invalid[2][1], E_INVARG, "invalid UTF-8 raises instead of replacing");
    const empty = $git_entry:mk(this:file_record("empty", binary_from_str("")), "repo", oid, true);
    $test_utils:assert_true(empty:has_content(), "empty file still has content");
    $test_utils:assert_eq(empty:text(), "", "empty file decodes");
    const link = $git_entry:mk(["path" -> "link", "kind" -> "symlink", "oid" -> oid,
      "size" -> 10, "content" -> binary_from_str("../outside")], "repo", oid, true);
    $test_utils:assert_eq(link.kind, 'symlink, "symlink remains a link");
    $test_utils:assert_eq(link:text(), "../outside", "target is data and is never followed");
    const executable = $git_entry:mk(["path" -> "script", "kind" -> "file", "oid" -> oid,
      "size" -> 0, "executable" -> true], "repo", oid);
    $test_utils:assert_true(executable.executable, "executable mode retained");
    for entry in ({executable,
      $git_entry:mk(["path" -> "dir", "kind" -> "directory", "oid" -> oid], "repo", oid, true),
      $git_entry:mk(["path" -> "sub", "kind" -> "submodule", "oid" -> oid], "repo", oid, true)})
      $test_utils:assert_false(entry:has_content(), "metadata has no content");
      const missing = this:call_as(#90102, entry, "bytes", {});
      $test_utils:assert_eq(missing[2][1], E_NACC, "missing bytes fail locally");
    endfor
    return true;
  endmethod

  method test_git_protocol_failures owner: #90100
    "Worker errors preserve stable codes; malformed and partial responses fail closed.";
    const failed = this:call_as(#90102, $git, "unpack", {'read,
      ["schema" -> 1, "ok" -> false, "error" -> ["code" -> "limit_exceeded", "message" -> "Too big."]]});
    $test_utils:assert_false(failed[1], "worker error raises");
    $test_utils:assert_eq(failed[2][1], E_GIT, "worker error has a distinct exception");
    $test_utils:assert_eq(failed[2][3]['code], "limit_exceeded", "stable code retained");
    $test_utils:assert_eq(failed[2][3]['message], "Too big.", "message retained");
    try
      $git:unpack('read, ["schema" -> 1, "ok" -> false,
        "error" -> ["code" -> "path_not_found", "message" -> "Absent."]]);
      raise(E_ASSERT, "Worker error must raise.");
    except error (E_GIT)
      $test_utils:assert_eq(error[3]['code], "path_not_found", "typed catch preserves worker details");
    endtry
    for response in ({[], ["schema" -> 2, "ok" -> true, "result" -> []],
      ["schema" -> 1, "ok" -> 1, "result" -> []],
      ["schema" -> 1, "ok" -> false, "error" -> ["message" -> "missing code"]],
      ["schema" -> 1, "ok" -> true, "result" -> ["commit" -> "bad"]]})
      const result = this:call_as(#90102, $git, "unpack", {'snapshot, response});
      $test_utils:assert_eq(result[2][1], E_INVARG, "malformed envelope rejected");
    endfor
    const oid = "sha1:0123456789abcdef0123456789abcdef01234567";
    for invalid_oid in ({"sha1:0123456789abcdef0123456789abcdef0123456g",
      "sha1:0123456789abcdef0123456789abcdef0123456", "SHA1:0123456789abcdef0123456789abcdef01234567"})
      const result = this:call_as(#90102, $git, "oid", {invalid_oid});
      $test_utils:assert_eq(result[2][1], E_INVARG, "malformed IDs are rejected");
    endfor
    const directory_read = this:call_as(#90102, $git, "unpack", {'read,
      ["schema" -> 1, "ok" -> true, "result" -> ["commit" -> oid,
        "entry" -> ["path" -> "dir", "kind" -> "directory", "oid" -> oid]]]});
    $test_utils:assert_eq(directory_read[2][1], E_INVARG, "read must contain a file or symlink");
    for record in ({["path" -> "missing", "kind" -> "file", "oid" -> oid, "size" -> 1, "executable" -> false],
      ["path" -> "wrong", "kind" -> "file", "oid" -> oid, "size" -> 1, "executable" -> false,
       "content" -> binary_from_str("too long")]})
      const response = ["schema" -> 1, "ok" -> true, "result" -> ["commit" -> oid, "tree" -> oid,
        "path" -> "", "entries" -> {record}]];
      const result = this:call_as(#90102, $git, "unpack", {'snapshot, response});
      $test_utils:assert_eq(result[2][1], E_INVARG, "incomplete snapshot rejected");
    endfor
    return true;
  endmethod

  method test_git_settings owner: #90100
    "Descriptors normalize limit keys and reject unsafe builtin timeouts before dispatch.";
    const repo = $git:repository("repo", ['max_entries -> 4, "max_file_bytes" -> 12], 5.0);
    $test_utils:assert_eq(repo.limits, ["max_entries" -> 4, "max_file_bytes" -> 12], "limits normalized");
    for timeout in ({0.0, -1.0, 86401.0})
      const result = this:call_as(#90100, $git, "request", {'capabilities, [], timeout});
      $test_utils:assert_eq(result[2][1], E_INVARG, "invalid timeout rejected before builtin");
    endfor
    for limits in ({['max_entries -> 0], ['unknown -> 1], ['max_entries -> 1, "max_entries" -> 2]})
      const result = this:call_as(#90102, $git, "repository", {"repo", limits});
      $test_utils:assert_eq(result[2][1], E_INVARG, "invalid limits rejected");
    endfor
    return true;
  endmethod

  method test_git_dispatch_and_results owner: #90100
    "Exercise the real adapter with a transaction-local transport substitute; restore it on every exit.";
    const original = verb_code($git, "_send");
    add_property($git, "test_request", {}, {#90100, ""});
    add_property($git, "test_response", [], {#90100, ""});
    try
      set_verb_code($git, "_send", {
        "this.test_request = {caller_perms(), @args};",
        "typeof(this.test_response) == TYPE_ERR && raise(this.test_response, \"Transport failed.\");",
        "return this.test_response;"});
      const repo = $git:repository("https://example.invalid/repo.git", ['max_entries -> 4], 5.0);
      const revision = ['ref -> "refs/heads/main"];
      $git.test_response = this:snapshot_response();
      const snapshot = repo:snapshot(revision, "src");
      $test_utils:assert_eq($git.test_request, {#90100, 'snapshot,
        ["schema" -> 1, "repository" -> repo.url, "revision" -> revision, "path" -> "src",
         "limits" -> ["max_entries" -> 4]], 5.0}, "schema, request settings, and actor preserved");
      $test_utils:assert_true(snapshot.complete, "snapshot response wrapped");
      const tree = repo:tree(['commit -> snapshot.commit], "src", true);
      $test_utils:assert_false(tree.complete, "tree is not a complete snapshot");
      $test_utils:assert_eq($git.test_request[3]["recursive"], true, "recursive setting sent");
      $test_utils:assert_eq($git.test_request[3]["revision"], ['commit -> snapshot.commit], "commit pin sent unchanged");
      $git.test_response = ["schema" -> 1, "ok" -> true, "result" -> ["commit" -> snapshot.commit,
        "entry" -> this:file_record("src/README", binary_from_str("hello"))]];
      const entry = repo:read(['commit -> snapshot.commit], "src/README");
      $test_utils:assert_eq(entry.path, "src/README", "read retains repository-relative path");
      $test_utils:assert_eq(entry:text(), "hello", "read content decoded explicitly");
      $git.test_response = ["schema" -> 1, "ok" -> true, "result" -> ["refs" -> {
        ["name" -> "refs/tags/v1", "oid" -> snapshot.commit, "peeled" -> snapshot.commit]}]];
      const refs = repo:refs();
      $test_utils:assert_eq(refs[1]['peeled], snapshot.commit, "peeled tag ID retained");
      $test_utils:assert_eq($git:request('refs, ['repository -> repo.url]), refs, "adapter accepts symbol keys");
      $git.test_response = ["schema" -> 1, "ok" -> false,
        "error" -> ["code" -> "invalid_request", "message" -> "Missing repository."]];
      const missing = this:call_as(#90100, $git, "request", {'refs, []});
      $test_utils:assert_eq(missing[2][1], E_GIT, "missing request fields preserve worker errors");
      $test_utils:assert_eq(missing[2][3]['code], "invalid_request", "invalid-request code retained");
      const caps = ["operations" -> {"refs"}, "transports" -> {"https"}, "object_formats" -> {"sha1"},
        "limits" -> [], "max_concurrent_requests" -> 4, "content_type" -> "binary", "path_encoding" -> "utf-8"];
      $git.test_response = ["schema" -> 1, "ok" -> true, "result" -> caps];
      $test_utils:assert_eq($git:capabilities(), caps, "capabilities returned intact");
      $git.test_response = E_QUOTA;
      const failure = this:call_as(#90100, repo, "refs", {});
      $test_utils:assert_eq(failure[2][1], E_QUOTA, "transport exceptions propagate unchanged");
    finally
      set_verb_code($git, "_send", original);
      delete_property($git, "test_request");
      delete_property($git, "test_response");
    endtry
    return true;
  endmethod
endobject
