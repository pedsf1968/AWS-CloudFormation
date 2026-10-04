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

# EasyRSA configuration parameters
readonly EASYRSA_REQ_COUNTRY="KR"
readonly EASYRSA_REQ_PROVINCE="Gyeonggi-Do"
readonly EASYRSA_REQ_CITY="Seoul"
readonly EASYRSA_REQ_ORG="Copyleft Certificate Co"
readonly EASYRSA_REQ_EMAIL="me@example.net"
readonly EASYRSA_REQ_OU="My Organizational Unit"
readonly EASYRSA_CA_EXPIRE="3650"
readonly EASYRSA_CERT_EXPIRE="825"
readonly EASYRSA_KEY_SIZE="2048"
readonly EASYRSA_ALGO="rsa"
readonly EASYRSA_DIGEST="sha512"


# Certificate parameters
readonly CA_NAME="ca"
readonly DOMAIN_NAME="domain.kr"

# Construct CA FQDN (optional, for better naming)
readonly CA_FQDN="${CA_NAME}.${DOMAIN_NAME}"

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

easy_rsa_ca_cert() {
    log "INFO" "Creating CA certificate with EasyRSA"
    log "INFO" "  CA Name: $CA_NAME"
    log "INFO" "  CA FQDN: $CA_FQDN"
    log "INFO" "  Domain: $DOMAIN_NAME"

    # Create working directory with proper permissions
    log "INFO" "Creating directories: $INSTALL_DIR and $CERT_DIR"
    mkdir -p "$INSTALL_DIR" "$CERT_DIR"
    chmod 755 "$INSTALL_DIR" "$CERT_DIR"

    cd "$INSTALL_DIR/easy-rsa/easyrsa3"

    # Check if CA already exists
    if [[ -f "pki/ca.crt" ]]; then
        log "WARN" "CA certificate already exists at pki/ca.crt"
        log "WARN" "Backing up existing CA before creating new one..."
        
        local backup_dir="$CERT_DIR/backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        
        if [[ -d "pki" ]]; then
            cp -r pki "$backup_dir/"
            log "INFO" "Existing PKI backed up to: $backup_dir"
        fi
    fi

    # Create vars file with required settings
    log "INFO" "Creating EasyRSA vars configuration file..."
    cat > vars <<'EOF'
# Easy-RSA 3 parameter settings for CA Certificate
set_var EASYRSA_REQ_COUNTRY    "{{EASYRSA_REQ_COUNTRY}}"
set_var EASYRSA_REQ_PROVINCE   "{{EASYRSA_REQ_PROVINCE}}"
set_var EASYRSA_REQ_CITY       "{{EASYRSA_REQ_CITY}}"
set_var EASYRSA_REQ_ORG        "{{EASYRSA_REQ_ORG}}"
set_var EASYRSA_REQ_EMAIL      "{{EASYRSA_REQ_EMAIL}}"
set_var EASYRSA_REQ_OU         "{{EASYRSA_REQ_OU}}"
set_var EASYRSA_REQ_CN         "{{CA_FQDN}}"
set_var EASYRSA_BATCH          "yes"
set_var EASYRSA_CA_EXPIRE      "{{EASYRSA_CA_EXPIRE}}"
set_var EASYRSA_CERT_EXPIRE    "{{EASYRSA_CERT_EXPIRE}}"
set_var EASYRSA_KEY_SIZE       "{{EASYRSA_KEY_SIZE}}"
set_var EASYRSA_ALGO           "{{EASYRSA_ALGO}}"
set_var EASYRSA_DIGEST         "{{EASYRSA_DIGEST}}"
EOF

    # Perform variable substitution
    sed -i "s|{{EASYRSA_REQ_COUNTRY}}|$EASYRSA_REQ_COUNTRY|g" vars
    sed -i "s|{{EASYRSA_REQ_PROVINCE}}|$EASYRSA_REQ_PROVINCE|g" vars
    sed -i "s|{{EASYRSA_REQ_CITY}}|$EASYRSA_REQ_CITY|g" vars
    sed -i "s|{{EASYRSA_REQ_ORG}}|$EASYRSA_REQ_ORG|g" vars
    sed -i "s|{{EASYRSA_REQ_EMAIL}}|$EASYRSA_REQ_EMAIL|g" vars
    sed -i "s|{{EASYRSA_REQ_OU}}|$EASYRSA_REQ_OU|g" vars
    sed -i "s|{{CA_FQDN}}|$CA_FQDN|g" vars
    sed -i "s|{{EASYRSA_CA_EXPIRE}}|$EASYRSA_CA_EXPIRE|g" vars
    sed -i "s|{{EASYRSA_CERT_EXPIRE}}|$EASYRSA_CERT_EXPIRE|g" vars
    sed -i "s|{{EASYRSA_KEY_SIZE}}|$EASYRSA_KEY_SIZE|g" vars
    sed -i "s|{{EASYRSA_ALGO}}|$EASYRSA_ALGO|g" vars
    sed -i "s|{{EASYRSA_DIGEST}}|$EASYRSA_DIGEST|g" vars

    log "INFO" "CA certificate common name: $CA_FQDN"
    log "INFO" "CA certificate validity: $EASYRSA_CA_EXPIRE days (~$(( EASYRSA_CA_EXPIRE / 365 )) years)"
    log "INFO" "Server/client certificate validity: $EASYRSA_CERT_EXPIRE days (~$(( EASYRSA_CERT_EXPIRE / 365 )) years)"

    # Initialize PKI
    log "INFO" "Initializing PKI infrastructure..."
    if ! ./easyrsa init-pki <<< yes 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR" "Failed to initialize PKI"
        return 1
    fi

    # Build CA
    log "INFO" "Building CA certificate..."
    if ! ./easyrsa --batch build-ca nopass 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR" "Failed to build CA certificate"
        return 1
    fi

    # Verify CA was created
    if [[ ! -f "pki/ca.crt" ]]; then
        log "ERROR" "CA certificate file was not created: pki/ca.crt"
        return 1
    fi

    # Validate CA certificate
    validate_ca_certificate

    # Copy certificates to organized directory
    log "INFO" "Organizing certificates in $CERT_DIR..."
    cp pki/ca.crt "$CERT_DIR/"
    cp pki/private/ca.key "$CERT_DIR/"

    # Set proper permissions
    chmod 600 "$CERT_DIR/ca.key"
    chmod 644 "$CERT_DIR/ca.crt"
    log "INFO" "Certificates created and organized successfully"
    ls -lh "$CERT_DIR/" | tee -a "$LOG_FILE"
    
    # Install certificate to system trust store
    install_system_trust_store
}

