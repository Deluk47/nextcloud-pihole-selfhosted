# Restore and disaster recovery

This document explains how to restore the `nextcloud-pihole-selfhosted` stack from automated backups.  
It assumes you are using the `scripts/backup-volumes.sh` approach documented in `AUTOMATED-BACKUPS.md`.

---

## 1. Concepts and assumptions

- Backups are stored under `/backups/docker-volumes/YYYYMMDD-HHMM/` on the host.
- Each backup run creates:
  - One `VOLUME.tar.gz` per Docker volume.
  - A `volume-list.txt` manifest with the intended volumes.
- Core volumes on your host:
  - `nextcloud_aio_mastercontainer`
  - `nextcloud_aio_apache`
  - `nextcloud_aio_nextcloud`
  - `nextcloud_aio_nextcloud_data`
  - `nextcloud_aio_database`
  - `nextcloud_aio_redis`
  - `reverse-proxy_caddy_certs`
  - `reverse-proxy_caddy_config`
  - `reverse-proxy_caddy_data`
  - `reverse-proxy_caddy_sites`

If Pi-hole volumes and Teleporter exports are included, the restore steps apply in addition to the ones below.

---

## 2. General restore pattern for a volume

Restoring any single Docker volume from a `VOLUME.tar.gz` backup follows the same pattern:

1. **Stop the containers using the volume.**

   Example (Nextcloud AIO + Caddy):

   ```bash
   cd ~/nextcloud-pihole-selfhosted
   docker compose -f nextcloud/docker-compose.yaml down
   docker compose -f nextcloud/reverse-proxy/compose.yaml down
   ```

   Adjust paths/filenames to your actual Compose files.

2. **Create a fresh volume (optional but recommended for DB volumes).**

   ```bash
   docker volume rm nextcloud_aio_nextcloud_data
   docker volume create nextcloud_aio_nextcloud_data
   ```

   For non-database volumes you can instead overwrite the existing volume contents, but recreating the volume gives a clean slate.

3. **Extract the backup into the volume using a helper container.**

   ```bash
   BACKUP_DIR="/backups/docker-volumes/20260714-0200"   # example; use your actual folder
   VOLUME="nextcloud_aio_nextcloud_data"

   docker run --rm \
     -v "${VOLUME}":/target \
     -v "${BACKUP_DIR}":/archive:ro \
     alpine:latest \
     sh -c "tar xzf /archive/${VOLUME}.tar.gz -C /target"
   ```

4. **Restart the containers.**

   ```bash
   cd ~/nextcloud-pihole-selfhosted
   docker compose -f nextcloud/docker-compose.yaml up -d
   docker compose -f nextcloud/reverse-proxy/compose.yaml up -d
   ```

5. **Verify the restore.**

   - Check logs:
     ```bash
     docker logs nextcloud-aio-apache --tail 50
     docker logs caddy --tail 50
     ```
   - Access `https://your.cloud.name` and confirm data and config look correct.

---

## 3. Full stack restore on an existing host

Use this when the stack is broken but the host is intact and backups are available.

### 3.1 Preparation

1. Choose a backup snapshot:

   ```bash
   ls -1 /backups/docker-volumes/
   ```

   Pick a date/time directory (e.g. `20260714-0200`) and set:

   ```bash
   BACKUP_DIR="/backups/docker-volumes/20260714-0200"
   ```

2. Review which volumes were backed up:

   ```bash
   cat "${BACKUP_DIR}/volume-list.txt"
   ```

### 3.2 Stop and clean up containers

```bash
cd ~/nextcloud-pihole-selfhosted

# Stop stacks (adjust file names to your setup)
docker compose -f nextcloud/docker-compose.yaml down
docker compose -f nextcloud/reverse-proxy/compose.yaml down
# If Pi-hole is running on this host:
# docker compose -f pihole/compose.yaml down
```

### 3.3 Recreate volumes and restore data

For each volume in your list:

```bash
for V in \
  nextcloud_aio_mastercontainer \
  nextcloud_aio_apache \
  nextcloud_aio_nextcloud \
  nextcloud_aio_nextcloud_data \
  nextcloud_aio_database \
  nextcloud_aio_redis \
  reverse-proxy_caddy_certs \
  reverse-proxy_caddy_config \
  reverse-proxy_caddy_data \
  reverse-proxy_caddy_sites
do
  # Recreate the volume
  docker volume rm "${V}" 2>/dev/null || true
  docker volume create "${V}"

  # Restore from backup
  docker run --rm \
    -v "${V}":/target \
    -v "${BACKUP_DIR}":/archive:ro \
    alpine:latest \
    sh -c "tar xzf /archive/${V}.tar.gz -C /target"
done
```

If any volume is intentionally left out (e.g. you don’t need to restore `reverse-proxy_caddy_data`), remove it from the loop.

### 3.4 Bring the stack back up

