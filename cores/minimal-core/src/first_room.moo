object FIRST_ROOM
  name: "The First Room"
  parent: ROOT
  owner: WIZARD

  override import_export_id = "first_room";

  verb eval (any any any) owner: WIZARD flags: "rd"
    set_task_perms(player);
    answer = eval("return " + argstr + ";");
    if (answer[1])
      notify(player, tostr("=> ", toliteral(answer[2])));
    else
      for line in (answer[2])
        notify(player, line);
      endfor
    endif
  endverb
endobject
