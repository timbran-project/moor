object PASSWORD
  name: "Password Flyweight Delegate"
  location: FIRST_ROOM
  owner: HACKER
  readable: true

  verb mk (this none this) owner: ARCH_WIZARD flags: "rxd"
    "mk(password) => <$password, { <encrypted_password> }>; return an argon2 encrypted password";
    if (typeof(this) == FLYWEIGHT)
      raise(E_INVARG);
    endif
    if (length(args) != 1)
      raise(E_ARGS);
    endif
    {password} = args;
    if (typeof(password) != STR)
      raise(E_INVARG);
    endif
    salt_str = salt();
    encrypted_password = argon2(password, salt_str);
    return <this, {encrypted_password}>;
  endverb

  verb challenge (this none this) owner: ARCH_WIZARD flags: "rxd"
    if (typeof(this) != FLYWEIGHT)
      raise(E_INVARG);
    endif
    if (length(args) != 1)
      raise(E_ARGS);
    endif
    {password} = args;
    encrypted = this[1];
    if (typeof(encrypted) != STR)
      raise(E_PERM);
    endif
    return argon2_verify(encrypted, password);
  endverb

  verb test_round_trip (this none this) owner: HACKER flags: "rxd"
    password = this:mk("foobarbaz");
    password:challenge("foobarbaz") != true && return e_assert;
    password:challenge("notmypassword") != false && return e_assert;
    return true;
  endverb
endobject
