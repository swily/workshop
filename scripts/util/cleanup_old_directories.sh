#!/bin/bash
#
# cleanup_old_directories.sh
#
# This script removes old directories that have been migrated to new locations
# as part of the repository reorganization.

# Set text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Repository Cleanup Script ===${NC}"
echo -e "This script will remove old directories that have been migrated to new locations."
echo -e "${RED}WARNING: This operation cannot be undone. Make sure you have verified the new directories.${NC}"
read -p "Do you want to continue? (y/n): " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo -e "${YELLOW}Cleanup aborted.${NC}"
  exit 0
fi

# Directories to remove
echo -e "\n${YELLOW}Removing old directories...${NC}"

# Remove /config/monitoring (migrated to /monitoring/config)
if [ -d "/Users/seanwiley/workshop/config/monitoring" ]; then
  echo -e "Removing /config/monitoring..."
  rm -rf /Users/seanwiley/workshop/config/monitoring
  echo -e "${GREEN}✓ Removed /config/monitoring${NC}"
else
  echo -e "${YELLOW}✓ /config/monitoring already removed${NC}"
fi

# Remove /config/otel (migrated to /monitoring/otel-integration)
if [ -d "/Users/seanwiley/workshop/config/otel" ]; then
  echo -e "Removing /config/otel..."
  rm -rf /Users/seanwiley/workshop/config/otel
  echo -e "${GREEN}✓ Removed /config/otel${NC}"
else
  echo -e "${YELLOW}✓ /config/otel already removed${NC}"
fi

# Remove /config/patches (migrated to /patches)
if [ -d "/Users/seanwiley/workshop/config/patches" ]; then
  echo -e "Removing /config/patches..."
  rm -rf /Users/seanwiley/workshop/config/patches
  echo -e "${GREEN}✓ Removed /config/patches${NC}"
else
  echo -e "${YELLOW}✓ /config/patches already removed${NC}"
fi

# Remove /config/services (migrated to /services)
if [ -d "/Users/seanwiley/workshop/config/services" ]; then
  echo -e "Removing /config/services..."
  rm -rf /Users/seanwiley/workshop/config/services
  echo -e "${GREEN}✓ Removed /config/services${NC}"
else
  echo -e "${YELLOW}✓ /config/services already removed${NC}"
fi

# Remove /config/templates (migrated to appropriate directories)
if [ -d "/Users/seanwiley/workshop/config/templates" ]; then
  echo -e "Removing /config/templates..."
  rm -rf /Users/seanwiley/workshop/config/templates
  echo -e "${GREEN}✓ Removed /config/templates${NC}"
else
  echo -e "${YELLOW}✓ /config/templates already removed${NC}"
fi

# Remove old build_scripts files (migrated to subdirectories)
echo -e "\n${YELLOW}Removing old build_scripts files...${NC}"
old_scripts=(
  "/Users/seanwiley/workshop/build_scripts/configure_cluster_base.sh"
  "/Users/seanwiley/workshop/build_scripts/create_new_cluster.sh"
  "/Users/seanwiley/workshop/build_scripts/fix_configure_otel_demo.sh"
  "/Users/seanwiley/workshop/build_scripts/install_gremlin.sh"
  "/Users/seanwiley/workshop/build_scripts/install_load_balancer.sh"
)

for script in "${old_scripts[@]}"; do
  if [ -f "$script" ]; then
    echo -e "Removing $script..."
    rm -f "$script"
    echo -e "${GREEN}✓ Removed $script${NC}"
  else
    echo -e "${YELLOW}✓ $script already removed${NC}"
  fi
done

echo -e "\n${GREEN}=== Cleanup completed successfully! ===${NC}"
echo -e "${YELLOW}The repository has been reorganized with a cleaner structure.${NC}"
echo -e "Please update any scripts or documentation that may reference the old paths."
