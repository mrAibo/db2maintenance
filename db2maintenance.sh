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

# Hilfe-Funktion
show_help() {
    cecho BGREEN "Verwendung: $0 [OPTIONEN]"
    echo "Optionen:"
    echo "  --help                     Diese Hilfe anzeigen"
    echo "  --database DB              Nur eine spezifische Datenbank bearbeiten (z.B. --database MYDB)"
    echo "  --dry-run                 Simuliert die AusfÃ¼hrung ohne echte DB-Ã„nderungen"
    echo "  --parallel                Parallele Verarbeitung mehrerer Datenbanken (erfordert 'parallel' Tool)"
    echo "  --table-parallel N        Parallele Verarbeitung von Tabellen (Standard: auto)"
    echo "  --batch-size N            Batch-GrÃ¶ÃŸe fÃ¼r Operationen (Standard: auto)"
    echo "  --reorg-only              Nur REORG durchfÃ¼hren"
    echo "  --runstats-only           Nur RUNSTATS durchfÃ¼hren"
    echo "  --rebind-only             Nur REBIND durchfÃ¼hren"
    echo "  --skip-reorg              REORG-Schritt Ã¼berspringen"
    echo "  --skip-runstats           RUNSTATS-Schritt Ã¼berspringen"
    echo "  --skip-rebind             REBIND-Schritt Ã¼berspringen"
    echo "  --table-priority P        TabellenprioritÃ¤t: low, medium, high (Standard: medium)"
    echo "  --table-filter F          Filter fÃ¼r Tabellennamen (z.B. 'ICMADMIN.%')"
    echo "  --check-resources         Systemressourcen vor dem Start prÃ¼fen"
    echo "  --auto-config             Automatische Konfiguration aller Parameter (Standard)"
    echo "  --config-file F           Verwende spezifische Konfigurationsdatei"
    echo "  --profile P               Verwende spezifisches Profil (quick, thorough, minimal)"
    echo "  --interactive             Interaktiver Modus"
    echo "  --resume                 Setze unterbrochene Wartung fort"
    echo "  --test-mode              Testmodus - zeige nur, was getan wÃ¼rde"
    echo "  --progress                Zeige detaillierte Fortschrittsanzeige"
    echo "  --force                   Erzwingt REORG, RUNSTATS und REBIND fÃ¼r alle Tabellen ohne vorherige PrÃ¼fung"
    exit 0
}