install_system_trust_store() {
    log "INFO" "Installing CA certificate to system trust store..."
    
    if command -v update-ca-trust &>/dev/null; then
        log "INFO" "Detected RHEL/CentOS/Amazon Linux system"
        cp "$CERT_DIR/ca.crt" /etc/pki/ca-trust/source/anchors/"${CA_FQDN}.crt"
        update-ca-trust extract
        log "INFO" "CA certificate installed successfully"
    elif command -v update-ca-certificates &>/dev/null; then
        log "INFO" "Detected Debian/Ubuntu system"
        cp "$CERT_DIR/ca.crt" /usr/local/share/ca-certificates/"${CA_FQDN}.crt"
        update-ca-certificates
        log "INFO" "CA certificate installed successfully"
    else
        log "ERROR" "Unsupported OS - Cannot determine package manager"
        return 1
    fi
    
    return 0
}

validate_ca_certificate() {
    log "INFO" "Validating CA certificate..."
    
    local ca_cert="$CERT_DIR/ca.crt"
    
    # Check certificate format
    if ! openssl x509 -in "$ca_cert" -text -noout > /dev/null 2>&1; then
        log "ERROR" "Invalid CA certificate format"
        return 1
    fi
    
    # Display certificate information
    log "INFO" "CA Certificate Subject:"
    openssl x509 -in "$ca_cert" -noout -subject | tee -a "$LOG_FILE"
    
    log "INFO" "CA Certificate Issuer:"
    openssl x509 -in "$ca_cert" -noout -issuer | tee -a "$LOG_FILE"
    
    log "INFO" "CA Certificate Validity:"
    openssl x509 -in "$ca_cert" -noout -dates | tee -a "$LOG_FILE"
    
    # Check if it's a CA certificate
    log "INFO" "Verifying CA certificate extensions..."
    local ca_extension
    ca_extension=$(openssl x509 -in "$ca_cert" -noout -text | grep -A 1 "CA:TRUE" || echo "")
    
    if [[ -n "$ca_extension" ]]; then
        log "INFO" "CA extension verification: PASSED"
    else
        log "ERROR" "CA extension verification: FAILED"
        log "ERROR" "Certificate does not have CA:TRUE extension"
        return 1
    fi
    
    # Display key usage
    log "INFO" "Certificate Key Usage:"
    openssl x509 -in "$ca_cert" -noout -ext keyUsage 2>/dev/null | tee -a "$LOG_FILE" || log "WARN" "Could not extract key usage"
    
    # Calculate and display fingerprints
    log "INFO" "Certificate Fingerprints:"
    log "INFO" "  SHA256: $(openssl x509 -in "$ca_cert" -noout -fingerprint -sha256 | cut -d= -f2)"
    log "INFO" "  SHA1: $(openssl x509 -in "$ca_cert" -noout -fingerprint -sha1 | cut -d= -f2)"
    
    log "INFO" "CA certificate validation completed successfully"
    return 0
}

