#!/bin/bash
# ***********************************************************************
# Programname   : arge_db2_maintenance.sh                              *
#                                                                       *
# Description   : DB2 Pflege nach einem DB2 Upgrade                     *
#                                                                       *
# Author        : A. V                                                  *
# Version       : 6.0.0 31.07.2025                                     *
#***********************************************************************
SCRIPT_USER="db2icm"
LOG_DIR="$HOME/db2_wartung_log"
CONFIG_DIR="$HOME/.db2_maintenance"
HISTORY_DIR="$HOME/.db2_maintenance/history"
TS=$(date +"%y%m%d_%H%M")  # Erweiterter Timestamp mit Uhrzeit (CEST: 31.07.2025, 14:00)

# Farbige Ausgaben (verbessert)
cecho() {
    local color="$1"
    local msg="$2"
    local color_code=""
    local color_reset=$(tput sgr0)
    case "$color" in
        BRED)    color_code=$(tput setaf 1 && tput bold) ;;
        BGREEN)  color_code=$(tput setaf 2 && tput bold) ;;
        BYELLOW) color_code=$(tput setaf 3 && tput bold) ;;
        BCYAN)   color_code=$(tput setaf 6 && tput bold) ;;
        RED)     color_code=$(tput setaf 1) ;;
        GREEN)   color_code=$(tput setaf 2) ;;
        *)       color_code="" ;;
    esac
    printf "%s%s%s\n" "${color_code}" "${msg}" "${color_reset}"
}

# Help function
show_help() {
    cecho BGREEN "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --help                     Show this help"
    echo "  --database DB              Process only a specific database (e.g. --database MYDB)"
    echo "  --dry-run                 Simulate execution without actual DB changes"
    echo "  --parallel                Parallel processing of multiple databases (requires 'parallel' tool)"
    echo "  --table-parallel N        Parallel processing of tables (default: auto)"
    echo "  --batch-size N            Batch size for operations (default: auto)"
    echo "  --reorg-only              Execute only REORG"
    echo "  --runstats-only           Execute only RUNSTATS"
    echo "  --rebind-only             Execute only REBIND"
    echo "  --skip-reorg              Skip REORG step"
    echo "  --skip-runstats           Skip RUNSTATS step"
    echo "  --skip-rebind             Skip REBIND step"
    echo "  --table-priority P        Table priority: low, medium, high (default: medium)"
    echo "  --table-filter F          Filter for table names (e.g. 'ICMADMIN.%')"
    echo "  --check-resources         Check system resources before start"
    echo "  --auto-config             Automatic configuration of all parameters (default)"
    echo "  --config-file F           Use specific configuration file"
    echo "  --profile P               Use specific profile (quick, thorough, minimal)"
    echo "  --interactive             Interactive mode"
    echo "  --resume                 Resume interrupted maintenance"
    echo "  --test-mode              Test mode - show only what would be done"
    echo "  --progress                Show detailed progress display"
    echo "  --force                   Force REORG, RUNSTATS and REBIND for all tables without prior check"
    exit 0
}

