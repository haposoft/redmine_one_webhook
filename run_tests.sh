#!/bin/bash
# Test runner script for Redmine ONE Webhook Plugin  
# Usage: ./run_tests.sh [test_file]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PLUGIN_NAME="redmine_one_webhook"

echo -e "${GREEN}Running Redmine ONE Webhook Plugin Tests${NC}"
echo "=========================================="

# Check if running in Docker or locally
if [ -f "/.dockerenv" ] || [ -n "$DOCKER_CONTAINER" ]; then
    # Running inside Docker container
    REDMINE_ROOT="/usr/src/redmine"
    cd "$REDMINE_ROOT"
    
    if [ -n "$1" ]; then
        # Run specific test file
        TEST_FILE="$1"
        echo -e "${YELLOW}Running test: $TEST_FILE${NC}"
        RAILS_ENV=test ruby -Itest "plugins/$PLUGIN_NAME/test/$TEST_FILE"
    else
        # Run all plugin tests
        echo -e "${YELLOW}Running all tests...${NC}"
        RAILS_ENV=test rake redmine:plugins:test NAME=$PLUGIN_NAME
    fi
else
    # Running locally - use Docker Compose
    if [ ! -d "../pms" ]; then
        echo -e "${RED}Error: Cannot find pms directory${NC}"
        echo "Please ensure docker-compose setup exists"
        exit 1
    fi
    
    echo -e "${YELLOW}Running tests via Docker Compose...${NC}"
    cd ../pms
    
    # Check if test database is configured
    TEST_DB_CONFIGURED=$(docker-compose exec -T redmine bash -c "grep -q 'test:' /usr/src/redmine/config/database.yml && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")
    
    if [ "$TEST_DB_CONFIGURED" = "no" ]; then
        echo -e "${RED}Error: Test database not configured${NC}"
        echo -e "${YELLOW}Please run './setup_test.sh' first${NC}"
        exit 1
    fi
    
    if [ -n "$1" ]; then
        # Run specific test file
        echo -e "${BLUE}Running test file: $1${NC}"
        # Add mocha to load path (it's not in Gemfile.lock due to --without test)
        docker-compose exec -T redmine bash -c "cd /usr/src/redmine && RUBYLIB='/usr/local/bundle/gems/mocha-3.0.1/lib' RAILS_ENV=test ruby -Itest plugins/$PLUGIN_NAME/test/$1"
    else
        # Run all tests
        echo -e "${BLUE}Running all tests...${NC}"
        # Add mocha to load path (it's not in Gemfile.lock due to --without test)
        docker-compose exec -T redmine bash -c "cd /usr/src/redmine && RUBYLIB='/usr/local/bundle/gems/mocha-3.0.1/lib' RAILS_ENV=test rake redmine:plugins:test NAME=$PLUGIN_NAME"
    fi
    
    TEST_EXIT_CODE=$?
    
    if [ $TEST_EXIT_CODE -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ All tests passed!${NC}"
    else
        echo ""
        echo -e "${RED}✗ Some tests failed${NC}"
    fi
    
    exit $TEST_EXIT_CODE
fi

echo -e "${GREEN}Tests completed!${NC}"
