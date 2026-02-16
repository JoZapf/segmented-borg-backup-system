# generate-segment-docs Runbook

## Overview

`generate-segment-docs.sh` is a configuration-driven documentation generator that automatically extracts metadata from segment scripts and produces comprehensive API reference documentation in Markdown format.

**Purpose:** Transform segment source code annotations into discoverable, version-tracked API documentation using paths defined in `config/secrets.env`.

---

## Prerequisites

### Configuration Requirement

The script reads path configuration from `config/secrets.env`:

```bash
# config/secrets.env (required variables)
export DOCS_SEGMENTS_DIR="segments"
export DOCS_API_OUTPUT_DIR="docs/api"
```

**Both variables must be present** for the script to execute. The configuration file is sourced at runtime and paths are resolved relative to project root.

### System Requirements

- **Windows:** Git Bash or WSL2 (bash execution environment)
- **Linux:** Bash shell (pre-installed)

---

## Windows (PowerShell)

### Step 1: Verify Configuration

Ensure `config/secrets.env` contains documentation paths:

```powershell
# Verify from project root
type .\config\secrets.env | findstr /C:"DOCS_"
```

Output should show:
```
export DOCS_SEGMENTS_DIR="segments"
export DOCS_API_OUTPUT_DIR="docs/api"
```

### Step 2: Execute Script

#### Option A: Using Git Bash

```powershell
cd E:\Projects\linux-backup-system\tools
bash generate-segment-docs.sh
```

#### Option B: Using WSL2

```powershell
wsl -e bash -c "cd /mnt/e/Projects/linux-backup-system/tools && bash generate-segment-docs.sh"
```

#### Option C: From Project Root

```powershell
cd E:\Projects\linux-backup-system
bash ./tools/generate-segment-docs.sh
```

### Step 3: Verify Output

```powershell
# Check exit code
echo $LASTEXITCODE  # 0 = success

# List generated files
ls .\docs\api\

# View index
notepad .\docs\api\README.md
```

---

## Linux (Terminal)

### Step 1: Verify Configuration

Ensure `config/secrets.env` contains documentation paths:

```bash
cd ~/Projects/linux-backup-system
grep "DOCS_" config/secrets.env
```

Output should show:
```
export DOCS_SEGMENTS_DIR="segments"
export DOCS_API_OUTPUT_DIR="docs/api"
```

### Step 2: Prepare Script

Make script executable (first time only):

```bash
chmod +x ./tools/generate-segment-docs.sh
```

### Step 3: Execute Script

#### From Project Root

```bash
./tools/generate-segment-docs.sh
```

#### From Tools Directory

```bash
cd tools
./generate-segment-docs.sh
```

### Step 4: Verify Output

```bash
# Check exit status
echo $?  # 0 = success, non-zero = error

# List generated files
ls -la docs/api/

# View index
cat docs/api/README.md
```

---

## Configuration Deep-Dive

### Required Variables in `config/secrets.env`

| Variable | Purpose | Example |
|----------|---------|---------|
| `DOCS_SEGMENTS_DIR` | Input directory (relative to project root) | `segments` |
| `DOCS_API_OUTPUT_DIR` | Output directory (relative to project root) | `docs/api` |

### Path Resolution

The script uses **relative paths from project root**:

```bash
# Configuration-driven path resolution
PROJECT_ROOT = /path/to/linux-backup-system/
SEGMENTS = ${PROJECT_ROOT}/${DOCS_SEGMENTS_DIR}        # ./segments
OUTPUT = ${PROJECT_ROOT}/${DOCS_API_OUTPUT_DIR}       # ./docs/api
```

**Benefit:** Works across all environments (Windows, Linux, macOS) without modification.

### Custom Path Configuration

To use different paths, update `config/secrets.env`:

```bash
# Example: custom paths
export DOCS_SEGMENTS_DIR="my-segments"
export DOCS_API_OUTPUT_DIR="documentation/api-ref"
```

Then run script—paths are resolved automatically.

---

## Understanding the Output

### Generated Files

```
docs/api/
├── README.md           # Master index
├── 01_mount.md        # Segment documentation
├── 02_backup.md
└── ...
```

### Segment Documentation Structure

Each generated segment includes:

- **Overview:** Description from `@description` header
- **Prerequisites:** Required environment variables and commands
- **Behavior:** Success paths and failure conditions
- **Exit Codes:** Return code meanings
- **Integration:** Dependencies via `@requires`
- **Source:** Link to segment source file

