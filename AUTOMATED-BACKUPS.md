# Automated backups for Nextcloud + Pi-hole stack

This document describes how to automate backups for the Docker volumes and configuration in the `nextcloud-pihole-selfhosted` stack.  
It focuses on host-level cron jobs that archive Docker volumes and export Pi-hole configuration, following common best practices for containerised backups.

## Backup goals

- Regular, automated backups of:
  - Nextcloud AIO data and configuration volumes.
  - Database and Redis volumes.
  - Caddy reverse proxy volumes (config, certs, site data).
- Backups stored on the host in a dedicated directory, suitable for syncing to external storage or off-site backup.
- Simple restore procedures that can be tested on a fresh VM or host.

---

## 1. Volumes to back up

On the Docker host, you can inspect volumes with:

```bash
docker volume ls
docker volume ls --format '{{.Name}}'
```

For this stack, the key volumes currently in use are:

- **Nextcloud AIO volumes**
  - `nextcloud_aio_mastercontainer` – AIO control container state.
  - `nextcloud_aio_apache` – Apache container state.
  - `nextcloud_aio_nextcloud` – Nextcloud application data.
  - `nextcloud_aio_nextcloud_data` – Nextcloud user file storage.
  - `nextcloud_aio_database` – Nextcloud database (MariaDB/Postgres).
  - `nextcloud_aio_redis` – Redis cache state.
- **Caddy reverse proxy volumes**
  - `reverse-proxy_caddy_certs` – TLS certificates and trust store.
  - `reverse-proxy_caddy_config` – Caddy configuration files.
  - `reverse-proxy_caddy_data` – Caddy internal data.
  - `reverse-proxy_caddy_sites` – Site-specific data (if used).

You may also see a `nextcloud_aio_database_dump` volume. That is usually an export/backup helper volume; you can back it up if you use it, but it is not strictly required if you already archive `nextcloud_aio_database`.

---

## 2. Host-level volume backup script

The recommended pattern is to use a short-lived helper container to tar each volume’s contents into a host-mounted backup directory.

Create `scripts/backup-volumes.sh` in the repo:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Where backups are stored on the host
BACKUP_ROOT="/backups/docker-volumes"
DATE="$(date +%Y%m%d-%H%M)"
BACKUP_DIR="${BACKUP_ROOT}/${DATE}"

mkdir -p "${BACKUP_DIR}"

echo "[$(date)] Starting Docker volume backup to ${BACKUP_DIR}"

# List volumes to include - tailored to this stack
VOLUMES="
nextcloud_aio_mastercontainer
nextcloud_aio_apache
nextcloud_aio_nextcloud
nextcloud_aio_nextcloud_data
nextcloud_aio_database
nextcloud_aio_redis
reverse-proxy_caddy_certs
reverse-proxy_caddy_config
reverse-proxy_caddy_data
reverse-proxy_caddy_sites
"

# Optional: record what we intended to back up
printf '%s\n' ${VOLUMES} > "${BACKUP_DIR}/volume-list.txt"

for VOLUME in ${VOLUMES}; do
  if ! docker volume inspect "${VOLUME}" >/dev/null 2>&1; then
    echo "[$(date)] Skipping missing volume: ${VOLUME}"
    continue
  fi

  echo "[$(date)] Backing up volume: ${VOLUME}"
  docker run --rm \
    -v "${VOLUME}":/source:ro \
    -v "${BACKUP_DIR}":/backup \
    alpine:latest \
    sh -c "tar czf /backup/${VOLUME}.tar.gz -C /source ."
done

echo "[$(date)] Backup complete: ${BACKUP_DIR}"
```

Make the script executable:

```bash
chmod +x scripts/backup-volumes.sh
```

Notes:

- Uses `alpine:latest` as a lightweight helper container.
- Mounts each Docker volume at `/source` (read-only) and a host backup dir at `/backup`.
- Creates one `VOLUME.tar.gz` per volume under a timestamped directory.
- Writes a `volume-list.txt` manifest so you can see what was backed up on that run.

---

## 3. Pi-hole backups (optional)

If Pi-hole runs on the same host (with volumes like `pihole_etc_pihole` and `pihole_etc_dnsmasq.d`), you can add them to the `VOLUMES` list and/or use Pi-hole Teleporter for configuration export.

Example additional entries in `VOLUMES` (if present):

```bash
VOLUMES="
nextcloud_aio_mastercontainer
nextcloud_aio_apache
nextcloud_aio_nextcloud
nextcloud_aio_nextcloud_data
nextcloud_aio_database
nextcloud_aio_redis
reverse-proxy_caddy_certs
reverse-proxy_caddy_config
reverse-proxy_caddy_data
reverse-proxy_caddy_sites
pihole_etc_pihole
pihole_etc_dnsmasq.d
"
```

And an optional Teleporter export at the end of `backup-volumes.sh`:

```bash
echo "[$(date)] Attempting Pi-hole Teleporter export"

