# Fehleranalyse: Backup-Ausfälle vom 2026-02-09

**Datum:** 2026-02-09  
**Backup-System Version:** 2.8.3  
**Betroffene Profile:** dev-data, system  
**Status:** Beide Backups fehlgeschlagen

---

## 1. Zusammenfassung

Am 09.02.2026 sind beide Backup-Profile (dev-data und system) fehlgeschlagen. Die Ursachen sind verschieden, hängen aber beide mit der Mount-Architektur zusammen. Das dev-data-Backup scheiterte bereits im PRE-Segment vor dem eigentlichen Mount-Vorgang, das system-Backup scheiterte am Mount-Segment selbst, weil das Root-Dateisystem fälschlicherweise am Backup-Mountpoint eingehängt war.

---

## 2. Fehleranalyse: dev-data-Profil

**Zeitraum:** 00:07:26 – 00:07:35 (9 Sekunden bis Abbruch)  
**Fehlgeschlagen bei:** PRE-01 (Nextcloud DB Dump)

### Fehlerbild

```
[PRE-01] Checking Nextcloud database dump...
[PRE-01] Nextcloud App Container: nextcloud-app
[PRE-01] Nextcloud DB Container: nextcloud-db
[PRE-01] Database: nextcloud
mkdir: das Verzeichnis »/mnt/system_backup/creaThink_docker-data" kann nicht angelegt werden: Vorgang nicht zulässig
```

### Ursache

Das Segment `pre_01_nextcloud_db_dump.sh` erstellt in Zeile 74 das Verzeichnis `${TARGET_DIR}/database-dumps` per `mkdir -p`. TARGET_DIR verweist hier auf `/mnt/system_backup/creaThink_docker-data`, also einen Pfad auf dem Backup-Laufwerk.

Das Problem: Die PRE-Segmente werden laut `main.sh` **vor** den Main-Segmenten ausgeführt. Das Mount-Segment (05) ist aber erst Teil der Main-Segmente. Die Ausführungsreihenfolge ist:

```
PRE_BACKUP_SEGMENTS    ← pre_01 läuft hier (TARGET_DIR nicht gemountet!)
MAIN_SEGMENTS_PART1    ← 05_mount_backup.sh läuft erst hier
```

Zum Zeitpunkt der PRE-Segment-Ausführung ist das Backup-Laufwerk entweder noch nicht gemountet oder der Mountpoint befindet sich in einem ungültigen Zustand (z.B. durch ein systemd-Automount-Problem). Das `mkdir -p` schlägt daher mit "Vorgang nicht zulässig" (EPERM) fehl.

### Bewertung

Das ist ein **Design-Fehler in der Ausführungsreihenfolge**: Pre-Backup-Segmente, die auf TARGET_DIR zugreifen, laufen vor dem Mount-Segment. Dieser Fehler besteht seit Einführung der PRE-Segment-Architektur, tritt aber nur auf, wenn das Automount nicht zufällig bereits aktiv ist.

---

## 3. Fehleranalyse: system-Profil

**Zeitraum:** 10:02:11 – 10:03:58 (ca. 107 Sekunden bis Abbruch)  
**Fehlgeschlagen bei:** Segment 05 (Mount Backup)

### Fehlerbild

Das Gerät `/dev/sdc1` wurde korrekt erkannt und war laut `lsblk`-Ausgabe sogar als an `/mnt/extern_backup` gemountet gelistet:

```
[04] Device info:
NAME MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sdc1   8:33   0  3,6T  0 part /mnt/extern_backup
                              /mnt/extern_backup
```

Beachtenswert: Der Mountpoint erscheint **doppelt** – ein klarer Hinweis auf gestapelte (stacked) Mounts.

Segment 05 prüft dann per `findmnt -rn -t ext4 -o SOURCE -M` den tatsächlichen Mount-Zustand und findet:

```
[WARN] ⚠ Wrong device mounted at /mnt/extern_backup
[WARN] Mounted device: /dev/nvme1n1p2[/mnt/extern_backup]
[WARN] Current UUID: <unknown>
[WARN] Expected UUID: f2c4624a-72ee-5e4b-85f8-a0d7f02e702f
```

Hier zeigt sich: `findmnt` sieht nicht `/dev/sdc1`, sondern `/dev/nvme1n1p2` (die Root-Partition) mit einem Bind-Mount-artigen Pfad `[/mnt/extern_backup]`. Das bedeutet, das Root-Dateisystem ist über einen Bind-Mount oder ein Automount-Problem auf `/mnt/extern_backup` eingehängt.

### Eskalation zur Katastrophe

