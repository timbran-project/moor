object PROG
    name: "Generic Programmer"
    parent: BUILDER
    owner: WIZ
    fertile: true
    readable: true

    verb eval (any any any) owner: ARCH_WIZARD flags: "rxd"
        set_task_perms(player);
        answer = eval("return " + argstr + ";");
        result_event = None;
        if (answer[1])
          result_event = $event:mk_eval_result(player, false, false, false, "=> ", toliteral(answer[2]));
        else
          result_event = $event:mk_eval_error(player, false, false, false, false, $block:mk(@answer[2]));
        endif
        player:tell(result_event);
    endverb
endobject