PIHOLE_COMPOSE_DIR="/home/youruser/nextcloud-pihole-selfhosted/pihole"

if docker ps --format '{{.Names}}' | grep -q '^pihole$'; then
  TELEPORTER_NAME="pihole_teleporter_${DATE}.tar.gz"

  (
    cd "${PIHOLE_COMPOSE_DIR}"
    docker compose exec pihole \
      pihole -a -t "/etc/pihole/backups/${TELEPORTER_NAME}"
  )

  docker cp pihole:/etc/pihole/backups/"${TELEPORTER_NAME}" "${BACKUP_DIR}/"

  echo "[$(date)] Pi-hole Teleporter exported to ${BACKUP_DIR}/${TELEPORTER_NAME}"
else
  echo "[$(date)] Pi-hole container not running, skipping Teleporter."
fi
```

Replace `/home/youruser/…` with the actual path on your host.

---

## 4. Nextcloud-specific notes

For Nextcloud AIO, your volume backups should cover:

- `nextcloud_aio_nextcloud` and `nextcloud_aio_nextcloud_data` – application and user data.
- `nextcloud_aio_database` – database contents.
- `nextcloud_aio_redis` – cache (not strictly required, but cheap to back up).
- `nextcloud_aio_apache` and `nextcloud_aio_mastercontainer` – application/runtime state.

If you ever need more granular backups, you can also tar specific directories from the Nextcloud Apache container (e.g. `data/`, `config/`), but the volume-based approach above is usually sufficient.

---

## 5. Scheduling backups with cron

Run backups from the Docker host with cron.

1. Edit the crontab for a user that can run `docker`:

   ```bash
   crontab -e
   ```

2. Add a nightly backup job, for example at 02:00:

   ```cron
   0 2 * * * /usr/bin/env bash /home/youruser/nextcloud-pihole-selfhosted/scripts/backup-volumes.sh >> /var/log/docker-volume-backup.log 2>&1
   ```

This will:

- Run the backup script every night at 02:00.
- Create timestamped tar.gz archives under `/backups/docker-volumes/YYYYMMDD-HHMM/`.
- Log output to `/var/log/docker-volume-backup.log` for debugging.

Adjust time, paths, and user to match your environment.

---

## 6. Restore procedures (high-level)

Test restores periodically on a disposable VM or test host.

### Restore a single volume

1. Create a new empty volume:

   ```bash
   docker volume create nextcloud_aio_nextcloud_data_restore
   ```

2. Extract the backup archive into the new volume:

   ```bash
   docker run --rm \
     -v nextcloud_aio_nextcloud_data_restore:/target \
     -v /backups/docker-volumes/20260714-0200:/backup \
     alpine:latest \
     sh -c "tar xzf /backup/nextcloud_aio_nextcloud_data.tar.gz -C /target"
   ```

3. Update your Compose file or container configuration to use `nextcloud_aio_nextcloud_data_restore` instead of the original volume, then start the container.

### Restore full stack

Typical high-level steps:

1. Stop and remove existing containers (Nextcloud AIO stack, Caddy, Pi-hole if applicable).
2. Create fresh volumes matching your original names.
3. For each `VOLUME.tar.gz`:
   - Create the corresponding volume if it does not exist.
   - Use the helper-container pattern above to extract into that volume.
4. Bring up the stack with `docker compose up -d` using the same Compose files and `.env` values.
5. Confirm:
   - Nextcloud login works and data is present.
   - Caddy configuration and certificates are restored.
   - Pi-hole configuration and local DNS records are restored (if included).

Document your exact restore steps (with real dates and paths) once you have tested them, so future restores are repeatable.

---

## 7. Recommendations

- Store `/backups` on a disk/partition with enough capacity and use another tool (rsync, restic, Borg, etc.) to push backups to external or off-site storage.
- Keep backup scripts in `scripts/` within the repo and track changes via Git.
- Review volume names whenever you change Compose files or upgrade Nextcloud AIO, Caddy, or Pi-hole, and update `VOLUMES` in `backup-volumes.sh` accordingly.
- Run periodic restore tests on a throwaway VM to validate that your backups are actually usable, not just present.
