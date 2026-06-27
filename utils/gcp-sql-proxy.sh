#!/usr/bin/env bash

# GCP Cloud SQL Proxy Utility
# Connect to GCP SQL instances via the Cloud SQL Auth Proxy.
#
# Two ways to reference an instance:
#   1. By profile name from the registry (recommended, fast, offline):
#        gcpsql be-test
#   2. By raw connection name (no registry needed):
#        gcpsql --instance project:region:instance --port 5432
#
# Registry: a whitespace-separated table at
#   $GCP_SQL_PROXY_REGISTRY  (default: ~/.config/gcp-sql-proxy/instances.tsv)
# seeded from utils/gcp-sql-instances.template by install.sh.
#
# Usage:
#   gcpsql [PROFILE] [--port PORT] [--instance CONNECTION_NAME]
#   gcpsql              # fzf-pick a profile from the registry
#   gcpsql ls           # list registered profiles
#   gcpsql --help

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Icons
INFO="ℹ️ "
SUCCESS="✅"
WARN="⚠️ "
ERROR="❌"

# Registry of predefined instances (data lives outside the repo)
REGISTRY="${GCP_SQL_PROXY_REGISTRY:-$HOME/.config/gcp-sql-proxy/instances.tsv}"

# Helper functions
info() {
    echo -e "${BLUE}${INFO}${NC}$1"
}

success() {
    echo -e "${GREEN}${SUCCESS}${NC} $1"
}

warn() {
    echo -e "${YELLOW}${WARN}${NC}$1"
}

error() {
    echo -e "${RED}${ERROR}${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# Registry helpers
# -----------------------------------------------------------------------------

# Emit normalized rows: names<TAB>instance<TAB>port<TAB>env  (env defaults to "-")
# The names field is a comma-separated list: first token is canonical, rest are aliases.
registry_rows() {
    [ -f "$REGISTRY" ] || return 0
    awk 'NF && $1 !~ /^#/ {print $1"\t"$2"\t"$3"\t"($4==""?"-":$4)}' "$REGISTRY"
}

# Every referenceable token — canonical names AND aliases (used by completion)
registry_names() {
    registry_rows | cut -f1 | tr ',' '\n'
}

# Look up a profile by canonical name or any alias; prints its row, non-zero if missing
registry_lookup() {
    registry_rows | awk -F'\t' -v n="$1" '
        { c = split($1, a, ","); for (i = 1; i <= c; i++) if (a[i] == n) { print; found = 1 } }
        END { exit !found }'
}

list_profiles() {
    if [ -z "$(registry_rows)" ]; then
        warn "No profiles registered in: $REGISTRY"
        info "Add entries there, or run 'gcpsql' for interactive gcloud selection."
        return 0
    fi
    # Auto-size columns so long names/aliases don't break alignment
    { printf "PROFILE\tALIASES\tENV\tPORT\tINSTANCE\n"; registry_display_rows; } \
        | column -t -s $'\t'
}

# Emit display rows: canonical<TAB>aliases<TAB>env<TAB>port<TAB>instance
registry_display_rows() {
    registry_rows | awk -F'\t' '{
        c = split($1, a, ","); canon = a[1];
        al = ""; for (i = 2; i <= c; i++) al = al (al == "" ? "" : ",") a[i];
        if (al == "") al = "-";
        print canon "\t" al "\t" $4 "\t" $3 "\t" $2
    }'
}

# Interactive profile picker over the registry (no gcloud call).
# Aliases are shown so you can fuzzy-match them; selection returns the canonical name.
select_profile() {
    registry_display_rows \
        | column -t -s $'\t' \
        | fzf --header="Select a SQL proxy profile" \
              --preview="echo {}" --preview-window=up:3:wrap \
        | awk '{print $1}'
}

# Refuse to silently connect to a prod-tagged instance
confirm_prod() {
    local env="$1" name="$2"
    [ "$env" = "prod" ] || return 0
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}${WARN}PRODUCTION instance: ${name}${NC}"
    echo -e "${RED}========================================${NC}"
    read -p "Type 'yes' to connect to PRODUCTION: " ans
    if [ "$ans" != "yes" ]; then
        error "Aborted."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Dependency / environment checks
# -----------------------------------------------------------------------------

