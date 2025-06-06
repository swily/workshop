# Workshop Enhanced

## Script Directory Requirements

All scripts in this repository are designed to be run from the root directory. The main entry point is `build_one.sh`, which orchestrates the cluster creation and configuration process.

Directory structure:
```
/
├── build_one.sh              # Main entry point
├── build_cluster.sh         # Called by build_one.sh
├── configure_cluster_base.sh
├── configure_otel_demo.sh
├── clean_cluster.sh         # Cleans cluster resources
├── delete_cluster.sh        # Deletes the entire cluster
├── refresh_dns_record.sh
├── dashboards/             # Grafana dashboards
│   ├── latency.json
│   └── memory.json
├── templates/              # Kubernetes and configuration templates
│   ├── eksctl-custom.yaml
│   └── otelcol-config-gremlin-enhanced.yaml
└── yaml/                   # Kubernetes service manifests
    ├── frontend-service.yaml
    └── monitoring-grafana-lb.yaml
```

## Prerequisites

Before starting, ensure you have the following installed and configured:

1. AWS CLI installed and configured with your credentials (`aws configure`)
2. `eksctl` installed
3. `kubectl` installed
4. A Gremlin account with Team ID and Team Secret

## Setup

1. Clone this repository and navigate to the workshop directory:
   ```bash
   cd workshop_enhanced/Bootcamps
   ```

2. Set required environment variables:
   ```bash
   # Set your desired EKS cluster name
   export CLUSTER_NAME=your-cluster-name
   
   # Set your Gremlin credentials
   export GREMLIN_TEAM_ID=your-team-id
   export GREMLIN_TEAM_SECRET=your-team-secret
   ```

3. Run the build script to create the EKS cluster and deploy all components:
   ```bash
   ./build_one.sh
   ```

## Accessing Dashboards

1. Start port forwarding for Grafana:
   ```bash
   kubectl port-forward svc/prometheus-operator-grafana 3000:80 -n monitoring &
   ```
   Access Grafana at: http://localhost:3000
   - Username: `admin`
   - Password: `prom-operator`

2. Start port forwarding for Prometheus (optional, for direct metric queries):
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-operator-kube-p-prometheus 9090:9090 &
   ```
   Access Prometheus at: http://localhost:9090

## Recommended Dashboards

Once in Grafana, the following dashboards are useful for monitoring during chaos experiments:

1. **Kubernetes / Compute Resources / Namespace**
   - Shows CPU and memory usage across your namespaces
   - Useful for monitoring overall resource consumption

2. **Kubernetes / Networking / Namespace**
   - Network traffic patterns and potential issues
   - Shows network latency and error rates