### Header Metadata

The script parses these source code annotations:

```bash
# @version      Version number
# @description  Human-readable purpose
# @author       Maintainer name
# @changed      Last modification date
# @requires     Comma-separated segment dependencies
```

---

## Troubleshooting

### Problem: Configuration File Not Found

```
[ERROR] Configuration file not found: /path/to/config/secrets.env
```

**Solution:**
- Ensure you're running from project root or tools directory
- Verify `config/secrets.env` exists in project root

### Problem: Missing Required Variables

```
[ERROR] Missing required variable: DOCS_SEGMENTS_DIR
```

**Solution:**
```bash
# Add to config/secrets.env
export DOCS_SEGMENTS_DIR="segments"
export DOCS_API_OUTPUT_DIR="docs/api"
```

### Problem: Segments Directory Not Found

```
[ERROR] Segments directory not found: /path/to/segments
```

**Solution:**
```bash
# Verify segments directory exists
ls ./segments/

# Check DOCS_SEGMENTS_DIR variable is correct in config/secrets.env
grep DOCS_SEGMENTS_DIR config/secrets.env
```

### Problem: Permission Denied (Linux/WSL)

```
bash: ./tools/generate-segment-docs.sh: Permission denied
```

**Solution:**
```bash
chmod +x ./tools/generate-segment-docs.sh
./tools/generate-segment-docs.sh
```

### Problem: Script Crashes with Path Errors

**Solution:**
```bash
# Verify you're running from correct location
pwd
# Should output: .../linux-backup-system or .../linux-backup-system/tools

# Debug mode: check configuration loading
bash -x ./tools/generate-segment-docs.sh 2>&1 | head -30
```

---

## Common Workflows

### Generate Documentation After Segment Changes

```bash
# Update segment source code
vim segments/01_mount.sh

# Generate documentation
./tools/generate-segment-docs.sh

# Verify changes
git diff docs/api/01_mount.md
```

### Automated Documentation Generation (CI/CD)

### GitHub Actions Example

```yaml
name: Generate Documentation
on: [push]

jobs:
  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Generate segment docs
        run: ./tools/generate-segment-docs.sh
      
      - name: Verify no uncommitted changes
        run: git diff --exit-code docs/api/
```

### Git Pre-Commit Hook

Save as `.git/hooks/pre-commit`:

```bash
#!/bin/bash
cd "$(git rev-parse --show-toplevel)"

# Generate fresh documentation
./tools/generate-segment-docs.sh

# Stage changes if successful
if [ $? -eq 0 ]; then
    git add docs/api/
fi
```

Make executable:

```bash
chmod +x .git/hooks/pre-commit
```

### Manual Scheduled Updates

Add to crontab (Linux):

```bash
# Daily documentation refresh at 2 AM
0 2 * * * cd /home/jo/Projects/linux-backup-system && ./tools/generate-segment-docs.sh >> /var/log/segment-docs.log 2>&1
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All segments processed successfully |
| 1 | Critical error (missing config, invalid paths, etc.) |

**Note:** Warnings or incomplete extraction don't affect exit code—generation continues.

---

## Performance Characteristics

- **Typical runtime:** <1 second for 8-12 segments
- **Resource usage:** Minimal (bash + grep utilities)
- **Idempotency:** Safe to run repeatedly; overwrites existing docs
- **Dependencies:** Core Unix utilities (grep, sed, awk)

---

## Implementation Design

### Configuration Management

- **Source:** `config/secrets.env` (centralized secrets + paths)
- **Loading:** Safe bash sourcing with validation
- **Flexibility:** Paths configurable without code changes

### Error Handling

- Non-fatal extraction failures (missing metadata continues generation)
- Critical path validation (config file, directories exist)
- Informative error messages with guidance

### Path Resolution

- Determines script location dynamically
- Calculates project root automatically
- Resolves all paths relative to project root
- Works across Windows/Linux/macOS without modification

---

## Related Resources

- [Segment Source Code](../segments/) – Implementation details
- [PROFILES.md](../docs/PROFILES.md) – Configuration profiles and variables
- [AI_GUIDELINES.md](../AI_GUIDELINES.md) – Development standards
- [secrets.env Configuration](../config/secrets.env) – Documentation path variables

---

*Last updated: 2026-02-06 | Version: 1.2.0*
