object CONDITION [
  import_export_id -> "condition",
  import_export_hierarchy -> {"rules"}
]
  name: "Conditions"
  parent: ROOT
  owner: HACKER
  readable: true

  method parse owner: HACKER
    "Parse the entire expression into the canonical condition tree, retaining source positions.";
    const {text} = args;
    const tokens = this:_tokens(text, true);
    length(tokens) > 0 || raise(E_INVARG, "Empty condition");
    const {tree, next} = this:_parse_or(tokens, 1, 0);
    next > length(tokens) || raise(E_INVARG, "Unexpected token at character " + tostr(tokens[next]['start]));
    return tree;
  endmethod

  method _tokens owner: HACKER
    "Tokenize quoted literals, names, punctuation, and comparison operators without evaluation. With arithmetic, + * / are tokens of their own.";
    const {text, ?arithmetic = false} = args;
    typeof(text) == TYPE_STR || raise(E_INVARG, "Condition must be text");
    length(text) <= 32768 || raise(E_QUOTA, "Condition exceeds 32768 characters");
    const breaks = arithmetic ? {" ", "\t", "\r", "\n", "(", ")", ",", ":", "=", "!", "<", ">", "+", "*", "/"} | {" ", "\t", "\r", "\n", "(", ")", ",", ":", "=", "!", "<", ">"};
    let tokens = {};
    let pos = 1;
    while (pos <= length(text))
      const start = pos;
      const char = text[pos];
      if (char in {" ", "\t", "\r", "\n"})
        pos = pos + 1;
        continue;
      endif
      if (char == "\"")
        pos = pos + 1;
        while (pos <= length(text) && text[pos] != "\"")
          if (text[pos] == "\\")
            pos = pos + 1;
          endif
          pos = pos + 1;
        endwhile
        pos <= length(text) || raise(E_INVARG, "Unterminated string at character " + tostr(start));
        pos = pos + 1;
      elseif (char in {"{", "["})
        let closing = {char == "{" ? "}" | "]"};
        pos = pos + 1;
        let quoted = false;
        while (pos <= length(text) && length(closing) > 0)
          const current = text[pos];
          if (quoted && current == "\\")
            pos = pos + 1;
          elseif (current == "\"")
            quoted = !quoted;
          elseif (!quoted)
            if (current in {"{", "["})
              closing = {@closing, current == "{" ? "}" | "]"};
            elseif (current in {"}", "]"})
              current == closing[$] || raise(E_INVARG, "Mismatched literal at character " + tostr(pos));
              closing = closing[1..$ - 1];
            endif
          endif
          pos = pos + 1;
        endwhile
        length(closing) == 0 || raise(E_INVARG, "Unterminated literal at character " + tostr(start));
      elseif (char in {"(", ")", ",", ":"} || (arithmetic && char in {"+", "*", "/"}))
        pos = pos + 1;
      elseif (char in {"=", "!", "<", ">"} || (char == "-" && pos < length(text) && text[pos + 1] == ">"))
        pos = pos + 1;
        if (pos <= length(text) && text[start..pos] in {"==", "!=", "<=", ">=", "->"})
          pos = pos + 1;
        endif
      else
        while (pos <= length(text) && !(text[pos] in breaks))
          pos = pos + 1;
        endwhile
      endif
      tokens = {@tokens, ['text -> text[start..pos - 1], 'start -> start, 'end -> pos]};
      length(tokens) <= 4096 || raise(E_QUOTA, "Condition exceeds 4096 tokens");
    endwhile
    return tokens;
  endmethod

  method _expect owner: HACKER
    "Require one token, retaining a source position in syntax errors.";
    const {tokens, pos, expected} = args;
    pos <= length(tokens) || raise(E_INVARG, "Expected " + expected + " at end of condition");
    tokens[pos]['text] == expected || raise(E_INVARG, "Expected " + expected + " at character " + tostr(tokens[pos]['start]));
    return pos + 1;
  endmethod

  method _parse_or owner: HACKER
    "Parse OR below AND in precedence. Parenthesized children retain their own trees.";
    let {tokens, pos, depth} = args;
    const start = pos;
    let {tree, next} = this:_parse_and(tokens, pos, depth);
    pos = next;
    let children = {tree};
    while (pos <= length(tokens) && tokens[pos]['text] == "OR")
      {tree, next} = this:_parse_and(tokens, pos + 1, depth);
      children = {@children, tree};
      pos = next;
    endwhile
    length(children) == 1 && return {children[1], pos};
    return {['kind -> 'any, 'children -> children, 'source -> ['start -> tokens[start]['start], 'end -> tokens[pos - 1]['end]]], pos};
  endmethod

  method _parse_and owner: HACKER
    "Parse a sequence of terms joined by AND.";
    let {tokens, pos, depth} = args;
    const start = pos;
    let {tree, next} = this:_parse_term(tokens, pos, depth);
    pos = next;
    let children = {tree};
    while (pos <= length(tokens) && tokens[pos]['text] == "AND")
      {tree, next} = this:_parse_term(tokens, pos + 1, depth);
      children = {@children, tree};
      pos = next;
    endwhile
    length(children) == 1 && return {children[1], pos};
    return {['kind -> 'all, 'children -> children, 'source -> ['start -> tokens[start]['start], 'end -> tokens[pos - 1]['end]]], pos};
  endmethod

  method _closing owner: HACKER
    "Return the position of the parenthesis that closes the one at pos.";
    const {tokens, pos} = args;
    let nesting = 0;
    for i in [pos..length(tokens)]
      tokens[i]['text] == "(" && (nesting = nesting + 1);
      tokens[i]['text] == ")" && (nesting = nesting - 1);
      nesting == 0 && return i;
    endfor
    raise(E_INVARG, "Expected ) for the ( at character " + tostr(tokens[pos]['start]));
  endmethod

  method _parse_term owner: HACKER
    "Parse a grouped condition, negation, exists or best, a predicate call, or a comparison of values.";
    let {tokens, pos, depth} = args;
    depth <= 16 || raise(E_QUOTA, "Condition nesting exceeds 16 levels");
    pos <= length(tokens) || raise(E_INVARG, "Expected condition at end of input");
    const start = pos;
    const token = tokens[pos]['text];
    const value_words = this:_functions();
    const after_group = token == "(" ? this:_closing(tokens, pos) + 1 | 0;
    const grouped_value = after_group > 0 && after_group <= length(tokens) && tokens[after_group]['text] in {"==", "!=", "<", "<=", ">", ">=", "+", "-", "*", "/"};
    let tree;
    if (token == "(" && !grouped_value)
      const {child, next} = this:_parse_or(tokens, pos + 1, depth + 1);
      return {child, this:_expect(tokens, next, ")")};
    elseif (token == "NOT")
      const {child, next} = this:_parse_term(tokens, pos + 1, depth + 1);
      tree = ['kind -> 'not, 'child -> child];
      pos = next;
    elseif (token == "exists" && pos < length(tokens) && tokens[pos + 1]['text] == "(")
      const {child, next} = this:_parse_or(tokens, pos + 2, depth + 1);
      tree = ['kind -> 'exists, 'child -> child];
      pos = this:_expect(tokens, next, ")");
    elseif (token == "best" && pos < length(tokens) && tokens[pos + 1]['text] == "(")
      const {child, next} = this:_parse_or(tokens, pos + 2, depth + 1);
      pos = this:_expect(tokens, next, ",");
      pos = this:_expect(tokens, pos, "by");
      pos = this:_expect(tokens, pos, ":");
      const {by, after} = this:_parse_value(tokens, pos, depth + 1);
      pos = after;
      let limit = 1;
      if (pos <= length(tokens) && tokens[pos]['text] == ",")
        pos = this:_expect(tokens, pos + 1, "limit");
        pos = this:_expect(tokens, pos, ":");
        pos <= length(tokens) || raise(E_INVARG, "Expected a limit at end of condition");
        limit = `fromliteral(tokens[pos]['text]) ! ANY => 0';
        typeof(limit) == TYPE_INT && limit >= 1 && limit <= 256 || raise(E_INVARG, "best limit must be 1 through 256 at character " + tostr(tokens[pos]['start]));
        pos = pos + 1;
      endif
      tree = ['kind -> 'best, 'child -> child, 'by -> by, 'limit -> limit];
      pos = this:_expect(tokens, pos, ")");
    elseif (token in {"TRUE", "FALSE"} && (pos == length(tokens) || !(tokens[pos + 1]['text] in {"==", "!=", "<", "<=", ">", ">="})))
      tree = ['kind -> token == "TRUE" ? 'all | 'any, 'children -> {}];
      pos = pos + 1;
    elseif (pos < length(tokens) && tokens[pos + 1]['text] == "(" && !(token in value_words) && !(token in {"(", "-"}))
      $behavior_schema:_name(tosym(token), "predicate");
      let relation = 0;
      let arguments_pos = pos + 2;
      if (token == "relation")
        arguments_pos <= length(tokens) || raise(E_INVARG, "Expected a relation reference.");
        relation = this:_value(tokens[arguments_pos]);
        arguments_pos = arguments_pos + 1;
        if (arguments_pos <= length(tokens) && tokens[arguments_pos]['text] != ")")
          arguments_pos = this:_expect(tokens, arguments_pos, ",");
          arguments_pos <= length(tokens) && tokens[arguments_pos]['text] != ")" || raise(E_INVARG, "Expected a field after comma.");
        endif
      endif
      const {arguments, next} = this:_named(tokens, arguments_pos, false, depth);
      pos = next;
      let bind = [];
      if (pos <= length(tokens) && tokens[pos]['text] == "->")
        pos = this:_expect(tokens, pos + 1, "(");
        const {outputs, after} = this:_named(tokens, pos, true, depth);
        bind = outputs;
        pos = after;
      endif
      tree = token == "relation" ? ['kind -> 'relation, 'relation -> relation, 'arguments -> arguments, 'bind -> bind] | ['kind -> 'predicate, 'name -> tosym(token), 'arguments -> arguments, 'bind -> bind];
    else
      const {left, next} = this:_parse_value(tokens, pos, depth + 1);
      pos = next;
      pos <= length(tokens) || raise(E_INVARG, "Expected comparison operator");
      const operators = ["==" -> 'eq, "!=" -> 'ne, "<" -> 'lt, "<=" -> 'le, ">" -> 'gt, ">=" -> 'ge];
      maphaskey(operators, tokens[pos]['text]) || raise(E_INVARG, "Expected comparison at character " + tostr(tokens[pos]['start]));
      const op = operators[tokens[pos]['text]];
      pos = pos + 1;
      pos <= length(tokens) || raise(E_INVARG, "Expected right comparison value");
      const {right, after} = this:_parse_value(tokens, pos, depth + 1);
      tree = ['kind -> 'compare, 'op -> op, 'left -> left, 'right -> right];
      pos = after;
    endif
    tree['source] = ['start -> tokens[start]['start], 'end -> tokens[pos - 1]['end]];
    return {tree, pos};
  endmethod

  method _functions owner: HACKER
    "Words that name value functions rather than predicates.";
    return {"abs", "min", "max", "count"};
  endmethod

  method _parse_value owner: HACKER
    "Parse a value: a sum of products of literals, references, groups, and function calls.";
    let {tokens, pos, depth} = args;
    depth <= 16 || raise(E_QUOTA, "Value nesting exceeds 16 levels");
    let {left, next} = this:_parse_product(tokens, pos, depth);
    pos = next;
    while (pos <= length(tokens) && tokens[pos]['text] in {"+", "-"})
      const op = tokens[pos]['text] == "+" ? 'add | 'sub;
      const {right, after} = this:_parse_product(tokens, pos + 1, depth);
      left = ['kind -> 'arith, 'op -> op, 'left -> left, 'right -> right, 'source -> ['start -> left['source]['start], 'end -> right['source]['end]]];
      pos = after;
    endwhile
    return {left, pos};
  endmethod

  method _parse_product owner: HACKER
    "Parse factors joined by * and /.";
    let {tokens, pos, depth} = args;
    let {left, next} = this:_parse_factor(tokens, pos, depth);
    pos = next;
    while (pos <= length(tokens) && tokens[pos]['text] in {"*", "/"})
      const op = tokens[pos]['text] == "*" ? 'mul | 'div;
      const {right, after} = this:_parse_factor(tokens, pos + 1, depth);
      left = ['kind -> 'arith, 'op -> op, 'left -> left, 'right -> right, 'source -> ['start -> left['source]['start], 'end -> right['source]['end]]];
      pos = after;
    endwhile
    return {left, pos};
  endmethod

  method _parse_factor owner: HACKER
    "Parse a negation, a parenthesized value, a function call, or a single literal or reference.";
    let {tokens, pos, depth} = args;
    depth <= 16 || raise(E_QUOTA, "Value nesting exceeds 16 levels");
    pos <= length(tokens) || raise(E_INVARG, "Expected a value at end of condition");
    const token = tokens[pos];
    const text = token['text];
    if (text == "-")
      const {operand, next} = this:_parse_factor(tokens, pos + 1, depth + 1);
      return {['kind -> 'neg, 'value -> operand, 'source -> ['start -> token['start], 'end -> operand['source]['end]]], next};
    elseif (text == "(")
      const {inner, next} = this:_parse_value(tokens, pos + 1, depth + 1);
      return {inner, this:_expect(tokens, next, ")")};
    elseif (text in this:_functions() && pos < length(tokens) && tokens[pos + 1]['text] == "(")
      if (text == "count")
        const {child, next} = this:_parse_or(tokens, pos + 2, depth + 1);
        const after = this:_expect(tokens, next, ")");
        return {['kind -> 'count, 'condition -> child, 'source -> ['start -> token['start], 'end -> tokens[after - 1]['end]]], after};
      endif
      let values = {};
      let at = pos + 2;
      while (true)
        const {value, next} = this:_parse_value(tokens, at, depth + 1);
        values = {@values, value};
        at = next;
        at <= length(tokens) || raise(E_INVARG, "Expected ) after " + text + " arguments");
        if (tokens[at]['text] != ",")
          break;
        endif
        at = at + 1;
      endwhile
      at = this:_expect(tokens, at, ")");
      text != "abs" || length(values) == 1 || raise(E_INVARG, "abs takes one value at character " + tostr(token['start]));
      text == "abs" || length(values) >= 2 || raise(E_INVARG, text + " takes two or more values at character " + tostr(token['start]));
      return {['kind -> 'call, 'name -> tosym(text), 'arguments -> values, 'source -> ['start -> token['start], 'end -> tokens[at - 1]['end]]], at};
    endif
    return {this:_value(token), pos + 1};
  endmethod

  method _named owner: HACKER
    "Parse named value arguments or output bindings through the closing parenthesis.";
    let {tokens, pos, outputs, ?depth = 0} = args;
    let fields = [];
    while (pos <= length(tokens) && tokens[pos]['text] != ")")
      const name = tosym(tokens[pos]['text]);
      $behavior_schema:_name(name, "argument");
      !maphaskey(fields, name) || raise(E_INVARG, "Repeated argument " + tostr(name));
      pos = this:_expect(tokens, pos + 1, ":");
      pos <= length(tokens) || raise(E_INVARG, "Expected argument value");
      if (outputs)
        const binding = tosym(tokens[pos]['text]);
        $behavior_schema:_name(binding, "output binding");
        fields[name] = binding;
        pos = pos + 1;
      else
        const {value, next} = this:_parse_value(tokens, pos, depth + 1);
        fields[name] = value;
        pos = next;
      endif
      if (pos <= length(tokens) && tokens[pos]['text] == ",")
        pos = pos + 1;
        pos <= length(tokens) && tokens[pos]['text] != ")" || raise(E_INVARG, "Expected argument after comma");
      else
        break;
      endif
    endwhile
    return {fields, this:_expect(tokens, pos, ")")};
  endmethod

  method _value owner: HACKER
    "Resolve literal syntax without object matching, or identify an explicit value namespace. A leading - negates a reference.";
    const {token} = args;
    const text = token['text];
    if (length(text) > 1 && text[1] == "-" && index(text, ".") > 2 && text[2..index(text, ".") - 1] in {"input", "parameter", "state", "binding"})
      const operand = this:_value(['text -> text[2..$], 'start -> token['start] + 1, 'end -> token['end]]);
      return ['kind -> 'neg, 'value -> operand, 'source -> ['start -> token['start], 'end -> token['end]]];
    endif
    const dot = index(text, ".");
    let value;
    if (dot > 1 && text[1..dot - 1] in {"input", "parameter", "state", "binding"})
      const name = tosym(text[dot + 1..$]);
      $behavior_schema:_name(name, "value");
      value = ['kind -> tosym(text[1..dot - 1]), 'name -> name];
    else
      try
        value = ['kind -> 'literal, 'value -> fromliteral(text)];
      except error (E_INVARG, E_TYPE)
        raise(E_INVARG, "Invalid value at character " + tostr(token['start]));
      endtry
    endif
    value['source] = ['start -> token['start], 'end -> token['end]];
    return value;
  endmethod

  method relation_target owner: HACKER
    "Resolve a fixed relation object or an explicit reaction setting. Event values cannot choose storage.";
    const {expression, parameters} = args;
    if (expression['kind] == 'literal)
      return expression['value];
    endif
    expression['kind] == 'parameter || raise(E_INVARG, "Use a relation object or a reaction setting.");
    maphaskey(parameters, expression['name]) || raise(E_INVARG, "Missing relation setting: " + tostr(expression['name]));
    return parameters[expression['name]];
  endmethod

  method prepare_relations owner: ARCH_WIZARD
    "Capture required field types when authoring; check existing requirements when installing or retargeting.";
    set_task_perms(caller_perms());
    let {tree, ?parameters = [], ?depth = 0} = args;
    depth <= 16 || raise(E_QUOTA, "Condition nesting exceeds 16 levels.");
    const kind = tree['kind];
    if (kind in {'all, 'any})
      tree['children] = { this:prepare_relations(child, parameters, depth + 1) for child in (tree['children]) };
    elseif (kind in {'not, 'exists})
      tree['child] = this:prepare_relations(tree['child], parameters, depth + 1);
    elseif (kind == 'best)
      tree['child] = this:prepare_relations(tree['child], parameters, depth + 1);
      tree['by] = this:_prepare_value(tree['by], parameters, depth + 1);
    elseif (kind == 'compare)
      tree['left] = this:_prepare_value(tree['left], parameters, depth + 1);
      tree['right] = this:_prepare_value(tree['right], parameters, depth + 1);
    elseif (kind in {'predicate, 'relation})
      for name in (mapkeys(tree['arguments]))
        tree['arguments][name] = this:_prepare_value(tree['arguments][name], parameters, depth + 1);
      endfor
      if (kind == 'relation)
        const relation = this:relation_target(tree['relation], parameters);
        const schema = $relation:schema(relation, `tree['fields] ! E_RANGE => 0');
        tree['fields] = schema['types];
        for field in (mapkeys($relation.meta_fields))
          if (maphaskey(tree['arguments], field) || maphaskey(tree['bind], field))
            tree['fields][field] = $relation.meta_fields[field];
          endif
        endfor
      endif
    endif
    return tree;
  endmethod

  method _prepare_value owner: ARCH_WIZARD
    "Prepare the relations in conditions that a counted value holds.";
    set_task_perms(caller_perms());
    let {value, parameters, depth} = args;
    depth <= 16 || raise(E_QUOTA, "Condition nesting exceeds 16 levels.");
    const kind = value['kind];
    if (kind == 'count)
      value['condition] = this:prepare_relations(value['condition], parameters, depth + 1);
    elseif (kind == 'arith)
      value['left] = this:_prepare_value(value['left], parameters, depth + 1);
      value['right] = this:_prepare_value(value['right], parameters, depth + 1);
    elseif (kind == 'neg)
      value['value] = this:_prepare_value(value['value], parameters, depth + 1);
    elseif (kind == 'call)
      value['arguments] = { this:_prepare_value(argument, parameters, depth + 1) for argument in (value['arguments]) };
    endif
    return value;
  endmethod

  method print owner: HACKER
    "Print an unambiguous editable expression. Source positions are recomputed when reparsed.";
    const {tree} = args;
    const kind = tree['kind];
    if (kind in {'all, 'any})
      length(tree['children]) == 0 && return kind == 'all ? "TRUE" | "FALSE";
      const children = { this:print(child) for child in (tree['children]) };
      return "(" + children:join(kind == 'all ? " AND " | " OR ") + ")";
    elseif (kind == 'not)
      return "NOT (" + this:print(tree['child]) + ")";
    elseif (kind == 'exists)
      return "exists(" + this:print(tree['child]) + ")";
    elseif (kind == 'best)
      const limit = tree['limit] == 1 ? "" | ", limit: " + tostr(tree['limit]);
      return "best(" + this:print(tree['child]) + ", by: " + this:print_value(tree['by]) + limit + ")";
    elseif (kind == 'compare)
      const operators = ['eq -> "==", 'ne -> "!=", 'lt -> "<", 'le -> "<=", 'gt -> ">", 'ge -> ">="];
      return this:print_value(tree['left]) + " " + operators[tree['op]] + " " + this:print_value(tree['right]);
    elseif (kind in {'predicate, 'relation})
      const arguments = { tostr(name) + ": " + this:print_value(tree['arguments][name]) for name in (mapkeys(tree['arguments])) };
      const prefix = kind == 'relation ? "relation(" + this:print_value(tree['relation]) + (length(arguments) > 0 ? ", " | "") | tostr(tree['name]) + "(";
      let text = prefix + arguments:join(", ") + ")";
      if (length(tree['bind]) > 0)
        const outputs = { tostr(name) + ": " + tostr(tree['bind][name]) for name in (mapkeys(tree['bind])) };
        text = text + " -> (" + outputs:join(", ") + ")";
      endif
      return text;
    endif
    raise(E_INVARG, "Unknown condition kind");
  endmethod

  method print_value owner: HACKER
    "Print exact literal values, namespace-qualified references, and computed values, grouping every operation.";
    const {value} = args;
    const kind = value['kind];
    if (kind == 'literal)
      const text = toliteral(value['value]);
      equal(fromliteral(text), value['value]) || raise(E_INVARG, "Literal has no exact text representation");
      return text;
    elseif (kind == 'arith)
      const operators = ['add -> " + ", 'sub -> " - ", 'mul -> " * ", 'div -> " / "];
      return "(" + this:print_value(value['left]) + operators[value['op]] + this:print_value(value['right]) + ")";
    elseif (kind == 'neg)
      return "- " + this:print_value(value['value]);
    elseif (kind == 'call)
      return tostr(value['name]) + "(" + { this:print_value(argument) for argument in (value['arguments]) }:join(", ") + ")";
    elseif (kind == 'count)
      return "count(" + this:print(value['condition]) + ")";
    endif
    return tostr(kind) + "." + tostr(value['name]);
  endmethod

  method resolve owner: HACKER
    "Read a literal, one declared value, or a computed value from the supplied environment. No world callbacks: counted conditions need an evaluation.";
    const {value, environment} = args;
    const kind = value['kind];
    kind == 'literal && return value['value];
    kind == 'count && raise(E_INVARG, "count() is evaluated only inside conditions");
    kind in {'arith, 'neg, 'call} && return this:_compute(value, {operand} => this:resolve(operand, environment));
    return environment[kind][value['name]];
  endmethod

  method _compute owner: HACKER
    "Apply one arithmetic operation or function to operands read through the given reader.";
    const {value, reader} = args;
    const kind = value['kind];
    if (kind == 'neg)
      return -reader(value['value]);
    elseif (kind == 'arith)
      const left = reader(value['left]);
      const right = reader(value['right]);
      const op = value['op];
      op == 'add && return left + right;
      op == 'sub && return left - right;
      op == 'mul && return left * right;
      return left / right;
    endif
    const values = { reader(argument) for argument in (value['arguments]) };
    value['name] == 'abs && return abs(values[1]);
    return value['name] == 'min ? min(@values) | max(@values);
  endmethod

  method references owner: HACKER
    "Collect syntax references. Literal values never become variable references.";
    const {tree} = args;
    let result = ['input -> {}, 'parameter -> {}, 'state -> {}, 'binding -> {}];
    let pending = {tree};
    while (length(pending) > 0)
      const node = pending[$];
      pending = pending[1..$ - 1];
      const kind = node['kind];
      if (kind in {'input, 'parameter, 'state, 'binding})
        result[kind] = setadd(result[kind], node['name]);
      elseif (kind in {'all, 'any})
        pending = {@pending, @node['children]};
      elseif (kind in {'not, 'exists})
        pending = {@pending, node['child]};
      elseif (kind == 'best)
        pending = {@pending, node['child], node['by]};
      elseif (kind in {'compare, 'arith})
        pending = {@pending, node['left], node['right]};
      elseif (kind == 'neg)
        pending = {@pending, node['value]};
      elseif (kind == 'call)
        pending = {@pending, @node['arguments]};
      elseif (kind == 'count)
        pending = {@pending, node['condition]};
      elseif (kind in {'predicate, 'relation})
        pending = {@pending, @mapvalues(node['arguments])};
        kind == 'relation && (pending = {@pending, node['relation]});
      endif
    endwhile
    return result;
  endmethod

  method evaluate owner: ARCH_WIZARD
    "Evaluate a validated condition with an explicit predicate callback under caller authority. With explain, the result carries a trace of what held and what failed.";
    set_task_perms(caller_perms());
    const {tree, environment, provider, ?limit = 256, ?explain = false} = args;
    typeof(limit) == TYPE_INT && limit > 0 && limit <= 256 || raise(E_INVARG, "Invalid condition limit");
    let scope = environment;
    explain && (scope['explain] = true);
    return this:_evaluate(tree, scope, provider, limit, 0);
  endmethod

  method _evaluate owner: ARCH_WIZARD
    "Compose bounded binding sets. Incomplete searches never establish absence.";
    set_task_perms(caller_perms());
    const {tree, environment, provider, limit, depth} = args;
    depth <= 16 || raise(E_QUOTA, "Condition nesting exceeds 16 levels");
    const kind = tree['kind];
    const initial = environment['binding];
    const explain = `environment['explain] ! E_RANGE => false';
    let result;
    let traces = {};
    if (kind == 'not)
      const inner = this:_evaluate(tree['child], environment, provider, limit, depth + 1);
      explain && (traces = {inner['trace]});
      if (length(inner['bindings]) > 0)
        result = ['bindings -> {}, 'complete -> true];
      else
        inner['complete] || raise(E_QUOTA, "Negation requires a complete search");
        result = ['bindings -> {initial}, 'complete -> true];
      endif
    elseif (kind == 'exists)
      const inner = this:_evaluate(tree['child], environment, provider, limit, depth + 1);
      explain && (traces = {inner['trace]});
      const found = length(inner['bindings]) > 0;
      result = ['bindings -> found ? {initial} | {}, 'complete -> found || inner['complete]];
    elseif (kind == 'best)
      const inner = this:_evaluate(tree['child], environment, provider, limit, depth + 1);
      explain && (traces = {inner['trace]});
      const rows = inner['bindings];
      let keys = {};
      if (tree['by]['kind] == 'binding)
        keys = { row[tree['by]['name]] for row in (rows) };
      else
        for row in (rows)
          let scope = environment;
          scope['binding] = row;
          keys = {@keys, this:_evaluate_value(tree['by], scope, provider, limit, depth + 1)};
        endfor
      endif
      const ordered = length(rows) > 1 ? sort(rows, keys) | rows;
      result = ['bindings -> ordered[1..min(length(ordered), tree['limit])], 'complete -> inner['complete]];
    elseif (kind == 'compare)
      const left = this:_evaluate_value(tree['left], environment, provider, limit, depth + 1);
      const right = this:_evaluate_value(tree['right], environment, provider, limit, depth + 1);
      result = ['bindings -> this:_compare(tree['op], left, right) ? {initial} | {}, 'complete -> true];
    elseif (kind in {'predicate, 'relation})
      let arguments = [];
      for name in (mapkeys(tree['arguments]))
        arguments[name] = this:_evaluate_value(tree['arguments][name], environment, provider, limit, depth + 1);
      endfor
      const found = this:_query(tree, arguments, environment, provider, limit);
      const outputs = mapkeys(tree['bind]);
      const pattern = { {'var, tree['bind][output]} for output in (outputs) };
      const rows = { { row[field] for field in (outputs) } for row in (found['rows]) };
      const bindings = term_match(pattern, rows, initial, ['case_sensitive -> true, 'dedupe -> true, 'max_solutions -> limit + 1]);
      result = ['bindings -> bindings[1..min(length(bindings), limit)], 'complete -> found['complete] && length(bindings) <= limit];
    else
      kind in {'all, 'any} || raise(E_INVARG, "Unknown condition kind");
      let bindings = kind == 'all ? {initial} | {};
      let complete = true;
      for child in (tree['children])
        let child_trace = 0;
        if (kind == 'all && !explain && child['kind] in {'predicate, 'relation} && length(this:references(child)['binding]) == 0)
          const {rows, done} = this:_join(child, bindings, environment, provider, limit, depth + 1);
          bindings = rows;
          complete = complete && done;
          continue;
        elseif (kind == 'all && !explain && child['kind] == 'compare)
          bindings = this:_filter(child, bindings, environment, provider, limit, depth + 1);
          continue;
        endif
        let found = kind == 'all ? {} | bindings;
        for candidate in (kind == 'all ? bindings | {initial})
          let scope = environment;
          scope['binding] = candidate;
          const inner = this:_evaluate(child, scope, provider, limit, depth + 1);
          explain && (child_trace = this:_merge_trace(child_trace, inner['trace]));
          complete = complete && inner['complete];
          found = {@found, @inner['bindings]};
        endfor
        explain && (traces = {@traces, child_trace ? child_trace | this:_trace(child, 0, {}, false)});
        const distinct = this:_distinct(found, limit);
        bindings = distinct['rows];
        complete = complete && distinct['complete];
      endfor
      result = ['bindings -> bindings, 'complete -> complete];
    endif
    explain && (result['trace] = this:_trace(tree, length(result['bindings]), traces, result['complete]));
    return result;
  endmethod

  method _evaluate_value owner: ARCH_WIZARD
    "Evaluate one value inside a condition: computed values and counted conditions included.";
    set_task_perms(caller_perms());
    const {value, environment, provider, limit, depth} = args;
    const kind = value['kind];
    if (kind == 'count)
      const inner = this:_evaluate(value['condition], environment, provider, limit, depth + 1);
      inner['complete] || raise(E_QUOTA, "count() requires a complete search");
      return length(inner['bindings]);
    elseif (kind in {'arith, 'neg, 'call})
      return this:_compute(value, {operand} => this:_evaluate_value(operand, environment, provider, limit, depth + 1));
    endif
    return this:resolve(value, environment);
  endmethod

  method _compare owner: HACKER
    "Compare two values as conditions do: exact equality, strings ordered by strcmp.";
    const {op, left, right} = args;
    if (op in {'eq, 'ne})
      return op == 'eq ? equal(left, right) | !equal(left, right);
    endif
    let first = left;
    let second = right;
    if (typeof(left) == TYPE_STR && typeof(right) == TYPE_STR)
      first = strcmp(left, right);
      second = 0;
    endif
    op == 'lt && return first < second;
    op == 'le && return first <= second;
    op == 'gt && return first > second;
    return first >= second;
  endmethod

  method _query owner: ARCH_WIZARD
    "Answer one predicate or relation with argument values. The one place a subclass changes how facts are found.";
    set_task_perms(caller_perms());
    const {tree, arguments, environment, provider, limit} = args;
    if (tree['kind] == 'relation)
      return $relation:query_rows(this:resolve(tree['relation], environment), tree['fields], arguments, limit);
    endif
    return provider(tree['name], arguments, limit);
  endmethod

  method _trace owner: HACKER
    "One node of an explanation: the condition as written, how many matches it gave, whether its search was complete, and its parts.";
    const {tree, matches, children, complete} = args;
    return ['condition -> this:print(tree), 'matches -> matches, 'complete -> complete, 'evaluations -> 1, 'children -> children];
  endmethod

  method _merge_trace owner: HACKER
    "Combine the traces of one condition evaluated for several candidate bindings.";
    const {total, trace} = args;
    total || return trace;
    let merged = total;
    merged['matches] = total['matches] + trace['matches];
    merged['evaluations] = total['evaluations] + trace['evaluations];
    merged['complete] = total['complete] && trace['complete];
    if (length(total['children]) == length(trace['children]))
      merged['children] = { this:_merge_trace(total['children][i], trace['children][i]) for i in [1..length(trace['children])] };
    endif
    return merged;
  endmethod

  method _distinct owner: HACKER
    "Keep the first of equal binding maps, comparing string case, up to the limit.";
    const {rows, limit} = args;
    length(rows) <= 1 && return ['rows -> rows, 'complete -> true];
    const kept = term_match({'var, 'row}, rows, [], ['case_sensitive -> true, 'dedupe -> true, 'max_solutions -> limit, 'max_steps -> length(rows), 'return -> 'detail]);
    return ['rows -> { match['row] for match in (kept['rows]) }, 'complete -> kept['complete]];
  endmethod

  method _join owner: ARCH_WIZARD
    "Answer a predicate whose arguments use no bindings once, and match its rows against every binding in one call.";
    set_task_perms(caller_perms());
    const {tree, bindings, environment, provider, limit, depth} = args;
    length(bindings) == 0 && return {{}, true};
    let arguments = [];
    for name in (mapkeys(tree['arguments]))
      arguments[name] = this:_evaluate_value(tree['arguments][name], environment, provider, limit, depth);
    endfor
    const found = this:_query(tree, arguments, environment, provider, limit);
    const outputs = mapkeys(tree['bind]);
    const pattern = { {'var, tree['bind][output]} for output in (outputs) };
    const rows = { { row[field] for field in (outputs) } for row in (found['rows]) };
    length(rows) == 0 && return {{}, found['complete]};
    const matched = term_match(pattern, rows, bindings, ['case_sensitive -> true, 'dedupe -> true, 'max_solutions -> limit, 'max_steps -> length(rows) * length(bindings), 'return -> 'detail]);
    return {matched['rows], found['complete] && matched['complete]};
  endmethod

  method _filter owner: ARCH_WIZARD
    "Keep the bindings for which a comparison holds, reading plain values directly.";
    set_task_perms(caller_perms());
    const {tree, bindings, environment, provider, limit, depth} = args;
    const plain = {'literal, 'input, 'parameter, 'state, 'binding};
    const left = tree['left];
    const right = tree['right];
    const left_plain = left['kind] in plain;
    const right_plain = right['kind] in plain;
    let kept = {};
    for row in (bindings)
      let scope = environment;
      scope['binding] = row;
      const a = left_plain ? this:resolve(left, scope) | this:_evaluate_value(left, scope, provider, limit, depth);
      const b = right_plain ? this:resolve(right, scope) | this:_evaluate_value(right, scope, provider, limit, depth);
      this:_compare(tree['op], a, b) && (kept = {@kept, row});
    endfor
    return kept;
  endmethod
  method _test_env owner: HACKER
    "An environment with the given inputs and nothing else.";
    const {?inputs = []} = args;
    return ['input -> inputs, 'parameter -> [], 'state -> [], 'binding -> []];
  endmethod

  method _test_holds owner: HACKER
    "Whether a condition text holds for the inputs, with a provider that has no predicates.";
    const {text, inputs} = args;
    const none = {name, values, limit} => raise(E_INVARG, "no predicates here");
    return length(this:evaluate(this:parse(text), this:_test_env(inputs), none)['bindings]) > 0;
  endmethod

  method test_values_compute owner: HACKER
    "Arithmetic, grouping, negation and functions compute as MOO does, and print back to the same tree.";
    const inputs = ['A -> 3, 'B -> 4, 'F -> 1.5];
    for text in ({"input.A + 2 * input.B == 11", "(input.A + 1) * 2 == 8", "input.B - input.A == 1", "input.B / 2 == 2", "abs(input.A - input.B) == 1", "min(input.A, input.B, 9) == 3", "max(input.A, input.B) == 4", "-input.A < 0", "- (input.A - input.B) == 1", "input.F * 2.0 == 3.0"})
      this:_test_holds(text, inputs) || raise(E_ASSERT, "Expected to hold: " + text);
      const tree = this:parse(text);
      const printed = this:print(tree);
      this:print(this:parse(printed)) == printed || raise(E_ASSERT, "Printing is not stable for " + text + ": " + printed);
    endfor
    this:_test_holds("input.A + 1 > 9", inputs) && raise(E_ASSERT, "A false comparison held");
    return true;
  endmethod

  method test_count_exists_and_best owner: HACKER
    "count and exists read a sub-condition's matches; best keeps the lowest by its value.";
    const rows = {['thing -> #1, 'score -> 5], ['thing -> #2, 'score -> 2], ['thing -> #3, 'score -> 9]};
    const near = {name, values, limit} => ['rows -> rows, 'complete -> true];
    const env = this:_test_env(['P -> #0]);
    const holds = {text} => length(this:evaluate(this:parse(text), env, near)['bindings]) > 0;
    holds("count(near(place: input.P) -> (thing: t, score: s)) == 3") || raise(E_ASSERT, "count");
    holds("count(near(place: input.P) -> (thing: t, score: s) AND binding.s > 4) == 2") || raise(E_ASSERT, "count of a conjunction");
    const found = this:evaluate(this:parse("exists(near(place: input.P) -> (thing: t, score: s))"), env, near);
    found['bindings] == {[]} || raise(E_ASSERT, "exists exposed bindings: " + toliteral(found['bindings]));
    const lowest = this:evaluate(this:parse("best(near(place: input.P) -> (thing: t, score: s), by: binding.s, limit: 2)"), env, near)['bindings];
    { row['t] for row in (lowest) } == {#2, #1} || raise(E_ASSERT, "best lowest: " + toliteral(lowest));
    const highest = this:evaluate(this:parse("best(near(place: input.P) -> (thing: t, score: s), by: -binding.s)"), env, near)['bindings];
    { row['t] for row in (highest) } == {#3} || raise(E_ASSERT, "best highest: " + toliteral(highest));
    return true;
  endmethod

  method test_incomplete_searches_never_prove_absence owner: HACKER
    "count over a cut-off search is an error; exists with no match there is incomplete; best keeps what it found, marked incomplete.";
    const cut = {name, values, limit} => ['rows -> {['thing -> #1, 'score -> 1]}, 'complete -> false];
    const nothing = {name, values, limit} => ['rows -> {}, 'complete -> false];
    const env = this:_test_env(['P -> #0]);
    try
      this:evaluate(this:parse("count(near(place: input.P) -> (thing: t, score: s)) > 0"), env, cut);
      raise(E_ASSERT, "count over an incomplete search succeeded");
    except error (E_QUOTA)
    endtry
    const absent = this:evaluate(this:parse("exists(near(place: input.P) -> (thing: t, score: s))"), env, nothing);
    absent['bindings] == {} && !absent['complete] || raise(E_ASSERT, "exists over an incomplete empty search: " + toliteral(absent));
    const best = this:evaluate(this:parse("best(near(place: input.P) -> (thing: t, score: s), by: binding.s)"), env, cut);
    length(best['bindings]) == 1 && !best['complete] || raise(E_ASSERT, "best over an incomplete search: " + toliteral(best));
    return true;
  endmethod

  method test_values_are_typed owner: HACKER
    "Validation types computed values, keeps count inside conditions, and orders best by numbers or strings.";
    const predicates = ['near -> ['description -> "Things near a place.", 'inputs -> ['place -> 'object], 'outputs -> ['thing -> 'object, 'score -> 'integer]]];
    const scope = ['input -> ['P -> 'object, 'A -> 'integer, 'F -> 'float], 'parameter -> [], 'state -> [], 'binding -> []];
    const check = {text} => $behavior_schema:condition(this:parse(text), scope, predicates);
    check("input.A + 1 > 2");
    check("count(near(place: input.P) -> (thing: t, score: s)) < 3");
    check("best(near(place: input.P) -> (thing: t, score: s), by: binding.s * 2)")['bindings]['t] == 'object || raise(E_ASSERT, "best keeps its child's bindings");
    for text in ({"input.A + input.F > 1", "input.P + 1 > 2", "best(near(place: input.P) -> (thing: t, score: s), by: binding.t)", "abs(input.A, input.A) > 1"})
      try
        check(text);
        raise(E_ASSERT, "Accepted: " + text);
      except error (E_INVARG)
      endtry
    endfor
    try
      $behavior_schema:expression(this:parse("count(near(place: input.P) -> (thing: t, score: s)) > 0")['left], scope);
      raise(E_ASSERT, "count accepted outside a condition");
    except error (E_INVARG)
    endtry
    return true;
  endmethod

  method test_explanations_show_what_failed owner: HACKER
    "An explained evaluation reports each part's matches, so a failed conjunction shows which part failed.";
    const rows = {['thing -> #1, 'score -> 5], ['thing -> #2, 'score -> 2]};
    const near = {name, values, limit} => ['rows -> rows, 'complete -> true];
    const result = this:evaluate(this:parse("near(place: input.P) -> (thing: t, score: s) AND binding.s > 9"), this:_test_env(['P -> #0]), near, 256, true);
    const trace = result['trace];
    trace['matches] == 0 || raise(E_ASSERT, "the conjunction matched");
    length(trace['children]) == 2 || raise(E_ASSERT, "expected two parts: " + toliteral(trace));
    {trace['children][1]['matches], trace['children][2]['matches], trace['children][2]['evaluations]} == {2, 0, 2} || raise(E_ASSERT, "part counts: " + toliteral(trace['children]));
    trace['children][2]['condition] == "binding.s > 9" || raise(E_ASSERT, "condition text: " + toliteral(trace['children][2]['condition]));
    "Without explain there is no trace.";
    !maphaskey(this:evaluate(this:parse("input.P == #0"), this:_test_env(['P -> #0]), near), 'trace) || raise(E_ASSERT, "an unexplained evaluation carried a trace");
    return true;
  endmethod
endobject
