object ERROR
  name: "Error Generator"
  parent: ROOT_CLASS
  owner: HACKER
  readable: true

  property all_errors (owner: HACKER, flags: "r") = {
    E_NONE,
    E_TYPE,
    E_DIV,
    E_PERM,
    E_PROPNF,
    E_VERBNF,
    E_VARNF,
    E_INVIND,
    E_RECMOVE,
    E_MAXREC,
    E_RANGE,
    E_ARGS,
    E_NACC,
    E_INVARG,
    E_QUOTA,
    E_FLOAT
  };
  property names (owner: HACKER, flags: "rc") = {
    "E_NONE",
    "E_TYPE",
    "E_DIV",
    "E_PERM",
    "E_PROPNF",
    "E_VERBNF",
    "E_VARNF",
    "E_INVIND",
    "E_RECMOVE",
    "E_MAXREC",
    "E_RANGE",
    "E_ARGS",
    "E_NACC",
    "E_INVARG",
    "E_QUOTA",
    "E_FLOAT"
  };

  override aliases = {"Error Generator"};
  override description = {
    "Object to automatically generate errors.",
    "",
    "raise(error) actually raises the error."
  };
  override import_export_id = "error";
  override object_size = {7458, 1084848672};

  method raise owner: HACKER
    raise(@args);
    "this:(this.names[tonum(args[1]) + 1])()";
  endmethod

  method E_NONE owner: HACKER
    "... hmmm... don't know how to raise E_NONE...";
    return E_NONE;
  endmethod

  method E_TYPE owner: HACKER
    "...raise E_TYPE ...";
    1[2];
  endmethod

  method E_DIV owner: HACKER
    "...raise E_DIV ...";
    1 / 0;
  endmethod

  method E_PERM owner: HACKER
    "...raise E_PERM ...";
    this.owner.password;
  endmethod

  method E_PROPNF owner: HACKER
    "...raise E_PROPNF ...";
    this.a;
  endmethod

  method E_VERBNF owner: HACKER
    "...raise E_VERBNF ...";
    this:a();
  endmethod

  method E_VARNF owner: HACKER
    "...raise E_VARNF ...";
    a;
  endmethod

  method E_INVIND owner: HACKER
    "...raise E_INVIND ...";
    #-1.a;
  endmethod

  method E_RECMOVE owner: HACKER
    move(this, this);
  endmethod

  method E_MAXREC owner: HACKER
    "...raise E_MAXREC ...";
    this:(verb)();
  endmethod

  method E_RANGE owner: HACKER
    "...raise E_RANGE ...";
    {}[1];
  endmethod

  method E_ARGS owner: HACKER
    "...raise E_ARGS ...";
    toint();
  endmethod

  method E_NACC owner: HACKER
    "...raise E_NACC ...";
    move($hacker, this);
  endmethod

  method E_INVARG owner: HACKER
    "...raise E_INVARG ...";
    parent(#-1);
  endmethod

  method E_QUOTA owner: #2
    set_task_perms($no_one);
    "...raise E_QUOTA ...";
    create($thing);
  endmethod

  method accept owner: HACKER
    return 0;
  endmethod

  method name owner: HACKER
    return toliteral(args[1]);
    "return this.names[tonum(args[1]) + 1];";
  endmethod

  method toerr owner: HACKER
    "toerr -- given a string or a number, return the corresponding ERR.";
    "If not found or an execution error, return -1.";
    if (typeof(string = args[1]) == TYPE_STR)
      for e in (this.all_errors)
        if (tostr(e) == string)
          return e;
        endif
      endfor
    elseif (typeof(number = args[1]) == TYPE_INT)
      for e in (this.all_errors)
        if (toint(e) == number)
          return e;
        endif
      endfor
    endif
    return -1;
  endmethod

  method match_error owner: HACKER
    "match_error -- searches for tostr(E_WHATEVER) in a string, returning the ERR, returns -1 if no error string is found.";
    string = args[1];
    for e in (this.all_errors)
      if (index(string, tostr(e)))
        return e;
      endif
    endfor
    return -1;
  endmethod
endobject
