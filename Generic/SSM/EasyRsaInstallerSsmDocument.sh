#!/bin/bash
set -euo pipefail  # Strict error handling


# Global parameters
readonly BUCKET="hawkfund-cloudformation"
readonly BUCKET_KEY="113_VpcPeeringConnectionOverClientVpn"
readonly ENVIRONMENT_NAME="dev"
readonly PROJECT_NAME="ANS"
readonly REGION="eu-west-3"
# readonly RESOURCE_NAME="AssociationWaitCondition"
# readonly WAIT_HANDLE_URL="https://cloudformation-waitcondition-eu-west-3.s3.eu-west-3.amazonaws.com/arn%3Aaws%3Acloudformation%3Aeu-west-3%3A612187453729%3Astack/ANS-113-PrincipalInstances-1VHJE85YT07F9-EasyRsaCACertificateSsmAssociation-HUJ1ZHSBVSNW/969cb190-c7a8-11f0-a669-0a344b714dd5/969e1120-c7a8-11f0-a669-0a344b714dd5/AssociationWaitConditionHandle?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Date=20251122T133856Z&X-Amz-SignedHeaders=host&X-Amz-Expires=86399&X-Amz-Credential=AKIAS7SGNIRT5XUBNSRT%2F20251122%2Feu-west-3%2Fs3%2Faws4_request&X-Amz-Signature=ef71cd722262fcef6313931112178a463532be9572c7beafe0400c4f07454b02"
# readonly STACK_NAME="ANS-113-PrincipalInstances-1VHJE85YT07F9-EasyRsaCACertificateSsmAssociation-HUJ1ZHSBVSNW"

# EasyRSA parameters
readonly CERT_DIR="/opt/certificates"
readonly INSTALL_DIR="/opt"
readonly LOG_DIR="/var/log/easy-rsa"
readonly LOG_FILE="$LOG_DIR/easyrsa-install.log"



# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_DIR/$LOG_FILE"
}

# CloudFormation signaling function
signal_cloudformation() {
    local exit_code="$1"
    local message="$2"
    local status=$([ "$exit_code" -eq 0 ] && echo "SUCCESS" || echo "FAILURE")
    
    log "INFO" "Signaling CloudFormation: Status=$status, Message=$message"
    
    if [[ -n "$WAIT_HANDLE_URL" ]]; then
        log "INFO" "Using WaitCondition URL for signaling"
        local response_code
        response_code=$(curl -w "%{http_code}" -s -X PUT \
            -H 'Content-Type: application/json' \
            --data-binary "{
                \"Status\": \"$status\",
                \"Reason\": \"$message\",
                \"UniqueId\": \"$(hostname)-$(date +%s)\",
                \"Data\": \"EasyRSA setup completed with exit code $exit_code\"
            }" \
            "$WAIT_HANDLE_URL" 2>/dev/null || echo "000")
        
        if [[ "$response_code" =~ ^2[0-9][0-9]$ ]]; then
            log "INFO" "Successfully signaled CloudFormation (HTTP: $response_code)"
        else
            log "WARN" "Failed to signal CloudFormation (HTTP: $response_code)"
        fi
    elif [[ -n "$STACK_NAME" && -n "$REGION" && -n "$RESOURCE_NAME" ]]; then
        log "INFO" "Using cfn-signal for CloudFormation signaling"
        if command -v /opt/aws/bin/cfn-signal >/dev/null 2>&1; then
            /opt/aws/bin/cfn-signal -e "$exit_code" \
                --stack "$STACK_NAME" \
                --resource "$RESOURCE_NAME" \
                --region "$REGION" || log "WARN" "cfn-signal failed"
        else
            log "WARN" "cfn-signal not available"
        fi
    else
        log "INFO" "No CloudFormation signaling configured"
    fi
}

# Error handler
cleanup_and_exit() {
    local exit_code=$?
    local line_number="${1:-unknown}"
    log "ERROR" "Script failed at line $line_number with exit code $exit_code"
    signal_cloudformation "$exit_code" "EasyRSA setup failed at line $line_number"
    exit "$exit_code"
}

# Set up error handling
trap 'cleanup_and_exit $LINENO' ERR

# Main installation function
install_dependencies() {
    log "INFO" "Installing dependencies..."
    
    if command -v yum >/dev/null 2>&1; then
        log "INFO" "Detected RHEL/Amazon Linux - using yum"
        yum update -y
        yum install -y git awscli
    elif command -v apt-get >/dev/null 2>&1; then
        log "INFO" "Detected Ubuntu/Debian - using apt"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y git awscli
    else
        log "ERROR" "Unsupported package manager"
        return 1
    fi
    
    # Verify AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        log "ERROR" "AWS CLI not available after installation"
        return 1
    fi
}

setup_easy_rsa() {
    log "INFO" "Setting up EasyRSA..."
    
    # Create working directory with proper permissions
    log "INFO" "Creating directories: $INSTALL_DIR and $CERT_DIR"
    mkdir -p "$INSTALL_DIR" "$CERT_DIR"
    
    # Ensure directories are writable
    chmod 755 "$INSTALL_DIR" "$CERT_DIR"

    cd "$INSTALL_DIR"

    # Clone EasyRSA
    if [[ -d "easy-rsa" ]]; then
        log "INFO" "EasyRSA directory exists, removing..."
        rm -rf easy-rsa
    fi
    
    log "INFO" "Cloning EasyRSA repository..."
    git clone --depth 1 https://github.com/OpenVPN/easy-rsa.git
    cd easy-rsa/easyrsa3
    
    # Make easyrsa executable
    chmod +x ./easyrsa
    
    # Initialize PKI
    log "INFO" "Initializing PKI..."
    ./easyrsa init-pki
}

# Main execution
main() {
    mkdir -p "$LOG_DIR"
    log "INFO" "Starting EasyRSA installation..."
    log "INFO" "Parameters: Project=$PROJECT_NAME, Environment=$ENVIRONMENT_NAME"
    log "INFO" "Certificates directory: $CERT_DIR"
    log "INFO" "Install directory: $INSTALL_DIR"
    log "INFO" "Log directory: $LOG_DIR"
    log "INFO" "Log file: $LOG_FILE"
    
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        log "WARN" "Not running as root, some operations might fail"
    fi
    
    install_dependencies
    setup_easy_rsa
    
    log "INFO" "EasyRSA installation completed successfully"
    
    signal_cloudformation 0 "EasyRSA installation completed successfully"
}

# Execute main function
main "$@"
