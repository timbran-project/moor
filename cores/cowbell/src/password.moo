object PASSWORD
  name: "Password Flyweight Delegate"
  parent: ROOT
  owner: HACKER
  readable: true

  override description = "Flyweight delegate for password storage using Argon2 encryption.";
  override import_export_id = "password";

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
    contents = flycontents(this);
    encrypted = contents[1];
    if (typeof(encrypted) != STR)
      raise(E_PERM);
    endif
    return argon2_verify(encrypted, password);
  endverb

  verb test_round_trip (this none this) owner: HACKER flags: "rxd"
    password = this:mk("foobarbaz");
    password:challenge("foobarbaz") != true && return E_ASSERT;
    password:challenge("notmypassword") != false && return E_ASSERT;
    return true;
  endverb
endobject