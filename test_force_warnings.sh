#!/bin/bash
set -euo pipefail

# Source required libraries
source lib/logging.sh
source lib/validation.sh

# Create test file
mkdir -p /tmp/force_test
cd /tmp/force_test
echo "existing content" > testfile.txt

echo "=== Testing non-interactive force mode ==="
export FORCE="true"
export ARCHIVE_DIR="/tmp/force_test/archive"
export SYNC_BASE_DIR="/tmp/force_test"
mkdir -p "$ARCHIVE_DIR"

echo "Testing force mode warnings..."
output=$(check_file_collision testfile.txt 2>&1 || true)
echo "Output received: $output"

if [[ "$output" == *"FORCE MODE"* ]]; then
    echo "✓ Force mode warnings are working correctly"
else
    echo "✗ Expected FORCE MODE warnings not found"
fi

# Cleanup
rm -rf /tmp/force_test
echo "Manual verification completed!"
