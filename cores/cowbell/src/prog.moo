object PROG
  name: "Generic Programmer"
  parent: BUILDER
  location: FIRST_ROOM
  owner: WIZ
  fertile: true
  readable: true

  verb eval (any any any) owner: ARCH_WIZARD flags: "rxd"
    set_task_perms(player);
    answer = eval("return " + argstr + ";");
    if (answer[1])
      result_event = $event:mk_eval_result(player, "=> ", toliteral(answer[2]));
    else
      result_event = $event:mk_eval_error(player, $block:mk(@answer[2]));
    endif
    player:tell(result_event);
  endverb
endobject