#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform/environments/prod"

# Get hosted zone ID and domain from Terraform
cd "$TERRAFORM_DIR"
HOSTED_ZONE_ID=$(terraform output -raw hosted_zone_id 2>/dev/null)
DOMAIN=$(terraform output -raw domain 2>/dev/null)

if [ -z "$HOSTED_ZONE_ID" ] || [ -z "$DOMAIN" ]; then
  echo "Error: Could not get hosted zone ID or domain from Terraform"
  echo "Run terraform apply first"
  exit 1
fi

# Get NLB hostname from kubectl
NLB_HOSTNAME=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$NLB_HOSTNAME" ]; then
  echo "Error: Could not get NLB hostname. Is nginx-ingress deployed?"
  exit 1
fi

echo "=== Updating DNS Record ==="
echo "Domain: $DOMAIN"
echo "Target: $NLB_HOSTNAME"
echo ""

# Create change batch JSON for CNAME record
CHANGE_BATCH=$(cat <<EOF
{
  "Comment": "Update DNS for EKS deployment",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$DOMAIN",
      "Type": "CNAME",
      "TTL": 60,
      "ResourceRecords": [{"Value": "$NLB_HOSTNAME"}]
    }
  }]
}
EOF
)

# Update DNS
CHANGE_ID=$(aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch "$CHANGE_BATCH" \
  --query 'ChangeInfo.Id' \
  --output text)

echo "DNS update submitted (Change ID: $CHANGE_ID)"
echo "Waiting for change to propagate..."

# Wait for change to complete
aws route53 wait resource-record-sets-changed --id "$CHANGE_ID"

echo ""
echo "DNS propagated successfully!"
echo ""
echo "Your service is now available at:"
echo "  http://$DOMAIN/health"
echo "  https://$DOMAIN/health"
