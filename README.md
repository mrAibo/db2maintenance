# DB2 Maintenance Script

Ein hochoptimiertes und intelligentes Shell-Skript zur Durchführung von routinemässigen Wartungsaufgaben für DB2-Datenbanken.

## Beschreibung

Dieses Skript automatisiert gängige DB2-Wartungsoperationen wie `REORG`, `RUNSTATS` und `REBIND`. Es ist darauf ausgelegt, deutlich performanter und effizienter zu sein als einfache, pauschale Wartungsskripte. Anstatt mehrfach Verbindungen aufzubauen und Befehle auf allen Objekten auszuführen, nutzt es einen Batch-orientierten Ansatz mit intelligenter Objektauswahl, um die Datenbanklast und die Wartungsfenster zu minimieren.

## Hauptmerkmale

- **Effiziente Batch-Verarbeitung**: Verbindet sich nur einmal pro Datenbank und führt alle Befehle für eine Operation (`REORG`, `RUNSTATS`) in einem einzigen Stapel aus, was den Verbindungs- und Befehls-Overhead drastisch reduziert.
- **Intelligente REORG-Selektion**: Verwendet `ADMIN_GET_TAB_INFO`, um Tabellen mit signifikant zurückgewinnbarem Speicherplatz zu identifizieren. Dadurch wird sichergestellt, dass I/O-intensive `REORG`-Operationen nur bei Bedarf durchgeführt werden.
- **Differenzierte RUNSTATS-Strategie**: Passt die `RUNSTATS`-Parameter automatisch an die Tabellengrösse (`CARD`) und den Reorganisationsstatus an. Kleine Tabellen werden gesampelt, während grosse oder kürzlich reorganisierte Tabellen detaillierte Statistiken erhalten.
- **Fokussierter REBIND-Prozess**: Nutzt zuerst `ADMIN_REVALIDATE_DB_OBJECTS` und bindet anschliessend gezielt nur die Pakete neu, die als ungültig (`VALID='N'`) markiert sind, um unnötige Rebinds zu vermeiden.
- **Parallelisierung auf Datenbankebene**: Unterstützt die parallele Ausführung der Wartung über mehrere Datenbanken hinweg (mit dem `--parallel`-Flag), um die Wartung in Umgebungen mit vielen Datenbanken zu beschleunigen.
- **Robuste Systemprüfungen**: Beinhaltet vorgelagerte Prüfungen der Systemressourcen und verfügt über verbesserte, portable Funktionen zur Überwachung der CPU- und Speicherauslastung.
- **Dry-Run-Modus**: Ein umfassender `--dry-run`-Modus ermöglicht es Ihnen, die exakten Befehle anzuzeigen, die ausgeführt würden, ohne Änderungen an der Datenbank vorzunehmen. Dies gewährleistet Sicherheit und Vorhersagbarkeit.

## Voraussetzungen

- `bash` Version 4 oder höher (für die Parallelverarbeitung).
- Ein installierter und konfigurierter `db2`-Kommandozeilen-Client.
- Das `bc`-Kommandozeilen-Dienstprogramm (für numerische Berechnungen).
- `xargs` für die Parallelverarbeitung.

## Verwendung

Das Skript wird über die Kommandozeile ausgeführt.

### Grundlegende Ausführung (Sequentiell)

Führt alle Wartungsschritte (REORG, RUNSTATS, REBIND) sequentiell für alle gefundenen Datenbanken aus.
```bash
./db2maintenance.sh
```

### Dry-Run (Testlauf)

Simuliert einen Lauf und gibt die generierten SQL/DB2-Befehle aus, ohne sie auszuführen. Dies ist der sicherste Weg, das Verhalten des Skripts zu testen.
```bash
./db2maintenance.sh --dry-run
```

### Ausführung für eine bestimmte Datenbank

Führt die Wartung nur für eine einzelne Datenbank durch.
```bash
./db2maintenance.sh --database MYDB
```

### Parallele Ausführung

Führt die Wartung für alle Datenbanken parallel aus. Die Anzahl der parallelen Jobs wird automatisch bestimmt oder kann über die Option `--table-parallel N` festgelegt werden.
```bash
./db2maintenance.sh --parallel
```

### Überspringen von Operationen

Sie können bestimmte Wartungsschritte überspringen.
```bash
./db2maintenance.sh --skip-reorg --skip-rebind
```

### Filtern von Tabellen

Wendet die Wartung nur auf Tabellen an, die einem bestimmten Filter entsprechen.
```bash
./db2maintenance.sh --database MYDB --table-filter 'ICMADMIN.%'
```

## Konfiguration

Bei der ersten Ausführung erstellt das Skript eine Standard-Konfigurationsdatei unter `~/.db2_maintenance/config.ini`. Diese Datei ermöglicht es Ihnen, verschiedene Parameter anzupassen, wie z.B.:
- Schwellenwerte für Tabellengrössen (`large_table_threshold`, `small_table_threshold`).
- `RUNSTATS`-Sampling-Raten.
- Ressourcengrenzwerte.
