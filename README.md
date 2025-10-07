# DB2 Wartungsskript (db2_maintenance.sh)

Automatisiertes und anpassbares Bash-Skript zur DB2-Datenbankwartung (REORG, RUNSTATS, REBIND) mit parallelisiertem Workflow, Logging und Konfigurationsprofilen.

## Features

- **Automatische REORG, RUNSTATS und REBIND** für alle oder spezifische Tabellen
- **Parallele Verarbeitung** von Datenbanken und Tabellen für hohe Performance
- **Adaptive Batch-Größen und Parallellisierung** basierend auf Systemressourcen und Konfiguration
- **Konfigurierbare Wartungsprofile** (quick, thorough, minimal) über INI-Datei
- **Detailliertes Logging** im gesicherten Log-Verzeichnis
- **Systemchecks** auf CPU, RAM und Diskspace (optional)
- **Force-Modus** für vollständige Wartung ohne Checks
- **Dry-Run/Testmodus** zur gefahrlosen Analyse
- **Interaktiver Modus** für manuelle Auswahl und sichere Durchführung
- **Tabellenfilter & Priorisierung** bei der Verarbeitung
- **Automatisierte Historie** der Laufdaten je Datenbank

## Voraussetzungen

- IBM DB2 ab Version 11.x (getestet auf LUW)
- Bash ab Version 4.x
- Standard-Unix-Tools: awk, grep, sed, bc, tput, nproc, free
- Ausführbare DB2-CLI (`db2`) im Pfad
- Der Nutzer muss als DB2-Instance-Owner (z.B. `db2icm`) laufen

## Installation

1. Kopieren Sie das Skript ins gewünschte Verzeichnis, z.B. `~/bin/`
2. Setzen Sie die Rechte:
chmod +x db2_maintenance.sh
3. Erstellen Sie das Konfigurationsverzeichnis (wird typischerweise beim ersten Aufruf automatisch angelegt):
mkdir -p ~/.db2_maintenance

## Nutzung

db2_maintenance.sh [OPTIONS]

### Häufige Optionen:
- `--database DB` nur eine spezifische Datenbank bearbeiten
- `--dry-run` Simulation ohne echte Änderungen
- `--parallel` parallele Verarbeitung mehrerer Datenbanken
- `--table-parallel N` parallele Verarbeitung von N Tabellen
- `--batch-size N` Batch-Größe für Operations
- `--reorg-only` nur REORG durchführen
- `--runstats-only` nur RUNSTATS durchführen
- `--rebind-only` nur REBIND durchführen
- `--skip-reorg` REORG überspringen
- `--skip-runstats` RUNSTATS überspringen
- `--skip-rebind` REBIND überspringen
- `--force` erzwingt REORG, RUNSTATS und REBIND für alle Tabellen
- `--config-file FILE` spezifische Konfigurationsdatei verwenden
- `--profile PROFILE` Profile (quick, thorough, minimal)
- `--interactive` Start im dialogischen Modus

Weitere Optionen im Skript oder Hilfe anzeigen via:
db2_maintenance.sh --help


## Logging & Historie

- Pro Datenbanklauf werden Logdateien und eine JSON-Historie im Verzeichnis `$LOG_DIR`/`$HISTORY_DIR` erstellt.
- Fehler, Fortschritt und kritische Hinweise werden farbcodiert auf die Konsole und ins Log geschrieben.

## Sicherheit

- Logs und Konfigurationsdateien werden mit Modus 700 vor Fremdzugriff geschützt
- SQL-Injection-Prävention bei Tabellennamen und -schemata
- Keine DB-Passwörter im Skript, alles via DB2-Umgebung

## Hinweise

- Das Skript ist für produktive Umgebungen optimiert, sollte aber immer zunächst im `--dry-run` Modus getestet werden.
- Bei großen Datenbanken und vielen Tabellen empfiehlt sich die Parallelisierung und adaptive Batch-Größen.

## Autor & Lizenz

- **Autor:** Aleksej Voronin.
- **Version:** 7.1.0 (13.08.2025)
- Lizensierung: MIT (frei verwendbar mit Hinweis auf den Autor)

## Kontakt & Support

Für Feedback, Fehler oder Verbesserungswünsche bitte Issues auf GitHub anlegen.

---

**Enjoy automated DB2 maintenance!**
