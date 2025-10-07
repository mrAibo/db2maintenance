#!/bin/bash
# ***********************************************************************
# Programname   : arge_db2_maintenance_optimized.sh                   *
#                                                                       *
# Description   : Optimized DB2 maintenance script                    *
#                                                                       *
# Author        : A. V                                                  *
# Version       : 7.1.0 13.08.2025                                     *
#***********************************************************************
SCRIPT_USER="db2icm"
LOG_DIR="$HOME/db2_wartung_log"
CONFIG_DIR="$HOME/.db2_maintenance"
HISTORY_DIR="$HOME/.db2_maintenance/history"
TS=$(date +"%y%m%d_%H%M")

# Farbige Ausgaben
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
        BGREEN)  color_code=$(tput setaf 2 && tput bold) ;;
        *)       color_code="" ;;
    esac
    printf "%s%s%s\n" "${color_code}" "${msg}" "${color_reset}"
}

# Standard-Konfiguration
DEFAULT_CONFIG=$(cat << 'EOF'
# DB2 Wartungskonfiguration (optimiert)
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
use_db2batch = true
max_io_concurrent_reorg = 2
max_total_reorg_pages = 100000
analyze_index_pctfree = false
flush_package_cache = true
[reorg]
enable = true
use_reorgchk = true
reorg_mode = INPLACE
reclaim_extents = true
max_parallel_reorg = 2
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
initial_light = true
full_after_reorg = true
detailed_stats_large_tables = true
large_table_threshold = 1000000
sample_small_tables = true
small_table_threshold = 100000
sample_rate = 10
async_operations = true
max_async_operations = 4
max_parallel_runstats = 8
flush_package_cache = true
[rebind]
enable = true
rebind_invalid_only = true
async_operations = true
max_async_operations = 4
[priorities]
size_weight = 0.3
access_weight = 0.4
overflow_weight = 0.2
stats_age_weight = 0.1
[profiles]
quick = {
    parallel_databases = true
    max_table_parallel = 8
    adaptive_batch_size = true
    min_batch_size = 10
    max_batch_size = 50
    reorg_use_reorgchk = true
    reorg_max_parallel = 2
    runstats_initial_light = true
    runstats_full_after_reorg = true
    runstats_max_parallel = 8
}
thorough = {
    parallel_databases = true
    max_table_parallel = 4
    adaptive_batch_size = true
    min_batch_size = 5
    max_batch_size = 20
    reorg_use_reorgchk = true
    reorg_max_parallel = 1
    runstats_initial_light = true
    runstats_full_after_reorg = true
    runstats_max_parallel = 4
}
minimal = {
    parallel_databases = false
    max_table_parallel = 2
    adaptive_batch_size = true
    min_batch_size = 5
    max_batch_size = 10
    reorg_use_reorgchk = true
    reorg_max_parallel = 1
    runstats_initial_light = true
    runstats_full_after_reorg = false
    runstats_max_parallel = 2
}
EOF
)

# Hilfe-Funktion
show_help() {
    cecho BGREEN "Verwendung: $0 [OPTIONEN]"
    echo "Optionen:"
    echo "  --help                     Diese Hilfe anzeigen"
    echo "  --database DB              Nur eine spezifische Datenbank bearbeiten"
    echo "  --dry-run                  Simuliert die Ausführung ohne echte DB-Änderungen"
    echo "  --parallel                 Parallele Verarbeitung mehrerer Datenbanken"
    echo "  --table-parallel N         Parallele Verarbeitung von Tabellen (Standard: auto)"
    echo "  --batch-size N             Batch-Größe für Operationen (Standard: auto)"
    echo "  --reorg-only               Nur REORG durchführen"
    echo "  --runstats-only            Nur RUNSTATS durchführen"
    echo "  --rebind-only              Nur REBIND durchführen"
    echo "  --skip-reorg               REORG-Schritt überspringen"
    echo "  --skip-runstats            RUNSTATS-Schritt überspringen"
    echo "  --skip-rebind              REBIND-Schritt überspringen"
    echo "  --table-priority P         Tabellenpriorität: low, medium, high"
    echo "  --table-filter F           Filter für Tabellennamen"
    echo "  --check-resources          Systemressourcen vor dem Start prüfen"
    echo "  --auto-config              Automatische Konfiguration aller Parameter"
    echo "  --config-file F            Verwende spezifische Konfigurationsdatei"
    echo "  --profile P                Verwende spezifisches Profil"
    echo "  --interactive              Interaktiver Modus"
    echo "  --resume                   Setze unterbrochene Wartung fort"
    echo "  --test-mode                Testmodus - zeige nur, was getan würde"
    echo "  --force                    Erzwingt REORG, RUNSTATS und REBIND für alle Tabellen"
    exit 0
}

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
        --force) FORCE_MODE=1 ;;
        *) cecho RED "Unbekannte Option: $1"; show_help ;;
    esac
    shift
done

# Exklusive Optionen prüfen
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

# Benutzer prüfen
if [ "${USER}" != "${SCRIPT_USER}" ]; then
    cecho RED "Benutzer muss ${SCRIPT_USER} sein, um das Skript auszuführen..."
    exit 1
fi

# Verzeichnisse erstellen
mkdir -p -m 700 "$LOG_DIR"
mkdir -p -m 700 "$CONFIG_DIR"
mkdir -p -m 700 "$HISTORY_DIR"

# Standard-Konfigurationsdatei erstellen
if [ ! -f "$CONFIG_DIR/config.ini" ]; then
    echo "$DEFAULT_CONFIG" > "$CONFIG_DIR/config.ini"
    cecho BCYAN "Standard-Konfigurationsdatei erstellt: $CONFIG_DIR/config.ini"
fi

