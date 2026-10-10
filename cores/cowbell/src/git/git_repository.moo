object GIT_REPOSITORY [
  import_export_id -> "git_repository",
  import_export_hierarchy -> {"git"}
]
  name: "Git Repository"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  override description = "A Git URL and request settings. Each network method preserves incoming permissions for the canonical Git adapter.";

  method refs owner: ARCH_WIZARD
    "List advertised refs as maps with name, oid, and optional peeled. Wizard only; suspends.";
    set_task_perms(caller_perms());
    const {} = args;
    return $git:request('refs, ["repository" -> this.url, "limits" -> this.limits], this.timeout);
  endmethod

  method tree owner: ARCH_WIZARD
    "List a directory without blob contents. Args: revision, optional path and recursive flag. Wizard only; suspends.";
    set_task_perms(caller_perms());
    const {revision, ?path = "", ?recursive = false} = args;
    return $git:request('tree, ["repository" -> this.url, "revision" -> revision,
      "path" -> path, "recursive" -> recursive, "limits" -> this.limits], this.timeout);
  endmethod

  method read owner: ARCH_WIZARD
    "Read one entry with exact bytes. Args: revision, repository-relative path. Wizard only; suspends.";
    set_task_perms(caller_perms());
    const {revision, path} = args;
    return $git:request('read, ["repository" -> this.url, "revision" -> revision,
      "path" -> path, "limits" -> this.limits], this.timeout);
  endmethod

  method snapshot owner: ARCH_WIZARD
    "Fetch a complete recursive directory snapshot. Args: revision, optional path. Wizard only; suspends.";
    set_task_perms(caller_perms());
    const {revision, ?path = ""} = args;
    return $git:request('snapshot, ["repository" -> this.url, "revision" -> revision,
      "path" -> path, "limits" -> this.limits], this.timeout);
  endmethod
endobject
