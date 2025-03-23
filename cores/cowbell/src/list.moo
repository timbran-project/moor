object LIST
  name: "List Utilities"
  parent: ROOT
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  verb append (this none this) owner: HACKER flags: "rxd"
    "append({a,b,c},{d,e},{},{f,g,h},...) =>  {a,b,c,d,e,f,g,h}";
    if ((n = length(args)) > 50)
      return {@this:append(@args[1..n / 2]), @this:append(@args[n / 2 + 1..n])};
    endif
    l = {};
    for a in (args)
      l = {@l, @a};
    endfor
    return l;
  endverb

  verb assoc (this none this) owner: HACKER flags: "rx"
    "assoc(list, target[,index]) returns the first element of `list' whose own index-th element is target.  Index defaults to 1.";
    "returns {} if no such element is found";
    {lst, target, ?indx = 1} = args;
    for t in (lst)
      if (t[indx] == target)
        "... do this test first since it's the most likely to fail; this needs -d";
        if (typeof(t) == list && length(t) >= indx)
          return t;
        endif
      endif
    endfor
    return {};
  endverb

  verb assoc_prefix (this none this) owner: HACKER flags: "rxd"
    "assoc_prefix(list, target[,index]) returns the first element of `list' whose own index-th element has target as a prefix.  Index defaults to 1.";
    {lst, target, ?indx = 1} = args;
    for t in (lst)
      if (typeof(t) == list && (length(t) >= indx && index(t[indx], target) == 1))
        return t;
      endif
    endfor
    return {};
  endverb

  verb check_type (this none this) owner: HACKER flags: "rxd"
    "check_type(list, type)";
    "Make sure all elements of <list> are of a given <type>.";
    "<type> can be either one of LIST, STR, OBJ, NUM, ERR, or a list of same.";
    "return true if all elements check, otherwise 0.";
    typelist = typeof(args[2]) == list ? args[2] | {args[2]};
    for element in (args[1])
      if (!(typeof(element) in typelist))
        return false;
      endif
    endfor
    return true;
  endverb

  verb compress (this none this) owner: HACKER flags: "rxd"
    "compress(list) => list with consecutive repeated elements removed, e.g.,";
    "compress({a,b,b,c,b,b,b,d,d,e}) => {a,b,c,b,d,e}";
    if (l = args[1])
      out = {last = l[1]};
      for x in (listdelete(l, 1))
        if (x != last)
          out = listappend(out, x);
          last = x;
        endif
      endfor
      return out;
    else
      return l;
    endif
  endverb

  verb english_list (this none this) owner: #184 flags: "rxd"
    "Prints the argument (must be a list) as an english list, e.g. {1, 2, 3} is printed as \"1, 2, and 3\", and {1, 2} is printed as \"1 and 2\".";
    "Optional arguments are treated as follows:";
    "  Second argument is the string to use when the empty list is given.  The default is \"nothing\".";
    "  Third argument is the string to use in place of \" and \".  A typical application might be to use \" or \" instead.";
    "  Fourth argument is the string to use instead of a comma (and space).  Gary_Severn's deranged mind actually came up with an application for this.  You can ask him.";
    "  Fifth argument is a string to use after the penultimate element before the \" and \".  The default is to have a comma without a space.";
    {things, ?nothingstr = "nothing", ?andstr = " and ", ?commastr = ", ", ?finalcommastr = ","} = args;
    nthings = length(things);
    nthings == 0 && return nothingstr;
    nthings == 1 && return tostr(things[1]);
    nthings == 2 && return tostr(things[1], andstr, things[2]);
    ret = "";
    for k in [1..nthings - 1]
      if (k == nthings - 1)
        commastr = finalcommastr;
      endif
      ret = tostr(ret, things[k], commastr);
    endfor
    return tostr(ret, andstr, things[nthings]);
  endverb
endobject
