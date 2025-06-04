# Gremlin Opentelemetry Demo application
This repository contains the configurations and instructions for installing a version of the Opentelemetry Demo that includes Service Definitions for Gremlin. 

The standard deployment creates:
- an EKS cluster in us-east-2 using eksctl
- Deploys the otel-demo environment
- Deploys gremlin agent
- Annotates the otel-demo services to be added as gremlin RM services.
- Ensures that 2 pods are running for each deployment.
- Deploys Dynatrace OneAgent for observability.

## Usage
```
# Deploy a single gremlin bootcamp environment.
bash ./build_many.sh 5

# Deploy multiple gremlin bootcamp environments.
bash ./build_many.sh 5 6 7 8
```
The parameters passed to this script specify which teams should be deployed.
First example: Group 05
Second example: Group 05, Group 06, Group 07, Group 08

## Delete all bootcamp clusters
```
bash ./delete_all_bootcamps.sh
```
Deletes all eksctl environments and deletes all Gremlin services from the teams.

## Deploy a single environment
```
bash ./deploy_single.sh -n otel-demo-custom -c otel-demo-single -o $(whoami) -e $(date -v +7d +%Y-%m-%d) -g Group 01
```

Example:
./deploy_single.sh -c basecampcluster -n Base_Camp -g "Gremlin Workshop Base Camp"

After deploying, run the port forward to access the frontend:
```
kubectl port-forward svc/otel-demo-frontendproxy -n otel-demo 8080:8080
```

Then navigate to http://localhost:8080

or http://localhost:8080/grafana to access the Grafana dashboard

There are Grafana dashboards stored in dashboards/ you can import them into grafana via the API or via the UI choose New Dashboard > Import > and paste the contents of the json file.















# Deprecated info!!!
## Create a Kubernetes secret with API Keys for your OTEL-enabled Observability tool
This is an optional step. It is currently setup to connect to Grafana (OOTB), Datadog, and New Relic. If the keys are not added or incorrect the Opentelemetry Collector service will not be able to connect to the endpoint.

Export the environment variables for your Observability Collectors,

```
export DD_SITE_PARAMETER="<add-your-datadog-otlp-endpoint>"
export DD_API_KEY="<add-your-datadog-api-key>"
export NR_API_ENDPOINT="<add-your-new-relic-api-endpoint>"
export NR_API_KEY="<add-your-new-relic-api-key>"
export DT_OTLP_ENDPOINT="<your-dyntrace-api-endpoint>"
export DT_API_TOKEN="<your-dt-api-token>"
```

```
kubectl create secret generic otelcol-keys \
  --from-literal="DD_SITE_PARAMETER=$DD_SITE_PARAMETER" \
  --from-literal="DD_API_KEY=$DD_API_KEY" \
  --from-literal="NR_API_ENDPOINT=$NR_API_ENDPOINT" \
  --from-literal="NR_API_KEY=$NR_API_KEY" \
  --from-literal="DT_OTLP_ENDPOINT=$DT_OTLP_ENDPOINT" \
  --from-literal="DT_API_TOKEN=$DT_API_TOKEN"  
```

## Install the Gremlin Opentelemetry demo application

Generate a new gremlin-sales-demo.yaml using Helm,

```
helm template otel-demo open-telemetry/opentelemetry-demo --values otelcol-config-extras.yaml -n otel-demo > gremlin-sales-demo.yaml
```

Deploy the application and create a LoadBalancer to expose the app to the Web

```shell
kubectl apply -n otel-demo -f ./gremlin-sales-demo.yaml
```
## (Optional): Add a Gremlin service_id annotation to deployments to have them automatically added to the Gremlin Service Catalog

### Enable annotation to automatically add Otel Deployments to the Gremlin Service Catalog.
Edit the __add-deployments-annotation.sh__ script. Add the service names to be annotated to the service_list array. Specify a service name prefix to make your service names uniqe...a username is a good prefix. Run the script using the command, 

```
./add-deployment-annotations.sh gremlin-sales-demo.yaml <unique-service-name-prefix>
```
This will create or update the annotated-deployments.yaml file. Apply the annotations to your Gremlin Otel Demo deployment, 

```
kubectl apply -f annotated-deployments.yaml -n otel-demo
```

## Get the AWS loadbalancer address from your EKS cluster:

```shell
kubectl get service otel-demo-frontendproxy -n otel-demo
```

copy the EXTERNAL-IP address from the output, this is your service endpoint

```
NAME                               TYPE           CLUSTER-IP      EXTERNAL-IP                                                              PORT(S)          AGE
otel-demo-frontendproxy   LoadBalancer   172.20.156.38   axxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-521855005.us-east-2.elb.amazonaws.com   8080:30779/TCP   25m
```
## Open the application in a browser:
In your browser connect to the Opentelemetry Demo frontendproxy External IP on port 8080 (e.g. https://axxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-521855005.us-east-2.elb.amazonaws.com:8080)

## (Optional): Create a DNS entry in Route53 (e.g. ddarwin-otel-demo.gremlin.rocks) 
Create a Route53 entry of Record type: A, that routes traffic to "Alias to Application or Classic Load Balancer" that maps to the External IP for the otel-demo-frontendproxy.  

## (Optional): Scale your deployments to resolve the Availability Zone Redundancy Detected Risk 
Increase the number of POD replicas for the service deployments by running the script
```
./scale-deployments.sh
```

## Install the Gremlin Agent:
To install the Gremlin Agent in your EKS cluster follow the [Helm installation](https://www.gremlin.com/docs/getting-started-install-kubernetes-helm). 

**TBD** Create a Grafana Alert on response time for Frontend Service
 
**TBD** Create a Datadog monitor for Frontend Service response time

**TBD** Create a New Relic Monitor for Service Response Time

**TBD** Create a Dynatrace monitor for Problems Health Check

<!-- Add instructions for creating a new EKS Cluster -->

## (Optional): To update to the latest version of Opentelemetry Demo:
To update this demo to the latest release of the Opentelemetry demo with the OTEL Collectors and a Loadbalancer defined, 

Make sure you have the Opentelemetry Demo Helm chart installed and updated,

```
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
```
## Additional resources:

### OTEL architecture diagram:
https://opentelemetry.io/docs/demo/architecture/

### OTEL Original Deployment documentation:
https://opentelemetry.io/docs/demo/kubernetes-deployment/
