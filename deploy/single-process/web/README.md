# Single-Process Web Deployment

Runs the combined `moor` backend in one container with the embedded curl worker enabled, and serves
the Meadow frontend from nginx. The browser UI is exposed on port 8080 and telnet is exposed on port
8888.

```bash
cp .env.example .env
docker compose up -d
```

Then visit `http://localhost:8080`.

## Settings

Copy `.env.example` to `.env` and change what you need:

| Setting               | What it does                                             | Default        |
| --------------------- | -------------------------------------------------------- | -------------- |
| `USER_ID`, `GROUP_ID` | The user and group the containers run as                 | `1000`, `1000` |
| `MOOR_VERSION`        | The release to run, which is the image tag               | `latest`       |
| `MOOR_BIND`           | The address the published ports listen on                | `0.0.0.0`      |
| `MOOR_CORE`           | The core a new world starts from, a directory in `cores` | `snore`        |

`moor.yaml` turns on the server features that the Snore and Cowbell cores are written for.

## The core

A new world is made from a core the first time the server starts. After that the world lives in
`moor-data`, and `MOOR_CORE` is not read again.

- **`snore`** is a classic MOO core in the LambdaCore tradition, at home over telnet.
- **`cowbell`** is the core built for the Meadow web client.

## Before you open it to anyone

Both cores start with a wizard account that can do anything in the world, and neither is safe to
expose as it comes. Start with `MOOR_BIND=127.0.0.1` in `.env`, so that the ports answer only on the
machine itself, and change the password from there:

- **Snore:** the wizard has no password.

  ```
  connect wizard
  @password <new-password>
  ```

- **Cowbell:** the wizard is `archwizard`, with the password `test`.

  ```
  connect archwizard test
  @password test <new-password>
  ```

  Cowbell also comes with a `Test_Player` account, a welcome message that names the wizard's
  password, and account creation open to visitors. Its own guide covers these:
  [Accounts](../../../cores/cowbell/book/src/running/accounts.md).

Then remove `MOOR_BIND` from `.env` and run `docker compose up -d` again.
