# Starting mooR on a cloud machine

Each mooR release comes with a file, `moor-cloud-init.yaml`, that sets up a server on a new cloud
machine with no steps on the machine itself. It is a [cloud-init](https://cloud-init.io/) file: you
give it to your provider when you create the machine, and the machine carries it out the first time
it starts.

`moor.yaml` in this directory is the template that file is made from. The release fills in which
version to install.

It gives you a running server, not a managed one: there is no HTTPS, no domain name, no backup and
no automatic upgrade.

## What it does

On the machine's first boot it:

1. installs Docker and Git from Ubuntu's packages;
2. creates a `moor` user for the server to run as;
3. fetches the mooR deployment files for one release into `/opt/moor/src`;
4. starts the [single-process web deployment](../single-process/web/), which is the whole server in
   one container with nginx serving the web client. The world starts from LambdaCore.

The web client is then on port 8080 and telnet on port 8888, **reachable only from the machine
itself** until you open them, for the reason given under "Before you let anyone in".

## What you need

- A provider that accepts cloud-init user data. Most do, AWS, Hetzner and DigitalOcean among them.
- A machine image of **Ubuntu 24.04**. The file uses Ubuntu's package names, and other systems name
  the Docker packages differently.

## Using it

1. Create a machine with your provider and choose Ubuntu 24.04. In the field for user data, which
   providers also call "cloud config" or an "initialization script", put these two lines, with the
   release you want in place of `<release>`:

   ```
   #include
   https://github.com/timbran-project/moor/releases/download/<release>/moor-cloud-init.yaml
   ```

   The machine fetches the file from the release when it starts. You can also download the file and
   paste its contents into the field instead.

2. Allow SSH to the machine in the provider's firewall. Leave ports 8080 and 8888 closed for now.
3. Wait a few minutes. To watch, log in and run:

   ```sh
   cloud-init status --wait
   ```

   The full output is in `/var/log/cloud-init-output.log`.

To change what the file does, copy `moor.yaml`, replace `@MOOR_VERSION@` with a release, and use
your copy.

## Before you let anyone in

A new LambdaCore world has a wizard account with no password. Anyone who can reach the server can
log in as the wizard and take it over. So the server starts out listening only on the machine
itself, and you set the password over an SSH tunnel.

1. From your own computer, open a tunnel to the machine:

   ```sh
   ssh -L 8888:127.0.0.1:8888 -L 8080:127.0.0.1:8080 <user>@<address>
   ```

2. In another terminal, connect and set the password:

   ```sh
   telnet localhost 8888
   ```

   ```
   connect wizard
   @password <new-password>
   ```

3. On the machine, open the server to the network and restart it:

   ```sh
   cd /opt/moor/src/deploy/single-process/web
   sudo sed -i 's/^MOOR_BIND=.*/MOOR_BIND=0.0.0.0/' .env
   sudo docker compose up -d
   ```

4. Allow ports 8080 and 8888 in the provider's firewall.

The web client is then at `http://<address>:8080` and telnet at `<address>:8888`.

## After that

- **HTTPS.** Port 8080 is plain HTTP, so logins through the web client are not encrypted. For
  anything beyond a trial, put the server behind HTTPS. The
  [clustered web-ssl deployment](../clustered/web-ssl/) shows nginx with certificates.
- **Backups.** The world is in `/opt/moor/src/deploy/single-process/web/moor-data`, and the server
  writes exports of it to `export` beside that. Copy them somewhere else.
- **Changing the configuration.** Everything is in `/opt/moor/src/deploy/single-process/web`. Its
  [README](../single-process/web/README.md) describes it.
- **Running it again.** cloud-init runs the setup once. The script it used is
  `/usr/local/sbin/moor-first-boot`, and the release it installed is in `/etc/moor/install.env`.
