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
readonly LOG_FILE="$LOG_DIR/easyrsa-cacert.log"

# Certificate parameters
readonly CA_NAME="ca"
readonly DOMAIN_NAME="domain.kr"
readonly SERVER_BASE_NAME="application"

# Construct full server name (FQDN)
readonly SERVER_FQDN="${SERVER_BASE_NAME}.${DOMAIN_NAME}"

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
                \"Data\": \"EasyRSA server certificate setup completed with exit code $exit_code\"
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
    signal_cloudformation "$exit_code" "Server certificate setup failed at line $line_number"
    exit "$exit_code"
}

# Set up error handling
trap 'cleanup_and_exit $LINENO' ERR

# Validate prerequisites
validate_prerequisites() {
    log "INFO" "Validating prerequisites..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log "ERROR" "This script must be run as root"
        return 1
    fi
    
    # Check if EasyRSA is installed
    if [[ ! -d "$INSTALL_DIR/easy-rsa/easyrsa3" ]]; then
        log "ERROR" "EasyRSA not found at $INSTALL_DIR/easy-rsa/easyrsa3"
        log "ERROR" "Please install EasyRSA first"
        return 1
    fi

    # Verify CA exists
    if [[ ! -f "$INSTALL_DIR/easy-rsa/easyrsa3/pki/ca.crt" ]]; then
        log "ERROR" "CA certificate not found at $INSTALL_DIR/easy-rsa/easyrsa3/pki/ca.crt"
        log "ERROR" "Please run CA setup first before creating server certificates"
        return 1
    fi
    log "INFO" "CA certificate found, proceeding with server certificate creation"

    # Check required commands
    local required_commands=("openssl" "aws" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "ERROR" "Required command not found: $cmd"
            return 1
        fi
    done
    
    log "INFO" "Prerequisites validation: PASSED"
    return 0
}

easy_rsa_server_cert() {
    log "INFO" "Creating server certificate with EasyRSA."
    log "INFO" "Server name: $SERVER_BASE_NAME"
    log "INFO" "Server FQDN: $SERVER_FQDN"
    log "INFO" "Domain: $DOMAIN_NAME"

    # Create working directory with proper permissions
    log "INFO" "Creating directories: $INSTALL_DIR and $CERT_DIR"
    mkdir -p "$INSTALL_DIR" "$CERT_DIR"
    chmod 755 "$INSTALL_DIR" "$CERT_DIR"

    cd "$INSTALL_DIR/easy-rsa/easyrsa3"

    # Check if server certificate already exists
    if [[ -f "pki/issued/$SERVER_FQDN.crt" ]]; then
        log "WARN" "Server certificate $SERVER_FQDN already exists. Removing it to create a new one..."
        rm -f "pki/issued/$SERVER_FQDN.crt"
        rm -f "pki/private/$SERVER_FQDN.key"
        rm -f "pki/reqs/$SERVER_FQDN.req"
    fi

    # Build server certificate with comprehensive SAN
    log "INFO" "Building server certificate for: $SERVER_FQDN"
    log "INFO" "SAN entries:"
    log "INFO" "  - DNS:$SERVER_FQDN (primary FQDN)"
    log "INFO" "  - DNS:*.$DOMAIN_NAME (wildcard domain)"
    log "INFO" "  - DNS:$SERVER_BASE_NAME (short name)"
    log "INFO" "  - DNS:localhost"
    
    if ! ./easyrsa --batch \
        --san="DNS:$SERVER_FQDN,DNS:*.$DOMAIN_NAME,DNS:$SERVER_BASE_NAME,DNS:localhost" \
        build-server-full "$SERVER_FQDN" nopass; then
        log "ERROR" "Failed to build server certificate"
        return 1
    fi

    # Validate certificate was created
    if [[ ! -f "pki/issued/${SERVER_FQDN}.crt" ]]; then
        log "ERROR" "Certificate file was not created: pki/issued/${SERVER_FQDN}.crt"
        return 1
    fi

    # Copy certificates to organized directory (including CA)
    log "INFO" "Organizing certificates in ${CERT_DIR}..."
    cp "pki/issued/${SERVER_FQDN}.crt" "${CERT_DIR}/"
    cp "pki/private/${SERVER_FQDN}.key" "${CERT_DIR}/"
    cp "pki/ca.crt" "${CERT_DIR}/"

    # Set proper permissions
    chmod 600 "${CERT_DIR}/${SERVER_FQDN}.key"
    chmod 644 "${CERT_DIR}/${SERVER_FQDN}.crt"
    
    log "INFO" "Certificates created and organized successfully"
    ls -lh $CERT_DIR/$SERVER_FQDN.*
    
    # Validate certificate
    validate_certificate
}

validate_certificate() {
    log "INFO" "Validating server certificate..."
    
    local cert_file="${CERT_DIR}/${SERVER_FQDN}.crt"
    local key_file="${CERT_DIR}/${SERVER_FQDN}.key"
    
    # Check certificate format
    if ! openssl x509 -in "$cert_file" -text -noout > /dev/null 2>&1; then
        log "ERROR" "Invalid certificate format"
        return 1
    fi
    
    # Display certificate information
    log "INFO" "Certificate Subject:"
    openssl x509 -in "$cert_file" -noout -subject | tee -a "$LOG_FILE"
    
    log "INFO" "Certificate Issuer:"
    openssl x509 -in "$cert_file" -noout -issuer | tee -a "$LOG_FILE"
    
    log "INFO" "Certificate Validity:"
    openssl x509 -in "$cert_file" -noout -dates | tee -a "$LOG_FILE"
    
    log "INFO" "Certificate SAN (Subject Alternative Names):"
    openssl x509 -in "$cert_file" -noout -ext subjectAltName 2>/dev/null | tee -a "$LOG_FILE" || log "WARN" "No SAN found in certificate"
    
    # Verify certificate chain
    log "INFO" "Verifying certificate chain..."
    if openssl verify -CAfile "$CERT_DIR/ca.crt" "$cert_file" > /dev/null 2>&1; then
        log "INFO" "Certificate chain verification: PASSED"
    else
        log "ERROR" "Certificate chain verification: FAILED"
        return 1
    fi
    
    # Check key and certificate match
    log "INFO" "Verifying key and certificate match..."
    local cert_modulus key_modulus
    cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" | openssl md5)
    key_modulus=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | openssl md5)
    
    if [[ "$cert_modulus" == "$key_modulus" ]]; then
        log "INFO" "Private key matches certificate: PASSED"
    else
        log "ERROR" "Private key does not match certificate: FAILED"
        return 1
    fi
    
    log "INFO" "Certificate validation completed successfully"
    return 0
}