# Standard-Konfiguration
DEFAULT_CONFIG=$(cat << 'EOF'
# DB2 Wartungskonfiguration
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
# TabellenprioritÃ¤t basierend auf verschiedenen Faktoren
size_weight = 0.3
access_weight = 0.4
overflow_weight = 0.2
stats_age_weight = 0.1

[profiles]
# Profile fÃ¼r verschiedene Wartungsszenarien
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

# Funktion zur sprachunabhÃ¤ngigen CPU-Auslastungsermittlung
get_cpu_usage() {
    # Versuche, mpstat zu verwenden
    if command -v mpstat >/dev/null 2>&1; then
        # Verwende sprachunabhÃ¤ngigen Muster
        mpstat 1 5 | awk '/Average:|Durchschn.:/{print 100 - $NF}'
    else
        # Fallback zu /proc/stat, wenn mpstat nicht verfÃ¼gbar
        local idle1=$(awk '/^cpu /{print $5}' /proc/stat)
        sleep 1
        local idle2=$(awk '/^cpu /{print $5}' /proc/stat)
        local idle_diff=$((idle2 - idle1))
        local total_diff=10  # 1 Sekunde * 10 (100ms pro Tick)
        echo "scale=2; (100 - ($idle_diff * 100 / $total_diff))" | bc
    fi
}

# Funktion zur automatischen Konfiguration
auto_configure() {
    cecho BYELLOW "FÃ¼hre automatische Konfiguration durch..."
    
    # CPU-Kerns ermitteln
    NUM_CORES=$(nproc)
    cecho BCYAN "Erkannte CPU-Kerne: $NUM_CORES"
    
    # Freien Speicher ermitteln
    FREE_MEM_GB=$(free -g | awk '/Mem:/ {print $7}')
    cecho BCYAN "Freier Speicher: ${FREE_MEM_GB}GB"
    
    # CPU-Auslastung sprachunabhÃ¤ngig ermitteln
    CPU_USAGE=$(get_cpu_usage)
    cecho BCYAN "CPU-Auslastung: ${CPU_USAGE}%"
    
    # Festplattenspeicher
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    cecho BCYAN "Festplattenspeicher: ${DISK_USAGE}% verwendet"
    
    # Automatische Konfiguration der ParallelitÃ¤t
    if [ "$TABLE_PARALLEL" = "auto" ]; then
        # Basis: Anzahl der Kerne, aber mindestens 1 und maximal aus Konfiguration
        TABLE_PARALLEL=$NUM_CORES
        local max_parallel=${config[general.max_table_parallel]}
        if [ $TABLE_PARALLEL -gt $max_parallel ]; then
            TABLE_PARALLEL=$max_parallel
        fi
        
        # Reduzierung bei hoher CPU-Auslastung
        if (( $(echo "$CPU_USAGE > 70" | bc -l) )); then
            TABLE_PARALLEL=$((TABLE_PARALLEL / 2))
            cecho BYELLOW "Reduziere Parallelisierung aufgrund hoher CPU-Auslastung auf $TABLE_PARALLEL"
        fi
        
        # Reduzierung bei geringem Speicher
        if [ "$FREE_MEM_GB" -lt 4 ]; then
            TABLE_PARALLEL=$((TABLE_PARALLEL / 2))
            cecho BYELLOW "Reduziere Parallelisierung aufgrund geringen Speichers auf $TABLE_PARALLEL"
        fi
        
        # Sicherstellen, dass mindestens 1 Thread verwendet wird
        if [ $TABLE_PARALLEL -lt 1 ]; then
            TABLE_PARALLEL=1
        fi
    fi
    
    # Automatische Konfiguration der Batch-GrÃ¶ÃŸe
    if [ "$BATCH_SIZE" = "auto" ]; then
        BATCH_SIZE=${config[general.default_batch_size]}
    fi
    
    cecho BGREEN "Automatische Konfiguration abgeschlossen:"
    cecho BGREEN "  - Tabellen-ParallelitÃ¤t: $TABLE_PARALLEL"
    cecho BGREEN "  - Batch-GrÃ¶ÃŸe: $BATCH_SIZE"
}

# Systemressourcen prÃ¼fen
check_system_resources() {
    cecho BYELLOW "PrÃ¼fe Systemressourcen..."
    
    # Freier Speicher
    FREE_MEM_GB=$(free -g | awk '/Mem:/ {print $7}')
    if [ "$FREE_MEM_GB" -lt 1 ]; then
        cecho RED "Nicht genÃ¼gend freier Speicher: ${FREE_MEM_GB}GB (mindestens 1GB erforderlich)"
        exit 1
    fi
    cecho GREEN "Freier Speicher: ${FREE_MEM_GB}GB"
    
    # CPU-Auslastung sprachunabhÃ¤ngig ermitteln
    CPU_USAGE=$(get_cpu_usage)
    if (( $(echo "$CPU_USAGE > 90" | bc -l) )); then
        cecho RED "CPU-Auslastung zu hoch: ${CPU_USAGE}%"
        exit 1
    fi
    cecho GREEN "CPU-Auslastung: ${CPU_USAGE}%"
    
    # Festplattenspeicher
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -gt 90 ]; then
        cecho RED "Festplattenspeicher zu voll: ${DISK_USAGE}%"
        exit 1
    fi
    cecho GREEN "Festplattenspeicher: ${DISK_USAGE}% verwendet"
}

