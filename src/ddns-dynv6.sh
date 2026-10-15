#!/bin/bash
# ddns-dynv6 - Dynamic DNS updater for dynv6.com
# 
# This script detects IPv6 address changes and updates dynv6 DNS records.
# It can be triggered by:
#   1. NetworkManager dispatcher (real-time)
#   2. systemd timer (periodic check)
#   3. Manual invocation
#
# Exit codes:
#   0   - Success
#   1   - General error
#   2   - Configuration file not found
#   3   - Configuration parameter missing
#   4   - No IPv6 address found
#   5   - DNS update failed
#   10  - Another instance already running (lock conflict)

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_CONFIG_NOT_FOUND=2
readonly EXIT_CONFIG_MISSING=3
readonly EXIT_NO_IPV6=4
readonly EXIT_UPDATE_FAILED=5
readonly EXIT_LOCK_CONFLICT=10

# Default configuration file
CONFIG_FILE="${CONFIG_FILE:-/etc/ddns-dynv6.conf}"

# State file to track last known IP
STATE_DIR="/var/lib/ddns-dynv6"
STATE_FILE="$STATE_DIR/last_ip"

# Lock file to prevent concurrent execution
LOCK_FILE="/var/run/ddns-dynv6.lock"

# Default values (can be overridden by config file)
INTERFACE=""
TOKEN=""
DOMAINS=""
NETMASK="${NETMASK:-128}"

# Logging to journal
log() {
    local level="$1"
    shift
    echo "$level: $*"
    logger -t ddns-dynv6 "$level: $*"
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

# Acquire lock to prevent concurrent execution
acquire_lock() {
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log_warn "Another instance is already running, exiting"
        return $EXIT_LOCK_CONFLICT
    fi
    return $EXIT_SUCCESS
}

# Load configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_error "Run 'sudo dpkg-reconfigure ddns-dynv6' to configure"
        return $EXIT_CONFIG_NOT_FOUND
    fi
    
    # shellcheck source=/dev/null
    source "$CONFIG_FILE" || {
        log_error "Failed to load configuration file"
        return $EXIT_GENERAL_ERROR
    }
    
    # Validate required parameters
    local missing=""
    [[ -z "$INTERFACE" ]] && missing="INTERFACE"
    [[ -z "$TOKEN" ]] && missing="$missing TOKEN"
    [[ -z "$DOMAINS" ]] && missing="$missing DOMAINS"
    
    if [[ -n "$missing" ]]; then
        log_error "Missing configuration parameters:$missing"
        return $EXIT_CONFIG_MISSING
    fi
    
    return $EXIT_SUCCESS
}

# Get current global IPv6 address from specified interface
get_current_ipv6() {
    local address
    
    # Get the first global IPv6 address, excluding:
    # - fd00::/8 (ULA - Unique Local Address)
    # - temporary addresses (privacy extensions)
    address=$(ip -6 addr list scope global dev "$INTERFACE" 2>/dev/null | \
              grep -v " fd" | \
              grep -v "temporary" | \
              sed -n 's/.*inet6 \([0-9a-f:]\+\).*/\1/p' | \
              head -n 1)
    
    if [[ -z "$address" ]]; then
        log_error "No global IPv6 address found on $INTERFACE"
        return $EXIT_NO_IPV6
    fi
    
    echo "$address"
    return $EXIT_SUCCESS
}

# Get last recorded IP
get_last_ip() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE" 2>/dev/null
    fi
}

# Save current IP to state file
save_current_ip() {
    local ip="$1"
    
    # Ensure state directory exists
    if ! mkdir -p "$STATE_DIR" 2>/dev/null; then
        log_error "Failed to create state directory: $STATE_DIR"
        return $EXIT_GENERAL_ERROR
    fi
    
    if ! echo "$ip" > "$STATE_FILE"; then
        log_error "Failed to write state file: $STATE_FILE"
        return $EXIT_GENERAL_ERROR
    fi
    
    return $EXIT_SUCCESS
}

# Update dynv6 DNS record
update_dns() {
    local ipv6="$1"
    local current="${ipv6}/${NETMASK}"
    local last_ip
    last_ip=$(get_last_ip)
    
    # Check if IP changed
    if [[ "$last_ip" == "$current" ]]; then
        log_info "IPv6 address unchanged: $current"
        return $EXIT_SUCCESS
    fi
    
    log_info "IPv6 address changed: $last_ip -> $current"
    
    # Update each domain
    local success=0
    local failed=0
    
    for domain in $DOMAINS; do
        log_info "Updating $domain..."
        
        local response
        local curl_exit=0
        
        response=$(curl -fsS -w "\n%{http_code}" \
            "http://dynv6.com/api/update?hostname=${domain}&ipv6=${current}&token=${TOKEN}" \
            2>&1) || curl_exit=$?
        
        if [[ $curl_exit -ne 0 ]]; then
            log_error "Failed to update $domain: curl exit code $curl_exit"
            failed=$((failed + 1))
            continue
        fi
        
        local http_code
        http_code=$(echo "$response" | tail -n 1)
        local body
        body=$(echo "$response" | head -n -1)
        
        if [[ "$http_code" == "200" ]]; then
            log_info "Successfully updated $domain: $current"
            success=$((success + 1))
        else
            log_error "Failed to update $domain: HTTP $http_code, response: $body"
            failed=$((failed + 1))
        fi
    done
    
    # Save current IP only if at least one update succeeded
    if [[ $success -gt 0 ]]; then
        save_current_ip "$current"
        log_info "Updated $success domain(s), $failed failed"
        return $EXIT_SUCCESS
    else
        log_error "All updates failed"
        return $EXIT_UPDATE_FAILED
    fi
}

# Main function
main() {
    # Acquire lock first
    local lock_result
    acquire_lock
    lock_result=$?
    if [[ $lock_result -ne $EXIT_SUCCESS ]]; then
        return $lock_result
    fi
    
    log_info "Starting ddns-dynv6 update check"
    
    # Load configuration
    local config_result
    load_config
    config_result=$?
    if [[ $config_result -ne $EXIT_SUCCESS ]]; then
        return $config_result
    fi
    
    # Get current IPv6
    local ipv6
    ipv6=$(get_current_ipv6)
    local ipv6_result=$?
    if [[ $ipv6_result -ne $EXIT_SUCCESS ]]; then
        return $ipv6_result
    fi
    
    log_info "Current IPv6 on $INTERFACE: $ipv6"
    
    # Update DNS
    update_dns "$ipv6"
}

# Run main function
main "$@"