# Starting on a Cloud Machine

If you rent a machine from a cloud provider, mooR can set itself up when the machine first starts.
You don't log in to install anything. Each mooR release includes a file for this, called
`moor-cloud-init.yaml`.

The file is a [cloud-init](https://cloud-init.io/) configuration. cloud-init is the standard way to
prepare a new cloud machine: you hand the provider some instructions when you create the machine,
and the machine carries them out on its first boot. AWS, Hetzner, DigitalOcean and most other
providers support it.

This gives you a running server, not a managed one. There is no HTTPS, no domain name, no backup and
no automatic upgrade. It is a good way to try mooR on a real machine, and a starting point for a
deployment you then look after yourself.

## What it sets up

On the machine's first boot, the file:

1. installs Docker and Git;
2. creates a `moor` user for the server to run as;
3. fetches the mooR deployment files for that release into `/opt/moor/src`;
4. starts the single-process web deployment described in
   [Docker Compose Setup](docker-compose-setup.md): the whole server in one container, with nginx
   serving the web client. The world starts from the Cowbell core, which is built for the web
   client.

## Creating the machine

You need a machine running **Ubuntu 24.04**. The file uses Ubuntu's package names.

1. Start creating a machine with your provider and choose Ubuntu 24.04.
2. Find the field for user data. Providers also call it "cloud config" or an "initialization
   script". Put these two lines in it, with the release you want in place of `<release>`:

   ```
   #include
   https://github.com/timbran-project/moor/releases/download/<release>/moor-cloud-init.yaml
   ```

   The machine fetches the file from the release when it starts. You can also download the file and
   paste its contents into the field.

3. In the provider's firewall, allow SSH. Leave ports 8080 and 8888 closed for now.
4. Create the machine and give it a few minutes. To watch its progress, log in and run:

   ```sh
   cloud-init status --wait
   ```

   The full output is in `/var/log/cloud-init-output.log`. When it has worked, that file ends with
   the line "mooR is running".

## Choosing the core

The file starts a new world from **Cowbell**, the core built for the web client. For a classic MOO
core in the LambdaCore tradition, at home over telnet, use **Snore**: download the file, change
`MOOR_CORE=cowbell` to `MOOR_CORE=snore`, and paste its contents as the user data. The core is only
read when the world is first made.

## Before you let anyone in

A new world has a wizard account that can do anything in it, and its password is one everybody
knows. Anyone who can reach a new server can take it over. So the server starts out listening only
on the machine itself. You change the password through an SSH tunnel, and open the server
afterwards.

1. From your own computer, open a tunnel to the machine:

   ```sh
   ssh -L 8888:127.0.0.1:8888 -L 8080:127.0.0.1:8080 <user>@<address>
   ```

2. In another terminal on your own computer, connect and change the password. A Cowbell world's
   wizard is `archwizard`, with the password `test`:

   ```sh
   telnet localhost 8888
   ```

   ```
   connect archwizard test
   @password test <new-password>
   ```

   While the tunnel is open, the web client is also at `http://localhost:8080`.

3. Look at what else Cowbell starts with. It has a `Test_Player` account, a welcome message that
   names the wizard's password, and account creation open to visitors. Cowbell's guide to
   [accounts](https://github.com/timbran-project/moor/blob/main/cores/cowbell/book/src/running/accounts.md)
   says how to change each.

4. On the machine, open the server to the network and restart it:

   ```sh
   cd /opt/moor/src/deploy/single-process/web
   sudo sed -i 's/^MOOR_BIND=.*/MOOR_BIND=0.0.0.0/' .env
   sudo docker compose up -d
   ```

5. In the provider's firewall, allow ports 8080 and 8888.

The web client is now at `http://<address>:8080`, and telnet at `<address>:8888`.

If you chose the Snore core, the wizard is `wizard` and has no password: use `connect wizard` and
then `@password <new-password>`.

## What to do next

- **Add HTTPS.** Port 8080 is plain HTTP, so logins through the web client are not encrypted. For
  anything beyond a trial, put the server behind HTTPS with a domain name.
- **Back up the world.** The database is in `/opt/moor/src/deploy/single-process/web/moor-data`, and
  the server writes exports of it to the `export` directory beside that. Copy them somewhere off the
  machine.
- **Configure the server.** See [Server Configuration](server-configuration.md). The files are in
  `/opt/moor/src/deploy/single-process/web`.

## Changing what it does

The file is made from a template in the mooR repository, `deploy/cloud-init/moor.yaml`. To change
the setup, copy the template, replace `@MOOR_VERSION@` with a release, edit it, and give your
provider your copy.
