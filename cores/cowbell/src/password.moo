object PASSWORD
    name: "Password Flyweight Delegate"
    owner: HACKER
    readable: true

    verb challenge (this none this) owner: ARCH_WIZARD flags: "rd"
        if (typeof(this) != flyweight)
          raise(E_INVARG);
        endif
        if (length(args) != 1)
          raise(E_ARGS);
        endif
        {password} = args;
        encrypted = this[1];
        if (typeof(encrypted) != str)
          raise(E_PERM);
        endif
        return argon2_verify(encrypted, password);
    endverb

    verb mk (this none this) owner: ARCH_WIZARD flags: "rd"
        "mk(password) => <$password, { <encrypted_password> }>; return an argon2 encrypted password";
        if (typeof(this) == flyweight)
          raise(E_INVARG);
        endif
        if (length(args) != 1)
          raise(E_ARGS);
        endif
        {password} = args;
        if (typeof(password) != str)
          raise(E_INVARG);
        endif
        salt_str = salt();
        encrypted_password = argon2(password, salt_str);
        return <this, {encrypted_password}>;
    endverb
endobject
