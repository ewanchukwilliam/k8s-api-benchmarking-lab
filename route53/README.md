# Route 53 DNS Automation

Automates DNS management for EKS deployments so you don't have to manually update DNS every time you get a new NLB URL.

## Overview

**Problem:** Every EKS deployment creates a new NLB with a new hostname.
**Solution:** Automatically update Route 53 DNS to point to the new NLB.

**Cost:** $0.50/month for hosted zone + $0.40/million DNS queries

## One-Time Setup

### Step 1: Create Hosted Zone

```bash
cd route53
./setup-hosted-zone.sh
```

This will:
- Create Route 53 hosted zone for `codeseeker.dev`
- Output 4 AWS nameservers
- Save zone ID to `.env.route53`

### Step 2: Update Nameservers at Porkbun

1. Go to Porkbun dashboard
2. Find `codeseeker.dev` → "nameservers"
3. Replace Porkbun nameservers with AWS nameservers from Step 1
4. Save changes
5. Wait 5-10 minutes for DNS propagation

### Step 3: Verify

```bash
# Should show AWS nameservers
dig codeseeker.dev NS

# Should show AWS nameservers starting with ns-*.awsdns-*.com
```

## Usage

### Automatic (Integrated with deploy script)

The `deploy-eks.sh` script automatically updates DNS after deployment.

```bash
cd eks
./deploy-eks.sh

# DNS is automatically updated to point to new NLB
# Access at: http://api.codeseeker.dev/health
```

### Manual (Update DNS for existing cluster)

```bash
cd route53

# Update api.codeseeker.dev to point to current NLB
./update-dns.sh

# Or specify custom subdomain
./update-dns.sh staging  # Creates staging.codeseeker.dev
./update-dns.sh www      # Creates www.codeseeker.dev

# Or manually specify NLB hostname
./update-dns.sh api abc123.elb.us-east-1.amazonaws.com
```

## Cleanup

When you're done with Route 53:

```bash
cd route53
./cleanup-hosted-zone.sh
```

This will:
- Delete all DNS records
- Delete hosted zone
- Remove `.env.route53`

**Don't forget:** Switch Porkbun nameservers back to Porkbun defaults:
- `curitiba.ns.porkbun.com`
- `fortaleza.ns.porkbun.com`
- `maceio.ns.porkbun.com`
- `salvador.ns.porkbun.com`

## SSL Certificates (HTTPS)

Once DNS is working with HTTP, you can add SSL certificates for HTTPS.

### How SSL Certificate Validation Works

1. **Request certificate** from AWS Certificate Manager (ACM)
2. **AWS gives you a validation CNAME record** to prove you own the domain
3. **Add CNAME to Route 53** (proves ownership)
4. **AWS validates** by checking Route 53 for that record (5-30 minutes)
5. **Certificate issued** and ready to use

### Step-by-Step SSL Setup

```bash
cd route53

# Step 1: Request certificate for api.codeseeker.dev
./request-ssl-cert.sh

# This creates a certificate request and shows you the validation record
# Saves certificate ARN and validation info to .env.route53

# Step 2: Add validation record to Route 53
./add-ssl-validation.sh

# This proves to AWS you own the domain
# Adds CNAME record with validation token

# Step 3: Wait for AWS to validate (5-30 minutes)
./check-ssl-status.sh

# Shows: PENDING_VALIDATION, ISSUED, or FAILED
# Once ISSUED, certificate is ready to use
```

### What's Happening Under the Hood

**DNS Validation Process:**
- AWS ACM generates a unique validation token for your domain
- Format: `_abc123.api.codeseeker.dev` → `_xyz789.acm-validations.aws.`
- You add this as a CNAME record in Route 53
- AWS's validation servers query Route 53 for this record
- If found, AWS knows you control the domain's DNS
- Certificate status changes from PENDING_VALIDATION to ISSUED

**Why DNS validation?**
- Proves you own the domain without email verification
- Fully automated (no clicking email links)
- Can be scripted and integrated into CI/CD

## Files

- `setup-hosted-zone.sh` - One-time setup, creates hosted zone
- `update-dns.sh` - Update DNS record (called by deploy script)
- `cleanup-hosted-zone.sh` - Delete everything
- `request-ssl-cert.sh` - Request SSL certificate from AWS ACM
- `add-ssl-validation.sh` - Add DNS validation record to Route 53
- `check-ssl-status.sh` - Check certificate validation status
- `.env.route53` - Stores zone ID and certificate info (gitignored)
- `README.md` - This file

## Common Issues

**"Error: .env.route53 not found"**
- Run `./setup-hosted-zone.sh` first

**"Could not get NLB hostname"**
- Make sure EKS cluster is deployed
- Or manually specify: `./update-dns.sh api YOUR-NLB-URL`

**DNS not resolving after update**
- Wait 60 seconds (TTL)
- Check nameservers at Porkbun are set to AWS
- Verify: `dig api.codeseeker.dev`

## How It Works

1. **One-time:** Create Route 53 hosted zone
2. **One-time:** Point Porkbun nameservers to AWS
3. **Every deploy:** Script gets new NLB URL from kubectl
4. **Every deploy:** Script updates Route 53 CNAME record
5. **60 seconds later:** DNS propagates, domain points to new cluster

## Cost Breakdown

- **Hosted zone:** $0.50/month
- **DNS queries:** $0.40/million queries (first 1B queries)
- **Total for learning:** ~$0.50/month (queries are negligible)
