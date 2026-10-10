object GIT_ENTRY [
  import_export_id -> "git_entry",
  import_export_hierarchy -> {"git"}
]
  name: "Git Entry"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  override description (owner: ARCH_WIZARD, flags: "rc") = "Local Git entry data. Files and symlinks can contain exact bytes; directories and submodules contain object IDs only.";

  method mk owner: HACKER
    "Validate and wrap an entry. No network access or authority is attached to the result.";
    const {record, repository, commit, ?require_content = false} = args;
    typeof(repository) == TYPE_STR || raise(E_TYPE);
    $git:oid(commit);
    typeof(require_content) == TYPE_BOOL || raise(E_TYPE);
    const path = $git:field(record, "path", TYPE_STR);
    const kind = $git:field(record, "kind", TYPE_STR);
    kind in {"file", "symlink", "directory", "submodule"} || raise(E_INVARG, "Unknown Git entry kind.");
    let slots = ['repository -> repository, 'commit -> commit, 'path -> path, 'kind -> tosym(kind), 'oid -> $git:oid($git:field(record, "oid", TYPE_STR))];
    if (kind in {"file", "symlink"})
      const size = $git:field(record, "size", TYPE_INT);
      size >= 0 || raise(E_INVARG, "Negative Git entry size.");
      slots['size] = size;
      if (kind == "file")
        slots['executable] = $git:field(record, "executable", TYPE_BOOL);
      endif
      if (require_content || maphaskey(record, "content"))
        const content = $git:field(record, "content", TYPE_BINARY);
        length(content) == size || raise(E_INVARG, "Git entry size does not match its contents.");
        slots['content] = content;
      endif
    elseif (maphaskey(record, "content"))
      raise(E_INVARG, "Git directories and submodules cannot contain blob data.");
    endif
    return toflyweight($git_entry, slots);
  endmethod

  method has_content owner: HACKER
    "Return whether this local entry includes blob bytes.";
    const {} = args;
    return maphaskey(flyslots(this), 'content);
  endmethod

  method bytes owner: HACKER
    "Return exact local bytes, including symlink targets. Raise E_NACC when content was not fetched.";
    const {} = args;
    maphaskey(flyslots(this), 'content) || raise(E_NACC, "Git entry has no local content.");
    return this.content;
  endmethod

  method text owner: HACKER
    "Decode local bytes as strict UTF-8. Invalid text raises E_INVARG; missing content raises E_NACC.";
    const {} = args;
    maphaskey(flyslots(this), 'content) || raise(E_NACC, "Git entry has no local content.");
    return binary_to_str(this.content);
  endmethod
endobject
