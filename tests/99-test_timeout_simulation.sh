#!/bin/bash

# TEST_DESCRIPTION: Timeout simulation test
# TEST_TIMEOUT: 3

set -euo pipefail

echo "Starting timeout simulation test..."
echo "This test will sleep for 5 seconds but has a 3 second timeout"
sleep 5
echo "This should never be printed due to timeout"
