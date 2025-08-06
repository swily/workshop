# Workshop

## Repository Structure

This repository has been reorganized with a unified monitoring framework:

### build_scripts/
Contains the main scripts for creating and configuring an EKS cluster with OpenTelemetry Demo:
- `cluster/create.sh` - Creates a new EKS cluster with proper VPC CNI and security group configuration
- `cluster/base_setup.sh` - Configures the base components of the cluster and calls the unified monitoring setup
- `demo/otel_demo.sh` - Configures the OpenTelemetry Demo application
- `gremlin/install.sh` - Interactive Gremlin installation with prompts for teamID, clusterID, and service tagging
- `load-balancer/install.sh` - Installs and configures load balancers for services

### monitoring/
Contains the unified monitoring framework scripts:
- `setup_monitoring.sh` - Master monitoring setup script that orchestrates the installation of monitoring tools
- `prometheus/install/install.sh` - Installs kube-prometheus-stack as the baseline monitoring
- `dynatrace/install/install.sh` - Installs and configures Dynatrace monitoring
- `newrelic/install/install.sh` - Installs and configures New Relic monitoring
- `datadog/install/install.sh` - Installs and configures DataDog monitoring

### helper_scripts/
Contains utility scripts that support the main build scripts:
- `configure_otel_demo_observability.sh` - Configures OpenTelemetry Demo with observability tools
- `cleanup/` - Scripts for cleaning up cluster resources
- `templates/` - YAML templates for configurations

### dynatrace_exports/
Contains scripts for Dynatrace entity mapping and exports:
- `generate_entity_mapping.sh` - Creates entity mapping between service names and Dynatrace entity IDs

## Usage

### Creating and Configuring a Cluster

```bash
# Step 1: Create a new EKS cluster
cd build_scripts/cluster
./create.sh -n my-cluster-name

# Step 2: Configure the base components and monitoring
./base_setup.sh -n my-cluster-name
# This will automatically install baseline monitoring via the unified monitoring framework

# Step 3: Install and configure OpenTelemetry Demo
# This will use the already installed monitoring and add OpenTelemetry-specific configurations
../../helper_scripts/configure_otel_demo_observability.sh
```

**Note:** The workflow above uses the unified monitoring framework automatically. The base cluster configuration script calls the master monitoring setup script to install Prometheus/Grafana, and the OpenTelemetry demo configuration script adds OpenTelemetry-specific configurations on top of that.

### Unified Monitoring Framework

The new monitoring framework provides a standardized way to install and configure monitoring tools:

```bash
# Install baseline monitoring (Prometheus/Grafana)
cd monitoring
./setup_monitoring.sh -t prometheus

# Install Dynatrace monitoring
./setup_monitoring.sh -t dynatrace

# Install New Relic monitoring
./setup_monitoring.sh -t newrelic

# Install DataDog monitoring
./setup_monitoring.sh -t datadog
```

### Gremlin Installation

The Gremlin installation script now supports interactive prompts:

```bash
cd build_scripts/gremlin
./install.sh
```

Options:
- `--team-id` - Specify Gremlin Team ID
- `--team-secret` - Specify Gremlin Team Secret
- `--cluster-id` - Specify custom Gremlin Cluster ID
- `--tag-namespaces` - Comma-separated list of namespaces to tag for Gremlin

## Prerequisites

Before starting, ensure you have the following installed and configured:

1. AWS CLI installed and configured with your credentials (`aws configure`)
2. `eksctl` installed
3. `kubectl` installed
4. Helm v3 installed
5. A Gremlin account with Team ID and Team Secret (optional)
6. Dynatrace, New Relic, or DataDog account (optional)

## Monitoring

### Prometheus and Grafana

The baseline monitoring includes Prometheus and Grafana installed via the kube-prometheus-stack Helm chart in the monitoring namespace.

### Observability Tools Integration

The framework supports integration with:
- Dynatrace
- New Relic
- DataDog
- Gremlin (for chaos engineering)

### Access

Grafana is accessible via port-forwarding:

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

Default credentials:
- Username: admin
- Password: prom-operator