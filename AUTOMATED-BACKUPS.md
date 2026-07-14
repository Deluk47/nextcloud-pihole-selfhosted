# Automated backups for Nextcloud + Pi-hole stack

This document describes how to automate backups for the Docker volumes and configuration in the `nextcloud-pihole-selfhosted` stack.[web:54]  
It focuses on host-level cron jobs that archive Docker volumes and export Pi-hole configuration, following common best practices for containerized backups.[web:67][web:65]

## Backup goals

- Regular, automated backups of:
  - Nextcloud data and configuration volumes.  
  - Database volumes (if applicable).  
  - Pi-hole data volumes and Pi-hole configuration via Teleporter.[web:55][web:68]
- Backups stored on the host in a dedicated directory, suitable for syncing to external storage or off-site backup.[web:54]  
- Simple restore procedures that can be tested on a fresh VM or host.

---

## 1. Identify volumes to back up

On the Docker host, list existing volumes:[web:52][web:57]

```bash
docker volume ls
docker volume ls --format '{{.Name}}'
```

For this stack, you typically want to include:

- Nextcloud volumes (examples, adjust to match your compose):
  - `nextcloud_aio_nextcloud`
  - `nextcloud_aio_nextcloud_data`
  - Database volume, if separate (for example `nextcloud_db_data`).[web:55][web:67]
- Pi-hole volumes:
  - `pihole_etc_pihole`
  - `pihole_etc_dnsmasq.d` (or equivalent).[web:56]

You can filter by prefix when debugging:

```bash
docker volume ls --format '{{.Name}}' | grep -E 'nextcloud|pihole'
```

Update the backup script below to match your actual volume names.

---

## 2. Host-level volume backup script

The recommended pattern is to use a short-lived helper container to tar each volume’s contents into a host-mounted backup directory.[web:57][web:63]

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

# List volumes to include - adjust to match your stack
VOLUMES="
nextcloud_aio_nextcloud
nextcloud_aio_nextcloud_data
nextcloud_db_data
pihole_etc_pihole
pihole_etc_dnsmasq.d
"

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

Key points:[web:54][web:57]

- Uses `alpine:latest` as a lightweight helper container.  
- Mounts each Docker volume at `/source` (read-only) and a host backup dir at `/backup`.  
- Creates one `VOLUME.tar.gz` per volume under a timestamped directory.

Make the script executable:

```bash
chmod +x scripts/backup-volumes.sh
```

---

## 3. Pi-hole Teleporter automated export (optional)

Pi-hole provides a built-in Teleporter feature that exports configuration (lists, DNS settings, etc.) to a tar archive.[web:65][web:68]  
You can combine this with your volume backups for extra safety.

Extend `backup-volumes.sh` with:

```bash
echo "[$(date)] Attempting Pi-hole Teleporter export"

# Adjust path to your pihole compose file if needed
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

This pattern mirrors community scripts that use Teleporter + cron to generate regular Pi-hole backups.[web:65][web:68]

---

## 4. Nextcloud-specific notes

For Nextcloud, ensure you include:[web:55][web:67]

- Data volume (`data/`): user files, uploads, etc.  
- Config volume (`config/`): `config.php`, app configuration, installed apps.  
- Database volume: your SQL database (MariaDB/Postgres) data.

If you prefer explicit Nextcloud-only backups, you can also use per-container tar commands:

```bash
docker run --rm \
  --volumes-from nextcloud-app \
  -v /backups/nextcloud/"${DATE}":/backup \
  ubuntu \
  sh -c "tar czf /backup/nextcloud-data.tar.gz -C /var/www/html/data ."

docker run --rm \
  --volumes-from nextcloud-app \
  -v /backups/nextcloud/"${DATE}":/backup \
  ubuntu \
  sh -c "tar czf /backup/nextcloud-config.tar.gz -C /var/www/html/config ."
```

The volume-based approach in `backup-volumes.sh` is usually simpler, but documenting both helps during restore testing.[web:58][web:67]

---

## 5. Scheduling backups with cron

Run backups from the Docker host with cron.[web:54][web:64]

1. Edit the crontab for a user that can run `docker`:

   ```bash
   crontab -e
   ```

2. Add a nightly backup job, e.g. 02:00:

   ```cron
   0 2 * * * /usr/bin/env bash /home/youruser/nextcloud-pihole-selfhosted/scripts/backup-volumes.sh >> /var/log/docker-volume-backup.log 2>&1
   ```

This will:[web:54]

- Run the backup script every night at 02:00.  
- Create timestamped tar.gz archives under `/backups/docker-volumes/YYYYMMDD-HHMM/`.  
- Log output to `/var/log/docker-volume-backup.log` for debugging.

Adjust the time and paths to your environment as needed.

---

## 6. Restore procedures (high-level)

Test restores periodically on a disposable VM or test host.[web:54][web:63]

### Restore a single volume

1. Create a new empty volume:

   ```bash
   docker volume create nextcloud_data_restore
   ```

2. Extract the backup archive into the volume:

   ```bash
   docker run --rm \
     -v nextcloud_data_restore:/target \
     -v /backups/docker-volumes/20260714-0200:/backup \
     alpine:latest \
     sh -c "tar xzf /backup/nextcloud_aio_nextcloud_data.tar.gz -C /target"
   ```

3. Update your Compose file or container to use `nextcloud_data_restore` instead of the old volume, then start the container.

### Restore full stack

Typical high-level steps:[web:55][web:67]

1. Stop and remove existing containers (Pi-hole, Nextcloud, DB, reverse proxy).  
2. Create fresh volumes matching your original names.  
3. Extract each `VOLUME.tar.gz` into the corresponding new volume using the helper container pattern above.  
4. Bring up the stack with `docker compose up -d` using the same Compose files and `.env` values.  
5. Confirm:
   - Nextcloud login works, data is present.  
   - Pi-hole configuration and local DNS records are restored.

Document your exact restore steps (with volume names and paths) once you have tested them, so future restores are repeatable.

---

## 7. Recommendations

- Store `/backups` on a disk/partition with enough capacity and use another tool (rsync, restic, Borg, etc.) to push backups off-site.[web:54][web:50]  
- Keep backup scripts in `scripts/` within the repo and track changes via Git.  
- Review volume names whenever you change Compose files or upgrade Nextcloud/Pi-hole, and update `VOLUMES` in `backup-volumes.sh` accordingly.[web:52]  
- Run periodic restore tests on a throwaway VM to validate that your backup strategy is actually usable, not just “present”.[web:54]