# Funktion zur Fortschrittsanzeige
show_progress() {
    local current=$1
    local total=$2
    local operation=$3
    local table=$4
    
    if [ $PROGRESS -eq 1 ]; then
        local percent=$((current * 100 / total))
        local width=50
        local filled=$((percent * width / 100))
        local empty=$((width - filled))
        
        printf "\r[%-${filled}s%${empty}s] %d%% %s: %s" "=" " " "$percent" "$operation" "$table"
        
        if [ $current -eq $total ]; then
            echo ""
        fi
    fi
}

# Funktion zur PrÃ¼fung, ob REORG notwendig ist
needs_reorg() {
    local schema=$1
    local table=$2
    local db=$3
    
    # Im Force-Modus immer REORG durchfÃ¼hren
    if [ $FORCE_MODE -eq 1 ]; then
        echo "true"
        return
    fi
    
    # PrÃ¼fe Overflow
    if [ "${config[reorg.check_overflow]}" = "true" ]; then
        local overflow_threshold=${config[reorg.overflow_threshold]}
        local overflow=$(db2 -x "connect to $db > /dev/null 2>&1; SELECT COALESCE(OVERFLOW, 0) FROM SYSCAT.TABLES WHERE TABSCHEMA = '$schema' AND TABNAME = '$table'; connect reset")
        if [ "$overflow" -gt "$overflow_threshold" ] 2>/dev/null; then
            echo "true"
            return
        fi
    fi
    
    # PrÃ¼fe gelÃ¶schte Zeilen
    if [ "${config[reorg.check_deleted_rows]}" = "true" ]; then
        local deleted_threshold=${config[reorg.deleted_rows_threshold]}
        local deleted_rows=$(db2 -x "connect to $db > /dev/null 2>&1; SELECT COALESCE(DELETED_ROWS, 0) FROM SYSCAT.TABLES WHERE TABSCHEMA = '$schema' AND TABNAME = '$table'; connect reset")
        local total_rows=$(db2 -x "connect to $db > /dev/null 2>&1; SELECT COALESCE(CARD, 0) FROM SYSCAT.TABLES WHERE TABSCHEMA = '$schema' AND TABNAME = '$table'; connect reset")
        
        if [ "$total_rows" -gt 0 ] 2>/dev/null; then
            local deleted_percent=$((deleted_rows * 100 / total_rows))
            if [ "$deleted_percent" -gt "$deleted_threshold" ]; then
                echo "true"
                return
            fi
        fi
    fi
    
    # PrÃ¼fe Alter der Statistiken
    if [ "${config[reorg.check_stats_time]}" = "true" ]; then
        local stats_time_threshold=${config[reorg.stats_time_threshold_days]}
        local stats_age_days=$(db2 -x "connect to $db > /dev/null 2>&1; SELECT DAYS(CURRENT TIMESTAMP) - DAYS(COALESCE(STATS_TIME, CURRENT TIMESTAMP - 365 DAYS)) FROM SYSCAT.TABLES WHERE TABSCHEMA = '$schema' AND TABNAME = '$table'; connect reset")
        
        if [ "$stats_age_days" -gt "$stats_time_threshold" ]; then
            echo "true"
            return
        fi
    fi
    
    echo "false"
}