Das Recovery-Verfahren in `safe_unmount()` versucht korrekt, den falschen Mount zu lösen. Da aber das Root-Dateisystem selbst am Mountpoint hängt, blockieren **alle Systemprozesse** das Unmount – insgesamt wurden über 400 Prozesse erkannt, davon 56 als geschützt (systemd, docker, containerd). Die Sicherheitsmechanismen greifen korrekt und verhindern ein Killen dieser Prozesse, was zu einem korrekten Safety-Abort führt.

### Ursache

Die wahrscheinlichste Ursache ist ein **systemd-Automount-Konflikt**. Möglicher Ablauf:

1. Eine `.automount`-Unit für `/mnt/extern_backup` existiert in systemd
2. Beim Systemstart oder durch einen früheren Zugriff wird die Automount-Unit getriggert
3. Das USB-Gerät war zu diesem Zeitpunkt noch nicht verfügbar
4. Systemd erstellt stattdessen einen Bind-Mount vom Root-Dateisystem (Fallback-Verhalten bei fehlendem Gerät mit `nofail`/`x-systemd.automount`)
5. Später wird das USB-Gerät angeschlossen (Shelly schaltet ein), aber der fehlerhafte Mount besteht bereits

Die doppelte Mountpoint-Anzeige in `lsblk` bestätigt diese Theorie: Sowohl der fehlerhafte Root-Bind-Mount als auch der neue sdc1-Mount existieren gestapelt am selben Punkt.

### Bewertung

Dies ist ein **systemd-Konfigurationsproblem**. Die Kombination aus `.automount`-Unit und verzögerter Geräteverfügbarkeit (USB-HDD wird erst per Shelly eingeschaltet) führt zu Race-Conditions und gestapelten Mounts.

---

## 4. Architektur-Überblick: Wo die Probleme liegen

```
┌─────────────────────────────────────────────────────────────┐
│                       main.sh                                │
│                                                              │
│  ┌───────────────────┐                                       │
│  │ PRE-BACKUP        │ ← pre_01 greift auf TARGET_DIR zu    │
│  │ (Profil-spezifisch)│   BEVOR das Laufwerk gemountet ist!  │
│  └────────┬──────────┘                                       │
│           ▼                                                  │
│  ┌───────────────────┐                                       │
│  │ 01-04: Validierung│                                       │
│  │ Logging, Shelly,  │                                       │
│  │ Device-Wait       │                                       │
│  └────────┬──────────┘                                       │
│           ▼                                                  │
│  ┌───────────────────┐                                       │
│  │ 05: Mount Backup  │ ← Mount passiert erst hier!          │
│  │ 06: Validate Mount│   Zu spät für PRE-Segmente           │
│  └────────┬──────────┘                                       │
│           ▼                                                  │
│  ┌───────────────────┐                                       │
│  │ 07-08: Borg Init  │                                       │
│  │ + Backup          │                                       │
│  └───────────────────┘                                       │
└─────────────────────────────────────────────────────────────┘
```

Die zwei Kernprobleme:

1. **Timing-Problem (dev-data):** PRE-Segmente laufen vor dem Mount. Segmente, die auf das Backup-Ziel zugreifen, haben kein gemountetes Dateisystem.

2. **Automount-Problem (system):** Systemd-Automount-Units erzeugen fehlerhafte Mounts, wenn das Gerät zum Trigger-Zeitpunkt nicht verfügbar ist. Bei externer USB-HDD mit Shelly-Steuerung ist das Gerät *absichtlich* erst spät verfügbar.

---

## 5. Lösungsvorschlag

### 5.1 Mount-Segment vor PRE-Segmente verschieben

**Problem:** PRE-Segmente greifen auf TARGET_DIR zu, bevor das Laufwerk gemountet ist.

**Lösung:** Die Segmente 03 (Shelly), 04 (Device-Wait), 05 (Mount) und 06 (Validate) müssen **vor** den PRE-Segmenten ausgeführt werden. Vorgeschlagene neue Reihenfolge in `main.sh`:

```
EARLY_SEGMENTS=(                    # NEU: Hardware + Mount zuerst
  "01_validate_config.sh"
  "02_init_logging.sh"
  "03_shelly_power_on.sh"
  "04_wait_device.sh"
  "05_mount_backup.sh"
  "06_validate_mount.sh"
)

PRE_BACKUP_SEGMENTS=(...)           # Profil-spezifisch, NACH Mount

MAIN_SEGMENTS_PART1=(               # Nur noch Borg-Operationen
  "07_init_borg_repo.sh"
  "08_borg_backup.sh"
)
```

