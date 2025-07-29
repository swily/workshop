#!/bin/bash -e

# Set default values if not already set
export AWS_DEFAULT_REGION=${AWS_REGION:-us-east-2}
export OWNER=${OWNER:-$(whoami)}
export CLUSTER_NAME=${CLUSTER_NAME:-seanwiley-otel}
export SSH_KEY_NAME=${SSH_KEY_NAME:-seanwiley-seanwiley-otel-key}

echo "Creating new node group for cluster: ${CLUSTER_NAME}"
echo "Using SSH key: ${SSH_KEY_NAME}"

# Create a temporary node group config file
NG_CONFIG="/tmp/ng-config-$(date +%s).yaml"

cat > $NG_CONFIG <<EOL
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "1.30"

vpc:
  id: vpc-0ae237bb717910ccc
  subnets:
    private:
      us-east-2a: { id: subnet-0403fbdc0a75620d6 }  # Private in us-east-2a
      us-east-2b: { id: subnet-0dcb40d6b8fad2c03 }  # Private in us-east-2b
      us-east-2c: { id: subnet-0d36418b808d97976 }  # Private in us-east-2c
    public:
      us-east-2a: { id: subnet-08038efe886c31791 }  # Public in us-east-2a
      us-east-2b: { id: subnet-0135b61262e48f4d6 }  # Public in us-east-2b
      us-east-2c: { id: subnet-0fe7be30ec2528c4c }  # Public in us-east-2c

managedNodeGroups:
  - name: ${CLUSTER_NAME}-ng-manual
    minSize: 2
    maxSize: 4
    desiredCapacity: 2
    instanceType: t3.medium
    volumeSize: 20
    amiFamily: AmazonLinux2023
    tags:
      Environment: Demo
      Owner: ${OWNER}
      k8s.io/cluster-autoscaler/enabled: "true"
      k8s.io/cluster-autoscaler/${CLUSTER_NAME}: owned
    iam:
      instanceRoleARN: arn:aws:iam::856940208208:role/DemosVPC-EksNodeInstanceRole
    securityGroups:
      attachIDs:
        - sg-0a499ed85cbdf45c5
    ssh:
      allow: true
      publicKeyName: ${SSH_KEY_NAME}
EOL

echo "Creating node group with config:"
cat $NG_CONFIG

eksctl create nodegroup -f $NG_CONFIG

# Wait for node group to be active
echo "Waiting for node group to be active..."
aws eks wait nodegroup-active \
  --cluster-name ${CLUSTER_NAME} \
  --nodegroup-name ${CLUSTER_NAME}-ng-manual \
  --region ${AWS_REGION}

echo "Node group creation complete!"
rm -f $NG_CONFIG