# Funktion zur Generierung von optimierten RUNSTATS-Parametern
get_runstats_params() {
    local schema=$1
    local table=$2
    local db=$3
    
    # Verbindung zur Datenbank herstellen
    db2 connect to $db > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        # Wenn die Verbindung fehlschlÃ¤gt, verwende Standardparameter
        echo "WITH DISTRIBUTION AND INDEXES ALL ALLOW WRITE ACCESS"
        return
    fi
    
    # TabellengrÃ¶ÃŸe abrufen
    local table_size=$(db2 -x "SELECT CARD FROM SYSCAT.TABLES WHERE TABSCHEMA = '$schema' AND TABNAME = '$table'" 2>/dev/null)
    
    # Verbindung trennen
    db2 connect reset > /dev/null 2>&1
    
    # Standardparameter
    local params="WITH DISTRIBUTION AND INDEXES ALL ALLOW WRITE ACCESS"
    
    # Im Force-Modus immer detaillierte Statistiken verwenden
    if [ $FORCE_MODE -eq 1 ]; then
        params="WITH DISTRIBUTION AND DETAILED INDEXES ALL ALLOW WRITE ACCESS"
        echo "$params"
        return
    fi
    
    # ÃœberprÃ¼fen, ob table_size eine gÃ¼ltige Ganzzahl ist
    if ! [[ "$table_size" =~ ^[0-9]+$ ]]; then
        # Wenn nicht, verwende Standardparameter
        echo "$params"
        return
    fi
    
    # FÃ¼r groÃŸe Tabellen detailliertere Statistiken
    if [ "${config[runstats.detailed_stats_large_tables]}" = "true" ]; then
        local large_table_threshold=${config[runstats.large_table_threshold]}
        if [ "$table_size" -gt "$large_table_threshold" ]; then
            params="WITH DISTRIBUTION AND DETAILED INDEXES ALL ALLOW WRITE ACCESS"
        fi
    fi
    
    # FÃ¼r kleine Tabellen Sampling verwenden
    if [ "${config[runstats.sample_small_tables]}" = "true" ]; then
        local small_table_threshold=${config[runstats.small_table_threshold]}
        local sample_rate=${config[runstats.sample_rate]}
        if [ "$table_size" -lt "$small_table_threshold" ]; then
            params="WITH DISTRIBUTION AND INDEXES ALL SAMPLE $sample_rate ALLOW WRITE ACCESS"
        fi
    fi
    
    echo "$params"
}


