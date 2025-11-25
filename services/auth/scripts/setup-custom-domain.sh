#!/bin/bash

# Script to configure custom domain for API Gateway
# Usage: ./scripts/setup-custom-domain.sh

set -e

REGION="us-east-2"
API_DOMAIN="api.demo.balansi.me"
FRONTEND_DOMAIN="demo.balansi.me"
HOSTED_ZONE_NAME="balansi.me"  # Adjust if your hosted zone is different

echo "🔧 Configuring custom domain for API Gateway..."
echo "API Domain: $API_DOMAIN"
echo "Region: $REGION"
echo ""

# Get API Gateway ID from serverless info
echo "📡 Getting API Gateway ID..."
API_INFO=$(serverless info --stage dev 2>&1 | grep -E 'https://[^/]+' | head -1)
API_GATEWAY_URL=$(echo "$API_INFO" | sed 's/.*\(https:\/\/[^/]*\).*/\1/')
API_GATEWAY_ID=$(echo "$API_GATEWAY_URL" | sed 's/.*\/\/\([^.]*\).*/\1/')

if [ -z "$API_GATEWAY_ID" ]; then
    echo "❌ Could not extract API Gateway ID from: $API_GATEWAY_URL"
    exit 1
fi

echo "✅ Found API Gateway ID: $API_GATEWAY_ID"
echo "   API URL: $API_GATEWAY_URL"
echo ""

# Check if certificate exists in ACM
echo "🔍 SSL Certificate..."
CERT_ARN=$(aws acm list-certificates \
    --region "$REGION" \
    --query "CertificateSummaryList[?DomainName=='$API_DOMAIN' || DomainName=='*.$HOSTED_ZONE_NAME'].CertificateArn" \
    --output text | head -1)

if [ -z "$CERT_ARN" ] || [ "$CERT_ARN" == "None" ]; then
    echo "⚠️  No SSL certificate found for $API_DOMAIN"
    echo "   Please create a certificate in ACM (Certificate Manager) for:"
    echo "   - $API_DOMAIN"
    echo "   - Or wildcard: *.$HOSTED_ZONE_NAME"
    echo ""
    echo "   You can create it via AWS Console:"
    echo "   https://console.aws.amazon.com/acm/home?region=$REGION#/certificates/request"
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

# Get API Gateway HTTP API ID (different from REST API)
echo "🔍 Getting HTTP API ID..."
HTTP_API_ID=$(aws apigatewayv2 get-apis \
    --region "$REGION" \
    --query "Items[?ApiEndpoint=='$API_GATEWAY_URL'].ApiId" \
    --output text | head -1)

if [ -z "$HTTP_API_ID" ] || [ "$HTTP_API_ID" == "None" ]; then
    # Try alternative method - get from API Gateway URL
    HTTP_API_ID=$(echo "$API_GATEWAY_URL" | sed 's/.*\/\/\([^.]*\)\.execute-api.*/\1/')
fi

if [ -z "$HTTP_API_ID" ]; then
    echo "❌ Could not find HTTP API ID"
    echo "   Please check your API Gateway configuration"
    exit 1
fi

echo "✅ Found HTTP API ID: $HTTP_API_ID"
echo ""

# Check if custom domain already exists
echo "🔍 Checking for existing custom domain..."
EXISTING_DOMAIN=$(aws apigatewayv2 get-domain-names \
    --region "$REGION" \
    --query "Items[?DomainName=='$API_DOMAIN'].DomainName" \
    --output text | head -1)

if [ -n "$EXISTING_DOMAIN" ] && [ "$EXISTING_DOMAIN" != "None" ]; then
    echo "✅ Custom domain $API_DOMAIN already exists"
    echo "   Continuing with configuration..."
fi

