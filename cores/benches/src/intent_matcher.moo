object INTENT_MATCHER [
  import_export_id -> "intent_matcher"
]
  name: "Intent Matcher"
  parent: ROOT
  owner: ARCH_WIZARD
  readable: true

  property intent_word_weight (owner: ARCH_WIZARD, flags: "r") = 0.65;
  property intent_trigram_weight (owner: ARCH_WIZARD, flags: "r") = 0.35;
  property synonym_index (owner: ARCH_WIZARD, flags: "rw") = [];

  property domain_synonyms (owner: ARCH_WIZARD, flags: "r") = [
    "buy" -> {"buy", "purchase", "acquire", "order", "get", "grab"},
    "price" -> {"price", "cost", "worth", "value", "charge", "rate"},
    "sell" -> {"sell", "vend", "trade"},
    "item" -> {"item", "thing", "object", "article", "ware"},
    "greet" -> {"greet", "hello", "hi", "hey"},
    "thanks" -> {"thanks", "gratitude", "obliged"},
    "farewell" -> {"farewell", "goodbye", "bye"},
    "identity" -> {"identity", "name", "self"},
    "help" -> {"help", "assist", "aid", "guide"},
    "browse" -> {"browse", "show", "view", "display"},
    "confirm" -> {"confirm", "yes", "yeah", "yep", "sure"},
    "decline" -> {"decline", "no", "nope", "refuse"}
  ];

  property intent_profiles (owner: ARCH_WIZARD, flags: "r") = [
    "buy" -> ["speech_act" -> "request", "topic" -> "commerce", "phrases" -> {"i would like to buy a sword", "give me two health potions", "i want to purchase that", "sell me a shield", "let me buy some food"}],
    "sell" -> ["speech_act" -> "request", "topic" -> "commerce", "phrases" -> {"i want to sell this", "can you buy my old dagger", "i would like to sell some herbs"}],
    "price" -> ["speech_act" -> "query", "topic" -> "commerce", "phrases" -> {"how much does this cost", "what is the price", "how much for the potion", "what do you charge"}],
    "browse" -> ["speech_act" -> "query", "topic" -> "commerce", "phrases" -> {"what do you have for sale", "show me your wares", "what are you selling"}],
    "greet" -> ["speech_act" -> "request", "topic" -> "social", "phrases" -> {"hello there", "hi", "greetings", "good day"}],
    "farewell" -> ["speech_act" -> "request", "topic" -> "social", "phrases" -> {"goodbye", "farewell", "i have to go", "see you later"}],
    "identity" -> ["speech_act" -> "query", "topic" -> "identity", "phrases" -> {"who are you", "what is your name", "introduce yourself", "tell me about yourself"}],
    "thanks" -> ["speech_act" -> "answer", "topic" -> "social", "phrases" -> {"thank you", "thanks a lot", "much obliged"}],
    "help" -> ["speech_act" -> "query", "topic" -> "social", "phrases" -> {"can you help me", "i need help", "what can you do"}],
    "confirm" -> ["speech_act" -> "answer", "topic" -> "confirmation", "phrases" -> {"yes", "yeah", "sure", "okay"}],
    "decline" -> ["speech_act" -> "answer", "topic" -> "confirmation", "phrases" -> {"no", "nope", "not really", "no thanks"}],
    "give" -> ["speech_act" -> "request", "topic" -> "social", "phrases" -> {"give me that", "hand it over", "let me have it"}]
  ];

  method lowercase owner: ARCH_WIZARD
    ":lowercase(STR string) => STR with ASCII letters lowercased.";
    {string} = args;
    from = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    to = "abcdefghijklmnopqrstuvwxyz";
    for i in [1..26]
      string = strsub(string, from[i], to[i], 1);
    endfor
    return string;
  endmethod

  method words owner: ARCH_WIZARD
    ":words(STR string) => LIST of whitespace-separated tokens.";
    {string} = args;
    out = {};
    token = "";
    for i in [1..length(string)]
      c = string[i];
      if (c == " " || c == "\t" || c == "\n")
        if (token)
          out = {@out, token};
          token = "";
        endif
      else
        token = token + c;
      endif
    endfor
    if (token)
      out = {@out, token};
    endif
    return out;
  endmethod

  method from_list owner: ARCH_WIZARD
    ":from_list(LIST list [, STR separator]) => STR joined.";
    {thelist, ?separator = ""} = args;
    if (!thelist)
      return "";
    endif
    result = tostr(thelist[1]);
    for elt in (listdelete(thelist, 1))
      result = tostr(result, separator, elt);
    endfor
    return result;
  endmethod

  method set_domain_synonyms owner: ARCH_WIZARD
    ":set_domain_synonyms(MAP value) => replace the synonym families and invalidate the cached index.";
    {value} = args;
    this.domain_synonyms = value;
    this.synonym_index = [];
  endmethod

  method synonym_index owner: ARCH_WIZARD
    ":synonym_index() => MAP surface form -> LIST canonical terms it implies.";
    "  Reverse of .domain_synonyms, built lazily once and cached thereafter.";
    if (this.synonym_index)
      return this.synonym_index;
    endif
    idx = [];
    for forms, canonical in (this.domain_synonyms)
      for form in (forms)
        if (form == canonical)
          continue;
        endif
        idx[form] = maphaskey(idx, form) ? setadd(idx[form], canonical) | {canonical};
      endfor
    endfor
    this.synonym_index = idx;
    return idx;
  endmethod

  method intent_normalize owner: ARCH_WIZARD
    ":intent_normalize(STR text) => STR lowercased with surface forms mapped to canonical terms.";
    {text} = args;
    normalized = this:lowercase(text);
    words = this:words(normalized);
    syns = this:synonym_index();
    out = {};
    for w in (words)
      out = {@out, maphaskey(syns, w) ? syns[w][1] | w};
    endfor
    return this:from_list(out, " ");
  endmethod

  method intent_features owner: ARCH_WIZARD
    ":intent_features(STR text) => MAP with \"tokens\" and \"trigrams\" for one string.";
    {text} = args;
    normalized = this:intent_normalize(text);
    words = this:words(normalized);
    tokens = {};
    for w in (words)
      if (length(w) > 2 && !(w in tokens))
        tokens = {@tokens, w};
      endif
    endfor
    compact = strsub(normalized, " ", "", 1);
    trigrams = {};
    if (length(compact) < 3)
      trigrams = compact ? {compact} | {};
    else
      for i in [1..length(compact) - 2]
        gram = compact[i..i + 2];
        if (!(gram in trigrams))
          trigrams = {@trigrams, gram};
        endif
      endfor
    endif
    return ["tokens" -> tokens, "trigrams" -> trigrams];
  endmethod

  method _jaccard owner: ARCH_WIZARD
    ":_jaccard(LIST a, LIST b) => set overlap similarity.";
    {a, b} = args;
    if (!a || !b)
      return 0.0;
    endif
    hits = 0;
    for x in (a)
      if (x in b)
        hits = hits + 1;
      endif
    endfor
    den = length(a) + length(b) - hits;
    return den > 0 ? tofloat(hits) / den | 0.0;
  endmethod

  method _feature_cosine owner: ARCH_WIZARD
    ":_feature_cosine(LIST query, LIST candidate) => binary feature cosine.";
    {query, candidate} = args;
    if (!query || !candidate)
      return 0.0;
    endif
    q = [];
    d = [];
    for t in (query)
      q[t] = `q[t] ! ANY => 0' + 1;
    endfor
    for t in (candidate)
      d[t] = `d[t] ! ANY => 0' + 1;
    endfor
    common = 0.0;
    qnorm = 0.0;
    dnorm = 0.0;
    for t in (mapkeys(q))
      qnorm = qnorm + q[t] * q[t];
      if (maphaskey(d, t))
        common = common + q[t] * d[t];
      endif
    endfor
    for t in (mapkeys(d))
      dnorm = dnorm + d[t] * d[t];
    endfor
    return qnorm > 0.0 && dnorm > 0.0 ? common / (sqrt(qnorm) * sqrt(dnorm)) | 0.0;
  endmethod

  method _profile_text owner: ARCH_WIZARD
    ":_profile_text(MAP profile) => searchable text for an intent profile.";
    {profile} = args;
    phrases = `profile["phrases"] ! E_RANGE => {}';
    if (typeof(phrases) != TYPE_LIST)
      phrases = {};
    endif
    text = this:from_list(phrases, " ");
    text = tostr(text, " ", `profile["speech_act"] ! E_RANGE => ""', " ", `profile["topic"] ! E_RANGE => ""');
    for canonical in (mapkeys(this.domain_synonyms))
      forms = this.domain_synonyms[canonical];
      if (index(" " + text + " ", " " + canonical + " "))
        text = tostr(text, " ", this:from_list(forms, " "));
      endif
    endfor
    return text;
  endmethod

  method intent_score owner: ARCH_WIZARD
    ":intent_score(STR text, MAP profile) => score diagnostics; score is the best example match.";
    "  The query's features are invariant across candidate phrases, so they are";
    "  computed once. Each candidate phrase is normalized once through :intent_features";
    "  rather than four times.";
    {text, profile} = args;
    phrases = maphaskey(profile, "phrases") ? profile["phrases"] | {};
    if (typeof(phrases) != TYPE_LIST)
      phrases = {};
    endif
    act = maphaskey(profile, "speech_act") ? profile["speech_act"] | "";
    top = maphaskey(profile, "topic") ? profile["topic"] | "";
    q = this:intent_features(text);
    best = ["score" -> 0.0, "word" -> 0.0, "trigram" -> 0.0, "prior" -> 0.0, "text" -> ""];
    for phrase in (phrases)
      candidate = this:_profile_text(["phrases" -> {phrase}, "speech_act" -> act, "topic" -> top]);
      d = this:intent_features(candidate);
      ws = this:_feature_cosine(q["tokens"], d["tokens"]);
      ts = this:_jaccard(q["trigrams"], d["trigrams"]);
      score = this.intent_word_weight * ws + this.intent_trigram_weight * ts;
      if (score > best["score"])
        best = ["score" -> score, "word" -> ws, "trigram" -> ts, "prior" -> 0.0, "text" -> candidate];
      endif
    endfor
    prior = maphaskey(profile, "prior") ? profile["prior"] | 0.0;
    if (typeof(prior) != TYPE_INT && typeof(prior) != TYPE_FLOAT)
      prior = 0.0;
    endif
    best["prior"] = prior;
    best["score"] = best["score"] + max(-0.1, min(0.1, tofloat(prior)));
    return best;
  endmethod

  method test_intent_match owner: ARCH_WIZARD
    ":test_intent_match(?iterations) => benchmark :intent_score over the seeded profiles.";
    "  Reports ticks for a single score and wall-clock per score averaged over";
    "  many passes. Pass --test-args \"{N}\" to change the iteration count.";
    iterations = length(args) > 0 ? toint(args[1]) | 20;
    utterances = {
      "hey there, can you tell me the price of a health potion",
      "who are you and what do you sell",
      "i would like to buy two swords please"
    };
    ids = mapkeys(this.intent_profiles);
    this:synonym_index();

    "Tick cost of a single score (deterministic).";
    t0 = ticks_left();
    this:intent_score(utterances[1], this.intent_profiles[ids[1]]);
    single_ticks = t0 - ticks_left();

    "Wall-clock across the whole corpus, yielding each score to reset the tick budget.";
    w0 = ftime();
    scores = 0;
    for i in [1..iterations]
      for speech in (utterances)
        for id in (ids)
          this:intent_score(speech, this.intent_profiles[id]);
          scores = scores + 1;
          suspend(0);
        endfor
      endfor
    endfor
    w1 = ftime();
    elapsed_ms = (w1 - w0) * 1000.0;
    per_score_ms = scores > 0 ? elapsed_ms / scores | 0.0;

    server_log("BENCH_DATA bench=intent_match iterations=" + tostr(iterations) + " profiles=" + tostr(length(ids)) + " utterances=" + tostr(length(utterances)) + " scores=" + tostr(scores) + " single_score_ticks=" + tostr(single_ticks) + " total_ms=" + tostr(elapsed_ms) + " per_score_ms=" + tostr(per_score_ms));
    return ["scores" -> scores, "single_score_ticks" -> single_ticks, "total_ms" -> elapsed_ms, "per_score_ms" -> per_score_ms];
  endmethod
endobject