# Funktion fÃ¼r REORG/RUNSTATS/REBIND pro DB
process_database() {
    local db="$1"
    local log_prefix="${LOG_DIR}/${db}.${TS}"
    
    cecho BYELLOW "====================="
    cecho BYELLOW "Wartung fÃ¼r $db..."
    cecho BYELLOW "====================="
    
    # Verbindung herstellen
    if ! db2 connect to "$db" > /dev/null 2>&1; then
        cecho RED "Fehler: Konnte keine Verbindung zu $db herstellen"
        return 1
    fi
    
    # Tabellenliste generieren
    TABLES_LIST=$(mktemp -p "$TMP_DIR" tables_${db}.XXXXXX)
    
    # Basiseabfrage
    local query="SELECT RTRIM(TABSCHEMA) || '.' || RTRIM(TABNAME) FROM SYSCAT.TABLES WHERE TYPE = 'T' AND TABSCHEMA NOT LIKE 'SYS%'"
    
    # Filter anwenden, falls angegeben
    if [ -n "$TABLE_FILTER" ]; then
        query="$query AND TABNAME LIKE '${TABLE_FILTER#*.}'"
        if [[ "$TABLE_FILTER" == *"."* ]]; then
            local schema="${TABLE_FILTER%.*}"
            query="$query AND TABSCHEMA = '$schema'"
        fi
    fi
    
    # Abfrage ausfÃ¼hren
    db2 -x "$query" > "$TABLES_LIST"
    
    total_tables=$(wc -l < "$TABLES_LIST")
    if [ "$total_tables" -eq 0 ]; then
        cecho YELLOW "Keine Tabellen in $db gefunden. Ãœberspringe..."
        db2 connect reset > /dev/null
        return 0
    fi
    
    cecho BCYAN "Verarbeite $total_tables Tabellen in $db"
    
    # REORG (wenn nicht Ã¼bersprungen)
    if [ $SKIP_REORG -eq 0 ]; then
        if [ $FORCE_MODE -eq 1 ]; then
            cecho BYELLOW "Force-Modus aktiv: FÃ¼hre REORG fÃ¼r alle Tabellen durch"
        fi
        
        {
            echo "=== REORG Start: $(date) ==="
            
            current=0
            while IFS= read -r table; do
                current=$((current + 1))
                if [ $PROGRESS -eq 1 ]; then
                    show_progress $current $total_tables "REORG" "$table"
                fi
                
                # PrÃ¼fe, ob REORG notwendig ist (auÃŸer im Force-Modus)
                if [ $FORCE_MODE -eq 0 ]; then
                    schema=${table%.*}
                    tablename=${table#*.}
                    needs_reorg_result=$(needs_reorg "$schema" "$tablename" "$db")
                    if [ "$needs_reorg_result" = "false" ]; then
                        echo "REORG fÃ¼r $table nicht notwendig, Ã¼berspringe..."
                        continue
                    fi
                fi
                
                # FÃ¼hre REORG durch
                cmd="REORG TABLE $table INPLACE ALLOW WRITE ACCESS"
                if [ $DRY_RUN -eq 1 ]; then
                    echo "Dry-Run: WÃ¼rde ausfÃ¼hren: $cmd"
                else
                    echo "FÃ¼hre REORG durch fÃ¼r: $table"
                    db2 "$cmd" 2>&1 || echo "Fehler bei REORG fÃ¼r $table"
                fi
            done < "$TABLES_LIST"
            
            echo "=== REORG End: $(date) ==="
        } > "${log_prefix}.reorg.log" 2>&1
        
        cecho BGREEN "REORG fÃ¼r $db abgeschlossen."
    else
        cecho YELLOW "REORG fÃ¼r $db Ã¼bersprungen."
    fi
    
    # RUNSTATS (wenn nicht Ã¼bersprungen) - NACH REORG
    if [ $SKIP_RUNSTATS -eq 0 ]; then
        if [ $FORCE_MODE -eq 1 ]; then
            cecho BYELLOW "Force-Modus aktiv: FÃ¼hre RUNSTATS fÃ¼r alle Tabellen durch"
        fi
        
        {
            echo "=== RUNSTATS Start: $(date) ==="
            
            current=0
            while IFS= read -r table; do
                current=$((current + 1))
                if [ $PROGRESS -eq 1 ]; then
                    show_progress $current $total_tables "RUNSTATS" "$table"
                fi
                
                # Optimiere RUNSTATS-Parameter basierend auf TabellengrÃ¶ÃŸe
                schema=${table%.*}
                tablename=${table#*.}
                runstats_params=$(get_runstats_params "$schema" "$tablename" "$db")
                
                # FÃ¼hre RUNSTATS durch
                cmd="RUNSTATS ON TABLE $table $runstats_params"
                if [ $DRY_RUN -eq 1 ]; then
                    echo "Dry-Run: WÃ¼rde ausfÃ¼hren: $cmd"
                else
                    echo "FÃ¼hre RUNSTATS durch fÃ¼r: $table"
                    db2 "$cmd" 2>&1 || echo "Fehler bei RUNSTATS fÃ¼r $table"
                fi
            done < "$TABLES_LIST"
            
            echo "=== RUNSTATS End: $(date) ==="
        } > "${log_prefix}.runstats.log" 2>&1
        
        cecho BGREEN "RUNSTATS fÃ¼r $db abgeschlossen."
    else
        cecho YELLOW "RUNSTATS fÃ¼r $db Ã¼bersprungen."
    fi
    
    # REBIND (wenn nicht Ã¼bersprungen) - NACH RUNSTATS
    if [ $SKIP_REBIND -eq 0 ]; then
        cecho BYELLOW "Starte REBIND fÃ¼r $db..."
        {
            echo "=== REBIND Start: $(date) ==="
            
            # ADMIN_CMD fÃ¼r effizientere REVALIDATE-Operationen
            if [ $DRY_RUN -eq 1 ]; then
                echo "Dry-Run: WÃ¼rde ausfÃ¼hren: CALL SYSPROC.ADMIN_REVALIDATE_DB_OBJECTS(NULL, NULL, NULL)"
            else
                db2 "CALL SYSPROC.ADMIN_REVALIDATE_DB_OBJECTS(NULL, NULL, NULL)" || echo "Fehler bei ADMIN_REVALIDATE_DB_OBJECTS"
            fi
            
            # Im Force-Modus alle Pakete neu binden, nicht nur ungÃ¼ltige
            if [ $FORCE_MODE -eq 1 ]; then
                cecho BYELLOW "Force-Modus aktiv: FÃ¼hre REBIND fÃ¼r alle Pakete durch"
                db2 -x "SELECT RTRIM(PKGSCHEMA) || '.' || RTRIM(PKGNAME)
                        FROM SYSCAT.PACKAGES
                        WHERE PKGSCHEMA NOT LIKE 'SYS%'
                        AND PKGSCHEMA NOT IN ('NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSPROC')" > "$TMP_DIR/all_packages_${db}.lst"
            else
                # Nur ungÃ¼ltige Pakete neu binden, wenn konfiguriert
                if [ "${config[rebind.rebind_invalid_only]}" = "true" ]; then
                    db2 -x "SELECT RTRIM(PKGSCHEMA) || '.' || RTRIM(PKGNAME)
                            FROM SYSCAT.PACKAGES
                            WHERE PKGSCHEMA NOT LIKE 'SYS%'
                            AND PKGSCHEMA NOT IN ('NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSPROC')
                            AND VALID = 'N'" > "$TMP_DIR/invalid_packages_${db}.lst"
                else
                    db2 -x "SELECT RTRIM(PKGSCHEMA) || '.' || RTRIM(PKGNAME)
                            FROM SYSCAT.PACKAGES
                            WHERE PKGSCHEMA NOT LIKE 'SYS%'
                            AND PKGSCHEMA NOT IN ('NULLID', 'SYSIBMADM', 'SYSIBMINTERNAL', 'SYSPROC')" > "$TMP_DIR/invalid_packages_${db}.lst"
                fi
            fi
            
            # Verwende die richtige Paketliste
            if [ $FORCE_MODE -eq 1 ]; then
                packages_list="$TMP_DIR/all_packages_${db}.lst"
            else
                packages_list="$TMP_DIR/invalid_packages_${db}.lst"
            fi
            
            if [ -s "$packages_list" ]; then
                total_packages=$(wc -l < "$packages_list")
                current=0
                while IFS= read -r package; do
                    current=$((current + 1))
                    if [ $PROGRESS -eq 1 ]; then
                        show_progress $current $total_packages "REBIND" "$package"
                    fi
                    
                    # FÃ¼hre REBIND durch
                    if [ $DRY_RUN -eq 1 ]; then
                        echo "Dry-Run: WÃ¼rde ausfÃ¼hren: REBIND PACKAGE $package"
                    else
                        echo "FÃ¼hre REBIND durch fÃ¼r: $package"
                        db2 connect to "$db" > /dev/null 2>&1
                        db2 "REBIND PACKAGE $package" 2>&1 || echo "Fehler bei REBIND PACKAGE $package"
                        db2 connect reset > /dev/null 2>&1
                    fi
                done < "$packages_list"
            else
                echo "Keine Pakete zum Binden gefunden."
            fi
            echo "=== REBIND End: $(date) ==="
        } > "${log_prefix}.rebind.log" 2>&1
        
        cecho BGREEN "REBIND fÃ¼r $db abgeschlossen."
    else
        cecho YELLOW "REBIND fÃ¼r $db Ã¼bersprungen."
    fi
    
    # Verbindung resetten
    db2 connect reset > /dev/null
    cecho BGREEN "Wartung fÃ¼r $db abgeschlossen. Logs in $log_prefix.*"
    echo
    
    # Historie speichern, wenn aktiviert
    if [ "${config[general.enable_history]}" = "true" ]; then
        local history_file="$HISTORY_DIR/${db}_${TS}.json"
        echo "{\"database\": \"$db\", \"timestamp\": \"$(date -Iseconds)\", \"tables_processed\": $total_tables}" > "$history_file"
    fi
}

# Interaktiver Modus
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
    databases=($(db2 list database directory | awk -F'= ' '/Datenbankname/ || /Database name/{print $2}'))
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

# Haupt-Schleife: Sequentielle Verarbeitung
for db in "${databases[@]}"; do
    process_database "$db"
done

cecho BGREEN "==================================="
cecho BGREEN "DB2-Datenbankwartung abgeschlossen!"
cecho BGREEN "Logs in $LOG_DIR"
cecho BGREEN "==================================="
