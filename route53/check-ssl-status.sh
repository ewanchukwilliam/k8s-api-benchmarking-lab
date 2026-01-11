#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load certificate info
if [ ! -f "$SCRIPT_DIR/.env.route53" ]; then
  echo "Error: .env.route53 not found."
  exit 1
fi

source "$SCRIPT_DIR/.env.route53"

if [ -z "$CERTIFICATE_ARN" ]; then
  echo "Error: No certificate ARN found."
  echo "Run ./request-ssl-cert.sh first"
  exit 1
fi

echo "=== Checking SSL Certificate Status ==="
echo ""

# Get certificate details
CERT_INFO=$(aws acm describe-certificate \
  --certificate-arn $CERTIFICATE_ARN \
  --region us-east-1 \
  --output json)

STATUS=$(echo $CERT_INFO | jq -r '.Certificate.Status')
DOMAIN=$(echo $CERT_INFO | jq -r '.Certificate.DomainName')
CREATED=$(echo $CERT_INFO | jq -r '.Certificate.CreatedAt')

echo "Domain: $DOMAIN"
echo "Status: $STATUS"
echo "Created: $CREATED"
echo ""

case $STATUS in
  "PENDING_VALIDATION")
    echo "⏳ Waiting for DNS validation..."
    echo ""
    echo "What's happening:"
    echo "1. AWS is checking your Route 53 for the validation CNAME record"
    echo "2. This usually takes 5-30 minutes"
    echo "3. Once found, status will change to ISSUED"
    echo ""
    echo "Wait with: aws acm wait certificate-validated --certificate-arn $CERTIFICATE_ARN --region us-east-1"
    ;;
  "ISSUED")
    echo "✅ Certificate is ISSUED and ready to use!"
    echo ""
    echo "Next step: Update your service to use HTTPS"
    echo "Run: ./enable-https.sh"
    ;;
  "FAILED")
    echo "❌ Certificate validation FAILED"
    echo ""
    echo "Reasons:"
    FAILURE=$(echo $CERT_INFO | jq -r '.Certificate.DomainValidationOptions[0].ValidationStatus')
    echo "  $FAILURE"
    ;;
  *)
    echo "Unknown status: $STATUS"
    ;;
esac
