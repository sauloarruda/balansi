#!/bin/bash

# Script to create SSL certificates in ACM for custom domains
# Usage: ./scripts/create-ssl-certificates.sh

set -e

API_DOMAIN="api.demo.balansi.me"
FRONTEND_DOMAIN="demo.balansi.me"
HOSTED_ZONE_NAME="balansi.me"
REGION_API="us-east-2"  # API Gateway region
REGION_CLOUDFRONT="us-east-1"  # CloudFront requires us-east-1

echo "🔐 Creating SSL certificates in AWS Certificate Manager..."
echo ""

# Check if certificates already exist
echo "🔍 Checking for existing certificates..."

# Check for API Gateway certificate (us-east-2)
API_CERT=$(aws acm list-certificates \
    --region "$REGION_API" \
    --query "CertificateSummaryList[?DomainName=='$API_DOMAIN' || DomainName=='*.$HOSTED_ZONE_NAME'].CertificateArn" \
    --output text | head -1)

# Check for CloudFront certificate (us-east-1)
CLOUDFRONT_CERT=$(aws acm list-certificates \
    --region "$REGION_CLOUDFRONT" \
    --query "CertificateSummaryList[?DomainName=='$FRONTEND_DOMAIN' || DomainName=='*.$HOSTED_ZONE_NAME'].CertificateArn" \
    --output text | head -1)

if [ -n "$API_CERT" ] && [ "$API_CERT" != "None" ]; then
    echo "✅ API Gateway certificate already exists: $API_CERT"
else
    echo "📝 Requesting certificate for API Gateway ($API_DOMAIN)..."
    echo "   Region: $REGION_API"

    API_CERT_ARN=$(aws acm request-certificate \
        --domain-name "$API_DOMAIN" \
        --validation-method DNS \
        --region "$REGION_API" \
        --query 'CertificateArn' \
        --output text)

    echo "✅ Certificate requested: $API_CERT_ARN"
    echo "   ⚠️  You need to validate this certificate by adding DNS records to Route53"
    echo ""
fi

if [ -n "$CLOUDFRONT_CERT" ] && [ "$CLOUDFRONT_CERT" != "None" ]; then
    echo "✅ CloudFront certificate already exists: $CLOUDFRONT_CERT"
else
    echo "📝 Requesting wildcard certificate for CloudFront (*.demo.balansi.me)..."
    echo "   Region: $REGION_CLOUDFRONT (required for CloudFront)"
    echo "   This certificate will cover demo.balansi.me and all subdomains like bal-7.demo.balansi.me"

    CLOUDFRONT_CERT_ARN=$(aws acm request-certificate \
        --domain-name "*.demo.balansi.me" \
        --subject-alternative-names "$FRONTEND_DOMAIN" \
        --validation-method DNS \
        --region "$REGION_CLOUDFRONT" \
        --query 'CertificateArn' \
        --output text)

    echo "✅ Certificate requested: $CLOUDFRONT_CERT_ARN"
    echo "   ⚠️  You need to validate this certificate by adding DNS records to Route53"
    echo ""
fi

echo ""
echo "📋 Next steps:"
echo ""
echo "1. Wait for certificate validation (check ACM console)"
echo "2. Add DNS validation records to Route53 if not done automatically"
echo "3. Run domain setup scripts:"
echo "   - API Gateway: cd services/auth && ./scripts/setup-custom-domain.sh"
echo "   - Amplify: cd services/web && ./scripts/setup-custom-domain.sh"
echo ""
echo "🔗 ACM Console:"
echo "   API Gateway: https://console.aws.amazon.com/acm/home?region=$REGION_API#/certificates"
echo "   CloudFront: https://console.aws.amazon.com/acm/home?region=$REGION_CLOUDFRONT#/certificates"
