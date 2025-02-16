object PROGRAMMER
    name: "Generic Programmer"
    parent: BUILDER
    owner: WIZARD
    fertile: true
    readable: true

    verb eval (any any any) owner: ARCH_WIZARD flags: "rd"
        set_task_perms(player);
        answer = eval("return " + argstr + ";");
        if (answer[1])
          let result_event = $event:mk_eval_result(player, false, false, false, "=> ", toliteral(answer[2]));
	  player:tell(result_event);
        else
          "todo: multi-line events...";
          for line in (answer[2])
            notify(player, line);
          endfor
        endif
    endverb
endobject
