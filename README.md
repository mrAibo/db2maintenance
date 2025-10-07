# DB2 Maintenance Script

Ein robustes Bash-Skript zur automatisierten und optimierten Wartung von DB2-Datenbanken. Es unterstützt die parallele Ausführung von `REORG`- und `RUNSTATS`-Operationen, um die Wartung großer Datenbanken effizient zu gestalten.

## Inhaltsverzeichnis

- [Vorteile gegenüber der DB2 Standardwartung](#vorteile-gegenüber-der-db2-standardwartung)
- [Voraussetzungen](#voraussetzungen)
- [Installation](#installation)
- [Konfiguration](#konfiguration)
- [Verwendung](#verwendung)
- [Optionen](#optionen)
- [Beispiele](#beispiele)
- [Automatisierung mit Cron](#automatisierung-mit-cron)
- [Logging und Historie](#logging-und-historie)
- [Fehlersuche](#fehlersuche)
- [Mitwirkende](#Autor)
- [Lizenz](#lizenz)

## Vorteile gegenüber der DB2 Standardwartung

Die in DB2 integrierte, automatische Wartung (`AUTO_MAINT`) ist für allgemeine Fälle konzipiert, stößt aber in komplexen oder leistungs kritischen Umgebungen an ihre Grenzen. Dieses Skript bietet entscheidende Vorteile:

| Merkmal | DB2 Standardwartung (`AUTO_MAINT`) | `db2maintenance.sh` Skript |
| :--- | :--- | :--- |
| **Parallelität** | Sehr begrenzt. Operationen werden oft sequenziell ausgeführt, was bei großen Datenbanken zu extrem langen Wartungszeiten führt. | **Volle Kontrolle über Parallelität.** `REORG` und `RUNSTATS` können auf mehreren Tabellen gleichzeitig laufen, was die Wartungszeit um den Faktor der eingestellten Parallelität verkürzt. |
| **Kontrolle & Flexibilität** | "Black Box". Die genaue Auswahl der Tabellen und der Zeitpunkt der Ausführung sind kaum steuerbar. | **Volle Transparenz und Kontrolle.** Sie definieren genau, welche Datenbanken gewartet werden, wann die Wartung läuft und welche Tabellen einbezogen werden. |
| **Intelligente Auswahl** | Basierend auf festen, internen Heuristiken. Kann ineffizient sein, indem es entweder zu viele oder zu wenige Tabellen für einen `REORG` auswählt. | **Intelligente und anpassbare Kandidatenauswahl.** Das Skript kann Tabellen basierend auf detaillierteren Regeln auswählen und bietet einen **Force-Modus**, um gezielt alle Tabellen zu reorganisieren. |
| **Ressourcenmanagement** | DB2 versucht, die Last zu steuern, hat aber keine feingranulare Kontrolle über die maximale Anzahl paralleler Operationen. | **Proaktives Ressourcenmanagement.** Das Skript kann die Parallelität automatisch reduzieren, wenn die geschätzte Gesamtgröße der Operationen einen Schwellenwert überschreitet, um die Systemlast zu begrenzen. |
| **Nachvollziehbarkeit** | Logs sind oft schwer zu interpretieren und über verschiedene DB2-Log-Dateien verstreut. | **Zentrales, detailliertes Logging.** Jede Operation wird in einer klar benannten Log-Datei protokolliert, was die Fehlersuche und Überwachung enorm vereinfacht. |
| **Erweiterbarkeit** | Nicht erweiterbar. Sie sind an die von IBM bereitgestellte Funktionalität gebunden. | **Vollständig anpassbar.** Das Skript kann leicht erweitert werden, um benutzerdefinierte Logik, zusätzliche Prüfungen (z.B. `PCTFREE`-Analyse) oder Integrationen in andere Systeme hinzuzufügen. |

### Standardwartung von DB2 deaktivieren

Um Konflikte zu vermeiden und die volle Kontrolle zu erlangen, wird dringend empfohlen, die automatische Wartung für die Datenbanken zu deaktivieren, die mit diesem Skript verwaltet werden.

Führen Sie folgende Befehle für jede relevante Datenbank aus:

```bash
# Mit der Datenbank verbinden
db2 connect to IHRE_DATENBANK

# Automatische Wartung vollständig deaktivieren
db2 update db cfg using AUTO_MAINT OFF
db2 update db cfg using AUTO_TBL_MAINT OFF
db2 update db cfg using AUTO_RUNSTATS OFF
db2 update db cfg using AUTO_REORG OFF

# Verbindung trennen
db2 connect reset
```

**Überprüfen der Einstellungen:**
```bash
db2 get db cfg for IHRE_DATENBANK | grep -i auto
```
Stellen Sie sicher, dass alle `AUTO_*`-Parameter auf `OFF` stehen.

## Voraussetzungen

- Ein Linux- oder UNIX-ähnliches Betriebssystem
- DB2-Datenbankserver mit den Kommandozeilenwerkzeugen (`db2`, `db2batch`)
- Bash-Shell (Version 4.0 oder höher)
- Standard-Unix-Werkzeuge: `awk`, `grep`, `wc`, `mktemp`, `tput`, `bc`

## Installation

1.  Klonen Sie dieses Repository auf Ihren Server:
    ```bash
    git clone https://github.com/mrAibo/db2maintenance.git
    cd [PROJEKT_ORDNER]
    ```

2.  Machen Sie das Skript ausführbar:
    ```bash
    chmod +x db2maintenance.sh
    ```

3.  Kopieren Sie die Beispielkonfigurationsdatei und passen Sie sie an:
    ```bash
    cp config.example.conf config.conf
    # Bearbeiten Sie config.conf mit Ihrem bevorzugten Editor
    ```

## Konfiguration

Das Skript wird über die Datei `config.conf` im selben Verzeichnis gesteuert. Jede Einstellung ist dort kommentiert.

**Wichtige Konfigurationsparameter:**

- `[db.databases]`: Eine durch Leerzeichen getrennte Liste der Datenbanken, die gewartet werden sollen.
- `[general.max_total_reorg_pages]`: Schwellenwert für die Gesamtzahl der Seiten, um die Parallelität bei sehr großen REORGs automatisch zu reduzieren.
- `[runstats.initial_light]`: Setzen Sie auf `true`, um vor dem REORG einen schnellen RUNSTATS-Lauf durchzuführen.
- `[runstats.full_after_reorg]`: Setzen Sie auf `true`, um nach dem REORG einen vollständigen RUNSTATS-Lauf durchzuführen.
- `[runstats.flush_package_cache]`: Setzen Sie auf `true`, um den Paket-Cache nach RUNSTATS zu leeren.

## Verwendung

### Grundlegende Verwendung

Führen Sie das Skript einfach ohne Parameter aus, um die Wartung für alle in `config.conf` definierten Datenbanken durchzuführen:

```bash
./db2maintenance.sh
```

### Optionen

- `-h, --help`: Zeigt die Hilfeseite an und beendet das Skript.
- `-f, --force`: Aktiviert den Force-Modus. Erzwingt REORG für **alle** Tabellen, unabhängig von den Statistiken.
- `-s, --skip-reorg`: Überspringt den REORG-Schritt vollständig.
- `-r, --skip-runstats`: Überspringt alle RUNSTATS-Schritte.
- `-b, --skip-rebind`: Überspringt den REVALIDATE/REBIND-Schritt am Ende.
- `-d, --databases "DB1 DB2"`: Führt die Wartung nur für die angegebenen Datenbanken durch.

## Beispiele

**1. Normale Wartung für alle konfigurierten Datenbanken:**
```bash
./db2maintenance.sh
```

**2. Wartung im Force-Modus für alle Datenbanken:**
```bash
./db2maintenance.sh --force
```

**3. Wartung nur für die Datenbanken `PROD_DB` und `TEST_DB`, aber REORG überspringen:**
```bash
./db2maintenance.sh --databases "PROD_DB TEST_DB" --skip-reorg
```

## Automatisierung mit Cron

Um die Wartung regelmäßig auszuführen, können Sie einen Cron-Job einrichten.

1.  Öffnen Sie die Crontab für den Benutzer, unter dem das Skript laufen soll (z.B. `db2inst1`):
    ```bash
    crontab -e
    ```

2.  Fügen Sie eine neue Zeile hinzu, um das Skript zu einem gewünschten Zeitpunkt auszuführen. Hier sind einige Beispiele:

    **Beispiel 1: Jeden Sonntag um 02:00 Uhr morgens**
    ```crontab
    0 2 * * 0 /pfad/zu/ihrem/skript/db2maintenance.sh >> /pfad/zu/ihrem/skript/logs/cron.log 2>&1
    ```

    **Beispiel 2: Jeden Werktag um 03:30 Uhr morgens**
    ```crontab
    30 3 * * 1-5 /pfad/zu/ihrem/skript/db2maintenance.sh >> /pfad/zu/ihrem/skript/logs/cron.log 2>&1
    ```

3.  Speichern und schließen Sie die Datei.

**Wichtige Hinweise für den Cron-Job:**

- **Absolute Pfade verwenden**: Cron hat eine sehr minimale Umgebungsvariable `PATH`. Geben Sie daher immer den vollständigen Pfad zum Skript an.
- **Umgebungsvariablen**: Das Skript benötigt möglicherweise DB2-spezifische Umgebungsvariablen (wie `DB2INSTANCE`). Wenn das Skript als der DB2-Instanzbenutzer ausgeführt wird, ist dies in der Regel kein Problem. Andernfalls müssen Sie diese eventuell im Skript selbst laden (z.B. durch Sourcing der `db2profile`).
- **Logging**: Es ist eine gute Praxis, die Ausgabe des Cron-Jobs in eine separate Log-Datei umzuleiten (`>> ... 2>&1`), um bei Fehlern die E-Mails von Cron zu überprüfen oder diese Log-Datei direkt zu betrachten.

## Logging und Historie

Das Skript erstellt ein detailliertes Log für jede Datenbank und jeden Vorgang im Verzeichnis, das in der Konfiguration unter `[paths.log_dir]` festgelegt ist (Standard: `logs`).

Die Log-Dateien folgen dem Namensschema:
`[DATENBANKNAME].[ZEITSTEMPEL].[VORGANG].log`

Beispiel: `PROD_DB.2023-10-27_15-30-00.reorg.log`

Wenn in der Konfiguration `[general.enable_history]` auf `true` gesetzt ist, wird zusätzlich eine JSON-Datei im `history`-Verzeichnis erstellt.

## Fehlersuche

**Der Spinner wird nicht angezeigt:**
Dies liegt meist daran, dass der Hintergrundprozess Ausgaben erzeugt, die mit dem Spinner kollidieren. Das Skript leitet diese Ausgaben bereits um (`> /dev/null 2>&1`).

**Ein Prozess schlägt fehl:**
Überprüfen Sie immer die entsprechende Log-Datei im `logs`-Verzeichnis. Sie enthält die genaue Fehlermeldung von DB2.

**Das Skript bricht mit "Permission denied" ab:**
Stellen Sie sicher, dass das Skript ausführbar ist (`chmod +x db2maintenance.sh`) und der Benutzer die notwendigen Berechtigungen hat.

## Autor

- [Voronin Aleksej](https://github.com/mrAibo/) - Hauptentwickler

## Lizenz

Dieses Projekt ist unter der MIT License lizenziert.
