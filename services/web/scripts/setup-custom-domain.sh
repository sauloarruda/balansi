#!/bin/bash

# Script to configure custom domain for AWS Amplify
# Usage: ./scripts/setup-custom-domain.sh

set -e

APP_ID="d37t3chm3rgne2"
BRANCH_NAME="BAL-7"
REGION="us-east-2"
FRONTEND_DOMAIN="demo.balansi.me"
HOSTED_ZONE_NAME="balansi.me"  # Adjust if your hosted zone is different

echo "🔧 Configuring custom domain for AWS Amplify..."
echo "Frontend Domain: $FRONTEND_DOMAIN"
echo "App ID: $APP_ID"
echo "Branch: $BRANCH_NAME"
echo "Region: $REGION"
echo ""

# Check if certificate exists in ACM (us-east-1 for CloudFront)
echo "🔐 SSL Certificate..."
CLOUDFRONT_REGION="us-east-1"  # CloudFront requires certificates in us-east-1
CERT_ARN=$(aws acm list-certificates \
    --region "$CLOUDFRONT_REGION" \
    --query "CertificateSummaryList[?DomainName=='$FRONTEND_DOMAIN' || DomainName=='*.demo.balansi.me' || DomainName=='*.$HOSTED_ZONE_NAME'].CertificateArn" \
    --output text | head -1)

if [ -z "$CERT_ARN" ] || [ "$CERT_ARN" == "None" ]; then
    echo "⚠️  No SSL certificate found for $FRONTEND_DOMAIN in $CLOUDFRONT_REGION"
    echo "   Amplify/CloudFront requires certificates in us-east-1 region"
    echo ""
    echo "   Please create a certificate in ACM (Certificate Manager):"
    echo "   - Domain: $FRONTEND_DOMAIN"
    echo "   - Or wildcard: *.$HOSTED_ZONE_NAME"
    echo "   - Region: us-east-1 (required for CloudFront)"
    echo ""
    echo "   You can create it via AWS Console:"
    echo "   https://console.aws.amazon.com/acm/home?region=$CLOUDFRONT_REGION#/certificates/request"
    echo ""
    read -p "   Do you want to continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    read -p "   Enter the Certificate ARN: " CERT_ARN
else
    echo "✅ Found certificate: $CERT_ARN"
fi
echo ""

# Check if domain already exists
echo "🔍 Checking for existing custom domain..."
EXISTING_DOMAIN=$(aws amplify list-domain-associations \
    --app-id "$APP_ID" \
    --region "$REGION" \
    --query "domainAssociations[?domainName=='$FRONTEND_DOMAIN'].domainName" \
    --output text | head -1)

if [ -n "$EXISTING_DOMAIN" ] && [ "$EXISTING_DOMAIN" != "None" ]; then
    echo "⚠️  Custom domain $FRONTEND_DOMAIN already exists"
    read -p "   Do you want to update it? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "   Skipping domain creation..."
        exit 0
    fi
fi

# Create domain association
if [ -z "$EXISTING_DOMAIN" ] || [ "$EXISTING_DOMAIN" == "None" ]; then
    echo "📝 Creating domain association..."

    # Create domain association
    # Use CUSTOM type when providing our own certificate
    aws amplify create-domain-association \
        --app-id "$APP_ID" \
        --domain-name "$FRONTEND_DOMAIN" \
        --certificate-settings type=CUSTOM,customCertificateArn="$CERT_ARN" \
        --sub-domain-settings prefix="$BRANCH_NAME",branchName="$BRANCH_NAME" \
        --region "$REGION" \
        --output json > /tmp/amplify-domain.json

    echo "✅ Domain association created!"
    echo ""

    # Wait for domain to be available
    echo "⏳ Waiting for domain to be available (this may take a few minutes)..."
    MAX_ATTEMPTS=30
    ATTEMPT=0

    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        DOMAIN_STATUS=$(aws amplify get-domain-association \
            --app-id "$APP_ID" \
            --domain-name "$FRONTEND_DOMAIN" \
            --region "$REGION" \
            --query 'domainAssociation.domainStatus' \
            --output text 2>/dev/null || echo "PENDING")

        if [ "$DOMAIN_STATUS" == "AVAILABLE" ]; then
            echo "✅ Domain is now available!"
            break
        fi

        ATTEMPT=$((ATTEMPT + 1))
        echo "   Status: $DOMAIN_STATUS (attempt $ATTEMPT/$MAX_ATTEMPTS)"
        sleep 10
    done

    if [ "$DOMAIN_STATUS" != "AVAILABLE" ]; then
        echo "⚠️  Domain is still being provisioned. Status: $DOMAIN_STATUS"
        echo "   This is normal - it can take 15-30 minutes for CloudFront distribution to be created"
    fi