```bash
cd ~/nextcloud-pihole-selfhosted

# Start Nextcloud AIO stack
docker compose -f nextcloud/docker-compose.yaml up -d

# Start Caddy reverse proxy
docker compose -f nextcloud/reverse-proxy/compose.yaml up -d

# Start Pi-hole (if managed on this host)
# docker compose -f pihole/compose.yaml up -d
```

### 3.5 Verify services

- Check containers:

  ```bash
  docker ps
  ```

- Check logs:

  ```bash
  docker logs nextcloud-aio-apache --tail 50
  docker logs nextcloud-aio-database --tail 50
  docker logs caddy --tail 50
  ```

- Test from a client:

  - `dig your.cloud.name +short` should return **Host IP**.
  - `curl -kI https://your.cloud.name` should return a 200 or 302, not an error.
  - Login to Nextcloud and confirm data is present.

---

## 4. Restore on a fresh host (disaster recovery)

Use this when you’ve lost the original host and need to rebuild on a new machine with the same stack.

### 4.1 Prepare the new host

1. Install Docker Engine and Docker Compose.
2. Set a static **Host IP** on the LAN.
3. Clone the repo:

   ```bash
   cd ~
   git clone https://github.com/Deluk47/nextcloud-pihole-selfhosted.git
   cd nextcloud-pihole-selfhosted
   ```

4. Recreate `.env` files from your documentation or off-site backups:

   ```bash
   cp nextcloud/.env.example nextcloud/.env
   cp nextcloud/reverse-proxy/.env.example nextcloud/reverse-proxy/.env
   cp pihole/.env.example pihole/.env     # if Pi-hole is used on this host
   nano nextcloud/.env
   nano nextcloud/reverse-proxy/.env
   nano pihole/.env
   ```

### 4.2 Transfer backup archives

Copy the relevant `/backups/docker-volumes/YYYYMMDD-HHMM/` directory from your old host or external storage to the new host, for example:

```bash
rsync -avz backups-host:/backups/docker-volumes/20260714-0200 /backups/docker-volumes/
BACKUP_DIR="/backups/docker-volumes/20260714-0200"
```

Ensure file ownership and permissions are correct so Docker can read the archives.

### 4.3 Restore volumes (same pattern as section 3)

Use the same loop:

```bash
for V in \
  nextcloud_aio_mastercontainer \
  nextcloud_aio_apache \
  nextcloud_aio_nextcloud \
  nextcloud_aio_nextcloud_data \
  nextcloud_aio_database \
  nextcloud_aio_redis \
  reverse-proxy_caddy_certs \
  reverse-proxy_caddy_config \
  reverse-proxy_caddy_data \
  reverse-proxy_caddy_sites
do
  docker volume rm "${V}" 2>/dev/null || true
  docker volume create "${V}"

  docker run --rm \
    -v "${V}":/target \
    -v "${BACKUP_DIR}":/archive:ro \
    alpine:latest \
    sh -c "tar xzf /archive/${V}.tar.gz -C /target"
done
```

### 4.4 Start stacks and reconnect DNS

```bash
cd ~/nextcloud-pihole-selfhosted

# Bring up Pi-hole (if used on this host)
# cd pihole && docker compose up -d

# Bring up Nextcloud AIO
cd nextcloud
docker compose up -d

# Bring up Caddy
cd ../nextcloud/reverse-proxy
docker compose up -d
```

Reconfigure Pi-hole or your router so `your.cloud.name` resolves to the new **Host IP**, then test Nextcloud and other services.

---

## 5. Pi-hole Teleporter restore (if used)

If you exported Pi-hole configuration via Teleporter:

1. Log into the Pi-hole admin UI on the restored host.
2. Navigate to *Settings* → *Teleporter*.
3. Use the “Restore” function to upload the `.tar.gz` file you copied into your backup directory.
4. Verify:
   - Adlists and blocklists are present.
   - Local DNS records (including `your.cloud.name`) are restored.

---

## 6. Testing and validation

Regularly test your restore process on a non-production environment:

- Create a small test VM.
- Copy a backup snapshot directory.
- Restore a subset of volumes (e.g. `nextcloud_aio_nextcloud_data` and `nextcloud_aio_database`).
- Start a minimal Nextcloud AIO stack and confirm:
  - Logins work.
  - A sample file appears.
  - Caddy can proxy to it.

Record any differences between your test and production setup and update this document accordingly so the restore procedure stays accurate.

---

## 7. Tips and cautions

- **Stop containers before restoring volumes.** Writing into volumes used by running containers can corrupt data.
- **Database volumes:** Prefer recreating the volume and restoring from a clean snapshot instead of overlaying data on top of a running DB.
- **Time alignment:** When restoring from older backups, remember:
  - Files, DB state, and configuration will reflect that backup’s date.
  - Any data created after the backup will not be present.
- **Document your choices:** If you decide not to restore certain volumes (e.g. Caddy data), note it so future restores are consistent.