# Check if Application Default Credentials are set up
check_adc() {
    local adc_path="$HOME/.config/gcloud/application_default_credentials.json"

    if [ ! -f "$adc_path" ]; then
        warn "Application Default Credentials (ADC) not found"
        echo ""
        info "Cloud SQL Proxy requires ADC to authenticate with Google Cloud."
        echo ""
        echo "Would you like to set up ADC now? (y/n)"
        read -r response

        if [[ "$response" =~ ^[Yy]$ ]]; then
            info "Running: gcloud auth application-default login"
            echo ""
            gcloud auth application-default login

            if [ $? -eq 0 ]; then
                success "ADC setup complete!"
                echo ""
            else
                error "Failed to set up ADC"
                exit 1
            fi
        else
            echo ""
            error "ADC is required to use Cloud SQL Proxy"
            info "Run this command manually: gcloud auth application-default login"
            exit 1
        fi
    fi
}

# Check if cloud-sql-proxy is installed
check_proxy_binary() {
    if ! command_exists cloud-sql-proxy; then
        warn "cloud-sql-proxy not found. Installing..."

        # Detect architecture
        local arch
        arch=$(uname -m)
        local os="darwin"

        case "$arch" in
            x86_64)
                arch="amd64"
                ;;
            arm64)
                arch="arm64"
                ;;
            *)
                error "Unsupported architecture: $arch"
                exit 1
                ;;
        esac

        local download_url="https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.1/cloud-sql-proxy.${os}.${arch}"
        local install_path="$HOME/.local/bin/cloud-sql-proxy"

        # Ensure .local/bin directory exists
        mkdir -p "$HOME/.local/bin"

        info "Downloading cloud-sql-proxy for ${os}/${arch}..."

        if curl -fsSL "$download_url" -o "$install_path"; then
            chmod +x "$install_path"
            success "cloud-sql-proxy installed to $install_path"

            # Check if .local/bin is in PATH
            if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
                warn "$HOME/.local/bin is not in your PATH"
                info "Add this to your shell config: export PATH=\"\$HOME/.local/bin:\$PATH\""
            fi
        else
            error "Failed to download cloud-sql-proxy"
            exit 1
        fi
    fi
}

# -----------------------------------------------------------------------------
# gcloud-backed interactive fallback (used only when no profile/instance given
# and the registry is empty)
# -----------------------------------------------------------------------------

# Get current GCP project
get_current_project() {
    gcloud config get-value project 2>/dev/null
}

# Get instance connection name
get_instance_connection_name() {
    local project="$1"
    local instance_name="$2"

    gcloud sql instances describe "$instance_name" \
        --project="$project" \
        --format="value(connectionName)" 2>/dev/null
}

# Get database type from instance
get_database_type() {
    local project="$1"
    local instance_name="$2"

    gcloud sql instances describe "$instance_name" \
        --project="$project" \
        --format="value(databaseVersion)" 2>/dev/null | cut -d'_' -f1
}

# Get default port for database type
get_default_port() {
    local db_type="$1"

    case "$db_type" in
        POSTGRES*)
            echo "5432"
            ;;
        MYSQL*)
            echo "3306"
            ;;
        SQLSERVER*)
            echo "1433"
            ;;
        *)
            echo "5432"
            ;;
    esac
}

# Interactive instance selection via the gcloud API
select_instance_from_gcloud() {
    local project="$1"

    local instances
    instances=$(gcloud sql instances list \
        --project="$project" \
        --format="value(name,databaseVersion,region,state)" 2>/dev/null)

    if [ -z "$instances" ]; then
        error "No SQL instances found in project: $project"
        exit 1
    fi

    echo "$instances" | fzf \
        --header="Select a SQL instance (project: $project)" \
        --preview="echo {}" \
        --preview-window=up:3:wrap \
        | awk '{print $1}'
}