else
    echo "✅ Domain already exists"
fi

# Get domain configuration
echo ""
echo "📋 Getting domain configuration..."
DOMAIN_CONFIG=$(aws amplify get-domain-association \
    --app-id "$APP_ID" \
    --domain-name "$FRONTEND_DOMAIN" \
    --region "$REGION" \
    --output json)

DOMAIN_STATUS=$(echo "$DOMAIN_CONFIG" | jq -r '.domainAssociation.domainStatus')
SUBDOMAIN=$(echo "$DOMAIN_CONFIG" | jq -r '.domainAssociation.subDomains[0]')
DNS_RECORDS=$(echo "$DOMAIN_CONFIG" | jq -r '.domainAssociation.subDomains[0].dnsRecord')

echo "✅ Domain configuration:"
echo "   Status: $DOMAIN_STATUS"
echo "   Subdomain: $SUBDOMAIN"
echo ""

# Configure Route53 records
echo "🌐 Configuring Route53 DNS records..."
ROUTE53_ZONE_ID=$(aws route53 list-hosted-zones \
    --query "HostedZones[?Name=='$HOSTED_ZONE_NAME.'].Id" \
    --output text | head -1 | sed 's|/hostedzone/||')

if [ -z "$ROUTE53_ZONE_ID" ] || [ "$ROUTE53_ZONE_ID" == "None" ]; then
    echo "⚠️  Could not find Route53 hosted zone for $HOSTED_ZONE_NAME"
    echo "   Please create the DNS records manually:"
    echo ""
    echo "$DNS_RECORDS" | jq -r '.type + " " + .name + " -> " + .value'
else
    echo "✅ Found Route53 hosted zone: $ROUTE53_ZONE_ID"

    # Parse DNS records and create them
    echo "$DNS_RECORDS" | jq -c '.' | while read -r record; do
        RECORD_TYPE=$(echo "$record" | jq -r '.type')
        RECORD_NAME=$(echo "$record" | jq -r '.name')
        RECORD_VALUE=$(echo "$record" | jq -r '.value')

        # Check if record already exists
        EXISTING_RECORD=$(aws route53 list-resource-record-sets \
            --hosted-zone-id "$ROUTE53_ZONE_ID" \
            --query "ResourceRecordSets[?Name=='$RECORD_NAME.' && Type=='$RECORD_TYPE'].Name" \
            --output text | head -1)

        if [ -z "$EXISTING_RECORD" ] || [ "$EXISTING_RECORD" == "None" ]; then
            echo "📝 Creating DNS record: $RECORD_TYPE $RECORD_NAME -> $RECORD_VALUE"

            if [ "$RECORD_TYPE" == "CNAME" ]; then
                CHANGE_BATCH=$(cat <<EOF
{
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "$RECORD_NAME",
            "Type": "$RECORD_TYPE",
            "TTL": 300,
            "ResourceRecords": [{"Value": "$RECORD_VALUE"}]
        }
    }]
}
EOF
)
            else
                # For A records (alias)
                CHANGE_BATCH=$(cat <<EOF
{
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "$RECORD_NAME",
            "Type": "$RECORD_TYPE",
            "AliasTarget": {
                "HostedZoneId": "Z2FDTNDATAQYW2",
                "DNSName": "$RECORD_VALUE",
                "EvaluateTargetHealth": false
            }
        }
    }]
}
EOF
)
            fi

            CHANGE_ID=$(aws route53 change-resource-record-sets \
                --hosted-zone-id "$ROUTE53_ZONE_ID" \
                --change-batch "$CHANGE_BATCH" \
                --query 'ChangeInfo.Id' \
                --output text)

            echo "   ✅ Record created (Change ID: $CHANGE_ID)"
        else
            echo "   ✅ Record already exists: $RECORD_TYPE $RECORD_NAME"
        fi
    done
fi
echo ""

echo "✨ Custom domain configuration complete!"
echo ""
echo "📋 Summary:"
echo "   Frontend Domain: $FRONTEND_DOMAIN"
echo "   App ID: $APP_ID"
echo "   Branch: $BRANCH_NAME"
echo "   Certificate ARN: $CERT_ARN"
echo "   Domain Status: $DOMAIN_STATUS"
echo ""
echo "🔗 Your frontend will be available at:"
echo "   https://$FRONTEND_DOMAIN"
echo ""
echo "⏳ Note:"
echo "   - DNS propagation may take a few minutes"
echo "   - CloudFront distribution creation can take 15-30 minutes"
echo "   - Check status: aws amplify get-domain-association --app-id $APP_ID --domain-name $FRONTEND_DOMAIN --region $REGION"