import_to_acm() {
    log "INFO" "Importing CA certificate to AWS Certificate Manager..."
    
    cd "$CERT_DIR"
    
    # Verify certificate files exist
    if [[ ! -f "ca.crt" ]] || [[ ! -f "ca.key" ]]; then
        log "ERROR" "CA certificate files not found in $CERT_DIR"
        return 1
    fi
    
    local file_size
    file_size=$(stat -c%s "ca.crt" 2>/dev/null || stat -f%z "ca.crt" 2>/dev/null || echo "0")
    log "INFO" "Found CA certificate file: ca.crt ($file_size bytes)"

    # Import CA certificate to ACM
    log "INFO" "Importing CA certificate to ACM..."
    if ! ca_arn=$(aws acm import-certificate \
        --certificate "fileb://ca.crt" \
        --private-key "fileb://ca.key" \
        --region "$REGION" \
        --tags \
            "Key=Domain,Value=$DOMAIN_NAME" \
            "Key=Name,Value=$CA_NAME" \
            "Key=FQDN,Value=$CA_FQDN" \
            "Key=Project,Value=$PROJECT_NAME" \
            "Key=Environment,Value=$ENVIRONMENT_NAME" \
            "Key=Type,Value=CA" \
            "Key=ManagedBy,Value=CloudFormation" \
            "Key=CreatedDate,Value=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --query 'CertificateArn' \
        --output text 2>&1); then
        log "ERROR" "Failed to import CA certificate to ACM: $ca_arn"
        return 1
    fi
    
    log "INFO" "CA certificate imported successfully to ACM"
    log "INFO" "Certificate ARN: $ca_arn"
    
    # Verify the imported certificate
    log "INFO" "Verifying imported certificate in ACM..."
    if aws acm describe-certificate \
        --certificate-arn "$ca_arn" \
        --region "$REGION" > /dev/null 2>&1; then
        log "INFO" "Certificate verification in ACM: PASSED"
    else
        log "WARN" "Could not verify certificate in ACM"
    fi
    
    return 0
}

store_arn_parameter_store() {
    log "INFO" "Storing CA ARN to SSM Parameter Store..."

    # Verify that ca_arn is set
    if [[ -z "$ca_arn" ]]; then
        log "ERROR" "CA ARN is not set, cannot store in Parameter Store"
        return 1
    fi

    # Store ARN with FQDN in path
    local param_name="/$PROJECT_NAME/$ENVIRONMENT_NAME/certificates/$CA_FQDN/arn"
    
    log "INFO" "Parameter name: $param_name"
    
    # First, put the parameter
    if ! aws ssm put-parameter \
        --name "$param_name" \
        --value "$ca_arn" \
        --description "ACM CA Certificate ARN for $CA_FQDN" \
        --type String \
        --overwrite \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"; 
    then
        log "ERROR" "Failed to store CA certificate ARN in SSM Parameter Store"
        return 1
    fi
    
    log "INFO" "CA certificate ARN stored in SSM: $param_name"
    
    # Then, add tags separately
    log "INFO" "Adding tags to SSM parameter..."
    if aws ssm add-tags-to-resource \
        --resource-type Parameter \
        --resource-id "$param_name" \
        --tags \
            "Key=Domain,Value=$DOMAIN_NAME" \
            "Key=Name,Value=$CA_NAME" \
            "Key=FQDN,Value=$CA_FQDN" \
            "Key=Type,Value=CA" \
            "Key=Project,Value=$PROJECT_NAME" \
            "Key=Environment,Value=$ENVIRONMENT_NAME" \
        --region "$REGION" 2>&1 | tee -a "$LOG_FILE"; then
        log "INFO" "Tags added to SSM parameter successfully"
    else
        log "WARN" "Failed to add tags to SSM parameter (permission may be missing)"
        log "WARN" "Consider adding ssm:AddTagsToResource permission to the instance role"
    fi
    
    return 0
}

copy_to_s3() {
    if [[ -z "$BUCKET" ]]; then
        log "INFO" "No S3 bucket specified, skipping S3 copy"
        return 0
    fi

    log "INFO" "Copying certificates to S3..."

    cd "$CERT_DIR"

    # Verify certificate files exist
    if [[ ! -f "ca.crt" ]] || [[ ! -f "ca.key" ]]; then
        log "ERROR" "Certificate files not found in $CERT_DIR"
        return 1
    fi

    # Copy certificates to S3 with error handling
    local s3_prefix="s3://$BUCKET/$BUCKET_KEY/certificates/$CA_FQDN"

    # Copy CA certificate (public)
    log "INFO" "Copying CA certificate to S3..."
    if aws s3 cp ca.crt "$s3_prefix/ca.crt" \
        --region "$REGION" \
        --metadata "fqdn=$CA_FQDN,domain=$DOMAIN_NAME,name=$CA_NAME,type=ca" 2>&1 | tee -a "$LOG_FILE"; then
        log "INFO" "CA certificate copied to: $s3_prefix/ca.crt"
    else
        log "WARN" "Failed to copy CA certificate to S3"
    fi
    
    # Copy CA private key (encrypted storage)
    log "INFO" "Copying CA private key to S3 (encrypted)..."
    if aws s3 cp ca.key "$s3_prefix/ca.key" \
        --region "$REGION" \
        --sse AES256 \
        --metadata "fqdn=$CA_FQDN,domain=$DOMAIN_NAME,name=$CA_NAME,type=ca-key" 2>&1 | tee -a "$LOG_FILE"; then
        log "INFO" "CA private key copied to: $s3_prefix/ca.key (encrypted)"
    else
        log "WARN" "Failed to copy CA private key to S3"
    fi
    
    return 0
}

# Main execution
main() {
    # Create log directory
    mkdir -p "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    
    log "INFO" "=========================================="
    log "INFO" "Starting CA Certificate Creation"
    log "INFO" "=========================================="
    log "INFO" "Script Parameters:"
    log "INFO" "  Project: $PROJECT_NAME"
    log "INFO" "  Environment: $ENVIRONMENT_NAME"
    log "INFO" "  CA Name: $CA_NAME"
    log "INFO" "  CA FQDN: $CA_FQDN"
    log "INFO" "  Domain: $DOMAIN_NAME"
    log "INFO" "  Region: $REGION"
    log "INFO" "  Install Directory: $INSTALL_DIR"
    log "INFO" "  Certificates Directory: $CERT_DIR"
    log "INFO" "  Log Directory: $LOG_DIR"
    log "INFO" "  CA Validity: $EASYRSA_CA_EXPIRE days (~$(( EASYRSA_CA_EXPIRE / 365 )) years)"
    log "INFO" "  Certificate Validity: $EASYRSA_CERT_EXPIRE days (~$(( EASYRSA_CERT_EXPIRE / 365 )) years)"
    log "INFO" "  Key Size: $EASYRSA_KEY_SIZE bits"
    log "INFO" "  Algorithm: $EASYRSA_ALGO"
    log "INFO" "  Digest: $EASYRSA_DIGEST"
    log "INFO" "=========================================="

    # Validate prerequisites
    if ! validate_prerequisites; then
        log "ERROR" "Prerequisites validation failed"
        signal_cloudformation 1 "Prerequisites validation failed"
        exit 1
    fi

    # Create CA certificate
    if ! easy_rsa_ca_cert; then
        log "ERROR" "Failed to create CA certificate"
        signal_cloudformation 1 "Failed to create CA certificate"
        exit 1
    fi
    log "INFO" "✓ CA certificate created successfully"
    
    # Import to ACM
    if ! import_to_acm; then
        log "ERROR" "Failed to import CA certificate to ACM"
        signal_cloudformation 1 "Failed to import CA certificate to ACM"
        exit 1
    fi
    log "INFO" "✓ CA certificate imported to ACM"
    
    # Store ARN in Parameter Store
    if ! store_arn_parameter_store; then
        log "ERROR" "Failed to store CA ARN in SSM Parameter Store"
        signal_cloudformation 1 "Failed to store CA ARN in SSM"
        exit 1
    fi
    log "INFO" "✓ CA ARN stored in SSM Parameter Store"
    
    # Copy to S3
    if ! copy_to_s3; then
        log "WARN" "Failed to copy certificates to S3 (non-critical)"
    else
        log "INFO" "✓ Certificates copied to S3"
    fi

    log "INFO" "=========================================="
    log "INFO" "CA Certificate Setup Completed Successfully"
    log "INFO" "=========================================="
    log "INFO" "Summary:"
    log "INFO" "  CA FQDN: $CA_FQDN"
    log "INFO" "  Certificate ARN: $ca_arn"
    log "INFO" "  Certificates Location: $CERT_DIR"
    log "INFO" "  SSM Parameter: /$PROJECT_NAME/$ENVIRONMENT_NAME/certificates/$CA_FQDN/arn"
    log "INFO" "  Log File: $LOG_FILE"
    log "INFO" "=========================================="

    signal_cloudformation 0 "CA certificate $CA_FQDN created and imported successfully"
}

# Execute main function
main "$@"

