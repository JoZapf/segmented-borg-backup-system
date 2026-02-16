#!/usr/bin/env bash
# generate-segment-docs.sh
# @version 1.3.0
# @description Generates comprehensive API documentation from segment scripts (config-driven)
# @author Jo Zapf
# @changed 2026-02-16

# NO set -euo pipefail - we want to continue on errors
set -u

# ============================================================================
# CONFIGURATION LOADING
# ============================================================================

# Determine script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_ROOT is one level up from tools/
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CONFIG_FILE="${PROJECT_ROOT}/config/secrets.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "==============================================================================="
echo "  Segment Documentation Generator"
echo "==============================================================================="
echo ""

# Load configuration
if [ ! -f "${CONFIG_FILE}" ]; then
    echo -e "${RED}[ERROR]${NC} Configuration file not found: ${CONFIG_FILE}"
    echo "        This script requires config/secrets.env with documentation paths"
    exit 1
fi

# Source configuration (safe: only export statements)
source "${CONFIG_FILE}"

# Validate required configuration variables
if [ -z "${DOCS_SEGMENTS_DIR:-}" ]; then
    echo -e "${RED}[ERROR]${NC} Missing required variable: DOCS_SEGMENTS_DIR"
    echo "        Add to config/secrets.env: export DOCS_SEGMENTS_DIR=\"segments\""
    exit 1
fi

if [ -z "${DOCS_API_OUTPUT_DIR:-}" ]; then
    echo -e "${RED}[ERROR]${NC} Missing required variable: DOCS_API_OUTPUT_DIR"
    echo "        Add to config/secrets.env: export DOCS_API_OUTPUT_DIR=\"docs/api\""
    exit 1
fi

# Resolve paths relative to project root
SEGMENTS_DIR="${PROJECT_ROOT}/${DOCS_SEGMENTS_DIR}"
OUTPUT_DIR="${PROJECT_ROOT}/${DOCS_API_OUTPUT_DIR}"
SCRIPT_NAME="$(basename "$0")"

# Validate paths exist
if [ ! -d "${SEGMENTS_DIR}" ]; then
    echo -e "${RED}[ERROR]${NC} Segments directory not found: ${SEGMENTS_DIR}"
    exit 1
fi

echo -e "${BLUE}[INFO]${NC} Configuration loaded from ${CONFIG_FILE}"
echo -e "${BLUE}[INFO]${NC} Segments directory: ${SEGMENTS_DIR}"
echo -e "${BLUE}[INFO]${NC} Output directory: ${OUTPUT_DIR}"
echo ""

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# ============================================================================
# EXTRACTION FUNCTIONS
# ============================================================================

# Function to extract header information (safe)
extract_header() {
    local file="$1"
    local tag="$2"
    grep "^# @${tag}" "${file}" 2>/dev/null | sed "s/^# @${tag} *//" | head -1 || echo ""
}

# Function to extract required variables (safe)
extract_required_vars() {
    local file="$1"
    awk '/required_vars=\(/,/\)/ {print}' "${file}" 2>/dev/null | \
        grep '"' 2>/dev/null | \
        sed 's/.*"\(.*\)".*/\1/' 2>/dev/null | \
        sort 2>/dev/null || echo ""
}

# Function to extract required commands (safe)
extract_required_commands() {
    local file="$1"
    awk '/required_commands=\(/,/\)/ {print}' "${file}" 2>/dev/null | \
        grep '"' 2>/dev/null | \
        sed 's/.*"\(.*\)".*/\1/' 2>/dev/null | \
        sort 2>/dev/null || echo ""
}

# Function to extract error messages (safe)
extract_error_messages() {
    local file="$1"
    grep 'echo.*\[ERROR\]' "${file}" 2>/dev/null | \
        sed 's/.*\[ERROR\] //' 2>/dev/null | \
        sed 's/"$//' 2>/dev/null | \
        sed 's/\${.*}/[VALUE]/' 2>/dev/null | \
        sort -u 2>/dev/null || echo ""
}

# Function to extract exit codes (safe)
extract_exit_codes() {
    local file="$1"
    {
        grep -n "exit 0" "${file}" 2>/dev/null | head -3
        grep -n "exit 1" "${file}" 2>/dev/null | head -5
    } | sort -t: -k1 -n 2>/dev/null || echo ""
}