# Resolve connection_name/port via the gcloud fallback path
resolve_via_gcloud() {
    if ! command_exists gcloud; then
        error "gcloud not found — needed for interactive discovery."
        info "Install with: brew install google-cloud-sdk, or register a profile in $REGISTRY"
        exit 1
    fi

    local project
    project=$(get_current_project)
    if [ -z "$project" ]; then
        error "No GCP project configured. Run: gcloud config set project PROJECT_ID"
        exit 1
    fi

    local instance_name
    instance_name=$(select_instance_from_gcloud "$project")
    [ -z "$instance_name" ] && { error "No instance selected"; exit 1; }
    info "Selected instance: $instance_name"

    connection_name=$(get_instance_connection_name "$project" "$instance_name")
    [ -z "$connection_name" ] && { error "Failed to get instance connection name"; exit 1; }

    if [ -z "$port" ]; then
        local db_type default_port
        db_type=$(get_database_type "$project" "$instance_name")
        default_port=$(get_default_port "$db_type")
        echo ""
        info "Database type: $db_type (default port: $default_port)"
        read -p "Enter port to bind (default: $default_port): " port
        port="${port:-$default_port}"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

usage() {
    echo "Usage: gcpsql [PROFILE] [OPTIONS]"
    echo ""
    echo "Reference a predefined profile from the registry, pick one interactively,"
    echo "or pass a raw connection name."
    echo ""
    echo "Options:"
    echo "  PROFILE                      Registered profile name (see 'gcpsql ls')"
    echo "  --port PORT                  Port to bind the proxy to (overrides registry)"
    echo "  --instance CONNECTION_NAME   Raw connection name (project:region:instance)"
    echo "  ls, list                     List registered profiles"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Registry: $REGISTRY"
    echo ""
    echo "Examples:"
    echo "  gcpsql be-test                        # connect via a registered profile"
    echo "  gcpsql                                # fzf-pick a profile (or gcloud if empty)"
    echo "  gcpsql ls                            # list profiles"
    echo "  gcpsql --instance my-proj:us-central1:my-db --port 5432"
}

main() {
    local port=""
    local connection_name=""
    local profile=""
    local env="-"

    # Parse arguments: first bare word is a subcommand or profile name
    while [[ $# -gt 0 ]]; do
        case $1 in
            --port)
                port="$2"; shift 2 ;;
            --instance)
                connection_name="$2"; shift 2 ;;
            -h|--help)
                usage; exit 0 ;;
            ls|list)
                list_profiles; exit 0 ;;
            __complete)
                # Fast path for shell completion — no dependency checks
                registry_names; exit 0 ;;
            -*)
                error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1 ;;
            *)
                if [ -z "$profile" ]; then
                    profile="$1"; shift
                else
                    error "Unexpected argument: $1"; exit 1
                fi ;;
        esac
    done

    info "GCP Cloud SQL Proxy Utility"
    echo ""

    # Resolve the target connection
    if [ -n "$profile" ]; then
        # By registry profile name
        local row
        if ! row=$(registry_lookup "$profile"); then
            error "Unknown profile: '$profile'"
            info "Available profiles:"
            list_profiles
            exit 1
        fi
        local r_inst r_port
        r_inst=$(echo "$row" | cut -f2)
        r_port=$(echo "$row" | cut -f3)
        env=$(echo "$row" | cut -f4)
        connection_name="$r_inst"
        port="${port:-$r_port}"   # --port still overrides the registry value
    elif [ -n "$connection_name" ]; then
        # Raw --instance mode: need a port
        if [ -z "$port" ]; then
            error "--instance requires --port (no registry entry to infer it from)"
            exit 1
        fi
    else
        # Nothing specified: prefer the registry, fall back to gcloud discovery
        if [ -n "$(registry_rows)" ]; then
            if ! command_exists fzf; then
                error "fzf not found — needed to pick a profile interactively."
                info "Install with: brew install fzf, or pass a profile name: gcpsql <name>"
                exit 1
            fi
            profile=$(select_profile)
            [ -z "$profile" ] && { error "No profile selected"; exit 1; }
            local row
            row=$(registry_lookup "$profile") || { error "Profile vanished: $profile"; exit 1; }
            connection_name=$(echo "$row" | cut -f2)
            port=$(echo "$row" | cut -f3)
            env=$(echo "$row" | cut -f4)
        else
            resolve_via_gcloud
        fi
    fi

    # Validate port
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        error "Invalid port: $port"
        exit 1
    fi

    # Ensure runtime prerequisites (binary + credentials)
    check_proxy_binary
    check_adc

    # Guard production
    confirm_prod "$env" "${profile:-$connection_name}"

    echo ""
    success "Starting Cloud SQL Proxy..."
    echo ""
    info "Connection details:"
    [ -n "$profile" ] && echo "  Profile:        $profile"
    [ "$env" != "-" ] && echo "  Environment:    $env"
    echo "  Instance:       $connection_name"
    echo "  Local Port:     $port"
    echo "  Connection:     localhost:$port"
    echo ""
    info "Press Ctrl+C to stop the proxy"
    echo ""

    cloud-sql-proxy "$connection_name" --port "$port"
}

main "$@"
