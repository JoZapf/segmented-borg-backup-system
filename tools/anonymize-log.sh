#!/usr/bin/env bash
# tools/anonymize-log.sh
# @version 1.1.0
# @description Anonymizes backup logs for public sharing (GitHub portfolio)
# @author Jo Zapf
# @date 2026-02-12
#
# Three-layer anonymization:
#   1. Bulk stripping: Borg progress, SQL dump rows, container log excerpts
#   2. secrets.env value replacement (auto-generates <VAR_NAME> placeholders)
#      - Resolves ${VAR} references within values before matching
#   3. Regex patterns (IPs, hostnames + variants, serial numbers, hashes, domains)
#
# Zero maintenance: new secrets in secrets.env are anonymized automatically.
# New segments/features need no changes unless they introduce new pattern types.
#
# Usage:
#   ./anonymize-log.sh <logfile>                    # Output to stdout
#   ./anonymize-log.sh <logfile> > anonymized.log   # Output to file
#
# Environment variables (optional):
#   SECRETS_FILE    - Path to secrets.env (default: ../config/secrets.env)
#   ANON_HOSTNAME   - Hostname to replace (default: auto-detect)
#   ANON_DOMAINS    - Space-separated private domains to replace
#   ANON_PATTERNS   - Space-separated extra strings to anonymize
#
# Example:
#   ANON_DOMAINS="mycloud.ddns.net homelab.local" \
#   ANON_PATTERNS="extraPattern" \
#     ./tools/anonymize-log.sh docs/dev-data_2026-02-12.log > docs/examples/dev-data.log

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${1:?Usage: $0 <logfile> [> output.log]}"
SECRETS_FILE="${SECRETS_FILE:-${SCRIPT_DIR}/../config/secrets.env}"
ANON_HOSTNAME="${ANON_HOSTNAME:-$(hostname 2>/dev/null || echo "")}"
ANON_DOMAINS="${ANON_DOMAINS:-}"
ANON_PATTERNS="${ANON_PATTERNS:-}"
SCRIPT_VERSION="1.1.0"

if [ ! -f "$LOG_FILE" ]; then
    echo "[ERROR] Log file not found: $LOG_FILE" >&2
    exit 1
fi

if [ ! -f "$SECRETS_FILE" ]; then
    echo "[ERROR] Secrets file not found: $SECRETS_FILE" >&2
    echo "[ERROR] Set SECRETS_FILE env var or ensure secrets.env exists at:" >&2
    echo "[ERROR]   ${SCRIPT_DIR}/../config/secrets.env" >&2
    exit 1
fi

# ============================================================================
# Phase 1: Strip bulk sensitive output (awk)
# ============================================================================
# Removes large blocks of sensitive data while preserving log structure:
#   - Borg --progress output (thousands of lines with real file paths)
#   - SQL dump data rows from health check (contain usernames, file paths, URLs)
#   - Container log excerpts in POST segments (unpredictable content)
#   - grep broken pipe errors (side effect of health check piping)

