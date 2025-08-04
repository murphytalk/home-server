#!/bin/bash

# --- Configuration ---
INSTANCE_ID="i-0fa824dcf80342032"
SSH_KEY_PATH="$HOME/.ssh/stargate-aws-hk.pem"
LOCAL_CFG_PATH="$HOME/vpn"
EC2_USER="ubuntu"
REMOTE_CONFIG_PATH="~/wireguard/config/peer_desktop/peer_desktop.conf"
PROFILE="my-stargate-profile"
TUNNEL_NAME="$(basename "$REMOTE_CONFIG_PATH" .conf)"
LOCAL_CONFIG_FILE="$LOCAL_CFG_PATH/$TUNNEL_NAME.conf"
WIREGUARD_INTERFACE="$TUNNEL_NAME"
START_VM_ONLY=0
SHUTDOWN=0
GET_CONFIG=0
GET_CONFIG_PATH=""

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Functions ---
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_success() { echo -e "${GREEN}[ OK ]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }

wait_for_ec2_running() {
    log_info "Checking EC2 instance state..."
    for ((i=1; i<=15; i++)); do
        state=$(aws ec2 describe-instances --profile "$PROFILE" \
            --instance-ids "$INSTANCE_ID" \
            --query "Reservations[0].Instances[0].State.Name" \
            --output text 2>/dev/null)

        if [[ "$state" == "running" ]]; then
            log_success "EC2 instance is running."
            return 0
        elif [[ "$state" == "stopped" ]]; then
            log_warn "Instance is stopped. Attempting to start it... (Attempt $i/15)"
            aws ec2 start-instances --profile "$PROFILE" --instance-ids "$INSTANCE_ID" >/dev/null
            sleep 5
        else
            log_info "Instance is $state. Waiting..."
        fi
        sleep 10
    done
    log_error "EC2 instance did not reach 'running' state in time."
    return 1
}

get_ec2_public_ip() {
    ip=$(aws ec2 describe-instances --profile "$PROFILE" \
        --instance-ids "$INSTANCE_ID" \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text 2>/dev/null)

    if [[ -z "$ip" || "$ip" == "None" ]]; then
        log_error "Unable to retrieve public IP."
        return 1
    fi

    echo "$ip"
    return 0
}

download_config_to_path() {
    local ip="$1"
    local dest_path="$2"
    local dest_dir=$(dirname "$dest_path")

    mkdir -p "$dest_dir"
    log_info "Downloading config via SCP to $dest_path..."
    scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$EC2_USER@$ip:$REMOTE_CONFIG_PATH" "$dest_path"

    if [[ $? -ne 0 ]]; then
        log_error "Failed to download config."
        return 1
    fi

    log_success "Config downloaded to $dest_path"
    return 0
}

download_config() {
    download_config_to_path "$1" "$LOCAL_CONFIG_FILE"
}

uninstall_tunnel() {
    if ip link show "$WIREGUARD_INTERFACE" &>/dev/null;
    then
        log_info "Removing existing tunnel $WIREGUARD_INTERFACE"
        sudo wg-quick down "$WIREGUARD_INTERFACE"
        log_success "Tunnel $WIREGUARD_INTERFACE brought down."
    else
        log_info "No active WireGuard interface named $WIREGUARD_INTERFACE"
    fi
}

install_tunnel() {
    if [[ ! -f "$LOCAL_CONFIG_FILE" ]]; then
        log_error "Config file $LOCAL_CONFIG_FILE does not exist."
        return 1
    fi

    log_info "Bringing up WireGuard tunnel $WIREGUARD_INTERFACE"
    sudo cp "$LOCAL_CONFIG_FILE" "/etc/wireguard/$WIREGUARD_INTERFACE.conf"
    sudo chmod 600 "/etc/wireguard/$WIREGUARD_INTERFACE.conf"
    sudo wg-quick up "$WIREGUARD_INTERFACE"

    if [[ $? -ne 0 ]]; then
        log_error "Failed to bring up tunnel."
        return 1
    fi

    log_success "Tunnel $WIREGUARD_INTERFACE is up."
    return 0
}

shutdown_instance() {
    log_info "Shutting down EC2 instance..."
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --profile "$PROFILE" >/dev/null
    log_success "Instance shutdown initiated."
}

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    echo "Processing arg $1"
    case $1 in
        --start-vm-only) START_VM_ONLY=1; shift ;; 
        --shutdown) SHUTDOWN=1; shift ;; 
        --get-config) GET_CONFIG=1; INSTANCE_ID="$2"; GET_CONFIG_PATH="$3"; shift 3;; 
        *) log_error "Unknown parameter passed: $1"; exit 1 ;; 
    esac
done

#echo "GET_CONFIG is $GET_CONFIG INSTANCE_ID is $INSTANCE_ID GET_CONFIG_PATH is $GET_CONFIG_PATH"

# --- Script Logic ---
if [[ "$SHUTDOWN" == 1 ]]; then
    uninstall_tunnel
    shutdown_instance
    exit 0
fi

wait_for_ec2_running || exit 1
EC2_IP=$(get_ec2_public_ip)
if [[ $? -ne 0 || -z "$EC2_IP" ]]; then
    log_error "Failed to retrieve public IP."
    exit 1
fi

log_success "Public IP retrieved: $EC2_IP"

if [[ "$START_VM_ONLY" == 1 ]]; then
    log_info "EC2 is running. Exiting as requested."
    exit 0
fi
log_info "EC2 is running. Continuing... GET_CONFIG is $GET_CONFIG"
if [[ "$GET_CONFIG" == 1 ]]; then
    if [[ -z "$GET_CONFIG_PATH" ]]; then
        log_error "The --get-config flag requires a destination path."
        exit 1
    fi
    log_info "Download config from $EC2_IP to path $GET_CONFIG_PATH"
    download_config_to_path "$EC2_IP" "$GET_CONFIG_PATH" || exit 1
    log_success "Config downloaded. Exiting as requested."
    exit 0
fi

download_config "$EC2_IP" || exit 1
uninstall_tunnel
install_tunnel || exit 1

log_success "Script completed successfully."
