#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load certificate validation info
if [ ! -f "$SCRIPT_DIR/.env.route53" ]; then
  echo "Error: .env.route53 not found."
  exit 1
fi

source "$SCRIPT_DIR/.env.route53"

if [ -z "$CERT_VALIDATION_NAME" ]; then
  echo "Error: No certificate validation info found."
  echo "Run ./request-ssl-cert.sh first"
  exit 1
fi

echo "=== Adding SSL Validation Record to Route 53 ==="
echo "This proves you own the domain to AWS"
echo ""
echo "Adding record:"
echo "  Type:  CNAME"
echo "  Name:  $CERT_VALIDATION_NAME"
echo "  Value: $CERT_VALIDATION_VALUE"
echo ""

# Create change batch
CHANGE_BATCH=$(cat <<EOF
{
  "Comment": "SSL certificate validation",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$CERT_VALIDATION_NAME",
      "Type": "CNAME",
      "TTL": 60,
      "ResourceRecords": [{"Value": "$CERT_VALIDATION_VALUE"}]
    }
  }]
}
EOF
)

# Add validation record to Route 53
CHANGE_ID=$(aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch "$CHANGE_BATCH" \
  --query 'ChangeInfo.Id' \
  --output text)

echo "✅ Validation record added to Route 53"
echo ""

# Wait for DNS propagation
echo "Waiting for DNS propagation..."
aws route53 wait resource-record-sets-changed --id "$CHANGE_ID"

echo "✅ DNS propagated!"
echo ""
echo "Now waiting for AWS to validate certificate..."
echo "This usually takes 5-30 minutes."
echo ""
echo "Check status with: ./check-ssl-status.sh"
echo "Or wait with: aws acm wait certificate-validated --certificate-arn $CERTIFICATE_ARN --region us-east-1"