phase1_strip_bulk() {
    awk '
    BEGIN {
        borg_progress = 0
        sql_rows = 0
        container_logs = 0
        in_container_logs = 0
    }

    # --- Borg progress lines ---
    # Pattern: "SIZE UNIT O SIZE UNIT C SIZE UNIT D COUNT N PATH"
    /^[0-9. ]+(B|kB|MB|GB|TB) O [0-9]/ {
        borg_progress++
        next
    }
    /^Initializing cache transaction:/ {
        borg_progress++
        next
    }
    # End of borg progress block
    /^Saving files cache|^Saving chunks cache|^Saving cache config|^-{10,}/ {
        if (borg_progress > 0) {
            printf "[...borg progress removed: %d lines with file-level detail...]\n\n", borg_progress
            borg_progress = 0
        }
        print
        next
    }

    # --- SQL dump data rows from health check ---
    # Pattern: [PRE-01]   (12345,1752259430,30,... - raw database rows
    /^\[PRE-01\][[:space:]]+[(][0-9]+,/ {
        sql_rows++
        next
    }
    # grep broken pipe from health check (side effect, not a real error)
    /^grep:.*([Bb]roken pipe|Datenübergabe unterbrochen)/ {
        next
    }

    # --- Container log excerpts in POST segments ---
    # Start: "[POST-xx] Last N log lines:"
    /^\[POST-[0-9]+\] Last [0-9]+ log lines:/ {
        in_container_logs = 1
        container_logs = 0
        print
        next
    }
    # Inside container log block: lines starting with [POST-xx]   (indented content)
    in_container_logs && /^\[POST-[0-9]+\][[:space:]]{3,}/ {
        container_logs++
        next
    }
    # End of container log block: next non-indented POST line
    in_container_logs && !/^\[POST-[0-9]+\][[:space:]]{3,}/ {
        if (container_logs > 0) {
            printf "[...container log output removed: %d lines...]\n", container_logs
        }
        in_container_logs = 0
        container_logs = 0
    }

    # --- Default: flush pending counters and print ---
    {
        if (borg_progress > 0) {
            printf "[...borg progress removed: %d lines with file-level detail...]\n\n", borg_progress
            borg_progress = 0
        }
        if (sql_rows > 0) {
            printf "[PRE-01]   [...SQL data rows removed: %d rows with personal data...]\n", sql_rows
            sql_rows = 0
        }
        print
    }

    END {
        if (borg_progress > 0)
            printf "[...borg progress removed: %d lines with file-level detail...]\n", borg_progress
        if (sql_rows > 0)
            printf "[PRE-01]   [...SQL data rows removed: %d rows...]\n", sql_rows
        if (container_logs > 0)
            printf "[...container log output removed: %d lines...]\n", container_logs
    }
    '
}

# ============================================================================
# Phase 2: Build sed commands from secrets.env
# ============================================================================
# Two passes:
#   Pass 1: Parse all VAR=value pairs into an associative array
#   Pass 2: Resolve ${VAR} references, then build sed replacements
# Sorted by resolved value length (longest first) to prevent partial matches.

build_secrets_sed() {
    # Pass 1: collect all raw values
    declare -A raw_values
    local -a var_order=()

    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        if [[ "$line" =~ ^[[:space:]]*export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=[\"\']*([^\"\']+)[\"\']*[[:space:]]*$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            var_value="${var_value%\"}"
            var_value="${var_value%\'}"
            raw_values["$var_name"]="$var_value"
            var_order+=("$var_name")
        fi
    done < "$SECRETS_FILE"

    # Pass 2: resolve ${VAR} references and build replacement pairs
    local -a pairs=()

    for var_name in "${var_order[@]}"; do
        local var_value="${raw_values[$var_name]}"

        # Resolve ${VAR} and $VAR references using other parsed values
        for ref_name in "${var_order[@]}"; do
            var_value="${var_value//\$\{${ref_name}\}/${raw_values[$ref_name]}}"
            var_value="${var_value//\$${ref_name}/${raw_values[$ref_name]}}"
        done

        # Skip short values (avoid false positives)
        [ "${#var_value}" -lt 4 ] && continue

        # Skip booleans and pure numbers
        [[ "$var_value" =~ ^(true|false|yes|no|[0-9]+)$ ]] && continue

        pairs+=("$(printf '%04d' "${#var_value}"):${var_name}:${var_value}")
    done

    # Sort by resolved value length descending (longest match first)
    local sorted
    sorted=$(printf '%s\n' "${pairs[@]}" | sort -t: -k1 -rn)

    local sed_cmds=""
    while IFS=: read -r _len var_name var_value; do
        [ -z "${var_value:-}" ] && continue

        # Escape sed special characters (using | as delimiter)
        local escaped
        escaped=$(printf '%s' "$var_value" | sed 's/[&|\\^$*+?{}()[\]]/\\&/g')

        sed_cmds="${sed_cmds}s|${escaped}|<${var_name}>|g
"
    done <<< "$sorted"

    echo "$sed_cmds"
}

# ============================================================================
# Phase 3: Regex patterns for remaining sensitive data
# ============================================================================

build_regex_sed() {
    local sed_cmds=""

    # Hostname + auto-generated variants
    if [ -n "$ANON_HOSTNAME" ]; then
        local -a host_variants=()

        # Original: CREA-think
        host_variants+=("$ANON_HOSTNAME")

        # Without dashes/underscores: CREAthink
        local no_sep="${ANON_HOSTNAME//[-_]/}"
        [ "$no_sep" != "$ANON_HOSTNAME" ] && host_variants+=("$no_sep")

        # Lowercase: crea-think, creathink
        local lower="${ANON_HOSTNAME,,}"
        [ "$lower" != "$ANON_HOSTNAME" ] && host_variants+=("$lower")
        local lower_no_sep="${no_sep,,}"
        [ "$lower_no_sep" != "$no_sep" ] && [ "$lower_no_sep" != "$lower" ] && host_variants+=("$lower_no_sep")

        # CamelCase: split on dash/underscore, capitalize each part
        local camel=""
        local IFS_BAK="$IFS"
        IFS='-_' read -ra parts <<< "$ANON_HOSTNAME"
        IFS="$IFS_BAK"
        for part in "${parts[@]}"; do
            camel+="${part^}"
        done
        [ "$camel" != "$ANON_HOSTNAME" ] && host_variants+=("$camel")

        # lowerCamelCase: CreaThink -> creaThink
        local lower_camel="${camel,}"
        [ "$lower_camel" != "$camel" ] && host_variants+=("$lower_camel")

        # Sort by length descending, deduplicate (case-insensitive)
        local sorted_variants
        sorted_variants=$(printf '%s\n' "${host_variants[@]}" | awk '{ print length, $0 }' | sort -rn | awk '{ print $2 }' | awk '!seen[tolower($0)]++')

        while IFS= read -r variant; do
            [ -z "$variant" ] && continue
            local escaped_v
            escaped_v=$(printf '%s' "$variant" | sed 's/[&/\\.^$*+?{}|()[\]]/\\&/g')
            sed_cmds="${sed_cmds}s/${escaped_v}/<HOSTNAME>/gI
"
        done <<< "$sorted_variants"
    fi

    # Private domains
    for domain in $ANON_DOMAINS; do
        local escaped_domain
        escaped_domain=$(printf '%s' "$domain" | sed 's/[&/\\.^$*+?{}|()[\]]/\\&/g')
        sed_cmds="${sed_cmds}s/${escaped_domain}/<PRIVATE_DOMAIN>/gI
"
    done

    # Extra patterns
    for pattern in $ANON_PATTERNS; do
        local escaped_pattern
        escaped_pattern=$(printf '%s' "$pattern" | sed 's/[&/\\.^$*+?{}|()[\]]/\\&/g')
        sed_cmds="${sed_cmds}s/${escaped_pattern}/<ANON>/gI
"
    done

    # Disk serial numbers in by-id paths: ata-WDC_WD4003FFBX-68MU3N0_V300ZSMF
    sed_cmds="${sed_cmds}s/ata-[A-Za-z0-9_-]\{10,\}/<DISK_BY_ID>/g
"

    # 64-char hex strings (repository IDs, archive fingerprints)
    sed_cmds="${sed_cmds}s/[0-9a-f]\{64\}/<HASH_64>/g
"

    # 12-char hex strings in parentheses - Docker container IDs
    sed_cmds="${sed_cmds}s/([0-9a-f]\{12\})/(<CID>)/g
"

    # 12-char hex standalone Docker container IDs (table output)
    sed_cmds="${sed_cmds}s/^[0-9a-f]\{12\}[[:space:]]/<CID>   /g
"

    # IPv4 addresses
    sed_cmds="${sed_cmds}s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/<IP_ADDR>/g
"

    echo "$sed_cmds"
}

# ============================================================================
# Execute anonymization pipeline
# ============================================================================

SECRETS_SED=$(build_secrets_sed)
REGEX_SED=$(build_regex_sed)

# Temp files for sed scripts (avoids "argument list too long")
SECRETS_SED_FILE=$(mktemp)
REGEX_SED_FILE=$(mktemp)
trap 'rm -f "$SECRETS_SED_FILE" "$REGEX_SED_FILE"' EXIT

echo "$SECRETS_SED" > "$SECRETS_SED_FILE"
echo "$REGEX_SED" > "$REGEX_SED_FILE"

# Header
cat <<EOF
# ============================================================================
# ANONYMIZED LOG - Sanitized for public sharing
# Tool: anonymize-log.sh v${SCRIPT_VERSION}
# Date: $(date -Iseconds)
# Original: $(basename "$LOG_FILE")
#
# Removed: secrets, credentials, hostnames, IPs, serial numbers,
#          borg file-level progress, SQL data rows, container logs
# ============================================================================

EOF

# Pipeline: strip bulk -> replace secrets -> apply regex
phase1_strip_bulk < "$LOG_FILE" \
    | sed -f "$SECRETS_SED_FILE" \
    | sed -f "$REGEX_SED_FILE"