# Default configuration
DEFAULT_CONFIG=$(cat << 'EOF'
# DB2 Maintenance Configuration
[general]
auto_config = true
check_resources = true
parallel_databases = true
max_table_parallel = 8
default_batch_size = 20
min_batch_size = 5
max_batch_size = 50
adaptive_batch_size = true
monitor_system_load = true
load_check_interval = 30
max_cpu_load = 80
max_memory_usage = 80
max_io_load = 80
log_level = info
enable_history = true
history_retention_days = 30

[reorg]
enable = true
check_overflow = true
overflow_threshold = 5
check_deleted_rows = true
deleted_rows_threshold = 10
check_stats_time = true
stats_time_threshold_days = 30
async_operations = true
max_async_operations = 4

[runstats]
enable = true
detailed_stats_large_tables = true
large_table_threshold = 1000000
sample_small_tables = true
small_table_threshold = 100000
sample_rate = 10
async_operations = true
max_async_operations = 4

[rebind]
enable = true
rebind_invalid_only = true
async_operations = true
max_async_operations = 4

[priorities]
# Table priority based on various factors
size_weight = 0.3
access_weight = 0.4
overflow_weight = 0.2
stats_age_weight = 0.1

[profiles]
# Profiles for different maintenance scenarios
quick = {
    parallel_databases = true
    max_table_parallel = 8
    adaptive_batch_size = true
    min_batch_size = 10
    max_batch_size = 50
    reorg_check_overflow = true
    reorg_check_deleted_rows = false
    reorg_check_stats_time = false
    runstats_detailed_stats_large_tables = true
    runstats_sample_small_tables = true
    runstats_sample_rate = 5
}

thorough = {
    parallel_databases = true
    max_table_parallel = 4
    adaptive_batch_size = true
    min_batch_size = 5
    max_batch_size = 20
    reorg_check_overflow = true
    reorg_check_deleted_rows = true
    reorg_check_stats_time = true
    runstats_detailed_stats_large_tables = true
    runstats_sample_small_tables = false
}

minimal = {
    parallel_databases = false
    max_table_parallel = 2
    adaptive_batch_size = true
    min_batch_size = 5
    max_batch_size = 10
    reorg_check_overflow = true
    reorg_check_deleted_rows = false
    reorg_check_stats_time = false
    runstats_detailed_stats_large_tables = false
    runstats_sample_small_tables = true
    runstats_sample_rate = 20
}
EOF
)

# Argumente parsen
DRY_RUN=0
PARALLEL=0
TABLE_PARALLEL="auto"
BATCH_SIZE="auto"
SPECIFIC_DB=""
SKIP_REORG=0
SKIP_RUNSTATS=0
SKIP_REBIND=0
REORG_ONLY=0
RUNSTATS_ONLY=0
REBIND_ONLY=0
TABLE_PRIORITY="medium"
TABLE_FILTER=""
CHECK_RESOURCES=0
AUTO_CONFIG=1
CONFIG_FILE=""
PROFILE=""
INTERACTIVE=0
RESUME=0
TEST_MODE=0
PROGRESS=0
FORCE_MODE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --help) show_help ;;
        --dry-run) DRY_RUN=1 ;;
        --parallel) PARALLEL=1 ;;
        --database) SPECIFIC_DB="$2"; shift ;;
        --table-parallel) TABLE_PARALLEL="$2"; shift ;;
        --batch-size) BATCH_SIZE="$2"; shift ;;
        --skip-reorg) SKIP_REORG=1 ;;
        --skip-runstats) SKIP_RUNSTATS=1 ;;
        --skip-rebind) SKIP_REBIND=1 ;;
        --reorg-only) REORG_ONLY=1 ;;
        --runstats-only) RUNSTATS_ONLY=1 ;;
        --rebind-only) REBIND_ONLY=1 ;;
        --table-priority) TABLE_PRIORITY="$2"; shift ;;
        --table-filter) TABLE_FILTER="$2"; shift ;;
        --check-resources) CHECK_RESOURCES=1 ;;
        --auto-config) AUTO_CONFIG=1 ;;
        --no-auto-config) AUTO_CONFIG=0 ;;
        --config-file) CONFIG_FILE="$2"; shift ;;
        --profile) PROFILE="$2"; shift ;;
        --interactive) INTERACTIVE=1 ;;
        --resume) RESUME=1 ;;
        --test-mode) TEST_MODE=1 ;;
        --progress) PROGRESS=1 ;;
        --force) FORCE_MODE=1 ;;
        *) cecho RED "Unbekannte Option: $1"; show_help ;;
    esac
    shift
done

# Exklusive Optionen prÃ¼fen
if [ $REORG_ONLY -eq 1 ]; then
    SKIP_RUNSTATS=1
    SKIP_REBIND=1
fi
if [ $RUNSTATS_ONLY -eq 1 ]; then
    SKIP_REORG=1
    SKIP_REBIND=1
fi
if [ $REBIND_ONLY -eq 1 ]; then
    SKIP_REORG=1
    SKIP_RUNSTATS=1
fi

# Benutzer prÃ¼fen
if [ "${USER}" != "${SCRIPT_USER}" ]; then
    cecho RED "Benutzer muss ${SCRIPT_USER} sein, um das Skript auszufÃ¼hren..."
    exit 1
