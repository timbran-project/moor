object WIZ
  name: "Generic Wizard"
  parent: PROG
  location: FIRST_ROOM
  owner: ARCH_WIZARD

  property test (owner: WIZ, flags: "r") = {};

  override description = "Generic wizard, parent of all wizards";
  override import_export_id = "wiz";

  verb counter_summary (this none this) owner: HACKER flags: "rxd"
    {before, after} = args;
    result = [];
    for value, key in (before)
      {bcnt, btotal} = value;
      {acnt, atotal} = after[key];
      {cnt, total} = {acnt - bcnt, atotal - btotal};
      if (cnt == 0)
        continue;
      endif
      {avg, cnt} = {total / 1000.0 / cnt, total};
      result[key] = {avg, cnt};
    endfor
    return result;
  endverb

  verb "@commit-bench" (none none none) owner: WIZ flags: "rxd"
    player:tell("Beginning, 100 sequential transactions, writing 100x100 items...");
    before_cnt = db_counters();
    start = ftime();
    this.test = {};
    for x in [1..100]
      for y in [1..100]
        this.test = {@this.test, {x, y}};
      endfor
      commit();
    endfor
    end = ftime();
    after_cnt = db_counters();
    cnt_summary = this:counter_summary(before_cnt, after_cnt);
    for value, key in (cnt_summary)
      player:tell(tostr(key) + " => " + tostr(value[1]) + "\u03BCs mean " + tostr(value[2] / 1000.0) + "ms total");
    endfor
    player:tell("Took " + tostr(end - start) + "s to write " + tostr(length(this.test)) + " tuples in property in 100 transactions");
    this.test = {};
  endverb
endobject