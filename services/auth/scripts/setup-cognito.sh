#!/bin/bash

# Script to setup Cognito User Pool and Client in cognito-local
# This script should be run after cognito-local is started
# cognito-local typically runs on port 9229

set -e

COGNITO_ENDPOINT="${COGNITO_ENDPOINT:-http://localhost:9229}"
REGION="${AWS_REGION:-us-east-2}"

# Configure AWS CLI to use cognito-local
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=$REGION

echo "Setting up Cognito in cognito-local..."
echo "Endpoint: $COGNITO_ENDPOINT"
echo "Region: $REGION"
echo ""

# Create User Pool
echo "Creating User Pool..."
USER_POOL_RESPONSE=$(aws --endpoint-url=$COGNITO_ENDPOINT cognito-idp create-user-pool \
  --pool-name balansi-users \
  --region $REGION \
  --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=true}" \
  --auto-verified-attributes email \
  --schema \
    Name=email,AttributeDataType=String,Required=true \
    Name=name,AttributeDataType=String,Required=false \
    Name=nickname,AttributeDataType=String,Required=false \
  --output json 2>&1)

if [ $? -ne 0 ]; then
  echo "Error: Failed to create User Pool"
  echo "$USER_POOL_RESPONSE"
  echo ""
  echo "Make sure cognito-local is running on port 9229"
  echo "You can start it with: npx cognito-local"
  exit 1
fi

USER_POOL_ID=$(echo $USER_POOL_RESPONSE | jq -r '.UserPool.Id')

if [ "$USER_POOL_ID" == "null" ] || [ -z "$USER_POOL_ID" ]; then
  echo "Error: Could not extract User Pool ID from response"
  echo "Response: $USER_POOL_RESPONSE"
  exit 1
fi

echo "✓ User Pool created: $USER_POOL_ID"
echo ""

# Create User Pool Client
echo "Creating User Pool Client..."
CLIENT_RESPONSE=$(aws --endpoint-url=$COGNITO_ENDPOINT cognito-idp create-user-pool-client \
  --user-pool-id $USER_POOL_ID \
  --client-name balansi-client \
  --region $REGION \
  --generate-secret \
  --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
  --output json 2>&1)

if [ $? -ne 0 ]; then
  echo "Error: Failed to create User Pool Client"
  echo "$CLIENT_RESPONSE"
  exit 1
fi

CLIENT_ID=$(echo $CLIENT_RESPONSE | jq -r '.UserPoolClient.ClientId')

if [ "$CLIENT_ID" == "null" ] || [ -z "$CLIENT_ID" ]; then
  echo "Error: Could not extract Client ID from response"
  echo "Response: $CLIENT_RESPONSE"
  exit 1
fi

echo "✓ User Pool Client created: $CLIENT_ID"
echo ""

# Output environment variables
echo "=========================================="
echo "Add these to your .env file:"
echo "=========================================="
echo "COGNITO_USER_POOL_ID=$USER_POOL_ID"
echo "COGNITO_CLIENT_ID=$CLIENT_ID"
echo "COGNITO_ENDPOINT=$COGNITO_ENDPOINT"
echo "AWS_REGION=$REGION"
echo "=========================================="
echo ""
echo "Note: cognito-local is available at http://localhost:9229"
echo "      Make sure cognito-local is running before starting the service"