# Create custom domain if it doesn't exist
if [ -z "$EXISTING_DOMAIN" ] || [ "$EXISTING_DOMAIN" == "None" ]; then
    echo "📝 Creating custom domain..."
    DOMAIN_RESULT=$(aws apigatewayv2 create-domain-name \
        --domain-name "$API_DOMAIN" \
        --domain-name-configurations CertificateArn="$CERT_ARN" \
        --region "$REGION" \
        --output json)

    DOMAIN_NAME_ID=$(echo "$DOMAIN_RESULT" | jq -r '.DomainNameId')
    DOMAIN_NAME_STATUS=$(echo "$DOMAIN_RESULT" | jq -r '.DomainNameStatus')

    echo "✅ Custom domain created!"
    echo "   Domain Name ID: $DOMAIN_NAME_ID"
    echo "   Status: $DOMAIN_NAME_STATUS"
    echo ""
else
    echo "✅ Using existing domain: $API_DOMAIN"
    # Get current domain config to check status
    DOMAIN_CONFIG=$(aws apigatewayv2 get-domain-name \
        --domain-name "$API_DOMAIN" \
        --region "$REGION" \
        --output json 2>/dev/null || echo '{}')
    CURRENT_STATUS=$(echo "$DOMAIN_CONFIG" | jq -r '.DomainNameStatus // "PENDING"')
    echo "   Current status: $CURRENT_STATUS"
fi

# Wait for domain to be available and get configuration
echo "⏳ Waiting for domain to be available..."
MAX_ATTEMPTS=30
ATTEMPT=0
TARGET_DOMAIN=""
HOSTED_ZONE_ID=""

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    DOMAIN_CONFIG=$(aws apigatewayv2 get-domain-name \
        --domain-name "$API_DOMAIN" \
        --region "$REGION" \
        --output json 2>/dev/null || echo '{}')

    DOMAIN_STATUS=$(echo "$DOMAIN_CONFIG" | jq -r '.DomainNameConfigurations[0].DomainNameStatus // .DomainNameStatus // "PENDING"')
    TARGET_DOMAIN=$(echo "$DOMAIN_CONFIG" | jq -r '.DomainNameConfigurations[0].ApiGatewayDomainName // .DomainNameConfigurations[0].TargetDomainName // ""')
    HOSTED_ZONE_ID=$(echo "$DOMAIN_CONFIG" | jq -r '.DomainNameConfigurations[0].HostedZoneId // ""')
    
    if [ "$DOMAIN_STATUS" == "AVAILABLE" ] && [ -n "$TARGET_DOMAIN" ] && [ "$TARGET_DOMAIN" != "null" ]; then
        echo "✅ Domain is available!"
        break
    fi

    ATTEMPT=$((ATTEMPT + 1))
    echo "   Status: $DOMAIN_STATUS (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    sleep 5
done

if [ -z "$TARGET_DOMAIN" ] || [ "$TARGET_DOMAIN" == "null" ]; then
    echo "⚠️  Domain is still being provisioned. Target domain not yet available."
    echo "   This can take 5-10 minutes. Please run this script again later."
    echo "   Or check status: aws apigatewayv2 get-domain-name --domain-name $API_DOMAIN --region $REGION"
    exit 1
fi

# Get final domain config
DOMAIN_CONFIG=$(aws apigatewayv2 get-domain-name \
    --domain-name "$API_DOMAIN" \
    --region "$REGION" \
    --output json)

DOMAIN_NAME_ID=$(echo "$DOMAIN_CONFIG" | jq -r '.DomainNameId')
TARGET_DOMAIN=$(echo "$DOMAIN_CONFIG" | jq -r '.DomainNameConfigurations[0].ApiGatewayDomainName // .DomainNameConfigurations[0].TargetDomainName')
HOSTED_ZONE_ID=$(echo "$DOMAIN_CONFIG" | jq -r '.DomainNameConfigurations[0].HostedZoneId')

echo "✅ Domain configuration retrieved:"
echo "   Domain Name ID: $DOMAIN_NAME_ID"
echo "   Target Domain: $TARGET_DOMAIN"
echo "   Hosted Zone ID: $HOSTED_ZONE_ID"
echo ""