**Begründung:** Die PRE-Segmente (DB-Dump, Docker-Stop) arbeiten logisch mit dem Backup-Ziel. Sie brauchen ein gemountetes, validiertes Dateisystem. Die Hardwaresteuerung (Shelly, Device-Wait, Mount) ist dagegen eine Voraussetzung für alles Weitere und gehört an den Anfang.

**Aufwand:** Gering – nur Umordnung der Arrays in `main.sh`. Keine Änderungen an den Segment-Dateien selbst nötig.

### 5.2 Zusätzliche Validierung in pre_01_nextcloud_db_dump.sh

**Problem:** pre_01 erstellt blind Verzeichnisse auf TARGET_DIR ohne zu prüfen, ob der Pfad auf dem richtigen Dateisystem liegt.

**Lösung:** Am Anfang von pre_01 eine Mount-Validierung einbauen:

```bash
# Validate that TARGET_DIR is on the expected backup filesystem
if [ -n "${BACKUP_UUID:-}" ]; then
  MOUNTED_DEV=$(findmnt -rn -t ext4 -o SOURCE -T "${TARGET_DIR}" 2>/dev/null || echo "")
  if [ -n "$MOUNTED_DEV" ]; then
    MOUNTED_UUID=$(blkid -s UUID -o value "$MOUNTED_DEV" 2>/dev/null || echo "")
    if [ "$MOUNTED_UUID" != "$BACKUP_UUID" ]; then
      echo "[ERROR] TARGET_DIR is NOT on the expected backup device!"
      echo "[ERROR] Expected UUID: $BACKUP_UUID"
      echo "[ERROR] Found UUID: $MOUNTED_UUID"
      exit 1
    fi
  else
    echo "[ERROR] TARGET_DIR is not on any ext4 filesystem"
    exit 1
  fi
fi
```

**Begründung:** Defense-in-Depth. Selbst wenn die Reihenfolge korrekt ist, sollte kein Segment blind auf ein Verzeichnis schreiben, das auf dem falschen Dateisystem liegen könnte. Diese Prüfung verhindert, dass Datenbank-Dumps versehentlich auf der Root-Partition oder einem fehlerhaften Mount landen.

**Aufwand:** Gering – ca. 15 Zeilen zusätzlicher Code in pre_01.

### 5.3 Systemd-Automount durch manuellen Mount ersetzen

**Problem:** Die `.automount`-Unit für `/mnt/extern_backup` triggert bei jedem Dateisystem-Zugriff auf den Mountpoint. Wenn das USB-Gerät nicht verfügbar ist (Shelly aus), erzeugt systemd einen fehlerhaften Fallback-Mount.

**Lösung:** Die Automount-Unit deaktivieren und ausschließlich das Backup-Skript für das Mounten verantwortlich machen:

```bash
# Auf dem Produktivsystem ausführen:
sudo systemctl disable mnt-extern_backup.automount
sudo systemctl stop mnt-extern_backup.automount
sudo systemctl disable mnt-system_backup.automount
sudo systemctl stop mnt-system_backup.automount
```

Die `.mount`-Units können bestehen bleiben (für `mount /mnt/extern_backup` via fstab), aber das automatische Triggern durch `.automount` muss weg.

**Begründung:** Das Backup-System hat ein eigenes Mount-Handling mit UUID-Validierung, Retry-Logik und Fehlerbehandlung (Segment 05). Automount untergräbt diese Kontrolle, indem es unkontrolliert Mounts auslöst. Bei Hardware, die absichtlich zeitverzögert eingeschaltet wird (Shelly), ist Automount kontraproduktiv.

**Aufwand:** Minimal – zwei systemctl-Befehle auf dem Produktivsystem. Keine Code-Änderungen nötig.

### 5.4 Stacked-Mount-Erkennung in Segment 05 verbessern

**Problem:** `lsblk` zeigt den Mountpoint doppelt, aber `findmnt` liefert nur den obersten (fehlerhaften) Mount. Segment 05 erkennt den Stacked Mount nicht explizit.

**Lösung:** Vor der UUID-Prüfung eine Stacked-Mount-Erkennung einbauen:

```bash
# Check for stacked mounts (multiple devices on same mount point)
stacked_count=$(findmnt -rn -o SOURCE -M "${BACKUP_MNT}" 2>/dev/null | wc -l)
if [ "$stacked_count" -gt 1 ]; then
  echo "[ERROR] Stacked mounts detected at ${BACKUP_MNT}!"
  echo "[ERROR] Multiple devices mounted on same point:"
  findmnt -rn -o SOURCE,FSTYPE,OPTIONS -M "${BACKUP_MNT}"
  echo "[ERROR] This is usually caused by systemd automount conflicts."
  echo "[ERROR] Fix: sudo umount -l ${BACKUP_MNT} && sudo mount ${BACKUP_MNT}"
  # Attempt automated recovery: unmount all layers
fi
```

