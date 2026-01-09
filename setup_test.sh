#!/bin/bash
# Setup test environment for Redmine plugin testing
# Run this ONCE after docker-compose up for the first time

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Setting up Redmine Test Environment ===${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "init.rb" ]; then
    echo -e "${RED}Error: Must run from plugin directory${NC}"
    exit 1
fi

cd ../pms

# Check if containers are running
if ! docker-compose ps redmine | grep -q "Up"; then
    echo -e "${YELLOW}Starting containers...${NC}"
    docker-compose up -d
    echo "Waiting for containers to be ready..."
    sleep 15
fi

echo -e "${BLUE}Step 1: Configuring test database...${NC}"
docker-compose exec -T redmine bash -c "
cd /usr/src/redmine
if ! grep -q 'test:' config/database.yml; then
    cat >> config/database.yml << 'EOF'

test:
  adapter: mysql2
  host: \"db\"
  port: \"3306\"
  username: \"redmine\"
  password: \"redmine_password\"
  database: \"redmine_test\"
  encoding: utf8mb4
EOF
    echo '✓ Test database configuration added'
else
    echo '✓ Test database already configured'
fi
"

echo -e "${BLUE}Step 2: Creating test database...${NC}"
docker-compose exec -T redmine bash -c "
cd /usr/src/redmine
echo 'Creating test database...'
RAILS_ENV=test bin/rails db:create 2>&1 | grep -v 'already exists' | head -1 || echo '✓ Database exists'
echo 'Running migrations...'
RAILS_ENV=test bin/rails db:migrate 2>&1 | tail -5
"

echo -e "${BLUE}Step 3: Installing test dependencies and patching Gemfile.lock...${NC}"
docker-compose exec -T redmine bash -c "
cd /usr/src/redmine
echo 'Installing compatible minitest 5.27.0...'
gem install minitest -v 5.27.0 --no-document 2>&1 | tail -1
echo 'Installing mocha gem...'
gem install mocha --no-document 2>&1 | tail -1
echo 'Patching Gemfile.lock to use minitest 5.27.0...'
# Replace minitest 6.0.1 with 5.27.0 in Gemfile.lock
sed -i 's/minitest (6\\.0\\.1)/minitest (5.27.0)/g' Gemfile.lock
sed -i 's/minitest (~> 6\\.0)/minitest (~> 5.27)/g' Gemfile.lock
echo '✓ Test dependencies installed and Gemfile.lock patched'
"

echo -e "${BLUE}Step 4: Loading default test data...${NC}"
docker-compose exec -T redmine bash -c "
cd /usr/src/redmine
RAILS_ENV=test bin/rails redmine:load_default_data REDMINE_LANG=en 2>&1 | grep -E '(Default|Select)' || echo '✓ Data loaded'
"

echo ""
echo -e "${GREEN}✓ Setup complete!${NC}"
echo ""
echo -e "${YELLOW}You can now run tests with:${NC}"
echo -e "  ${BLUE}cd $(dirname $0) && ./run_tests.sh${NC}"
echo ""
echo -e "${YELLOW}Note: This setup persists across 'docker-compose restart'${NC}"
echo -e "${YELLOW}Only need to run this again after 'docker-compose down'${NC}"
