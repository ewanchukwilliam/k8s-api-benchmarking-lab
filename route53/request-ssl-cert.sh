#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load domain from .env.route53
if [ ! -f "$SCRIPT_DIR/.env.route53" ]; then
  echo "Error: .env.route53 not found. Run setup-hosted-zone.sh first"
  exit 1
fi

source "$SCRIPT_DIR/.env.route53"

SUBDOMAIN="${1:-api}"
FULL_DOMAIN="$SUBDOMAIN.$DOMAIN"

echo "=== Requesting SSL Certificate for $FULL_DOMAIN ==="
echo ""

# Request certificate
CERT_ARN=$(aws acm request-certificate \
  --domain-name $FULL_DOMAIN \
  --validation-method DNS \
  --region us-east-1 \
  --query 'CertificateArn' \
  --output text)

echo "✅ Certificate requested!"
echo "Certificate ARN: $CERT_ARN"
echo ""

# Wait a moment for AWS to generate validation record
echo "Waiting for validation record..."
sleep 5

# Get DNS validation record
VALIDATION_RECORD=$(aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
  --output json)

VALIDATION_NAME=$(echo $VALIDATION_RECORD | jq -r '.Name')
VALIDATION_VALUE=$(echo $VALIDATION_RECORD | jq -r '.Value')
VALIDATION_TYPE=$(echo $VALIDATION_RECORD | jq -r '.Type')

echo "=== DNS Validation Record ==="
echo "You need to add this to Route 53 to prove you own the domain:"
echo ""
echo "Type:  $VALIDATION_TYPE"
echo "Name:  $VALIDATION_NAME"
echo "Value: $VALIDATION_VALUE"
echo ""

# Save cert ARN for later
echo "CERTIFICATE_ARN=$CERT_ARN" >> .env.route53
echo "CERT_VALIDATION_NAME=$VALIDATION_NAME" >> .env.route53
echo "CERT_VALIDATION_VALUE=$VALIDATION_VALUE" >> .env.route53

echo "Saved certificate info to .env.route53"
echo ""
echo "Next step: Run ./add-ssl-validation.sh to add the DNS record"
