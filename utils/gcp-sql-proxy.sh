#!/usr/bin/env bash

# GCP Cloud SQL Proxy Utility
# Helps select and connect to GCP SQL instances via Cloud SQL Auth Proxy
#
# Usage: ./gcp-sql-proxy.sh [--port PORT] [--instance INSTANCE_CONNECTION_NAME]

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

# Check dependencies
check_dependencies() {
    local missing_deps=()

    if ! command_exists gcloud; then
        missing_deps+=("gcloud (Google Cloud SDK)")
    fi

    if ! command_exists fzf; then
        missing_deps+=("fzf (fuzzy finder)")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Missing required dependencies:"
        printf '  - %s\n' "${missing_deps[@]}"
        echo ""
        echo "Install with: brew install google-cloud-sdk fzf"
        exit 1
    fi
}

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

# Get current GCP project
get_current_project() {
    gcloud config get-value project 2>/dev/null
}

# List SQL instances
list_sql_instances() {
    local project="$1"

    info "Fetching SQL instances from project: $project"

    gcloud sql instances list \
        --project="$project" \
        --format="table(name,databaseVersion,region,tier,state)" 2>/dev/null
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

# Interactive instance selection
select_instance() {
    local project="$1"

    # Get instances with formatted output
    local instances
    instances=$(gcloud sql instances list \
        --project="$project" \
        --format="value(name,databaseVersion,region,state)" 2>/dev/null)

    if [ -z "$instances" ]; then
        error "No SQL instances found in project: $project"
        exit 1
    fi

    # Use fzf for selection
    echo "$instances" | fzf \
        --header="Select a SQL instance (project: $project)" \
        --preview="echo {}" \
        --preview-window=up:3:wrap \
        | awk '{print $1}'
}

# Main function
main() {
    local port=""
    local instance_name=""
    local connection_name=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --port)
                port="$2"
                shift 2
                ;;
            --instance)
                connection_name="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --port PORT                  Port to bind the proxy to"
                echo "  --instance CONNECTION_NAME   Instance connection name (project:region:instance)"
                echo "  -h, --help                   Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                                    # Interactive mode"
                echo "  $0 --port 5433                        # Interactive with custom port"
                echo "  $0 --instance my-project:us-central1:my-instance --port 5432"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    info "GCP Cloud SQL Proxy Utility"
    echo ""

    # Check dependencies
    check_dependencies

    # Check Application Default Credentials
    check_adc

    # Check/install cloud-sql-proxy
    check_proxy_binary

    # Get current project
    local project
    project=$(get_current_project)

    if [ -z "$project" ]; then
        error "No GCP project configured. Run: gcloud config set project PROJECT_ID"
        exit 1
    fi

    # If instance not provided, select interactively
    if [ -z "$connection_name" ]; then
        instance_name=$(select_instance "$project")

        if [ -z "$instance_name" ]; then
            error "No instance selected"
            exit 1
        fi

        info "Selected instance: $instance_name"

        # Get connection name
        connection_name=$(get_instance_connection_name "$project" "$instance_name")
    else
        # Extract instance name from connection name
        instance_name=$(echo "$connection_name" | cut -d':' -f3)
    fi

    if [ -z "$connection_name" ]; then
        error "Failed to get instance connection name"
        exit 1
    fi

    # Get database type and default port
    local db_type
    db_type=$(get_database_type "$project" "$instance_name")
    local default_port
    default_port=$(get_default_port "$db_type")

    # If port not provided, prompt for it
    if [ -z "$port" ]; then
        echo ""
        info "Database type: $db_type (default port: $default_port)"
        read -p "Enter port to bind (default: $default_port): " port
        port="${port:-$default_port}"
    fi

    # Validate port
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        error "Invalid port: $port"
        exit 1
    fi

    echo ""
    success "Starting Cloud SQL Proxy..."
    echo ""
    info "Connection details:"
    echo "  Instance:       $connection_name"
    echo "  Database Type:  $db_type"
    echo "  Local Port:     $port"
    echo "  Connection:     localhost:$port"
    echo ""
    info "Press Ctrl+C to stop the proxy"
    echo ""

    # Start the proxy
    cloud-sql-proxy "$connection_name" --port "$port"
}

main "$@"