**Begründung:** Stacked Mounts sind ein Symptom des Automount-Problems und können nach Fix 5.3 eigentlich nicht mehr auftreten. Diese Erkennung dient als zusätzliche Sicherheitsebene und liefert bei einem erneuten Auftreten eine klare Diagnose.

**Aufwand:** Gering – ca. 10 Zeilen zusätzlicher Code in Segment 05.

### 5.5 Root-Filesystem-Schutz in safe_unmount()

**Problem:** Wenn das Root-Dateisystem (`/`) am Backup-Mountpoint hängt, versucht `fuser` *alle* Systemprozesse zu analysieren. Das ist extrem langsam (400+ Prozesse im Log) und führt zwangsläufig zum Abort, da systemd, docker etc. naturgemäß auf `/` arbeiten.

**Lösung:** Vor der Prozessanalyse prüfen, ob es sich um das Root-Dateisystem handelt:

```bash
# Before expensive fuser analysis: check if root filesystem is mounted here
local mounted_source
mounted_source=$(findmnt -rn -o SOURCE -M "$mount_point" 2>/dev/null | head -1 || echo "")
local root_source
root_source=$(findmnt -rn -o SOURCE -M "/" 2>/dev/null || echo "")

if [ "$mounted_source" = "$root_source" ]; then
  echo "[ERROR] ROOT FILESYSTEM is mounted at $mount_point!"
  echo "[ERROR] This is a systemd automount misconfiguration."
  echo "[ERROR] Recovery: sudo umount -l $mount_point"
  echo "[ERROR] Skipping process analysis (would list ALL system processes)."
  return 1
fi
```

**Begründung:** Die Prozessanalyse per `fuser` bei einem Root-Filesystem-Mount ist sinnlos und erzeugt nur extrem langes Log-Output (mehrere hundert Zeilen), ohne zu einer Lösung zu führen. Eine Frühzeitige Erkennung spart Zeit und liefert eine klare Fehlermeldung.

**Aufwand:** Gering – ca. 12 Zeilen zusätzlicher Code in `safe_unmount()`.

---

## 6. Priorisierung der Maßnahmen

| Prio | Maßnahme | Aufwand | Wirkung |
|------|----------|---------|---------|
| 1 | **5.3** Automount deaktivieren | Minimal | Beseitigt die Hauptursache des system-Fehlers |
| 2 | **5.1** Mount vor PRE-Segmente | Gering | Beseitigt die Hauptursache des dev-data-Fehlers |
| 3 | **5.5** Root-FS-Schutz | Gering | Verhindert unnötige 400-Zeilen-Prozessliste im Log |
| 4 | **5.2** UUID-Validierung in pre_01 | Gering | Defense-in-Depth für DB-Dump-Segment |
| 5 | **5.4** Stacked-Mount-Erkennung | Gering | Diagnostik-Verbesserung für Zukunft |

Maßnahme 5.3 (Automount deaktivieren) sollte **sofort** umgesetzt werden, da sie ohne Code-Änderungen möglich ist und das dringendste Problem (system-Backup komplett blockiert) löst.

Maßnahme 5.1 (Reihenfolge anpassen) erfordert eine Änderung in `main.sh` und ist der wichtigste Code-Fix. Die Segmente 03–06 bilden logisch eine "Hardware-Bereitstellung" und gehören vor jede profilspezifische Logik.

Die übrigen Maßnahmen (5.2, 5.4, 5.5) sind Härtungen, die das System robuster machen, aber keine akuten Fehler beheben, wenn 5.1 und 5.3 umgesetzt sind.

---

## 7. Sofortmaßnahme (manuell)

Bis zur Code-Änderung kann das system-Backup manuell wiederhergestellt werden:

```bash
# Automount-Units stoppen und deaktivieren
sudo systemctl stop mnt-extern_backup.automount
sudo systemctl disable mnt-extern_backup.automount
sudo systemctl stop mnt-system_backup.automount  
sudo systemctl disable mnt-system_backup.automount

# Ggf. vorhandene Fehl-Mounts bereinigen
sudo umount -l /mnt/extern_backup 2>/dev/null || true
sudo umount -l /mnt/system_backup 2>/dev/null || true

# Systemd neu laden
sudo systemctl daemon-reload

# Backup erneut starten
sudo /opt/backup-system/run-backup.sh system
sudo /opt/backup-system/run-backup.sh dev-data
```
