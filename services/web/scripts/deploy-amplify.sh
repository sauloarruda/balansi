#!/bin/bash

# Deploy script for AWS Amplify
# Usage: ./deploy-amplify.sh
#
# Prerequisites:
# - AWS CLI configured with appropriate credentials
# - jq installed for JSON processing

set -e

BRANCH_NAME=$(git branch --show-current 2>/dev/null || echo "")
REGION="us-east-2"
APP_ID=$(aws amplify list-apps --region "$REGION" --query 'apps[?name==`balansi-staging`].appId' --output text 2>/dev/null || echo "")

# Validate branch name
if [ -z "$BRANCH_NAME" ]; then
    echo "❌ Could not determine current git branch. Make sure you're in a git repository."
    exit 1
fi

# Validate app ID
if [ -z "$APP_ID" ] || [ "$APP_ID" = "None" ]; then
    echo "❌ Could not find Amplify app 'balansi-staging' in region $REGION."
    echo "   Please check that the app exists and you have the correct permissions."
    exit 1
fi

echo "🚀 Starting manual deployment to Amplify..."
echo "App ID: $APP_ID"
echo "Branch: $BRANCH_NAME"
echo "Region: $REGION"
echo ""

# Use custom domains for API Gateway
API_URL="https://api.demo.balansi.me"
JOURNAL_API_URL="https://journal.demo.balansi.me"
echo "🔍 Using API Gateway custom domains:"
echo "   Auth API: $API_URL"
echo "   Journal API: $JOURNAL_API_URL"
echo ""
echo "🔧 Configuring environment variables..."

    # Get current environment variables and merge with new ones
    CURRENT_ENV=$(aws amplify get-app \
      --app-id "$APP_ID" \
      --region "$REGION" \
      --output json 2>/dev/null | jq -r '.app.environmentVariables // {}')

    # Merge with VITE_API_URL and VITE_JOURNAL_API_URL
    UPDATED_ENV=$(echo "$CURRENT_ENV" | jq \
      --arg api_url "$API_URL" \
      --arg journal_url "$JOURNAL_API_URL" \
      '. + {"VITE_API_URL": $api_url, "VITE_JOURNAL_API_URL": $journal_url}')

    # Convert to AWS CLI format: key1=value1,key2=value2
    ENV_STRING=$(echo "$UPDATED_ENV" | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')

    # Update app with new environment variables
    if aws amplify update-app \
      --app-id "$APP_ID" \
      --region "$REGION" \
      --environment-variables "$ENV_STRING" \
      --output json > /dev/null 2>&1; then
        echo "✅ Environment variables configured successfully!"
        echo "   VITE_API_URL = $API_URL"
        echo "   VITE_JOURNAL_API_URL = $JOURNAL_API_URL"
    else
        echo "⚠️  WARNING: Could not configure environment variables automatically."
        echo "   Please configure manually in Amplify Console:"
        echo "   App settings → Environment variables → Add:"
        echo "   - VITE_API_URL = $API_URL"
        echo "   - VITE_JOURNAL_API_URL = $JOURNAL_API_URL"
    fi
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "❌ jq is not installed. Installing via brew..."
    if command -v brew &> /dev/null; then
        brew install jq
    else
        echo "Please install jq manually: https://stedolan.github.io/jq/"
        exit 1
    fi
fi

# Build with API URLs if available
if [ -n "$API_URL" ] && [ "$API_URL" != "" ]; then
    echo "🔨 Building with environment variables..."
    echo "   VITE_API_URL=$API_URL"
    echo "   VITE_JOURNAL_API_URL=$JOURNAL_API_URL"
    VITE_API_URL="$API_URL" VITE_JOURNAL_API_URL="$JOURNAL_API_URL" npm run build
else
    echo "⚠️  Building without API URLs (will use localhost fallbacks)..."
    echo "   Make sure to configure environment variables in Amplify Console for future builds"
    if [ ! -d "build" ]; then
        echo "❌ Build directory not found. Running build first..."
        npm run build
    fi
fi

# Check for pending deployments
echo "🔍 Checking for pending deployments..."
PENDING_JOBS=$(aws amplify list-jobs \
  --app-id "$APP_ID" \
  --branch-name "$BRANCH_NAME" \
  --region "$REGION" \
  --max-results 10 \
  --output json 2>/dev/null | jq -r '.jobSummaries[] | select(.status == "PENDING" or .status == "RUNNING") | .jobId' | head -1)

if [ -n "$PENDING_JOBS" ]; then
    echo "⚠️  Found pending/running deployment(s): $PENDING_JOBS"
    echo "   Please wait for them to complete or cancel them manually."
    echo "   Monitor at: https://console.aws.amazon.com/amplify/home?region=$REGION#/$APP_ID/$BRANCH_NAME"
    read -p "   Do you want to continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "📦 Creating deployment..."
DEPLOYMENT=$(aws amplify create-deployment \
  --app-id "$APP_ID" \
  --branch-name "$BRANCH_NAME" \
  --region "$REGION" \
  --output json)

JOB_ID=$(echo "$DEPLOYMENT" | jq -r '.jobId')
ZIP_URL=$(echo "$DEPLOYMENT" | jq -r '.zipUploadUrl')

if [ -z "$JOB_ID" ] || [ "$JOB_ID" == "null" ]; then
    echo "❌ Failed to create deployment. Response:"
    echo "$DEPLOYMENT"
    exit 1
fi

echo "✅ Deployment created. Job ID: $JOB_ID"
echo ""

echo "📤 Creating zip file from build directory..."
cd build
zip -r ../deploy.zip . -q
cd ..

echo "📤 Uploading zip file..."
curl -X PUT "$ZIP_URL" --upload-file deploy.zip --silent --show-error

echo "✅ Upload complete!"
echo ""

echo "🚀 Starting deployment..."
aws amplify start-deployment \
  --app-id "$APP_ID" \
  --branch-name "$BRANCH_NAME" \
  --job-id "$JOB_ID" \
  --region "$REGION" \
  --output json | jq -r '.jobSummary.jobId' > /dev/null

echo "✅ Deployment started!"
echo ""
echo "📊 You can monitor the deployment at:"
echo "https://console.aws.amazon.com/amplify/home?region=$REGION#/$APP_ID/$BRANCH_NAME"
echo ""

# Clean up
rm -f deploy.zip

echo "✨ Deployment initiated successfully!"
echo "Check the Amplify console for deployment status."