# Function to extract success messages (safe)
extract_success_messages() {
    local file="$1"
    local segment_num=$(basename "${file}" | grep -oP '^\d+' 2>/dev/null || echo "00")
    grep "echo.*\[${segment_num}\]" "${file}" 2>/dev/null | \
        grep -v '\[ERROR\]' 2>/dev/null | \
        sed "s/.*echo \"//" 2>/dev/null | \
        sed 's/"$//' 2>/dev/null | \
        head -5 2>/dev/null || echo ""
}

# Function to extract conditional dependencies (safe)
extract_conditional_deps() {
    local file="$1"
    grep -A5 'if \[.*ENABLED' "${file}" 2>/dev/null | \
        grep -E 'command -v|which' 2>/dev/null | \
        sed 's/.*command -v //' 2>/dev/null | \
        sed 's/.*which //' 2>/dev/null | \
        sed 's/ .*//' 2>/dev/null | \
        tr -d '"' 2>/dev/null | \
        sort -u 2>/dev/null || echo ""
}

# ============================================================================
# DOCUMENTATION GENERATION
# ============================================================================

# Function to generate documentation for a segment
generate_segment_doc() {
    local segment_file="$1"
    local segment_name=$(basename "${segment_file}" .sh)
    local segment_num=$(echo "${segment_name}" | grep -oP '^\d+' 2>/dev/null || echo "00")
    local output_file="${OUTPUT_DIR}/${segment_name}.md"
    
    echo -e "${BLUE}[INFO]${NC} Generating documentation for ${segment_name}..."
    
    # Extract metadata
    local version=$(extract_header "${segment_file}" "version")
    local description=$(extract_header "${segment_file}" "description")
    local author=$(extract_header "${segment_file}" "author")
    local changed=$(extract_header "${segment_file}" "changed")
    local requires=$(extract_header "${segment_file}" "requires")
    
    # Set defaults if empty
    version="${version:-1.0.0}"
    description="${description:-No description available}"
    author="${author:-Unknown}"
    changed="${changed:-Unknown}"
    
    # Extract code analysis
    local required_vars=$(extract_required_vars "${segment_file}")
    local required_commands=$(extract_required_commands "${segment_file}")
    local error_messages=$(extract_error_messages "${segment_file}")
    local success_messages=$(extract_success_messages "${segment_file}")
    local conditional_deps=$(extract_conditional_deps "${segment_file}")
    
    # Generate markdown
    cat > "${output_file}" <<EOF
# Segment ${segment_num}: ${description}

**Version:** ${version} | **Author:** ${author} | **Changed:** ${changed}

## Overview

${description}

EOF

    # Prerequisites section
    if [ -n "${required_vars}" ] || [ -n "${required_commands}" ]; then
        cat >> "${output_file}" <<EOF
## Prerequisites

EOF
        
        # Required environment variables
        if [ -n "${required_vars}" ]; then
            cat >> "${output_file}" <<EOF
**Required Environment Variables:**

EOF
            while IFS= read -r var; do
                [ -n "${var}" ] && echo "- \`${var}\`" >> "${output_file}"
            done <<< "${required_vars}"
            echo "" >> "${output_file}"
            echo "*See segment source code and [PROFILES.md](../PROFILES.md) for variable descriptions and usage.*" >> "${output_file}"
            echo "" >> "${output_file}"
        fi
        
        # Required commands
        if [ -n "${required_commands}" ]; then
            cat >> "${output_file}" <<EOF
**Required Commands:**

EOF
            while IFS= read -r cmd; do
                [ -n "${cmd}" ] && echo "- \`${cmd}\`" >> "${output_file}"
            done <<< "${required_commands}"
            echo "" >> "${output_file}"
        fi
        
        # Conditional dependencies
        if [ -n "${conditional_deps}" ]; then
            cat >> "${output_file}" <<EOF
**Conditional Dependencies:**

EOF
            while IFS= read -r dep; do
                [ -n "${dep}" ] && echo "- \`${dep}\` - Required under certain conditions" >> "${output_file}"
            done <<< "${conditional_deps}"
            echo "" >> "${output_file}"
        fi
    fi
    
    # Behavior section
    if [ -n "${error_messages}" ] || [ -n "${success_messages}" ]; then
        cat >> "${output_file}" <<EOF
## Behavior

EOF
        
        if [ -n "${success_messages}" ]; then
            cat >> "${output_file}" <<EOF
**Success Path:**

\`\`\`
EOF
            while IFS= read -r msg; do
                [ -n "${msg}" ] && echo "${msg}" >> "${output_file}"
            done <<< "${success_messages}"
            cat >> "${output_file}" <<EOF
\`\`\`

EOF
        fi
        
        if [ -n "${error_messages}" ]; then
            cat >> "${output_file}" <<EOF
**Failure Conditions:**

EOF
            while IFS= read -r msg; do
                [ -n "${msg}" ] && echo "- ${msg}" >> "${output_file}"
            done <<< "${error_messages}"
            echo "" >> "${output_file}"
        fi
    fi
    
    # Exit codes section
    cat >> "${output_file}" <<EOF
## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - segment completed successfully |
| 1 | Failure - see error output for details |

EOF
    
    # Integration section
    if [ -n "${requires}" ]; then
        cat >> "${output_file}" <<EOF
## Integration

**Depends on:**

EOF
        IFS=',' read -ra DEPS <<< "${requires}"
        for dep in "${DEPS[@]}"; do
            dep=$(echo "${dep}" | xargs 2>/dev/null || echo "${dep}") # trim whitespace
            [ -n "${dep}" ] && echo "- \`${dep}\`" >> "${output_file}"
        done
        echo "" >> "${output_file}"
    fi
    
    # Source file reference
    cat >> "${output_file}" <<EOF
## Source

[\`${segment_name}.sh\`](../${DOCS_SEGMENTS_DIR}/${segment_name}.sh)

---

*Generated by ${SCRIPT_NAME} on $(date '+%Y-%m-%d %H:%M:%S')*
EOF
    
    echo -e "${GREEN}[✓]${NC} Generated ${output_file}"
}

# Function to generate index file
generate_index() {
    local index_file="${OUTPUT_DIR}/README.md"
    
    echo -e "${BLUE}[INFO]${NC} Generating index file..."
    
    cat > "${index_file}" <<EOF
# Segment API Reference

This directory contains auto-generated documentation for all backup system segments.

## Core Segments

EOF
    
    # List all segment docs
    for segment in $(ls "${SEGMENTS_DIR}"/*.sh 2>/dev/null | sort); do
        local segment_name=$(basename "${segment}" .sh)
        local segment_num=$(echo "${segment_name}" | grep -oP '^\d+' 2>/dev/null || echo "00")
        local description=$(extract_header "${segment}" "description")
        description="${description:-No description}"
        
        echo "- [${segment_num} - ${description}](${segment_name}.md)" >> "${index_file}"
    done
    
    cat >> "${index_file}" <<EOF

## Generation

Documentation is automatically generated from segment source files using:

\`\`\`bash
./tools/generate-segment-docs.sh
\`\`\`

Configuration paths defined in: \`config/secrets.env\`

Last generated: $(date '+%Y-%m-%d %H:%M:%S')

## Guidelines

- This documentation is **auto-generated** - do not edit manually
- Update segment source code comments to improve documentation
- Ensure \`DOCS_SEGMENTS_DIR\` and \`DOCS_API_OUTPUT_DIR\` are set in \`config/secrets.env\`
- Run \`./tools/generate-segment-docs.sh\` after changes

---

*For development guidelines, see [../AI_GUIDELINES.md](../AI_GUIDELINES.md)*
EOF
    
    echo -e "${GREEN}[✓]${NC} Generated ${index_file}"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo "Processing segments in ${SEGMENTS_DIR}/..."
    echo ""
    
    local segment_count=0
    local failed_count=0
    
    # Process all segment files
    for segment in "${SEGMENTS_DIR}"/*.sh; do
        if [ -f "${segment}" ]; then
            if generate_segment_doc "${segment}"; then
                ((segment_count++))
            else
                ((failed_count++))
                echo -e "${RED}[ERROR]${NC} Failed to generate documentation for ${segment}"
            fi
        fi
    done
    
    echo ""
    generate_index
    
    echo ""
    echo "==============================================================================="
    if [ ${failed_count} -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS]${NC} Generated documentation for ${segment_count} segments"
    else
        echo -e "${YELLOW}[WARNING]${NC} Generated documentation for ${segment_count} segments (${failed_count} failed)"
    fi
    echo "           Output directory: ${OUTPUT_DIR}/"
    echo "           Index: ${OUTPUT_DIR}/README.md"
    echo "==============================================================================="
}

# Run
main "$@"
