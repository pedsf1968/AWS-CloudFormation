#!/bin/bash
set -euo pipefail  # Strict error handling

# Variables - Using proper path expansion
readonly BUCKET="hawkfund-cloudformation"
readonly BUCKET_KEY="113_VpcPeeringConnectionOverClientVpn"
readonly PROJECT_NAME="ANS"
readonly ENVIRONMENT_NAME="dev"
readonly WAIT_HANDLE_URL="https://cloudformation-waitcondition-eu-west-3.s3.eu-west-3.amazonaws.com/arn%3Aaws%3Acloudformation%3Aeu-west-3%3A612187453729%3Astack/ANS-113-PrincipalInstances-1VHJE85YT07F9-EasyRsaCACertificateSsmAssociation-HUJ1ZHSBVSNW/969cb190-c7a8-11f0-a669-0a344b714dd5/969e1120-c7a8-11f0-a669-0a344b714dd5/AssociationWaitConditionHandle?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Date=20251122T133856Z&X-Amz-SignedHeaders=host&X-Amz-Expires=86399&X-Amz-Credential=AKIAS7SGNIRT5XUBNSRT%2F20251122%2Feu-west-3%2Fs3%2Faws4_request&X-Amz-Signature=ef71cd722262fcef6313931112178a463532be9572c7beafe0400c4f07454b02"
readonly STACK_NAME="ANS-113-PrincipalInstances-1VHJE85YT07F9-EasyRsaCACertificateSsmAssociation-HUJ1ZHSBVSNW"
readonly REGION="eu-west-3"
readonly RESOURCE_NAME="AssociationWaitCondition"
readonly CA_NAME="root-ca.domain.kr"
readonly WORKING_DIR="/opt/openvpn-setup"
readonly LOG_FILE="/var/log/openvpn-easyrsa-cacert.log"
readonly CERT_DIR="/opt/certificates"

# Logging function
log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
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
                \"Data\": \"EasyRSA CA certificate setup completed with exit code $exit_code\"
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
    signal_cloudformation "$exit_code" "EasyRSA CA certificate setup failed at line $line_number"
    exit "$exit_code"
}

# Set up error handling
trap 'cleanup_and_exit $LINENO' ERR

easy_rsa_ca_cert() {
    log "INFO" "Creating CA certificate with EasyRSA."
    
    # Create working directory with proper permissions
    log "INFO" "Creating directories: $WORKING_DIR and $CERT_DIR"
    mkdir -p "$WORKING_DIR" "$CERT_DIR"
    
    # Ensure directories are writable
    chmod 755 "$WORKING_DIR" "$CERT_DIR"
    
    cd "$WORKING_DIR/easy-rsa/easyrsa3"
  
    # Create or update vars file with required settings
    log "INFO" "Creating EasyRSA vars configuration file..."
    cat > vars <<EOF
# Easy-RSA 3 parameter settings
#set_var EASYRSA_REQ_COUNTRY    "US"
#set_var EASYRSA_REQ_PROVINCE   "California"
#set_var EASYRSA_REQ_CITY       "San Francisco"
#set_var EASYRSA_REQ_ORG        "Copyleft Certificate Co"
#set_var EASYRSA_REQ_EMAIL      "me@example.net"
#set_var EASYRSA_REQ_OU         "My Organizational Unit"
set_var EASYRSA_REQ_CN "$CA_NAME"
set_var EASYRSA_BATCH "yes"
set_var EASYRSA_CA_EXPIRE 3650
set_var EASYRSA_CERT_EXPIRE 825
set_var EASYRSA_KEY_SIZE 2048
set_var EASYRSA_ALGO rsa
set_var EASYRSA_DIGEST sha256
EOF

    log "INFO" "CA certificate common name: $CA_NAME"
    log "INFO" "CA certificate validity: 3650 days"
    log "INFO" "Server/client certificate validity: 825 days"

    # Source the vars file
    log "INFO" "Loading EasyRSA configuration..."
    source ./vars
    
    # Remove previous CA
    log "INFO" "Removing CA certificate..."
    ./easyrsa init-pki <<< yes

    # Build CA
    log "INFO" "Building CA certificate..."
    ./easyrsa --batch build-ca nopass
    
    # Copy certificates to organized directory
    log "INFO" "Organizing certificates in $CERT_DIR..."
    cp pki/ca.crt "$CERT_DIR/"
    
    # Set proper permissions
    chmod 644 "$CERT_DIR"/*.crt
    
    log "INFO" "Certificates created and organized successfully"
    ls -la "$CERT_DIR/"
}

copy_to_s3() {
    if [[ -z "$BUCKET" ]]; then
        log "INFO" "No S3 bucket specified, skipping S3 copy"
        return 0
    fi
    
    log "INFO" "Copying certificates to S3..."
    
    cd "$CERT_DIR"
    
    # Copy certificates to S3 with error handling
    local s3_prefix="s3://$BUCKET/$BUCKET_KEY"
    
    if ! aws s3 cp ca.crt "$s3_prefix/ca.crt" --region "$REGION"; then
        log "WARN" "Failed to copy CA certificate to S3"
    else
        log "INFO" "CA certificate copied to: $s3_prefix/ca.crt"
    fi
}

# Main execution
main() {
    log "INFO" "Starting CA certificate creation with EasyRSA..."
    log "INFO" "Parameters: Project=$PROJECT_NAME, Environment=$ENVIRONMENT_NAME"
    log "INFO" "Certificate details: CA=$CA_NAME, Region=$REGION"

    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        log "WARN" "Not running as root, some operations might fail"
    fi
    
    easy_rsa_ca_cert
    copy_to_s3
    
    log "INFO" "CA certificate completed successfully"
    log "INFO" "Certificates stored in: $CERT_DIR"
    log "INFO" "Certificate stored in S3"
    
    signal_cloudformation 0 "CA certificate created and imported completed successfully"
}

# Execute main function
main "$@"
