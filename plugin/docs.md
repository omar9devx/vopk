# ⚡ VOPK Plugin Masterclass: The Architect's Guide
**Version:** 3.0.0 (Jammy) | **Core Engine:** Bash 4.4+

> **⚠️ Warning: With Great Power Comes Great Responsibility.**
> Unlike other plugin systems that sandbox extensions, VOPK plugins are **sourced** directly into the core runtime. This means your plugin has **God-mode access**. You share the memory, the variables, the file descriptors, and the process ID. You can override core functions, inject logic into the AI brain, and manipulate the UI buffer.
>
> **This guide will teach you how to become a VOPK Architect.**

---

## 🗂 Table of Contents
1.  [The Architecture: Understanding "Sourcing"](#-the-architecture-understanding-sourcing)
2.  [The VOPK Lifecycle](#-the-vopk-lifecycle)
3.  [Deep Dive: The IO System (File Descriptors)](#-deep-dive-the-io-system-file-descriptors)
4.  [The UI & Theme Engine (Atomic Level)](#-the-ui--theme-engine-atomic-level)
5.  [The AI & Neural Arrays](#-the-ai--neural-arrays)
6.  [Privilege Escalation & Security](#-privilege-escalation--security)
7.  [Masterclass: Building a "Turbo Cleaner" Plugin](#-masterclass-building-a-turbo-cleaner-plugin)
8.  [Internal Variable Reference](#-internal-variable-reference)

---

## 🏗 The Architecture: Understanding "Sourcing"

VOPK is a monolithic Bash script. When it starts, it performs a `source` operation on every file in `~/.config/vopk/plugins/*.sh`.

**What this implies physically:**
* **Shared RAM:** Your variables live next to VOPK's core variables. **ALWAYS** use `local` inside functions.
* **Shared Environment:** If you change `IFS` or `umask` without resetting it, you break VOPK.
* **Shared Signals:** If your plugin traps `SIGINT` (Ctrl+C), you hijack VOPK's exit procedure.

**The Golden Rule:**
> "Prefix everything. Encapsulate logic in functions. Never run code in the global scope; run it via triggers."

---

## 🔄 The VOPK Lifecycle

Understanding *when* your code runs is crucial for building complex tools.

1.  **Bootstrap Phase:** VOPK defines constants (`VOPK_VERSION`, colors).
2.  **Plugin Load Phase:** VOPK loops through plugins and sources them.
    * *Your code loads here.* Define functions now. Do **not** execute heavy logic yet.
3.  **Config Phase:** VOPK parses YAML/JSON configs and overrides defaults.
4.  **Detection Phase:** VOPK scans the OS (`detect_distro`, `detect_all_package_managers`).
5.  **Execution Phase:** VOPK parses arguments and calls the target function (e.g., `cmd_install`).

---

## 📟 Deep Dive: The IO System (File Descriptors)

VOPK 3.0 uses advanced File Descriptor (FD) management to handle logging while keeping the UI clean. As a plugin developer, you can write directly to these streams.

| FD | Stream Name | Purpose | Raw Usage Example |
| :--- | :--- | :--- | :--- |
| `1` | **STDOUT** | Standard Output (User UI). | `echo "Hello" >&1` |
| `2` | **STDERR** | Standard Error (Warnings). | `echo "Error" >&2` |
| `3` | **LOG_FD** | **Main Log File** (`vopk.log`). Rotating, compressed history. | `echo "[INFO] My Plugin started" >&3` |
| `4` | **DEBUG_FD** | **Debug Log** (`debug.log`). High verbosity. | `echo "Var x=$x" >&4` |
| `5` | **AUDIT_FD** | **Audit Trail** (`audit.log`). Security critical events. | `echo "[AUDIT] ROOT_ACCESS_GRANTED" >&5` |

**The Wrapper Functions (Use these instead of raw echo):**

```bash
# Writes to UI (colored) + FD 3 (timestamped)
log "Connecting to server..." 

# Writes to UI (green) + FD 3 + Metrics Counter
log_success "Operation complete."

# Writes to UI (red) + FD 3 + FD 5 (Audit) + Exits Script
die "Database corruption detected."

# Writes to FD 4 ONLY (Invisible to user unless -d is used)
debug "Loading payload: $payload"
```

---

## 🎨 The UI & Theme Engine (Atomic Level)

VOPK uses ANSI escape codes stored in variables. The theme is loaded dynamically.

**Context-Aware Variables:**
These variables change value based on the active theme (Dracula, Nord, etc.) and the user's color settings (`--no-color`).

* `$PRIMARY` : Main brand color.
* `$SECONDARY` : Borders and Titles.
* `$ACCENT1` : Highlights/Banners.
* `$SUCCESS` / `$WARNING` / `$ERROR` : Status indicators.
* `$MUTED` : For hints/comments (Gray).
* `$BOLD`, `$DIM`, `$RESET` : Typography control.

**Component Constructors:**

```bash
# 1. The Title Block
ui_title "Advanced Plugin"
# Result:
# ════════════════════════════════════
# ╡ Advanced Plugin ╞
# ════════════════════════════════════

# 2. The Data Table Row (Auto-padded)
ui_row "Kernel" "$(uname -r)"
# Result:
#   • Kernel                   5.15.0-generic

# 3. The Animator
# Syntax: ui_animate "Text" "Effect" [Delay]
ui_animate "Compiling assets..." "typewriter" 0.01
```

---

## 🧠 The AI & Neural Arrays

VOPK 3.0 has a "Brain" composed of associative arrays (`declare -A`). You can perform "Knowledge Injection" to make VOPK smarter.

### 1. The Recommendation Engine (`RECOMMENDATION_DB`)
Maps a package name to a list of suggested extras.
* **Structure:** `[trigger_package]="suggestion1 suggestion2"`

**Injection Code:**
```bash
# Logic: If user installs 'terraform', suggest 'aws-cli' and 'kubectl'
RECOMMENDATION_DB["terraform"]+=" aws-cli kubectl"
```

### 2. The Conflict Engine (`CONFLICT_DB`)
Maps a package name to a conflicting package.
* **Structure:** `[trigger_package]="conflict_package"`

**Injection Code:**
```bash
# Logic: Warn user if they have 'nginx' and try to install 'apache2'
CONFLICT_DB["apache2"]="nginx"
```

### 3. The Universal Registry (`UNIVERSAL_MGRS`)
If you build a plugin for a custom package manager (e.g., `winget` on Linux), you must register it so VOPK's core knows it exists.

**Injection Code:**
```bash
if command -v winget >/dev/null; then
    UNIVERSAL_MGRS[winget]="1"
fi
```

---

## 🛡️ Privilege Escalation & Security

**NEVER use `sudo` directly in your plugin.**
Why?
1.  The user might use `doas`.
2.  The user might already be root.
3.  VOPK handles the `sudo` timeout/keepalive logic.

**Use the Core Function:** `run_with_privileges`

```bash
# Wrong ❌
sudo apt update

# Right ✅
run_with_privileges apt update

# Right (Complex command) ✅
run_with_privileges bash -c "echo 'data' > /etc/protected_file"
```

This function respects `$VOPK_SUDO`, checks `$VOPK_DRY_RUN`, and logs the action to `AUDIT_FD` (Descriptor 5).

---

## 🎓 Masterclass: Building a "Turbo Cleaner" Plugin

Let's combine **UI, Logic, File Descriptors, Privileges, and AI** into one massive plugin.
This plugin will find large files, ask to delete them, and update the package cache.

**File:** `~/.config/vopk/plugins/turbo-clean.sh`

```bash
#!/usr/bin/env bash

# 1. Define the Master Function
plugin_turbo_clean() {
    # Local scope for safety
    local threshold="${1:-100M}" 
    local target_dir="${2:-/var/log}"
    local count=0

    # UI Header
    ui_title "🚀 VOPK Turbo Cleaner"
    ui_row "Target" "$target_dir"
    ui_row "Threshold" "$threshold"
    
    # Audit Log Start
    log_to_audit "PLUGIN_START" "TurboCleaner" "INIT"

    # 2. Check Dependencies
    if ! command -v find >/dev/null; then
        die "The 'find' command is missing from your OS."
    fi

    # 3. Complex Logic with Animation
    ui_section "Scanning Filesystem"
    ui_animate "Scanning for files larger than $threshold..." "pulse"

    # We use a temporary file to store results because pipe creates a subshell
    local tmp_list=$(mktemp)
    
    # Run find, suppress permission errors to /dev/null
    find "$target_dir" -type f -size +"$threshold" 2>/dev/null > "$tmp_list"

    if [[ ! -s "$tmp_list" ]]; then
        log_success "System is clean! No large files found."
        rm -f "$tmp_list"
        return 0
    fi

    # 4. Interactive UI
    echo ""
    ui_row "Files Found" "$(wc -l < "$tmp_list")"
    echo ""
    
    # Read file line by line
    while read -r file; do
        # Print file with size
        local size=$(du -h "$file" | cut -f1)
        printf "  %b%s%b (%s)\n" "$ERROR" "$file" "$RESET" "$size"
    done < "$tmp_list"

    echo ""
    
    # 5. User Interaction (Respecting VOPK flags)
    if [[ "$VOPK_ASSUME_YES" -eq 1 ]]; then
        log "Auto-confirming deletion (-y flag detected)."
    else
        # Custom confirmation prompt
        printf "%bDelete these files? [y/N] %b" "$BOLD$WARNING" "$RESET"
        read -r response
        if [[ ! "$response" =~ ^[yY]$ ]]; then
            warn "Operation aborted by user."
            rm -f "$tmp_list"
            return 0
        fi
    fi

    # 6. Execution with Privileges & Dry Run check
    ui_section "Cleaning Process"
    
    while read -r file; do
        if [[ "$VOPK_DRY_RUN" -eq 1 ]]; then
            ui_hint "[DRY RUN] Would delete: $file"
        else
            # Use Core Privilege Function
            if run_with_privileges rm -f "$file"; then
                log_success "Deleted: $file"
                log_to_audit "DELETE" "$file" "SUCCESS"
            else
                warn "Failed to delete: $file"
            fi
        fi
    done < "$tmp_list"

    # 7. Integration: Trigger core optimization
    ui_section "Post-Clean Optimization"
    log "Running VOPK Core Optimize..."
    cmd_optimize

    # Cleanup
    rm -f "$tmp_list"
    ui_animate "Turbo Clean Complete!" "bounce"
}

# 8. Register Command Alias
alias v-turbo="plugin_turbo_clean"

# 9. Knowledge Injection (Optional)
# If user runs 'vopk clean', suggest our new tool
RECOMMENDATION_DB["vopk-clean"]+=" v-turbo"
```

---

## 🔬 Internal Variable Reference

Use these variables to make your plugin adaptive.

| Variable | Type | Description |
| :--- | :--- | :--- |
| `$VOPK_CONFIG_DIR` | Path | `~/.config/vopk` |
| `$VOPK_CACHE_DIR` | Path | `~/.cache/vopk` |
| `$PKG_MGR` | String | Active manager (`apt`, `dnf`, `pacman`). |
| `$PKG_MGR_FAMILY` | String | Family (`debian`, `arch`, `redhat`). |
| `$DISTRO_ID` | String | `/etc/os-release` ID (`ubuntu`, `alpine`). |
| `$VOPK_SUDO` | String | Command used for root (`sudo`, `doas`). |
| `$VOPK_DRY_RUN` | Bool (0/1) | **CRITICAL:** Check this before modifying files. |
| `$VOPK_ASSUME_YES`| Bool (0/1) | Check this to skip prompts (`-y`). |
| `$VOPK_DEBUG` | Bool (0/1) | Use this to toggle verbose logging. |

---

<div align="center">
  <h3>Ready to Build?</h3>
  <p>You now possess the knowledge of the Core Developers.</p>
  <p><i>"The code is yours. The power is yours."</i></p>
</div>
