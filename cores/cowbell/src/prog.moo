object PROG
    name: "Generic Programmer"
    parent: BUILDER
    owner: WIZ
    fertile: true
    readable: true

    verb eval (any any any) owner: ARCH_WIZARD flags: "rd"
        set_task_perms(player);
        answer = eval("return " + argstr + ";");
        if (answer[1])
          let result_event = $event:mk_eval_result(player, false, false, false, "=> ", toliteral(answer[2]));
          player:tell(result_event);
        else
          let error_event = $event:mk_eval_error(player, false, false, false, false, $block:mk(@answer[2]));
          player:tell(error_event);
        endif
    endverb
endobject