import_to_acm() {
    log "INFO" "Importing server certificate to AWS Certificate Manager..."
    
    cd "$CERT_DIR"
    
    local cert_file="${SERVER_FQDN}.crt"
    local key_file="${SERVER_FQDN}.key"
    local ca_file="ca.crt"
    
    # Verify certificate files exist
    for file in "$cert_file" "$key_file" "$ca_file"; do
        if [[ ! -f "$file" ]]; then
            log "ERROR" "Certificate file $file not found in $CERT_DIR"
            return 1
        fi
        local file_size
        file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
        log "INFO" "Found certificate file: $file ($file_size bytes)"
    done

    # Verify certificate files exist
    for file in "$cert_file" "$key_file" ; do
        if [[ ! -f "$file" ]]; then
            log "ERROR" "Certificate file $file not found in $CERT_DIR"
            return 1
        fi
        local file_size
        file_size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
        log "INFO" "Found certificate file: $file ($file_size bytes)"
    done

    # Import certificate to ACM
    log "INFO" "Importing certificate with FQDN: $SERVER_FQDN"
    if ! server_arn=$(aws acm import-certificate \
        --certificate "fileb://$cert_file" \
        --private-key "fileb://$key_file" \
        --certificate-chain "fileb://$ca_file" \
        --region "$REGION" \
        --tags \
            "Key=Name,Value=$SERVER_FQDN" \
            "Key=ShortName,Value=$SERVER_BASE_NAME" \
            "Key=Domain,Value=$DOMAIN_NAME" \
            "Key=Project,Value=$PROJECT_NAME" \
            "Key=Environment,Value=$ENVIRONMENT_NAME" \
            "Key=Type,Value=Server" \
            "Key=ManagedBy,Value=CloudFormation" \
            "Key=CreatedDate,Value=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --query 'CertificateArn' \
        --output text 2>&1); then
        log "ERROR" "Failed to import server certificate to ACM: $server_arn"
        return 1
    fi
    
    log "INFO" "Server certificate imported successfully to ACM"
    log "INFO" "Certificate ARN: $server_arn"
    log "INFO" "Certificate FQDN: $SERVER_FQDN"
    
    # Verify the imported certificate
    log "INFO" "Verifying imported certificate in ACM..."
    if aws acm describe-certificate \
        --certificate-arn "$server_arn" \
        --region "$REGION" > /dev/null 2>&1; then
        log "INFO" "Certificate verification in ACM: PASSED"
    else
        log "WARN" "Could not verify certificate in ACM"
    fi
    
    return 0
}

store_arn_parameter_store() {
    log "INFO" "Store ARN to SSM parameter store"

    cd "$CERT_DIR"

    # Verify that server_arn is set
    if [[ -z "$server_arn" ]]; then
        log "ERROR" "Server ARN is not set, cannot store in Parameter Store"
        return 1
    fi

    # Store ARN with FQDN in path
    local param_name="/$PROJECT_NAME/$ENVIRONMENT_NAME/certificates/$SERVER_FQDN/arn"

    # First, put the parameter
    if ! aws ssm put-parameter \
        --name "$param_name" \
        --value "$server_arn" \
        --description "ACM Server Certificate ARN for $SERVER_FQDN" \
        --type String \
        --overwrite \
        --region "$REGION" 2>&1; 
    then
        log "INFO" "Server certificate ARN stored in SSM: $param_name"
        return 1
    fi

    # Then, add tags separately
    log "INFO" "Adding tags to SSM parameter..."
    if aws ssm add-tags-to-resource \
        --resource-type Parameter \
        --resource-id "$param_name" \
        --tags \
            "Key=Domain,Value=$DOMAIN_NAME" \
            "Key=Name,Value=$SERVER_BASE_NAME" \
            "Key=FQDN,Value=$SERVER_FQDN" \
            "Key=Type,Value=Server" \
            "Key=Project,Value=$PROJECT_NAME" \
            "Key=Environment,Value=$ENVIRONMENT_NAME" \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"; then
        log "INFO" "Tags added to SSM parameter successfully"
    else
        log "WARN" "Failed to add tags to SSM parameter (permission may be missing)"
        log "WARN" "Consider adding ssm:AddTagsToResource permission to the instance role"
    fi
}

copy_to_s3() {
    if [[ -z "$BUCKET" ]]; then
        log "INFO" "No S3 bucket specified, skipping S3 copy"
        return 0
    fi
    
    log "INFO" "Copying certificates to S3..."
    
    cd "$CERT_DIR"
    
    # Copy certificates to S3 with error handling
    local s3_prefix="s3://$BUCKET/$BUCKET_KEY/certificates/$SERVER_FQDN"
    
    # Copy all certificate files
    for file in "${SERVER_BASE_NAME}.crt" "${SERVER_BASE_NAME}.key" "ca.crt"; do
        if [[ -f "$file" ]]; then
            if ! aws s3 cp "$file" "$s3_prefix/$file" \
                --region "$REGION" \
                --metadata "fqdn=$SERVER_FQDN,domain=$DOMAIN_NAME,shortname=$SERVER_BASE_NAME"; then
                log "WARN" "Failed to copy $file to S3"
            else
                log "INFO" "Certificate file copied to: $s3_prefix/$file"
            fi
        fi
    done
}

# Main execution
main() {
    # Create log directory
    mkdir -p "$LOG_DIR"
    chmod 755 "$LOG_DIR"

    log "INFO" "=========================================="
    log "INFO" "Starting Server Certificate Creation"
    log "INFO" "=========================================="
    log "INFO" "Starting server certificate creation with EasyRSA..."
    log "INFO" "Parameters:"
    log "INFO" "  Project: $PROJECT_NAME"
    log "INFO" "  Environment: $ENVIRONMENT_NAME"
    log "INFO" "  CA Name: $CA_NAME"
    log "INFO" "  Domain: $DOMAIN_NAME"
    log "INFO" "  Region: $REGION"
    log "INFO" "  Install Directory: $INSTALL_DIR"
    log "INFO" "  Certificates Directory: $CERT_DIR"
    log "INFO" "  Log Directory: $LOG_DIR"
    log "INFO" "  Server FQDN: $SERVER_FQDN"
    log "INFO" "  Server Base Name: $SERVER_BASE_NAME"
    log "INFO" "=========================================="
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        log "WARN" "Not running as root, some operations might fail"
    fi
    
    easy_rsa_server_cert
    log "INFO" "Server certificate completed successfully"
    log "INFO" "Certificates stored in: $CERT_DIR"
    
    import_to_acm
    log "INFO" "Certificate imported in ACM"
    
    store_arn_parameter_store
    log "INFO" "Certificate ARN stored in SSM Parameter Store"
    
    copy_to_s3
    log "INFO" "Certificate stored in S3"
    
    signal_cloudformation 0 "Server certificate $SERVER_FQDN created and imported completed successfully"
}

# Execute main function
main "$@"