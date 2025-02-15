object PROGRAMMER
    name: "Generic Programmer"
    parent: BUILDER
    owner: WIZARD
    fertile: true
    readable: true

    verb eval (any any any) owner: ARCH_WIZARD flags: "d"
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