fi

# Verzeichnisse erstellen
mkdir -p "$LOG_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "$HISTORY_DIR"

# Standard-Konfigurationsdatei erstellen, falls nicht vorhanden
if [ ! -f "$CONFIG_DIR/config.ini" ]; then
    echo "$DEFAULT_CONFIG" > "$CONFIG_DIR/config.ini"
    cecho BCYAN "Standard-Konfigurationsdatei erstellt: $CONFIG_DIR/config.ini"
fi

# Konfigurationsdatei laden
load_config() {
    local config_file="$1"
    local section=""
    
    while IFS= read -r line; do
        # Kommentare und leere Zeilen Ã¼berspringen
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        # Sektionsheader erkennen
        if [[ "$line" =~ ^\[([^\]]+)\] ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi
        
        # SchlÃ¼ssel-Wert-Paare verarbeiten
        if [[ "$line" =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            local key="${BASH_REMATCH[1]// /}"
            local value="${BASH_REMATCH[2]}"
            
            # Entferne fÃ¼hrende/nachfolgende Leerzeichen vom Wert
            value=$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            
            # Speichere in assoziativem Array
            config["${section}.${key}"]="$value"
        fi
    done < "$config_file"
}

# Lade Konfiguration
declare -A config
if [ -n "$CONFIG_FILE" ]; then
    if [ -f "$CONFIG_FILE" ]; then
        load_config "$CONFIG_FILE"
        cecho BCYAN "Konfiguration geladen von: $CONFIG_FILE"
    else
        cecho RED "Konfigurationsdatei nicht gefunden: $CONFIG_FILE"
        exit 1
    fi
else
    load_config "$CONFIG_DIR/config.ini"
fi

# Profil anwenden, falls angegeben
if [ -n "$PROFILE" ]; then
    if [[ -v "config[profiles.$PROFILE]" ]]; then
        cecho BCYAN "Verwende Profil: $PROFILE"
        # Hier wÃ¼rde die Profilkonfiguration angewendet werden
        # In einer vollstÃ¤ndigen Implementierung wÃ¼rde dies die Standardkonfiguration Ã¼berschreiben
    else
        cecho RED "Profil nicht gefunden: $PROFILE"
        exit 1
    fi
fi

# Temp-Verzeichnis
TMP_DIR=$(mktemp -d -p /tmp db2_maintenance.XXXXXX) || { cecho RED "Fehler beim Erstellen des Temp-Verzeichnisses"; exit 1; }
trap 'rm -rf "$TMP_DIR"' EXIT

# Funktion zur sprachunabhängigen CPU-Auslastungsermittlung
get_cpu_usage() {
    # Stellt sicher, dass die Ausgabe von Tools sprachunabhängig ist
    export LC_ALL=C
    if command -v mpstat >/dev/null 2>&1; then
        # mpstat 1 1: 1 Sekunde Intervall, 1 Mal ausführen
        # awk sucht nach der Zeile "Average" und druckt 100 minus der letzten Spalte (%idle)
        mpstat 1 1 | awk '/Average:|Durchschnitt:/{print 100 - $NF}'
    else
        # Fallback zu /proc/stat, wenn mpstat nicht verfügbar ist
        local stat1=($(head -n1 /proc/stat))
        sleep 1
        local stat2=($(head -n1 /proc/stat))

        local user_diff=$((stat2[1] - stat1[1]))
        local nice_diff=$((stat2[2] - stat1[2]))
        local system_diff=$((stat2[3] - stat1[3]))
        local idle_diff=$((stat2[4] - stat1[4]))

        local total_diff=$((user_diff + nice_diff + system_diff + idle_diff))
        if [ $total_diff -eq 0 ]; then
            echo 0
        else
            echo $((100 * (total_diff - idle_diff) / total_diff))
        fi
    fi
}

# Funktion zur automatischen Konfiguration
auto_configure() {
    cecho BYELLOW "Führe automatische Konfiguration durch..."

    NUM_CORES=$(nproc)
    cecho BCYAN "Erkannte CPU-Kerne: $NUM_CORES"

    # free -m für präzisere Werte in MB statt gerundeten GB
    FREE_MEM_MB=$(free -m | awk '/Mem:/ {print $7}')
    cecho BCYAN "Freier Speicher: ${FREE_MEM_MB}MB"

    CPU_USAGE=$(get_cpu_usage)
    cecho BCYAN "CPU-Auslastung: ${CPU_USAGE}%"

    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    cecho BCYAN "Festplattenspeicher: ${DISK_USAGE}% verwendet"

    if [ "$TABLE_PARALLEL" = "auto" ]; then
        TABLE_PARALLEL=$NUM_CORES
        local max_parallel=${config[general.max_table_parallel]:-4}
        if [ "$TABLE_PARALLEL" -gt "$max_parallel" ]; then
            TABLE_PARALLEL=$max_parallel
        fi
        if (( $(echo "$CPU_USAGE > 80" | bc -l) )); then
            TABLE_PARALLEL=$((TABLE_PARALLEL / 2))
        fi
        if [ "$FREE_MEM_MB" -lt 4000 ]; then # 4GB
            TABLE_PARALLEL=$((TABLE_PARALLEL / 2))
        fi
        [ $TABLE_PARALLEL -lt 1 ] && TABLE_PARALLEL=1
    fi
    
    if [ "$BATCH_SIZE" = "auto" ]; then
        BATCH_SIZE=${config[general.default_batch_size]:-20}
    fi

    cecho BGREEN "Automatische Konfiguration abgeschlossen:"
    cecho BGREEN "  - Tabellen-Parallelität: $TABLE_PARALLEL"
    cecho BGREEN "  - Batch-Größe: $BATCH_SIZE"
}

# Systemressourcen prüfen
check_system_resources() {
    cecho BYELLOW "Prüfe Systemressourcen..."
    
    FREE_MEM_MB=$(free -m | awk '/Mem:/ {print $7}')
    if [ "$FREE_MEM_MB" -lt 1024 ]; then
        cecho RED "Nicht genügend freier Speicher: ${FREE_MEM_MB}MB (mindestens 1GB erforderlich)"
        exit 1
    fi
    cecho GREEN "Freier Speicher: ${FREE_MEM_MB}MB"

    CPU_USAGE=$(get_cpu_usage)
    if (( $(echo "$CPU_USAGE > 95" | bc -l) )); then
        cecho RED "CPU-Auslastung zu hoch: ${CPU_USAGE}%"
        exit 1
    fi
    cecho GREEN "CPU-Auslastung: ${CPU_USAGE}%"

    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -gt 95 ]; then
        cecho RED "Festplattenspeicher zu voll: ${DISK_USAGE}%"
        exit 1
    fi
    cecho GREEN "Festplattenspeicher: ${DISK_USAGE}% verwendet"
}

# Führt ein generiertes SQL/CMD-Skript aus oder zeigt es im Dry-Run-Modus an
execute_script() {
    local db="$1"
    local script_file="$2"
    local operation_name="$3"
    local log_file="$4"

    if [ ! -s "$script_file" ]; then
        cecho YELLOW "Keine Befehle für $operation_name in $db gefunden. Überspringe."
        return
    fi
    
    cecho BYELLOW "Starte $operation_name für $db..."
    
    if [ $DRY_RUN -eq 1 ]; then
        cecho BCYAN "--- Dry-Run: $operation_name Skript für $db ---"
        cat "$script_file"
        cecho BCYAN "--- Ende Dry-Run ---"
    else
        {
            echo "=== $operation_name Start: $(date) ==="
            db2 -tvf "$script_file"
            echo "=== $operation_name Ende: $(date) ==="
        } >> "$log_file" 2>&1
        cecho BGREEN "$operation_name für $db abgeschlossen."
    fi
}

# Hauptfunktion für die Datenbankverarbeitung (NEU & OPTIMIERT)
process_database() {
    local db="$1"
    local log_prefix="${LOG_DIR}/${db}.${TS}"

    cecho BYELLOW "====================="
    cecho BYELLOW "Wartung für $db..."
    cecho BYELLOW "====================="

    if [ $DRY_RUN -eq 0 ]; then
        if ! db2 connect to "$db" > "${log_prefix}.connect.log" 2>&1; then
            cecho RED "Fehler: Konnte keine Verbindung zu $db herstellen. Siehe ${log_prefix}.connect.log"
            return 1
        fi
    else
        cecho BCYAN "Dry-Run: Würde Verbindung zu $db herstellen."
    fi

    # --- Tabelleninformationen sammeln ---
    cecho BCYAN "Sammle Tabelleninformationen (Größe, etc.)..."
    local all_tables_info_file="$TMP_DIR/tables_info_${db}.txt"
    local all_tables_list_file="$TMP_DIR/tables_list_${db}.txt"
    
    local filter_clause=""
    if [ -n "$TABLE_FILTER" ]; then
        local schema_filter="${TABLE_FILTER%%.*}"
        local table_filter="${TABLE_FILTER#*.}"
        if [ "$schema_filter" != "$table_filter" ]; then
            filter_clause="AND T.TABSCHEMA = '${schema_filter}' AND T.TABNAME LIKE '${table_filter}'"
        else
            filter_clause="AND T.TABNAME LIKE '${TABLE_FILTER}'"
        fi
    fi

    local tables_query="SELECT RTRIM(T.TABSCHEMA), RTRIM(T.TABNAME), T.CARD, T.NPAGES, T.FPAGES FROM SYSCAT.TABLES T WHERE T.TYPE = 'T' AND T.TABSCHEMA NOT LIKE 'SYS%' ${filter_clause} WITH UR"
    
    if [ $DRY_RUN -eq 0 ]; then
        db2 -x "$tables_query" | awk '{printf "%s.%s %d %d %d\n", $1, $2, $3, $4, $5}' > "$all_tables_info_file"
        awk '{print $1}' "$all_tables_info_file" > "$all_tables_list_file"
    else
        # Im Dry-Run Modus mit Beispieldaten arbeiten
        cecho BCYAN "Dry-Run: Generiere Beispieldaten für Tabellen."
        cat << EOF > "$all_tables_info_file"
SCHEMA1.TABLE1 10000 100 10
SCHEMA1.TABLE2 5000000 5000 4500
SCHEMA2.TABLE3 200 5 1
EOF
        awk '{print $1}' "$all_tables_info_file" > "$all_tables_list_file"
    fi
    
    local total_tables=$(wc -l < "$all_tables_list_file")
    if [ "$total_tables" -eq 0 ]; then
        cecho YELLOW "Keine Tabellen in $db gefunden, die dem Filter entsprechen. Überspringe..."
        [ $DRY_RUN -eq 0 ] && db2 connect reset > /dev/null
        return 0
    fi
    cecho BCYAN "Verarbeite $total_tables Tabellen in $db"

    # --- REORG ---
    local reorg_script="$TMP_DIR/reorg_${db}.sql"
    local reorged_tables_list="$TMP_DIR/reorged_tables_${db}.txt"
    if [ $SKIP_REORG -eq 0 ]; then
        cecho BCYAN "Ermittle Tabellen, die eine Reorganisation benötigen..."
        if [ $FORCE_MODE -eq 1 ]; then
            cecho BYELLOW "Force-Modus: REORG für alle Tabellen geplant."
            cp "$all_tables_list_file" "$reorged_tables_list"
        else
            # Intelligente Selektion mit ADMIN_GET_TAB_INFO
            # Diese Abfrage ist ein Beispiel und muss ggf. angepasst werden
            local reorg_check_query="SELECT TABSCHEMA, TABNAME FROM TABLE(SYSPROC.ADMIN_GET_TAB_INFO(NULL, NULL)) WHERE RECLAIMABLE_SPACE > 1024 * 1024 * 100" # >100MB
            if [ $DRY_RUN -eq 0 ]; then
                 db2 -x "$reorg_check_query" | awk '{print $1"."$2}' > "$reorged_tables_list"
            else
                cecho BCYAN "Dry-Run: Simuliere REORG-Prüfung. Wähle 1 Tabelle für REORG aus."
                head -n 1 "$all_tables_list_file" > "$reorged_tables_list"
            fi
        fi
        
        while IFS= read -r table; do
            echo "REORG TABLE $table INPLACE ALLOW WRITE ACCESS;" >> "$reorg_script"
        done < "$reorged_tables_list"
        execute_script "$db" "$reorg_script" "REORG" "${log_prefix}.reorg.log"
    else
        cecho YELLOW "REORG für $db übersprungen."
    fi

    # --- RUNSTATS ---
    local runstats_script="$TMP_DIR/runstats_${db}.sql"
    if [ $SKIP_RUNSTATS -eq 0 ]; then
        cecho BCYAN "Generiere RUNSTATS-Befehle basierend auf Tabellengröße..."
        
        local large_table_threshold=${config[runstats.large_table_threshold]:-1000000}
        local small_table_threshold=${config[runstats.small_table_threshold]:-10000}
        local sample_rate=${config[runstats.sample_rate]:-10}

        # Generiere RUNSTATS basierend auf Größe und Reorg-Status
        while IFS= read -r line; do
            local table=$(echo "$line" | awk '{print $1}')
            local card=$(echo "$line" | awk '{print $2}')
            
            local params="WITH DISTRIBUTION AND INDEXES ALL"
            
            # Überschreibe Parameter für große/kleine Tabellen
            if [ "$card" -gt "$large_table_threshold" ]; then
                params="WITH DISTRIBUTION AND DETAILED INDEXES ALL"
            elif [ "$card" -lt "$small_table_threshold" ]; then
                params="TABLESAMPLE SYSTEM($sample_rate) WITH DISTRIBUTION AND INDEXES ALL"
            fi
            
            # Immer detaillierte Statistiken für reorganisierte Tabellen
            if grep -q "^${table}$" "$reorged_tables_list" 2>/dev/null; then
                params="WITH DISTRIBUTION AND DETAILED INDEXES ALL"
            fi
            
            echo "RUNSTATS ON TABLE $table $params ALLOW WRITE ACCESS;" >> "$runstats_script"
        done < "$all_tables_info_file"

        execute_script "$db" "$runstats_script" "RUNSTATS" "${log_prefix}.runstats.log"
    else
        cecho YELLOW "RUNSTATS für $db übersprungen."
    fi

    # --- REBIND ---
    local rebind_script="$TMP_DIR/rebind_${db}.sql"
    if [ $SKIP_REBIND -eq 0 ]; then
        cecho BCYAN "Generiere REBIND-Befehle..."
        echo "CALL SYSPROC.ADMIN_REVALIDATE_DB_OBJECTS(NULL, NULL, NULL);" > "$rebind_script"
        
        local invalid_packages_query="SELECT 'REBIND PACKAGE \"' || RTRIM(PKGSCHEMA) || '\".\"' || RTRIM(PKGNAME) || '\";' FROM SYSCAT.PACKAGES WHERE VALID = 'N' AND PKGSCHEMA NOT LIKE 'SYS%'"
        if [ $DRY_RUN -eq 0 ]; then
            db2 -x "$invalid_packages_query" >> "$rebind_script"
        else
            cecho BCYAN "Dry-Run: Füge Beispiel-REBIND-Befehl hinzu."
            echo "REBIND PACKAGE \"MYSCHEMA.MYPACKAGE\";" >> "$rebind_script"
        fi
        execute_script "$db" "$rebind_script" "REBIND" "${log_prefix}.rebind.log"
    else
        cecho YELLOW "REBIND für $db übersprungen."
    fi

    if [ $DRY_RUN -eq 0 ]; then
        db2 connect reset > /dev/null
    fi
    cecho BGREEN "Wartung für $db abgeschlossen. Logs in $log_prefix.*"
    echo
}

# Interaktiver Modus (bleibt weitgehend unverändert)
interactive_mode() {
    cecho BGREEN "Interaktiver Modus"
    echo "Bitte wÃ¤hlen Sie die auszufÃ¼hrenden Aktionen:"
    
    # Datenbank auswÃ¤hlen
    if [ -z "$SPECIFIC_DB" ]; then
        echo "VerfÃ¼gbare Datenbanken:"
        select db in "${databases[@]}"; do
            if [ -n "$db" ]; then
                SPECIFIC_DB="$db"
                break
            else
                cecho RED "UngÃ¼ltige Auswahl"
            fi
        done
    fi
    
    # Aktionen auswÃ¤hlen
    echo "Welche Aktionen sollen ausgefÃ¼hrt werden?"
    options=("REORG" "RUNSTATS" "REBIND" "Alle Aktionen" "Beenden")
    select action in "${options[@]}"; do
        case "$action" in
            "REORG")
                SKIP_REORG=0
                SKIP_RUNSTATS=1
                SKIP_REBIND=1
                break
                ;;
            "RUNSTATS")
                SKIP_REORG=1
                SKIP_RUNSTATS=0
                SKIP_REBIND=1
                break
                ;;
            "REBIND")
                SKIP_REORG=1
                SKIP_RUNSTATS=1
                SKIP_REBIND=0
                break
                ;;
            "Alle Aktionen")
                SKIP_REORG=0
                SKIP_RUNSTATS=0
                SKIP_REBIND=0
                break
                ;;
            "Beenden")
                cecho BGREEN "Skript wird beendet."
                exit 0
                ;;
            *)
                cecho RED "UngÃ¼ltige Auswahl"
                ;;
        esac
    done
    
    # Tabellenfilter auswÃ¤hlen
    echo "MÃ¶chten Sie einen Tabellenfilter verwenden?"
    select filter_choice in "Ja" "Nein"; do
        case "$filter_choice" in
            "Ja")
                read -p "Geben Sie den Tabellenfilter ein (z.B. 'SCHEMA.%' oder '%TABLE'): " TABLE_FILTER
                break
                ;;
            "Nein")
                TABLE_FILTER=""
                break
                ;;
            *)
                cecho RED "UngÃ¼ltige Auswahl"
                ;;
        esac
    done
    
    # PrioritÃ¤t auswÃ¤hlen
    echo "Welche PrioritÃ¤t soll fÃ¼r die Tabellenverarbeitung verwendet werden?"
    select priority in "Niedrig" "Mittel" "Hoch"; do
        case "$priority" in
            "Niedrig")
                TABLE_PRIORITY="low"
                break
                ;;
            "Mittel")
                TABLE_PRIORITY="medium"
                break
                ;;
            "Hoch")
                TABLE_PRIORITY="high"
                break
                ;;
            *)
                cecho RED "UngÃ¼ltige Auswahl"
                ;;
        esac
    done
    
    # Force-Modus auswÃ¤hlen
    echo "MÃ¶chten Sie den Force-Modus verwenden (alle Tabellen ohne PrÃ¼fung verarbeiten)?"
    select force_choice in "Ja" "Nein"; do
        case "$force_choice" in
            "Ja")
                FORCE_MODE=1
                break
                ;;
            "Nein")
                FORCE_MODE=0
                break
                ;;
            *)
                cecho RED "UngÃ¼ltige Auswahl"
                ;;
        esac
    done
    
    # Zusammenfassung anzeigen
    cecho BGREEN "Zusammenfassung der ausgewÃ¤hlten Optionen:"
    echo "Datenbank: $SPECIFIC_DB"
    echo "Aktionen: $(if [ $SKIP_REORG -eq 0 ]; then echo "REORG "; fi)$(if [ $SKIP_RUNSTATS -eq 0 ]; then echo "RUNSTATS "; fi)$(if [ $SKIP_REBIND -eq 0 ]; then echo "REBIND"; fi)"
    echo "Tabellenfilter: ${TABLE_FILTER:-"Keiner"}"
    echo "PrioritÃ¤t: $TABLE_PRIORITY"
    echo "Force-Modus: $(if [ $FORCE_MODE -eq 1 ]; then echo "Ja"; else echo "Nein"; fi)"
    
    # BestÃ¤tigung einholen
    echo "MÃ¶chten Sie mit diesen Einstellungen fortfahren?"
    select confirm in "Ja" "Nein"; do
        case "$confirm" in
            "Ja")
                break
                ;;
            "Nein")
                cecho BGREEN "Skript wird beendet."
                exit 0
                ;;
            *)
                cecho RED "UngÃ¼ltige Auswahl"
                ;;
        esac
    done
}

