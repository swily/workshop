#!/bin/bash

# Cleanup Deprecated Monitoring Scripts
# Run this ONLY after verifying health checks work correctly

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           Cleanup Deprecated Monitoring Scripts             ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}⚠️  WARNING: This will remove deprecated scripts${NC}"
echo ""
echo "Files to be removed:"
echo "  - monitoring/gremlin/create_health_checks.sh (770 lines)"
echo "  - monitoring/gremlin/validate_integration.sh"
echo "  - monitoring/gremlin/gremlin_credentials_manager.sh"
echo ""
echo "These are replaced by:"
echo "  ✅ monitoring/create_health_checks.sh (unified entry point)"
echo "  ✅ build_scripts/demo/healthchecks.sh (platform-specific)"
echo ""
echo -e "${RED}This action cannot be undone!${NC}"
echo ""
read -p "Have you verified health checks work in Gremlin UI? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo -e "${YELLOW}Aborted. Please verify health checks first.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}Removing deprecated scripts...${NC}"

# Remove deprecated Gremlin scripts
if [ -f "monitoring/gremlin/create_health_checks.sh" ]; then
    rm monitoring/gremlin/create_health_checks.sh
    echo -e "${GREEN}✅ Removed monitoring/gremlin/create_health_checks.sh${NC}"
fi

if [ -f "monitoring/gremlin/validate_integration.sh" ]; then
    rm monitoring/gremlin/validate_integration.sh
    echo -e "${GREEN}✅ Removed monitoring/gremlin/validate_integration.sh${NC}"
fi

if [ -f "monitoring/gremlin/gremlin_credentials_manager.sh" ]; then
    rm monitoring/gremlin/gremlin_credentials_manager.sh
    echo -e "${GREEN}✅ Removed monitoring/gremlin/gremlin_credentials_manager.sh${NC}"
fi

# Remove empty configs directory if it exists
if [ -d "monitoring/gremlin/configs" ] && [ -z "$(ls -A monitoring/gremlin/configs)" ]; then
    rmdir monitoring/gremlin/configs
    echo -e "${GREEN}✅ Removed empty monitoring/gremlin/configs directory${NC}"
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    CLEANUP COMPLETE                          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✅ Deprecated scripts removed${NC}"
echo ""
echo -e "${BLUE}Current monitoring structure:${NC}"
echo "  monitoring/"
echo "  ├── create_health_checks.sh (unified entry point)"
echo "  ├── prometheus/ (install, servicemonitors, values)"
echo "  ├── grafana/ (alerts, auth, ingress, install)"
echo "  ├── gremlin/ (README.md only)"
echo "  ├── dynatrace/ (install, health checks, entity mapping)"
echo "  ├── newrelic/ (install, health checks, auth)"
echo "  ├── datadog/ (install, health checks)"
echo "  ├── common/ (validate_metrics.sh)"
echo "  └── config/ (servicemonitors, prometheus values)"
echo ""
echo -e "${GREEN}All monitoring platforms now use consistent structure!${NC}"
