object ROOM
    name: "The First Room"
    parent: ROOT
    owner: WIZARD

    verb eval (any any any) owner: WIZARD flags: "d"
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
