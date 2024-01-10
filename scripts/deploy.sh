#!/bin/bash

# Navigate to the build directory
cd docusaurus/build

# Sync files to S3
aws s3 sync . s3://marketplacepro-docs --delete

echo "Deployment to S3 completed."