# Spezielle Funktionen fÃ¼r die Parameterberechnung
if [ "$1" = "--needs-reorg" ]; then
    needs_reorg "$2" "$3" "$4"
    exit 0
fi

if [ "$1" = "--get-runstats-params" ]; then
    get_runstats_params "$2" "$3" "$4"
    exit 0
fi

# Automatische Konfiguration durchfÃ¼hren
if [ $AUTO_CONFIG -eq 1 ]; then
    auto_configure
fi

# Systemressourcen prÃ¼fen, falls gewÃ¼nscht
if [ $CHECK_RESOURCES -eq 1 ]; then
    check_system_resources
fi

# Datenbanken auflisten
if [ -n "$SPECIFIC_DB" ]; then
    databases=("$SPECIFIC_DB")
else
    if [ $DRY_RUN -eq 0 ]; then
        databases=($(db2 list database directory | awk -F'= ' '/Datenbankname/ || /Database name/{print $2}'))
    else
        cecho BYELLOW "Dry-Run: Verwende Beispieldatenbank 'TESTDB'"
        databases=("TESTDB")
    fi
fi

if [ ${#databases[@]} -eq 0 ]; then
    cecho RED "Keine Datenbanken gefunden!"
    exit 1
fi

# Interaktiver Modus, falls gewÃ¼nscht
if [ $INTERACTIVE -eq 1 ]; then
    interactive_mode
fi

# Ausgabe des Force-Modus, falls aktiviert
if [ $FORCE_MODE -eq 1 ]; then
    cecho BRED "ACHTUNG: Force-Modus aktiviert! REORG, RUNSTATS und REBIND werden fÃ¼r alle Tabellen ohne vorherige PrÃ¼fung durchgefÃ¼hrt."
fi

cecho BGREEN "=========================================="
cecho BGREEN "Starte DB2-Datenbankwartung... (Datum: $(date '+%d.%m.%Y %H:%M CEST'))"
cecho BGREEN "=========================================="
echo

# --- HAUPTSTEUERUNG ---

# Funktionen und Variablen für Subshells exportieren, wenn parallel ausgeführt wird
if [ $PARALLEL -eq 1 ]; then
    export -f cecho
    export -f execute_script
    export -f process_database
    export LOG_DIR CONFIG_DIR HISTORY_DIR TMP_DIR TS
    export DRY_RUN SKIP_REORG SKIP_RUNSTATS SKIP_REBIND FORCE_MODE
    declare -A config
    # config muss für subshells verfügbar gemacht werden
    # Dies ist eine Bash 4+ Syntax
    if ((BASH_VERSINFO[0] >= 4)); then
        export CONFIG_CONTENT=$(declare -p config)
        process_db_parallel() {
            eval "declare -A config; ${CONFIG_CONTENT#*=}"
            process_database "$1"
        }
        export -f process_db_parallel
    fi
fi

cecho BGREEN "=========================================="
cecho BGREEN "Starte DB2-Datenbankwartung... (Datum: $(date '+%d.%m.%Y %H:%M'))"
cecho BGREEN "=========================================="
echo

# Haupt-Schleife: Sequentiell oder Parallel
if [ $PARALLEL -eq 1 ] && ((BASH_VERSINFO[0] >= 4)); then
    cecho BGREEN "Führe Wartung parallel für ${#databases[@]} Datenbanken aus (max. $TABLE_PARALLEL gleichzeitig)..."
    printf "%s\n" "${databases[@]}" | xargs -P "$TABLE_PARALLEL" -I {} bash -c 'process_db_parallel "{}"'
else
    cecho BGREEN "Führe Wartung sequentiell für ${#databases[@]} Datenbanken aus..."
    for db in "${databases[@]}"; do
        process_database "$db"
    done
fi

cecho BGREEN "==================================="
cecho BGREEN "DB2-Datenbankwartung abgeschlossen!"
cecho BGREEN "Logs in $LOG_DIR"
cecho BGREEN "==================================="




