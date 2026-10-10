object GIT_SNAPSHOT [
  import_export_id -> "git_snapshot",
  import_export_hierarchy -> {"git"}
]
  name: "Git Snapshot"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  override description = "Local Git directory data with repository, commit, tree, path, complete, and entries slots. Lookup never fetches missing data.";

  method mk owner: HACKER
    "Wrap a directory result. Complete means recursive contents from snapshot, rather than a tree listing.";
    const {result, repository, complete} = args;
    typeof(repository) == TYPE_STR || raise(E_TYPE);
    typeof(complete) == TYPE_BOOL || raise(E_TYPE);
    const commit = $git:oid($git:field(result, "commit", TYPE_STR));
    const tree = $git:oid($git:field(result, "tree", TYPE_STR));
    const path = $git:field(result, "path", TYPE_STR);
    const raw_entries = $git:field(result, "entries", TYPE_LIST);
    let entries = {};
    for record in (raw_entries)
      entries = {@entries, $git_entry:mk(record, repository, commit, complete)};
    endfor
    return toflyweight($git_snapshot, ['repository -> repository, 'commit -> commit,
      'tree -> tree, 'path -> path, 'complete -> complete, 'entries -> entries]);
  endmethod

  method entry owner: HACKER
    "Find a local entry by exact, case-sensitive subtree-relative path; raise E_RANGE if absent.";
    const {path} = args;
    typeof(path) == TYPE_STR || raise(E_TYPE);
    for entry in (this.entries)
      strcmp(entry.path, path) == 0 && return entry;
    endfor
    raise(E_RANGE, "Path is absent from this Git result: " + path);
  endmethod
endobject
