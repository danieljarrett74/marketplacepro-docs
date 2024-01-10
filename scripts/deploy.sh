#!/bin/bash

# Navigate to the build directory
cd docusaurus/build || { echo "Failed to navigate to docusaurus/build directory"; exit 1; }

# Output the contents of the build directory
echo "Contents of the build directory:"
ls -al

# Sync files to S3 with verbose output
if aws s3 sync . s3://marketplacepro-docs --delete --debug; then
    echo "Deployment to S3 completed successfully."
else
    echo "Deployment to S3 failed."
    exit 1
fi
