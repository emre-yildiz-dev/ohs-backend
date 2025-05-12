#!/bin/bash

# Ensure wget is installed
if ! command -v wget &> /dev/null; then
    echo "Installing wget..."
    apt-get update && apt-get install -y wget && rm -rf /var/lib/apt/lists/*
fi

# Wait for Garage to be ready
echo "Waiting for Garage to be ready..."
until wget --spider -q http://garage:3900; do
  echo "Garage is not ready yet. Sleeping for 5 seconds..."
  sleep 5
done

echo "Garage is up! Initializing..."

# Get node ID
NODE_ID=$(/garage status | grep -v "HEALTHY NODES" | grep -v "ID " | awk '{print $1}' | head -1)
echo "Found node ID: $NODE_ID"

# Configure layout (required before any operation)
echo "Configuring layout..."
/garage layout assign -z dc1 -c 1G $NODE_ID
/garage layout apply
echo "Layout applied!"

# Create an admin key
echo "Creating admin key..."
ADMIN_KEY=$(/garage key create --name admin)
echo "Created admin key: $ADMIN_KEY"

# Get key ID from output
KEY_ID=$(echo "$ADMIN_KEY" | grep "Key ID:" | awk '{print $3}')
echo "Extracted Key ID: $KEY_ID"

# Add S3 credentials
echo "Setting key permissions..."
/garage key allow --bucket-put=true --bucket-read=true --object-put=true --object-read=true $KEY_ID
echo "Allowed permissions for admin key"

# Create the bucket
echo "Creating bucket..."
/garage bucket create ohs-bucket
echo "Created bucket: ohs-bucket"

# Set allow-read permission for bucket
echo "Setting bucket permissions..."
/garage bucket allow --website ohs-bucket --read $KEY_ID
echo "Set allow-read permission for bucket"

echo "Garage initialization complete!" 