# Konfigurationsdatei laden
load_config() {
    local config_file="$1"
    local section=""
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        if [[ "$line" =~ ^\[([^\]]+)\] ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*([^=]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            local key="${BASH_REMATCH[1]// /}"
            local value="${BASH_REMATCH[2]}"
            value=$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
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

# Profil anwenden
if [ -n "$PROFILE" ]; then
    if [[ -v "config[profiles.$PROFILE]" ]]; then
        cecho BCYAN "Verwende Profil: $PROFILE"
    else
        cecho RED "Profil nicht gefunden: $PROFILE"
        exit 1
    fi
fi

# Temp-Verzeichnis
TMP_DIR=$(umask 077; mktemp -d -p /tmp db2_maintenance.XXXXXX) || { cecho RED "Fehler beim Erstellen des Temp-Verzeichnisses"; exit 1; }
trap 'rm -rf "$TMP_DIR"' EXIT

# DB2 Version ermitteln
get_db2_version() {
    local version=$(db2level | grep "DB2 v" | sed 's/.*DB2 v\([0-9]*\.[0-9]*\).*/\1/')
    echo "$version"
}

DB2_VERSION=$(get_db2_version)
cecho BCYAN "DB2 Version: $DB2_VERSION"


# Korrigierte CPU-Auslastungsermittlung
get_cpu_usage() {
    if command -v mpstat >/dev/null 2>&1; then
        LC_ALL=C mpstat 1 5 | awk '/Average:/ {print 100 - $NF}'
    else
        local cpu_line=$(grep '^cpu ' /proc/stat)
        local user=$(echo "$cpu_line" | awk '{print $2}')
        local nice=$(echo "$cpu_line" | awk '{print $3}')
        local system=$(echo "$cpu_line" | awk '{print $4}')
        local idle=$(echo "$cpu_line" | awk '{print $5}')
        local iowait=$(echo "$cpu_line" | awk '{print $6}')
        local irq=$(echo "$cpu_line" | awk '{print $7}')
        local softirq=$(echo "$cpu_line" | awk '{print $8}')
        sleep 1
        local cpu_line2=$(grep '^cpu ' /proc/stat)
        local user2=$(echo "$cpu_line2" | awk '{print $2}')
        local nice2=$(echo "$cpu_line2" | awk '{print $3}')
        local system2=$(echo "$cpu_line2" | awk '{print $4}')
        local idle2=$(echo "$cpu_line2" | awk '{print $5}')
        local iowait2=$(echo "$cpu_line2" | awk '{print $6}')
        local irq2=$(echo "$cpu_line2" | awk '{print $7}')
        local softirq2=$(echo "$cpu_line2" | awk '{print $8}')
        local user_diff=$((user2 - user))
        local nice_diff=$((nice2 - nice))
        local system_diff=$((system2 - system))
        local idle_diff=$((idle2 - idle))
        local iowait_diff=$((iowait2 - iowait))
        local irq_diff=$((irq2 - irq))
        local softirq_diff=$((softirq2 - softirq))
        local total_diff=$((user_diff + nice_diff + system_diff + idle_diff + iowait_diff + irq_diff + softirq_diff))
        local busy_diff=$((total_diff - idle_diff))
        if [ $total_diff -gt 0 ]; then
            echo "scale=2; ($busy_diff * 100) / $total_diff" | bc -l
        else
            echo "0"
        fi
    fi
}

# Funktion zur automatischen Konfiguration
auto_configure() {
    cecho BYELLOW "Führe automatische Konfiguration durch..."
    local NUM_CORES=$(nproc)
    cecho BCYAN "Erkannte CPU-Kerne: $NUM_CORES"
    local FREE_MEM_MB=$(free -m | awk '/Mem:/ {print $7}')
    cecho BCYAN "Freier Speicher: ${FREE_MEM_MB}MB"
    local CPU_USAGE=$(get_cpu_usage)
    cecho BCYAN "CPU-Auslastung: ${CPU_USAGE}%"
    local DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    cecho BCYAN "Festplattenspeicher: ${DISK_USAGE}% verwendet"
    
    if [ "$TABLE_PARALLEL" = "auto" ]; then
        TABLE_PARALLEL=$NUM_CORES
        local max_parallel=${config[general.max_table_parallel]:-8}
        if [ "$TABLE_PARALLEL" -gt "$max_parallel" ]; then
            TABLE_PARALLEL=$max_parallel
        fi
        if [ "$(echo "$CPU_USAGE > 70" | bc -l)" -eq 1 ]; then
            TABLE_PARALLEL=$((TABLE_PARALLEL / 2))
            cecho BYELLOW "Reduziere Parallelisierung aufgrund hoher CPU-Auslastung auf $TABLE_PARALLEL"
        fi
        if [ "$FREE_MEM_MB" -lt 4096 ]; then
            TABLE_PARALLEL=$((TABLE_PARALLEL / 2))
            cecho BYELLOW "Reduziere Parallelisierung aufgrund geringen Speichers auf $TABLE_PARALLEL"
        fi
        if [ "$TABLE_PARALLEL" -lt 1 ]; then
            TABLE_PARALLEL=1
        fi
    fi
    
    local max_reorg_parallel=${config[reorg.max_parallel_reorg]:-2}
    if [ "$TABLE_PARALLEL" -gt "$max_reorg_parallel" ]; then
        REORG_PARALLEL=$max_reorg_parallel
    else
        REORG_PARALLEL=$TABLE_PARALLEL
    fi
    
    local max_runstats_parallel=${config[runstats.max_parallel_runstats]:-8}
    if [ "$TABLE_PARALLEL" -gt "$max_runstats_parallel" ]; then
        RUNSTATS_PARALLEL=$max_runstats_parallel
    else
        RUNSTATS_PARALLEL=$TABLE_PARALLEL
    fi
    
    if [ "$BATCH_SIZE" = "auto" ]; then
        BATCH_SIZE=${config[general.default_batch_size]:-20}
    fi
    
    cecho BGREEN "Automatische Konfiguration abgeschlossen:"
    cecho BGREEN "  - Tabellen-Parallelität: $TABLE_PARALLEL"
    cecho BGREEN "  - REORG-Parallelität: $REORG_PARALLEL"
    cecho BGREEN "  - RUNSTATS-Parallelität: $RUNSTATS_PARALLEL"
    cecho BGREEN "  - Batch-Größe: $BATCH_SIZE"
}

# Systemressourcen prüfen
check_system_resources() {
    cecho BYELLOW "Prüfe Systemressourcen..."
    local FREE_MEM_MB=$(free -m | awk '/Mem:/ {print $7}')
    if [ "$FREE_MEM_MB" -lt 1024 ]; then
        cecho RED "Nicht genügend freier Speicher: ${FREE_MEM_MB}MB (mindestens 1GB erforderlich)"
        exit 1
    fi
    cecho GREEN "Freier Speicher: ${FREE_MEM_MB}MB"
    local CPU_USAGE=$(get_cpu_usage)
    if [ $(echo "$CPU_USAGE > 90" | bc -l) -eq 1 ]; then
        cecho RED "CPU-Auslastung zu hoch: ${CPU_USAGE}%"
        exit 1
    fi
    cecho GREEN "CPU-Auslastung: ${CPU_USAGE}%"
    local DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -gt 90 ]; then
        cecho RED "Festplattenspeicher zu voll: ${DISK_USAGE}%"
        exit 1
    fi
    cecho GREEN "Festplattenspeicher: ${DISK_USAGE}% verwendet"
}

# Funktion zur Ermittlung der Tabellengrößen
get_table_sizes() {
    local db="$1"
    local output_file="$2"
    db2 connect to "$db" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        cecho RED "Fehler: Konnte keine Verbindung zu $db herstellen"
        return 1
    fi
    local query="SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME), CARD, NPAGES FROM SYSCAT.TABLES WHERE TYPE = 'T' AND TABSCHEMA NOT LIKE 'SYS%' AND TABSCHEMA NOT IN ('NULLID', 'SYSCAT', 'SYSSTAT', 'SYSFUN', 'SYSIBM', 'SYSPUBLIC')"
    db2 -x "$query" > "$output_file" 2>/dev/null
    db2 connect reset > /dev/null 2>&1
    
    if [ ! -s "$output_file" ]; then
        echo "-- Keine Tabellen gefunden" > "$output_file"
    fi
}

# Funktion zur Ermittlung der REORG-Kandidaten
get_reorg_candidates() {
    local db="$1"
    local output_file="$2"
    db2 connect to "$db" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        cecho RED "Fehler: Konnte keine Verbindung zu $db herstellen"
        return 1
    fi
    local overflow_threshold="${config[reorg.overflow_threshold]}"
    local stats_time_threshold_days="${config[reorg.stats_time_threshold_days]}"
    
    # Definiere die funktionierende Fallback-Abfrage einmal, um Code-Duplikation zu vermeiden
    local fallback_query="SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME) FROM SYSCAT.TABLES WHERE TYPE = 'T' AND TABSCHEMA NOT LIKE 'SYS%' AND (OVERFLOW > $overflow_threshold OR STATS_TIME IS NULL OR DAYS(CURRENT TIMESTAMP) - DAYS(STATS_TIME) > $stats_time_threshold_days)"
    
    if [ "${config[reorg.use_reorgchk]}" = "true" ]; then
        # Verwende die korrekte REORGCHK-Syntax für DB2 v12.1.1.0
        local reorgchk_cmd
        if [[ "${DB2_VERSION%%.*}" -ge 11 ]]; then
            reorgchk_cmd="REORGCHK CURRENT STATISTICS"
        else
            reorgchk_cmd="REORGCHK UPDATE STATISTICS"
        fi
        
        if ! db2 "$reorgchk_cmd" > "$TMP_DIR/reorgchk_output.txt" 2>&1; then
            cecho YELLOW "Hinweis: REORGCHK nicht verfügbar, verwende Fallback-Methode"
            db2 -x "$fallback_query" > "$output_file" 2>/dev/null
            db2 connect reset > /dev/null 2>&1
            return 0
        fi
        
        if grep -q "SQLSTATE\|SQL0104N\|DB2" "$TMP_DIR/reorgchk_output.txt"; then
            cecho YELLOW "Hinweis: REORGCHK enthielt Fehler - verwende Fallback-Methode"
            db2 -x "$fallback_query" > "$output_file" 2>/dev/null
        else
            # Verwende das getestete AWK-Skript, um REORG-Kandidaten zu extrahieren
            awk '
            /\*/ {
                # Wenn die aktuelle Zeile ein Sternchen enthält, prüfe die vorherige Zeile
                if (prev ~ /^Tabelle:/) {
                    # Extrahiere den Tabellennamen aus der vorherigen Zeile
                    split(prev, parts, " ");
                    print parts[2];
                }
            }
            {
                # Speichere die aktuelle Zeile für die nächste Iteration
                prev = $0;
            }
            ' "$TMP_DIR/reorgchk_output.txt" > "$output_file"
            
            # Wenn keine Tabellen gefunden wurden, gib eine klare Meldung aus
            if [ ! -s "$output_file" ]; then
                cecho BCYAN "REORGCHK abgeschlossen: Keine Tabellen benötigen REORG"
                echo "-- Keine REORG-Kandidaten gefunden" > "$output_file"
            fi
        fi
    else
        db2 -x "$fallback_query" > "$output_file" 2>/dev/null
    fi
    
    db2 connect reset > /dev/null 2>&1
    
    if [ ! -s "$output_file" ]; then
        echo "-- Keine REORG-Kandidaten gefunden" > "$output_file"
    fi
}

# Neue Funktion zur Überprüfung der Existenz von Tabellen
verify_existing_tables() {
    local db="$1"
    local input_file="$2"
    local temp_file="$TMP_DIR/verified_tables.txt"
    
    if [ ! -s "$input_file" ]; then
        return 0
    fi
    
    > "$temp_file"
    while IFS= read -r table; do
        if [[ "$table" =~ ^-- ]] || [ -z "$table" ]; then
            continue
        fi
        
        # Überprüfen, ob die Tabelle existiert
        local schema=$(echo "$table" | cut -d'.' -f1)
        local tablename=$(echo "$table" | cut -d'.' -f2)
        
        if db2 -x "SELECT 1 FROM SYSCAT.TABLES WHERE TABSCHEMA = '$schema' AND TABNAME = '$tablename' WITH UR" > /dev/null 2>&1; then
            echo "$table" >> "$temp_file"
        else
            cecho YELLOW "Tabelle $table existiert nicht, wird aus REORG-Liste entfernt"
        fi
    done < "$input_file"
    
    mv "$temp_file" "$input_file"
}

# Funktion zur Generierung von RUNSTATS-SQL
generate_runstats_sql() {
    local input_file="$1"
    local output_file="$2"
    local mode="$3"
    printf -- "-- RUNSTATS Statements (%s mode)\n" "$mode" > "$output_file"
    
    if [ ! -s "$input_file" ]; then
        echo "-- Keine Tabellen gefunden" >> "$output_file"
        return 0
    fi
    
    while IFS=' ' read -r table card npages; do
        if [ -z "$table" ] || [[ "$table" =~ ^-- ]]; then
            continue
        fi
        if ! [[ "$card" =~ ^[0-9]+$ ]]; then
            continue
        fi
        
        if [ "$mode" = "light" ]; then
            # Leichtgewichtige RUNSTATS für alle Tabellen
            echo "RUNSTATS ON TABLE $table WITH DISTRIBUTION AND INDEXES ALL ALLOW WRITE ACCESS" >> "$output_file"
        else
            # Volle RUNSTATS nur nach REORG
            echo "RUNSTATS ON TABLE $table WITH DISTRIBUTION AND INDEXES ALL ALLOW WRITE ACCESS" >> "$output_file"
        fi
    done < "$input_file"
}

# Funktion zur Generierung von REORG-SQL
generate_reorg_sql() {
    local input_file=$1
    local output_file=$2
    local table_sizes=$3
    echo "-- REORG Statements" > "$output_file"
    
    if [ ! -s "$input_file" ] || grep -q "Keine.*REORG-Kandidaten gefunden" "$input_file"; then
        echo "-- Keine REORG-Kandidaten gefunden" >> "$output_file"
        return 0
    fi
    
    local valid_count=0
    local invalid_count=0
    
    while read -r table; do
        if [[ "$table" =~ ^-- ]] || [ -z "$table" ]; then
            continue
        fi
        # Überprüfen, ob die Zeile eine Fehlermeldung enthält
        if [[ "$table" =~ SQL[0-9]+N ]] || [[ "$table" =~ SQLSTATE ]]; then
            invalid_count=$((invalid_count + 1))
            continue
        fi
        if [[ ! "$table" =~ ^[A-Z][A-Z0-9_]{0,127}\.[A-Z][A-Z0-9_]{0,127}$ ]]; then
            cecho YELLOW "Ungültiger Tabellenname: $table - überspringe"
            invalid_count=$((invalid_count + 1))
            continue
        fi
        local schema="${table%%.*}"
        if [[ "$schema" =~ ^SYS ]]; then
            cecho YELLOW "System-Schema $schema nicht erlaubt - überspringe"
            continue
        fi
        local reorg_mode="${config[reorg.reorg_mode]:-INPLACE}"
        echo "REORG TABLE $table $reorg_mode ALLOW WRITE ACCESS" >> "$output_file"
        valid_count=$((valid_count + 1))
    done < "$input_file"
    
    if [ $valid_count -eq 0 ]; then
        echo "-- Keine gültigen REORG-Anweisungen generiert" >> "$output_file"
        cecho YELLOW "Warnung: Keine gültigen REORG-Anweisungen generiert. Gültige: $valid_count, Ungültige: $invalid_count"
    else
        cecho BGREEN "Generierte REORG-Anweisungen für $valid_count Tabellen. (Ungültige: $invalid_count)"
    fi
}

# Funktion zur Generierung von REORG-SQL im Force-Modus
generate_reorg_sql_force() {
    local table_sizes_file=$1
    local output_file=$2
    echo "-- REORG Statements (Force-Modus)" > "$output_file"
    
    if [ ! -s "$table_sizes_file" ]; then
        echo "-- Keine Tabellen gefunden (Force-Modus)" >> "$output_file"
        return 0
    fi
    
    local reorg_mode="${config[reorg.reorg_mode]:-INPLACE}"
    local valid_count=0
    local invalid_count=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*-- ]]; then
            continue
        fi
        
        line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        local raw_table=$(printf '%s' "$line" | awk '{print $1}')
        raw_table=$(printf '%s' "$raw_table" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        local table=$(printf '%s' "$raw_table" | tr -cd '[:print:]')
        
        if [[ -n "$table" && "$table" =~ ^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            echo "REORG TABLE $table $reorg_mode ALLOW WRITE ACCESS" >> "$output_file"
            valid_count=$((valid_count + 1))
        else
            invalid_count=$((invalid_count + 1))
            printf "Ungueltiger Tabellenname (Force-Modus): raw='%s', cleaned='%s' - ueberspringe\n" "$raw_table" "$table" >&2
        fi
    done < "$table_sizes_file"
    
    if [ ! -s "$output_file" ] || ! grep -q "REORG TABLE" "$output_file"; then
        echo "-- Keine gültigen REORG-Anweisungen generiert (Force-Modus)" >> "$output_file"
        cecho RED "Warnung: Keine gültigen REORG-Anweisungen generiert. Gültige: $valid_count, Ungueltige: $invalid_count"
    else
        cecho BGREEN "Force-Modus: Generierte REORG-Anweisungen fuer $valid_count Tabellen. (Ungueltige: $invalid_count)"
    fi
}

# Funktion zur Generierung von REBIND-SQL
generate_rebind_sql() {
    local db="$1"
    local output_file="$2"
    db2 connect to "$db" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        cecho RED "Fehler: Konnte keine Verbindung zu $db herstellen"
        return 1
    fi
    local header="-- REBIND Statements"
    echo "$header" > "$output_file"
    
    if [ "${config[rebind.rebind_invalid_only]}" = "true" ]; then
        db2 -x "SELECT 'REBIND PACKAGE ' || RTRIM(PKGSCHEMA) || '.' || RTRIM(PKGNAME) || ';'
                 FROM SYSCAT.PACKAGES
                 WHERE PKGSCHEMA NOT LIKE 'SYS%'
                 AND PKGSCHEMA NOT IN ('NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSPROC')
                 AND VALID = 'N'" >> "$output_file" 2>/dev/null
    else
        db2 -x "SELECT 'REBIND PACKAGE ' || RTRIM(PKGSCHEMA) || '.' || RTRIM(PKGNAME) || ';'
                 FROM SYSCAT.PACKAGES
                 WHERE PKGSCHEMA NOT LIKE 'SYS%'
                 AND PKGSCHEMA NOT IN ('NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSPROC')" >> "$output_file" 2>/dev/null
    fi
    
    db2 connect reset > /dev/null 2>&1
    
    if [ ! -s "$output_file" ] || ! grep -q "REBIND PACKAGE" "$output_file"; then
        local no_packages="-- Keine gültigen Pakete zum Binden gefunden"
        echo "$no_packages" >> "$output_file"
    fi
}

# Funktion zur Ausführung mit db2batch
execute_with_db2batch() {
    local db="$1"
    local sql_file="$2"
    local parallel="$3"
    local log_file="$4"
    if [ ! -s "$sql_file" ]; then
        cecho YELLOW "Keine Statements in $sql_file gefunden - überspringe Ausführung"
        return 0
    fi
    mkdir -p "$(dirname "$log_file")"
    local line_count
    line_count=$(wc -l < "$sql_file" 2>/dev/null)
    local message="Führe ${line_count} Statements mit db2batch aus..."
    cecho BCYAN "$message"
    if [ $DRY_RUN -eq 1 ]; then
        cecho YELLOW "Dry-Run: Würde ausführen: db2batch -d $db -f $sql_file -r $log_file"
        return 0
    fi
    if ! db2batch -d "$db" -f "$sql_file" -r "$log_file"; then
        cecho RED "Fehler bei db2batch-Ausführung. Siehe $log_file für Details."
        if [ -f "$log_file" ]; then
            cecho RED "Letzte Zeilen des Logs:"
            tail -10 "$log_file"
        else
            cecho RED "Log-Datei wurde nicht erstellt."
        fi
        return 1
    fi
    return 0
}

# Funktion zur parallelen Ausführung mit CLP
execute_parallel() {
    local db="$1"
    local sql_file="$2"
    local parallel="$3"
    local log_file="$4"
    if [ ! -s "$sql_file" ]; then
        cecho YELLOW "Keine Statements in $sql_file gefunden - überspringe Ausführung"
        return 0
    fi
    mkdir -p "$(dirname "$log_file")"
    local line_count
    line_count=$(wc -l < "$sql_file" 2>/dev/null)
    local message="Führe ${line_count} Statements parallel aus (parallel: ${parallel})..."
    cecho BCYAN "$message"
    if [ $DRY_RUN -eq 1 ]; then
        cecho YELLOW "Dry-Run: Würde parallele Ausführung mit ${parallel} Prozessen starten"
        return 0
    fi
    local statements_dir="$TMP_DIR/statements_${RANDOM}"
    mkdir -p "$statements_dir"
    local statement_count=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^-- ]]; then
            continue
        fi
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$line" ]; then
            continue
        fi
        if [[ "$line" =~ ^(REORG|RUNSTATS|REBIND) ]]; then
            statement_count=$((statement_count + 1))
            echo "$line" > "$statements_dir/statement_${statement_count}.sql"
        fi
    done < "$sql_file"
    if [ $statement_count -eq 0 ]; then
        cecho YELLOW "Keine Aufgaben zur Verarbeitung gefunden. Überspringe diesen Schritt."
        rm -rf "$statements_dir"
        return 0
    fi
    cecho BCYAN "Gefunden: ${statement_count} gültige SQL-Anweisungen"
    
    # Überprüfen, ob wir mehr Prozesse als Anweisungen haben
    # Überprüfen, ob wir mehr Prozesse als Anweisungen haben
    if [ $parallel -gt $statement_count ]; then
        old_parallel=$parallel
        parallel=$statement_count
        cecho BCYAN "Optimiere Verarbeitung: $statement_count Aufgabe(n) → $parallel Prozess(e) (statt $old_parallel)"
    fi
    
    local statements_per_process=$((statement_count / parallel))
    local remainder=$((statement_count % parallel))
    cecho BCYAN "Verteile ${statement_count} Anweisungen auf ${parallel} Prozesse"
    local pids=()
    for ((i=1; i<=parallel; i++)); do
        local process_file="$statements_dir/process_${i}.clp"
        local process_log="${log_file}.${i}"
        local start=$(( (i-1) * statements_per_process + 1 ))
        local end=$(( i * statements_per_process ))
        if [ $i -le $remainder ]; then
            start=$((start + i - 1))
            end=$((end + i))
        else
            start=$((start + remainder))
            end=$((end + remainder))
        fi
        echo "-- Prozess $i - Anweisungen $start bis $end" > "$process_file"
        echo "CONNECT TO $db;" >> "$process_file"
        for ((j=start; j<=end; j++)); do
            if [ -f "$statements_dir/statement_${j}.sql" ]; then
                cat "$statements_dir/statement_${j}.sql" >> "$process_file"
                echo ";" >> "$process_file"
            fi
        done
        echo "CONNECT RESET;" >> "$process_file"
        if [ -s "$process_file" ]; then
            db2 -tvf "$process_file" > "$process_log" 2>&1 &
            pids+=($!)
            cecho BCYAN "Prozess ${i} gestartet (Anweisungen ${start} bis ${end})"
        fi
    done
    local success=0
    local error_count=0
    for pid in "${pids[@]}"; do
        wait $pid
        local exit_code=$?
        if [ $exit_code -ne 0 ]; then
            success=1
            error_count=$((error_count + 1))
        fi
    done
    > "$log_file"
    for ((i=1; i<=parallel; i++)); do
        local process_log="${log_file}.${i}"
        if [ -f "$process_log" ]; then
            cat "$process_log" >> "$log_file"
            rm -f "$process_log"
        fi
    done
    rm -rf "$statements_dir"
    
    # Bereinige die Variablen von Zeilenumbrüchen
    local missing_table_errors=$(grep -c "SQL2306N.*nicht vorhanden" "$log_file" 2>/dev/null | tr -d '\n' || echo 0)
    local syntax_errors=$(grep -c "SQL0104N" "$log_file" 2>/dev/null | tr -d '\n' || echo 0)
    local total_errors=$(grep -c "SQL[0-9]*N" "$log_file" 2>/dev/null | tr -d '\n' || echo 0)
    local successful_statements=$(grep -c "DB20000I" "$log_file" 2>/dev/null | tr -d '\n' || echo 0)
    
    # Korrigiere die Zählung der Gesamtoperationen
    local total_operations=$((successful_statements + total_errors))
    
    # Debug-Ausgabe
    echo "DEBUG: success=$success, missing_table_errors='$missing_table_errors', syntax_errors='$syntax_errors', total_errors='$total_errors', successful_statements='$successful_statements', total_operations=$total_operations" >> "$log_file"
    
    # Korrigierte Bedingungen mit bereinigten Variablen
    if [ "$success" -eq 0 ]; then
        return 0
    elif [ "$successful_statements" -gt 0 ] && [ "$missing_table_errors" -gt 0 ] && [ "$missing_table_errors" -eq "$total_errors" ]; then
        cecho YELLOW "Einige Tabellen wurden nicht gefunden, aber $successful_statements Operationen waren erfolgreich."
        return 0
    elif [ "$syntax_errors" -gt 0 ] && [ "$syntax_errors" -eq "$total_errors" ]; then
        cecho YELLOW "Syntaxfehler in den SQL-Anweisungen, aber keine kritischen Fehler."
        return 0
    elif [ "$missing_table_errors" -gt 0 ] && [ "$missing_table_errors" -eq "$total_errors" ]; then
        cecho YELLOW "Einige Tabellen wurden nicht gefunden, aber die Wartung war erfolgreich."
        return 0
    elif [ "$successful_statements" -gt 0 ] && [ "$total_errors" -le "$successful_statements" ]; then
        cecho YELLOW "Einige Fehler sind aufgetreten, aber die meisten Operationen ($successful_statements von $total_operations) waren erfolgreich."
        return 0
    else
        cecho RED "Fehler bei mindestens einem parallelen Prozess. Siehe $log_file für Details."
        return 1
    fi
}

# Funktion zur Analyse der Index-PCTFREE-Werte
analyze_index_pctfree() {
    local db="$1"
    local table_list_file="$2"
    local output_log="$3"
    local log_prefix="$4"
    db2 connect to "$db" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        cecho RED "${log_prefix}Fehler: Konnte keine Verbindung zu $db fuer PCTFREE-Analyse herstellen"
        return 1
    fi
    echo "Index PCTFREE Analyse fuer $db (Datum: $(date))" > "$output_log"
    echo "=============================================" >> "$output_log"
    if [ ! -s "$table_list_file" ]; then
        echo "Keine Tabellen fuer Analyse gefunden." >> "$output_log"
        db2 connect reset > /dev/null 2>&1
        return 0
    fi
    local table_count=0
    while IFS= read -r table; do
        if [ -z "$table" ] || [[ "$table" =~ ^[[:space:]]*-- ]]; then
            continue
        fi
        table=$(echo "$table" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ ! "$table" =~ ^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            continue
        fi
        table_count=$((table_count + 1))
        local schema=$(echo "$table" | cut -d'.' -f1)
        local tablename=$(echo "$table" | cut -d'.' -f2)
        echo "Indizes fuer Tabelle: $table" >> "$output_log"
        db2 -x "SELECT INDNAME, PCTFREE FROM SYSCAT.INDEXES WHERE TABSCHEMA = '${schema}' AND TABNAME = '${tablename}'" >> "$output_log" 2>/dev/null
        echo "" >> "$output_log"
    done < "$table_list_file"
    db2 connect reset > /dev/null 2>&1
    cecho BCYAN "${log_prefix}PCTFREE-Analyse fuer $table_count Tabellen in $db abgeschlossen. Ergebnisse in $output_log"
}

spinner_with_message() {
    local pid=$1
    local message="$2"
    local delay=0.2
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    # Verstecke den Cursor
    tput civis 2>/dev/null
    
    while kill -0 $pid 2>/dev/null; do
        # Gehe zum Zeilenanfang und gib Nachricht und Spinner aus
        printf "\r%s [%s]  " "$message" "${spinstr:$i:1}"
        
        # Erhöhe den Index
        ((i = (i + 1) % ${#spinstr}))
        
        sleep $delay
    done
    
    # Prozess ist abgeschlossen
    printf "\r%s [✓]  \n" "$message"
    
    # Zeige den Cursor wieder
    tput cnorm 2>/dev/null
}

# Funktion für REORG/RUNSTATS/REBIND pro DB
process_database() {
    local db="$1"
    local log_prefix="${LOG_DIR}/${db}.${TS}"
    mkdir -p "$LOG_DIR"
    cecho BYELLOW "====================="
    cecho BYELLOW "Wartung für $db..."
    cecho BYELLOW "====================="
    local table_sizes_file="$TMP_DIR/${db}_table_sizes.txt"
    get_table_sizes "$db" "$table_sizes_file"
    if [ ! -s "$table_sizes_file" ] || grep -q "Keine Tabellen gefunden" "$table_sizes_file"; then
        cecho YELLOW "Keine Tabellen in $db gefunden. Überspringe..."
        return 0
    fi
    local total_tables=$(wc -l < "$table_sizes_file")
    cecho BCYAN "Verarbeite $total_tables Tabellen in $db"
    local reorg_candidates_file="$TMP_DIR/${db}_reorg_candidates.txt"
    local reorg_count=0
    local reorg_source_file=""

    if [ $SKIP_REORG -eq 0 ]; then
        if [ $FORCE_MODE -eq 1 ]; then
            cecho BRED "Force-Modus: Verwende alle $total_tables Tabellen fuer REORG"
            reorg_source_file="$table_sizes_file"
            reorg_count=$total_tables
        else
            get_reorg_candidates "$db" "$reorg_candidates_file"
            if [ ! -s "$reorg_candidates_file" ] || grep -q "Keine REORG-Kandidaten gefunden" "$reorg_candidates_file"; then
                cecho BCYAN "Keine Tabellen benötigen REORG"
                reorg_count=0
                reorg_source_file=""
            else
                local raw_count
                raw_count=$(grep -v "^--" "$reorg_candidates_file" | grep -c "." 2>/dev/null)
                if [[ "$raw_count" =~ ^[0-9]+$ ]]; then
                    reorg_count=$raw_count
                else
                    cecho RED "Warnung: Konnte Anzahl der REORG-Kandidaten nicht bestimmen. Setze auf 0."
                    reorg_count=0
                fi
                cecho BCYAN "$reorg_count Tabellen benötigen REORG"
                reorg_source_file="$reorg_candidates_file"
            fi
        fi
    fi

    # Führe RUNSTATS (leicht) für alle Tabellen durch
    if [ $SKIP_RUNSTATS -eq 0 ] && [ "${config[runstats.initial_light]}" = "true" ]; then
        local runstats_light_sql="$TMP_DIR/${db}_runstats_light.sql"
        generate_runstats_sql "$table_sizes_file" "$runstats_light_sql" "light"
        # Prüfen, ob die SQL-Datei Anweisungen enthält
        if [ ! -s "$runstats_light_sql" ] || grep -q "Keine Tabellen gefunden" "$runstats_light_sql"; then
            cecho YELLOW "Keine Tabellen für RUNSTATS gefunden. Überspringe RUNSTATS (leicht)."
        else
            execute_parallel "$db" "$runstats_light_sql" "$RUNSTATS_PARALLEL" "${log_prefix}.runstats_light.log"
            local runstats_light_result=$?
            if [ $runstats_light_result -eq 0 ]; then
                cecho BGREEN "RUNSTATS (leicht) für $db abgeschlossen."
                if [ "${config[runstats.flush_package_cache]}" = "true" ]; then
                    cecho BYELLOW "Führe FLUSH PACKAGE CACHE DYNAMIC aus (nach RUNSTATS light)..."
                    local flush_clp="$TMP_DIR/flush_cache_light.clp"
                    echo "CONNECT TO $db;" > "$flush_clp"
                    echo "FLUSH PACKAGE CACHE DYNAMIC;" >> "$flush_clp"
                    echo "CONNECT RESET;" >> "$flush_clp"
                    if db2 -tvf "$flush_clp" > "${log_prefix}.flush_cache_light.log" 2>&1; then
                        cecho BGREEN "FLUSH PACKAGE CACHE DYNAMIC erfolgreich ausgeführt (nach RUNSTATS light)."
                    else
                        cecho RED "Fehler bei FLUSH PACKAGE CACHE DYNAMIC (nach RUNSTATS light). Siehe ${log_prefix}.flush_cache_light.log"
                    fi
                    rm -f "$flush_clp"
                fi
            else
                cecho RED "Fehler bei RUNSTATS (leicht) für $db."
            fi
        fi
    fi

    # Führe REORG durch, wenn erforderlich
    if [ $SKIP_REORG -eq 0 ]; then
        if ( [[ "$reorg_count" =~ ^[0-9]+$ ]] && [ "$reorg_count" -gt 0 ] 2>/dev/null ) || [ $FORCE_MODE -eq 1 ]; then
            if [ $FORCE_MODE -eq 1 ]; then
                cecho BRED "Starte REORG für ALLE $total_tables Tabellen (Force-Modus)..."
            else
                cecho BCYAN "Starte REORG für $reorg_count Tabellen..."
            fi
            local reorg_sql="$TMP_DIR/${db}_reorg.sql"
            if [ $FORCE_MODE -eq 1 ]; then
                generate_reorg_sql_force "$table_sizes_file" "$reorg_sql"
            else
                generate_reorg_sql "$reorg_candidates_file" "$reorg_sql" "$table_sizes_file"
            fi
            # Prüfen, ob die SQL-Datei Anweisungen enthält
            if [ ! -s "$reorg_sql" ] || grep -q "Keine.*REORG-Kandidaten gefunden" "$reorg_sql" || grep -q "Keine gültigen REORG-Anweisungen generiert" "$reorg_sql"; then
                cecho YELLOW "Keine REORG-Anweisungen generiert. Überspringe REORG."
                reorg_count=0
            else
                local total_reorg_pages
                if [ $FORCE_MODE -eq 1 ]; then
                    total_reorg_pages=$(awk -F' ' '{sum+=$3} END {print sum+0}' "$table_sizes_file")
                else
                    total_reorg_pages=$(awk -F' ' '{sum+=$3} END {print sum+0}' "$table_sizes_file")
                fi
                local max_pages=${config[general.max_total_reorg_pages]:-100000}
                local adjusted_parallel=$REORG_PARALLEL
                if [ "$total_reorg_pages" -gt "$max_pages" ]; then
                    cecho BYELLOW "Reduziere REORG-Parallelität aufgrund hoher Seitenanzahl ($total_reorg_pages > $max_pages)"
                    adjusted_parallel=1
                fi
                execute_parallel "$db" "$reorg_sql" "$adjusted_parallel" "${log_prefix}.reorg.log" &
                local pid=$!
                spinner_with_message $pid "REORG wird ausgeführt"
                wait $pid
                local reorg_result=$?
                if [ $reorg_result -eq 0 ]; then
                    if [ $FORCE_MODE -eq 1 ]; then
                        cecho BRED "REORG für ALLE Tabellen in $db abgeschlossen (Force-Modus)."
                    else
                        cecho BGREEN "REORG für $db abgeschlossen."
                    fi
                    if [ "${config[general.analyze_index_pctfree]}" = "true" ]; then
                        cecho BYELLOW "Führe Index-PCTFREE-Analyse durch..."
                        local pctfree_log="${log_prefix}.pctfree_analysis.log"
                        local analysis_source_file=""
                        if [ $FORCE_MODE -eq 1 ]; then
                            local temp_all_tables="$TMP_DIR/${db}_all_tables_for_analysis.txt"
                            awk -F' ' '{print $1}' "$table_sizes_file" > "$temp_all_tables"
                            analysis_source_file="$temp_all_tables"
                        else
                            analysis_source_file="$reorg_candidates_file"
                        fi
                        analyze_index_pctfree "$db" "$analysis_source_file" "$pctfree_log" "[$db] "
                        if [ $FORCE_MODE -eq 1 ] && [ -f "$temp_all_tables" ]; then
                            rm -f "$temp_all_tables"
                        fi
                    fi
                else
                    cecho RED "Fehler bei REORG für $db."
                fi
            fi
        else
            cecho BCYAN "Kein REORG erforderlich (Anzahl: $reorg_count)."
        fi
    fi

    # Führe vollständige RUNSTATS nach REORG durch, wenn konfiguriert
    if [ $SKIP_RUNSTATS -eq 0 ] && [ "${config[runstats.full_after_reorg]}" = "true" ]; then
        if ( [[ "$reorg_count" =~ ^[0-9]+$ ]] && [ "$reorg_count" -gt 0 ] 2>/dev/null ) || [ $FORCE_MODE -eq 1 ]; then
            if [ $FORCE_MODE -eq 1 ]; then
                cecho BRED "Starte vollständige RUNSTATS für ALLE $total_tables Tabellen (Force-Modus nach REORG)..."
                local runstats_full_sql="$TMP_DIR/${db}_runstats_full_force.sql"
                generate_runstats_sql "$table_sizes_file" "$runstats_full_sql" "full"
            else
                cecho BCYAN "Starte vollständige RUNSTATS für $reorg_count reorgte Tabellen..."
                local runstats_full_sql="$TMP_DIR/${db}_runstats_full.sql"
                generate_runstats_sql "$reorg_candidates_file" "$runstats_full_sql" "full"
            fi
            if [ ! -s "$runstats_full_sql" ] || grep -q "Keine Tabellen gefunden" "$runstats_full_sql"; then
                if [ -s "$reorg_candidates_file" ] && ! grep -q "Keine.*REORG-Kandidaten gefunden" "$reorg_candidates_file"; then
                    cecho YELLOW "Hinweis: Die reorganisierten Tabellen benötigen keine weiteren Statistiken. Überspringe diesen Schritt."
                else
                    cecho BCYAN "Hinweis: Nach dem REORG sind keine zusätzlichen Statistiken erforderlich."
                fi
            else
                execute_parallel "$db" "$runstats_full_sql" "$RUNSTATS_PARALLEL" "${log_prefix}.runstats_full.log" &
                local pid=$!
                spinner_with_message $pid "RUNSTAT wird ausgeführt"
                wait $pid
                local runstats_full_result=$?
                if [ $runstats_full_result -eq 0 ]; then
                    if [ $FORCE_MODE -eq 1 ]; then
                        cecho BRED "RUNSTATS (voll) für ALLE Tabellen in $db abgeschlossen (Force-Modus)."
                    else
                        cecho BGREEN "RUNSTATS (voll) für reorgte Tabellen in $db abgeschlossen."
                    fi
                    if [ "${config[runstats.flush_package_cache]}" = "true" ]; then
                        cecho BYELLOW "Führe FLUSH PACKAGE CACHE DYNAMIC aus (nach RUNSTATS full)..."
                        local flush_clp="$TMP_DIR/flush_cache_full.clp"
                        echo "CONNECT TO $db;" > "$flush_clp"
                        echo "FLUSH PACKAGE CACHE DYNAMIC;" >> "$flush_clp"
                        echo "CONNECT RESET;" >> "$flush_clp"
                        if db2 -tvf "$flush_clp" > "${log_prefix}.flush_cache_full.log" 2>&1; then
                            cecho BGREEN "FLUSH PACKAGE CACHE DYNAMIC erfolgreich ausgeführt (nach RUNSTATS full)."
                        else
                            cecho RED "Fehler bei FLUSH PACKAGE CACHE DYNAMIC (nach RUNSTATS full). Siehe ${log_prefix}.flush_cache_full.log"
                        fi
                        rm -f "$flush_clp"
                    fi
                else
                    if [ $FORCE_MODE -eq 1 ]; then
                        cecho RED "Fehler bei RUNSTATS (voll) für ALLE Tabellen in $db (Force-Modus)."
                    else
                        cecho RED "Fehler bei RUNSTATS (voll) für reorgte Tabellen in $db."
                    fi
                fi
            fi
        else
            cecho BCYAN "Keine vollständigen RUNSTATS erforderlich (keine REORG durchgeführt)."
        fi
    fi

    # Führe REVALIDATE/REBIND durch
    if [ $SKIP_REBIND -eq 0 ]; then
        cecho BYELLOW "Starte REVALIDATE/REBIND für $db..."
        local revalidate_sql="$TMP_DIR/${db}_revalidate.sql"
        echo "-- REVALIDATE Statements" > "$revalidate_sql"
        echo "CALL SYSPROC.ADMIN_REVALIDATE_DB_OBJECTS(NULL, NULL, NULL);" >> "$revalidate_sql"
        execute_with_db2batch "$db" "$revalidate_sql" 1 "${log_prefix}.revalidate.log"
        local rebind_sql="$TMP_DIR/${db}_rebind.sql"
        generate_rebind_sql "$db" "$rebind_sql"
        execute_with_db2batch "$db" "$rebind_sql" 1 "${log_prefix}.rebind.log"
        if [ $? -eq 0 ]; then
            cecho BGREEN "REBIND für $db abgeschlossen."
        else
            cecho RED "Fehler bei REBIND für $db."
        fi
    fi

    cecho BGREEN "Wartung für $db abgeschlossen. Logs in $log_prefix.*"
    echo

    # Speichere Historie, wenn konfiguriert
    if [ "${config[general.enable_history]}" = "true" ]; then
        local history_file="$HISTORY_DIR/${db}_${TS}.json"
        mkdir -p "$HISTORY_DIR"
        echo "{\"database\": \"$db\", \"timestamp\": \"$(date -Iseconds)\", \"tables_processed\": $total_tables}" > "$history_file"
    fi
}


# Interaktiver Modus
interactive_mode() {
    cecho BGREEN "Interaktiver Modus"
    echo "Bitte wählen Sie die auszuführenden Aktionen:"
    if [ -z "$SPECIFIC_DB" ]; then
        echo "Verfügbare Datenbanken:"
        select db in "${databases[@]}"; do
            if [ -n "$db" ]; then
                SPECIFIC_DB="$db"
                break
            else
                cecho RED "Ungültige Auswahl"
            fi
        done
    fi
    echo "Welche Aktionen sollen ausgeführt werden?"
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
                cecho RED "Ungültige Auswahl"
                ;;
        esac
    done
    echo "Möchten Sie einen Tabellenfilter verwenden?"
    select filter_choice in "Ja" "Nein"; do
        case "$filter_choice" in
            "Ja")
                read -p "Geben Sie den Tabellenfilter ein: " TABLE_FILTER
                break
                ;;
            "Nein")
                TABLE_FILTER=""
                break
                ;;
            *)
                cecho RED "Ungültige Auswahl"
                ;;
        esac
    done
    echo "Welche Priorität soll für die Tabellenverarbeitung verwendet werden?"
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
                cecho RED "Ungültige Auswahl"
                ;;
        esac
    done
    echo "Möchten Sie den Force-Modus verwenden?"
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
                cecho RED "Ungültige Auswahl"
                ;;
        esac
    done
    cecho BGREEN "Zusammenfassung der ausgewählten Optionen:"
    echo "Datenbank: $SPECIFIC_DB"
    echo "Aktionen: $(if [ $SKIP_REORG -eq 0 ]; then echo "REORG "; fi)$(if [ $SKIP_RUNSTATS -eq 0 ]; then echo "RUNSTATS "; fi)$(if [ $SKIP_REBIND -eq 0 ]; then echo "REBIND"; fi)"
    echo "Tabellenfilter: ${TABLE_FILTER:-"Keiner"}"
    echo "Priorität: $TABLE_PRIORITY"
    echo "Force-Modus: $(if [ $FORCE_MODE -eq 1 ]; then echo "Ja"; else echo "Nein"; fi)"
    echo "Möchten Sie mit diesen Einstellungen fortfahren?"
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
                cecho RED "Ungültige Auswahl"
                ;;
        esac
    done
}

# Automatische Konfiguration durchführen
if [ $AUTO_CONFIG -eq 1 ]; then
    auto_configure
fi

# Systemressourcen prüfen
if [ $CHECK_RESOURCES -eq 1 ]; then
    check_system_resources
fi

# Datenbanken auflisten
if [ -n "$SPECIFIC_DB" ]; then
    databases=("$SPECIFIC_DB")
else
    databases=($(db2 list database directory | awk -F'= ' '/Datenbankname/ || /Database name/{print $2}'))
fi

if [ ${#databases[@]} -eq 0 ]; then
    cecho RED "Keine Datenbanken gefunden!"
    exit 1
fi

# Interaktiver Modus
if [ $INTERACTIVE -eq 1 ]; then
    interactive_mode
fi

# Ausgabe des Force-Modus
if [ $FORCE_MODE -eq 1 ]; then
    cecho BRED "ACHTUNG: Force-Modus aktiviert! REORG, RUNSTATS und REBIND werden für alle Tabellen ohne vorherige Prüfung durchgeführt."
fi

cecho BGREEN "=========================================="
cecho BGREEN "Starte DB2-Datenbankwartung... (Datum: $(date '+%d.%m.%Y %H:%M CEST'))"
cecho BGREEN "=========================================="
echo

# Haupt-Schleife: Sequentielle Verarbeitung
for db in "${databases[@]}"; do
    process_database "$db"
done

cecho BGREEN "==================================="
cecho BGREEN "DB2-Datenbankwartung abgeschlossen!"
cecho BGREEN "Logs in $LOG_DIR"
cecho BGREEN "==================================="
