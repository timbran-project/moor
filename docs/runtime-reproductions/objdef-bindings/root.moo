object #0
  name: "root"
  owner: #0

  method probe owner: #0
    "Return a sum from explicit local bindings.";
    const fixed = 1;
    let changing = 2;
    changing = changing + 1;
    return fixed + changing;
  endmethod
endobject
