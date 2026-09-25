object OBJECT_UTILS [
  import_export_id -> "object_utils"
]
  name: "object utilities"
  parent: GENERIC_UTILS
  owner: #2
  readable: true

  override aliases (owner: #2, flags: "rc") = {"object utilities"};
  override description (owner: #2, flags: "rc") = {
    "This is the object utilities utility package.  See `help $object_utils' for more details."
  };
  override help_msg (owner: #2, flags: "rc") = {
    "These routines are useful for finding out information about individual objects.",
    "",
    "Examining everything an object has defined on it:",
    "  all_verbs          (object) => like it says",
    "  all_properties     (object) => likewise",
    "  findable_properties(object) => tests to see if caller can \"find\" them",
    "  owned_properties   (object[, owner]) => tests for ownership",
    "",
    "Investigating inheritance:",
    "  ancestors(object[,object...]) => all ancestors",
    "  descendants      (object)     => all descendants",
    "  ordered_descendants(object)   => object and descendants, depth-first",
    "  leaves           (object)     => descendants with no children",
    "  branches         (object)     => descendants with children ",
    "  isa        (object,class) => true iff object is a descendant of class (or ==)",
    "  property_conflicts (object,newparent) => can object chparent to newparent?",
    "  isoneof     (object,list)     => true if object :isa class in list of parents",
    "",
    "Considering containment:",
    "  contains      (obj1, obj2) => Does obj1 contain obj2 (nested)?",
    "  all_contents      (object) => return all the (nested) contents of object",
    "  locations         (object) => list of location hierarchy above object",
    "",
    "Verifying verbs and properties:",
    "  has_property(object,pname) => false/true   according as object.(pname) exists",
    "  has_readable_property(object,pname) => false/true if prop exists and is +r",
    "  defines_property(object,pname) => does object *define* this property",
    "  has_verb    (object,vname) => false/{#obj} according as object:(vname) exists",
    "  has_callable_verb          => same, but verb must be callable from a program",
    "  defines_verb(object,vname) => does this object *define* this verb",
    "  match_verb  (object,vname) => false/{location, newvname}",
    "                               (identify location and usable name of verb)",
    "  accessible_verbs(object)   => a list of verb names (or E_PERM) regardless of ",
    "                                readability of object",
    "",
    "Player checking:",
    "  connected         (object) => true if object is a player and is connected",
    "",
    "Suspending:",
    "  Many of the above verbs have ..._suspended versions to assist with very large object hierarchies.  The following exist:",
    "   descendants_suspended              ",
    "   branches_suspended                 ",
    "   leaves_suspended                   ",
    "   all_properties_suspended / all_verbs_suspended",
    "   descendants_with_property_suspended"
  };
  override object_size (owner: HACKER, flags: "r") = {21564, 1084848672};

  method has_property owner: #2
    "Return whether a property exists, including inherited and builtin properties.";
    "This wizard metadata probe does not return the property's value.";
    const {object, prop} = args;
    try
      object.(prop);
      return true;
    except (E_PROPNF, E_INVIND)
      return false;
    endtry
  endmethod

  method "all_properties all_verbs" owner: #2
    "Return ancestor-first definitions; an object's owner can also inspect private ancestors.";
    const {root} = args;
    const principal = caller_perms();
    root.owner != principal && set_task_perms(principal);
    const operation = verb == "all_verbs" ? "verbs" | "properties";
    let object = root;
    let result = {};
    while (valid(object))
      result = {@`call_function(operation, object) ! E_PERM => {}', @result};
      object = parent(object);
    endwhile
    return result;
  endmethod

  method has_verb owner: #2
    "Return {defining_object} for an inherited or local verb, or 0 if absent.";
    "This wizard metadata probe also finds private verbs.";
    let {object, verb_name} = args;
    while (valid(object))
      const info = `verb_info(object, verb_name) ! E_VERBNF => {}';
      info && return {object};
      object = parent(object);
    endwhile
    return 0;
  endmethod

  method has_callable_verb owner: #2
    "Return {defining_object} for an executable, nonempty verb, or 0 if absent.";
    "Search ancestors when a local verb is empty or lacks x permission.";
    let {object, verb_name} = args;
    while (valid(object))
      const info = `verb_info(object, verb_name) ! E_VERBNF => {}';
      if (info && index(info[2], "x"))
        verb_code(object, verb_name) && return {object};
      endif
      object = parent(object);
    endwhile
    return 0;
  endmethod

  method match_verb owner: #2
    "Return {defining_object, usable_name}, removing wildcard markers, or 0.";
    const {object, pattern} = args;
    const verb_name = strsub(pattern, "*", "");
    const found = this:has_verb(object, verb_name);
    return found ? {found[1], verb_name} | 0;
  endmethod

  method isa owner: HACKER
    "Return whether object is class or inherits from it; invalid objects return false.";
    let {object, class} = args;
    while (valid(object))
      object == class && return true;
      object = parent(object);
    endwhile
    return false;
  endmethod

  method ancestors owner: HACKER
    "Return ancestors, excluding each argument, nearest first and without duplicates.";
    "For several arguments, retain the order of their first occurrence.";
    let result = {};
    for object in (args)
      let ancestor = parent(object);
      while (valid(ancestor))
        result = setadd(result, ancestor);
        ancestor = parent(ancestor);
      endwhile
    endfor
    return result;
  endmethod

  method ordered_descendants owner: HACKER
    "Return object and its descendants in depth-first preorder.";
    const {object} = args;
    const pending = {object};
    let result = {};
    while (pending)
      const next = pending[1];
      pending[1..1] = children(next);
      result = {@result, next};
    endwhile
    return result;
  endmethod

  method contains owner: HACKER
    "Return whether container contains object through one or more location links.";
    let {container, object} = args;
    while (valid(object))
      object = object.location;
      object == container && return valid(container);
    endwhile
    return false;
  endmethod

  method all_contents owner: HACKER
    "Return direct contents first, followed by each child's nested contents.";
    const {object} = args;
    const direct = object.contents;
    let result = direct;
    for child in (direct)
      child.contents && (result = {@result, @this:all_contents(child)});
    endfor
    return result;
  endmethod

  method findable_properties owner: #2
    "Return ancestor-first properties defined on objects readable by the caller.";
    "An object's owner and wizards can also see its definitions.";
    let {object} = args;
    const principal = caller_perms();
    let result = {};
    while (object != $nothing)
      if (object.r || object.owner == principal || principal.wizard)
        result = {@properties(object), @result};
      endif
      object = parent(object);
    endwhile
    return result;
  endmethod

  method owned_properties owner: #2
    "Return local and inherited properties owned by the caller, nearest definitions first.";
    "Only wizards can specify an alternate owner as the second argument.";
    const object = args[1];
    const principal = caller_perms();
    const owner = principal.wizard && length(args) > 1 ? args[2] | principal;
    let ancestor = object;
    let result = {};
    while (ancestor != $nothing)
      for prop in (properties(ancestor))
        property_info(object, prop)[1] == owner && (result = {@result, prop});
      endfor
      ancestor = parent(ancestor);
    endwhile
    return result;
  endmethod

  method property_conflicts owner: #2
    "Return {property_name, @defining_objects} groups that would prevent chparent.";
    "Return E_INVARG or E_PERM when the requested change is not permitted.";
    "Budget yields commit; recheck authority before each object's metadata scan.";
    const {object, new_parent} = args;
    const principal = caller_perms();
    !valid(object) && return E_INVARG;
    !valid(new_parent) && return new_parent == $nothing ? {} | E_INVARG;
    let names = {};
    let conflicts = {};
    let pending = {object};
    while (pending)
      !valid(object) || !valid(new_parent) && return E_INVARG;
      $perm_utils:controls(principal, object) || return E_PERM;
      new_parent.f || $perm_utils:controls(principal, new_parent) || return E_PERM;
      const candidate = pending[1];
      pending = pending[2..$];
      if (valid(candidate) && this:isa(candidate, object))
        pending = {@pending, @children(candidate)};
        for prop in (properties(candidate))
          if (`property_info(new_parent, prop) ! E_PROPNF => {}')
            const position = prop in names;
            if (position)
              conflicts[position] = {@conflicts[position], candidate};
            else
              names = {@names, prop};
              conflicts = {@conflicts, {prop, candidate}};
            endif
          endif
        endfor
      endif
      pending && $command_utils:suspend_if_needed(0);
    endwhile
    return conflicts;
  endmethod

  method descendants_with_property_suspended owner: #2
    "Return the first objects with property on each descendant branch, including object.";
    "An inherited property also counts. The caller must control object or object must be writable.";
    "Budget yields commit; recheck the root grant before scanning each candidate.";
    const {object, prop} = args;
    const principal = caller_perms();
    let pending = {object};
    let result = {};
    while (pending)
      valid(object) || return E_INVARG;
      object.w || $perm_utils:controls(principal, object) || return E_PERM;
      const candidate = pending[1];
      pending = pending[2..$];
      if (valid(candidate) && this:isa(candidate, object))
        if (`property_info(candidate, prop) ! E_PROPNF => {}')
          result = {@result, candidate};
        else
          pending = {@children(candidate), @pending};
        endif
      endif
      pending && $command_utils:suspend_if_needed(0);
    endwhile
    return result;
  endmethod

  method locations owner: #2
    "Return the location chain above object, nearest first, excluding object.";
    const {object} = args;
    let location = object.location;
    let result = {};
    while (valid(location))
      result = {@result, location};
      location = location.location;
    endwhile
    return result;
  endmethod

  method "all_properties_suspended all_verbs_suspended" owner: #2
    "Return ancestor-first definitions; an object's owner can also inspect private ancestors.";
    "Budget yields commit. Losing ownership drops that grant for the rest of the scan.";
    const {root} = args;
    const principal = caller_perms();
    root.owner != principal && set_task_perms(principal);
    const operation = verb == "all_verbs_suspended" ? "verbs" | "properties";
    let object = root;
    let result = {};
    while (valid(object))
      !valid(root) || root.owner != principal && set_task_perms(principal);
      result = {@`call_function(operation, object) ! E_PERM => {}', @result};
      object = parent(object);
      valid(object) && $command_utils:suspend_if_needed(0);
    endwhile
    return result;
  endmethod

  method connected owner: HACKER
    "Return whether object is a connected player.";
    return typeof(`connected_seconds(@args) ! E_INVARG') == TYPE_INT;
  endmethod

  method isoneof owner: HACKER
    "Return whether object is, or inherits from, any class in the supplied list.";
    let {object, classes} = args;
    while (valid(object))
      object in classes && return true;
      object = parent(object);
    endwhile
    return false;
  endmethod

  method defines_verb owner: #2
    "Return whether verb_info succeeds locally; invalid descriptors return false.";
    return !!(`verb_info(@args) ! ANY => false');
  endmethod

  method defines_property owner: #2
    "Return whether object defines property; builtin properties count at a root.";
    const {object, prop} = args;
    !valid(object) && return false;
    const ancestor = parent(object);
    !valid(ancestor) && return this:has_property(object, prop);
    return !this:has_property(ancestor, prop) && this:has_property(object, prop);
  endmethod

  method "has_any_verb has_any_property" owner: #2
    "Return whether object defines any verbs or properties; invalid objects return false.";
    const {object} = args;
    const operation = verb == "has_any_verb" ? "verbs" | "properties";
    return !!(`call_function(operation, object) ! E_INVARG => {}');
  endmethod

  method "has_readable_prop*erty hrp" owner: #2
    "Return whether property is public; builtin properties are publicly readable.";
    const {object, prop} = args;
    try
      return index(property_info(object, prop)[2], "r") > 0;
    except (E_PROPNF)
      return tostr(prop) in $code_utils.builtin_props > 0;
    endtry
  endmethod

  method "descendants descendents" owner: HACKER
    "Return descendants in breadth-first order, excluding root.";
    const {root} = args;
    let pending = children(root);
    let result = {};
    while (pending)
      const object = pending[1];
      pending = pending[2..$];
      const kids = children(object);
      pending = {@pending, @kids};
      result = {@result, object};
    endwhile
    return result;
  endmethod

  method leaves owner: HACKER
    "Return leaves in depth-first order, including root if it is a leaf.";
    const {root} = args;
    let pending = {root};
    let result = {};
    while (pending)
      const object = pending[1];
      pending = pending[2..$];
      const kids = children(object);
      pending = {@kids, @pending};
      !kids && (result = {@result, object});
    endwhile
    return result;
  endmethod

  method branches owner: HACKER
    "Return branches in depth-first preorder, including root if it has children.";
    const {root} = args;
    let pending = {root};
    let result = {};
    while (pending)
      const object = pending[1];
      pending = pending[2..$];
      const kids = children(object);
      pending = {@kids, @pending};
      kids && (result = {@result, object});
    endwhile
    return result;
  endmethod

  method "descendants_suspended descendents_suspended" owner: #2
    "Return descendants in breadth-first order, excluding root.";
    "Budget yields commit; candidates detached or deleted between transactions are skipped.";
    set_task_perms(caller_perms());
    const {root} = args;
    let pending = children(root);
    let result = {};
    while (pending)
      const object = pending[1];
      pending = pending[2..$];
      if (valid(object) && $object_utils:isa(object, root))
        const kids = children(object);
        pending = {@pending, @kids};
        result = {@result, object};
      endif
      pending && $command_utils:suspend_if_needed(0);
    endwhile
    return result;
  endmethod

  method leaves_suspended owner: #2
    "Return leaves in depth-first order, including root if it is a leaf.";
    "Budget yields commit; candidates detached or deleted between transactions are skipped.";
    set_task_perms(caller_perms());
    const {root} = args;
    let pending = {root};
    let result = {};
    while (pending)
      const object = pending[1];
      pending = pending[2..$];
      if (valid(object) && $object_utils:isa(object, root))
        const kids = children(object);
        pending = {@kids, @pending};
        !kids && (result = {@result, object});
      endif
      pending && $command_utils:suspend_if_needed(0);
    endwhile
    return result;
  endmethod

  method branches_suspended owner: #2
    "Return branches in depth-first preorder, including root if it has children.";
    "Budget yields commit; candidates detached or deleted between transactions are skipped.";
    set_task_perms(caller_perms());
    const {root} = args;
    let pending = {root};
    let result = {};
    while (pending)
      const object = pending[1];
      pending = pending[2..$];
      if (valid(object) && $object_utils:isa(object, root))
        const kids = children(object);
        pending = {@kids, @pending};
        kids && (result = {@result, object});
      endif
      pending && $command_utils:suspend_if_needed(0);
    endwhile
    return result;
  endmethod

  method "disown disinherit" owner: #2
    "Move a foreign child of your object to its grandparent; return true on success.";
    "Wizard authority permits chparent only after checking control of the parent.";
    const {victim} = args;
    const principal = caller_perms();
    const ancestor = parent(victim);
    $perm_utils:controls(principal, victim) && raise(E_INVARG, tostr(victim.name, " (", victim, ") is yours.  Use @chparent."));
    valid(ancestor) || raise(E_INVARG, tostr(victim.name, " (", victim, ") is already an orphan."));
    $perm_utils:controls(principal, ancestor) || raise(E_PERM, tostr(ancestor.name, " (", ancestor, "), the parent of ", victim.name, " (", victim, "), is not yours."));
    const grandparent = parent(ancestor);
    valid(grandparent) || raise(E_INVARG, tostr(victim.name, " (", victim, ") has no grandparent to take custody."));
    chparent(victim, grandparent);
    return true;
  endmethod

  method accessible_verbs owner: #2
    "Return local verb names or E_PERM for unreadable verbs, even on unreadable objects.";
    const {object} = args;
    valid(object) || raise(E_INVARG, "Invalid object argument");
    const count = length(verbs(object));
    set_task_perms(caller_perms());
    return { `verb_info(object, position)[3] ! E_PERM' for position in [1..count] };
  endmethod

  method "accessible_prop*erties accessible_props" owner: #2
    "Return local property names or E_PERM, regardless of object readability.";
    "Budget yields commit. Deleted properties are omitted; access is checked after each yield.";
    const {object} = args;
    const names = properties(object);
    set_task_perms(caller_perms());
    let result = {};
    for prop in (names)
      $command_utils:suspend_if_needed(0);
      const info = `property_info(object, prop) ! ANY';
      info != E_PROPNF && (result = {@result, info ? prop | E_PERM});
    endfor
    return result;
  endmethod
endobject