# Create API mapping
echo "🔗 Creating API mapping..."
EXISTING_MAPPING=$(aws apigatewayv2 get-api-mappings \
    --domain-name "$API_DOMAIN" \
    --region "$REGION" \
    --query "Items[?ApiId=='$HTTP_API_ID'].ApiMappingId" \
    --output text | head -1)

if [ -z "$EXISTING_MAPPING" ] || [ "$EXISTING_MAPPING" == "None" ]; then
    aws apigatewayv2 create-api-mapping \
        --domain-name "$API_DOMAIN" \
        --api-id "$HTTP_API_ID" \
        --stage "\$default" \
        --region "$REGION" \
        --output json > /dev/null

    echo "✅ API mapping created!"
else
    echo "✅ API mapping already exists"
fi
echo ""

# Configure Route53 record
echo "🌐 Configuring Route53 DNS record..."
ROUTE53_ZONE_ID=$(aws route53 list-hosted-zones \
    --query "HostedZones[?Name=='$HOSTED_ZONE_NAME.'].Id" \
    --output text | head -1 | sed 's|/hostedzone/||')

if [ -z "$ROUTE53_ZONE_ID" ] || [ "$ROUTE53_ZONE_ID" == "None" ]; then
    echo "⚠️  Could not find Route53 hosted zone for $HOSTED_ZONE_NAME"
    echo "   Please create the DNS record manually:"
    echo "   Type: A (or CNAME)"
    echo "   Name: $API_DOMAIN"
    echo "   Value: $TARGET_DOMAIN"
else
    echo "✅ Found Route53 hosted zone: $ROUTE53_ZONE_ID"

    # Check if record already exists
    EXISTING_RECORD=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$ROUTE53_ZONE_ID" \
        --query "ResourceRecordSets[?Name=='$API_DOMAIN.'].Name" \
        --output text | head -1)

    if [ -z "$EXISTING_RECORD" ] || [ "$EXISTING_RECORD" == "None" ]; then
        echo "📝 Creating DNS record..."

        # Use the Hosted Zone ID from API Gateway domain configuration (not Route53)
        # This is the CloudFront/API Gateway hosted zone ID
        API_GATEWAY_HOSTED_ZONE_ID="$HOSTED_ZONE_ID"

        CHANGE_BATCH=$(cat <<EOF
{
    "Changes": [{
        "Action": "UPSERT",
        "ResourceRecordSet": {
            "Name": "$API_DOMAIN",
            "Type": "A",
            "AliasTarget": {
                "HostedZoneId": "$API_GATEWAY_HOSTED_ZONE_ID",
                "DNSName": "$TARGET_DOMAIN",
                "EvaluateTargetHealth": false
            }
        }
    }]
}
EOF
)

        CHANGE_ID=$(aws route53 change-resource-record-sets \
            --hosted-zone-id "$ROUTE53_ZONE_ID" \
            --change-batch "$CHANGE_BATCH" \
            --query 'ChangeInfo.Id' \
            --output text)

        echo "✅ DNS record created!"
        echo "   Change ID: $CHANGE_ID"
        echo "   DNS propagation may take a few minutes..."
    else
        echo "✅ DNS record already exists"
    fi
fi
echo ""

echo "✨ Custom domain configuration complete!"
echo ""
echo "📋 Summary:"
echo "   API Domain: $API_DOMAIN"
echo "   API Gateway ID: $HTTP_API_ID"
echo "   Certificate ARN: $CERT_ARN"
echo "   Target Domain: $TARGET_DOMAIN"
echo ""
echo "🔗 Your API will be available at:"
echo "   https://$API_DOMAIN"
echo ""
echo "⏳ Note: DNS propagation may take a few minutes to complete."
echo "   You can check DNS propagation status at:"
echo "   https://dnschecker.org/#A/$API_DOMAIN"
