object ROOT
    name: "Root Prototype"
    owner: HACKER
    fertile: true
    readable: true

    property aliases (owner: HACKER, flags: "rc") = {};
    property description (owner: HACKER, flags: "rc") = "";

    verb accept (this none this) owner: HACKER flags: "rxd"
        set_task_perms(caller_perms());
        return this:acceptable(@args);
    endverb

    verb acceptable (this none this) owner: HACKER flags: "rxd"
        "Returns true if the object can accept items. Called by :accept (runtime-initiated) but can also be called elsewhere in scenarios where we are just checking in-advance.";
        return false;
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
        verbs = {};
        while (valid(what))
          verbs = {@verbs(what) || {}, @verbs};
          what = parent(what);
        endwhile
        return verbs;
    endverb

    verb ancestors (this none this) owner: HACKER flags: "rxd"
        "Usage:  ancestors([]object...])";
        "Return a list of all ancestors of this object(s), plus (optionally) the objects in in args, with no duplicates.";
        "If called with a single object, the result will be in order ascending up the inheritance hierarchy.  If called with multiple objects, it probably won't.";
        ret = {};
        search_set = {this, @args};
        for o in (search_set)
          what = o;
        while (valid(what = parent(what)))
            ret = setadd(ret, what);
          endwhile
        endfor
        return ret;
    endverb

    verb branches (this none this) owner: #35 flags: "rxd"
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

    verb "descendants descendents" (this none this) owner: #184 flags: "rxd"
        what = this;
        kids = children(what);
        result = {};
        for x in (kids)
          result = {@result, @x:descendants()};
        endfor
        return {@kids, @result};
    endverb

    verb contents (this none this) owner: HACKER flags: "rxd"
        "Returns a list of the objects that are apparently inside this one.  Don't confuse this with .contents, which is a property kept consistent with .location by the server.  This verb should be used in `VR' situations, for instance when looking in a room, and does not necessarily have anything to do with the value of .contents (although the default implementation does).  `Non-VR' commands (like @contents) should look directly at .contents.";
        return this.contents;
    endverb

    verb description (this none this) owner: HACKER flags: "rxd"
        "Returns the external description of the object.";
        return this.description;
    endverb

    verb name (this none this) owner: HACKER flags: "rxd"
        "Returns the presentation name of the object.";
        return this.name;
    endverb
endobject
