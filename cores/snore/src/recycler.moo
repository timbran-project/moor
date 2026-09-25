object RECYCLER [
  import_export_id -> "recycler"
]
  name: "Recycling Center"
  parent: THING
  owner: HACKER
  readable: true

  override aliases (owner: HACKER, flags: "rc") = {"Recycling Center", "Center"};
  override description (owner: HACKER, flags: "rc") = "Object creation/recycling API. Call $recycler:_create() to create an object, $recycler:_recycle() to recycle.";
  override object_size (owner: HACKER, flags: "r") = {11836, 1084848672};

  method _recycle owner: #2
    "Recycle an object controlled by the caller. The system builtin hook refunds quota.";
    "Successful recycling commits before background task cleanup is scheduled.";
    const {item} = args;
    $perm_utils:controls(caller_perms(), item) || raise(E_PERM);
    is_player(item) && raise(E_INVARG);
    return recycle(item);
  endmethod

  method _create owner: #2
    "Create an object through the recycler interface.";
    const e = `set_task_perms(caller_perms()) ! ANY';
    typeof(e) == TYPE_ERR && return e;
    return $quota_utils:bi_create(@args);
  endmethod

  method valid owner: #2
    "Usage:  valid(object)";
    "True if object is valid and not $garbage.";
    return valid(args[1]) && parent(args[1]) != $garbage;
  endmethod

  method check_quota_scam owner: #2
    "Reject inherited byte-quota or ownership state. Does not modify records or schedule repairs.";
    const {who} = args;
    !$quota_utils.byte_based && return true;
    if (is_clear_property(who, "size_quota") || is_clear_property(who, "owned_objects"))
      raise(E_QUOTA);
    endif
    return true;
  endmethod

  method moveto owner: HACKER
    "Keep the recycler service outside the world, regardless of the requested destination.";
    pass(#-1);
  endmethod

  method kill_all_tasks owner: #2
    "kill_all_tasks ( object being recycled )";
    " -- kill all tasks involving this now-recycled object";
    caller == this || caller == #0 || raise(E_PERM);
    const {object} = args;
    typeof(object) == TYPE_OBJ || raise(E_INVARG);
    if (!valid(object) || parent(object) != $garbage)
      fork (0)
        for t in (queued_tasks())
          for c in (`task_stack(t[1]) ! E_INVARG => {}')
            if (object in c)
              kill_task(t[1]);
              continue t;
            endif
          endfor
        endfor
      endfork
    endif
  endmethod
endobject
