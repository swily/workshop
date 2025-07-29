#!/bin/bash -e

export AWS_DEFAULT_REGION=us-east-2
export AWS_REGION=us-east-2
export CLUSTER_NAME=seanwiley-otel

echo "Fixing security group configuration for cluster: ${CLUSTER_NAME}"

# Get cluster security group ID
CLUSTER_SG=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)
echo "Cluster security group: ${CLUSTER_SG}"

# Get node security group ID
NODE_SG="sg-0a499ed85cbdf45c5"
echo "Node security group: ${NODE_SG}"

# Add rule to allow all traffic from node security group to cluster security group
echo "Adding rule to allow all traffic from node security group to cluster security group..."
aws ec2 authorize-security-group-ingress \
  --group-id ${CLUSTER_SG} \
  --protocol all \
  --source-group ${NODE_SG} \
  --region ${AWS_REGION} || echo "Rule already exists or couldn't be added"

# Add rule to allow all traffic from cluster security group to node security group
echo "Adding rule to allow all traffic from cluster security group to node security group..."
aws ec2 authorize-security-group-ingress \
  --group-id ${NODE_SG} \
  --protocol all \
  --source-group ${CLUSTER_SG} \
  --region ${AWS_REGION} || echo "Rule already exists or couldn't be added"

# Wait for node groups to be deleted
echo "Waiting for existing node groups to be deleted..."
while true; do
  NODE_GROUPS=$(aws eks list-nodegroups --cluster-name ${CLUSTER_NAME} --query "nodegroups" --output text)
  if [ -z "${NODE_GROUPS}" ]; then
    echo "All node groups have been deleted"
    break
  fi
  
  echo "Node groups still exist: ${NODE_GROUPS}"
  echo "Waiting 30 seconds..."
  sleep 30
done

# Force delete the VPC CNI addon if it's in a failed state
echo "Checking VPC CNI addon status..."
VPC_CNI_STATUS=$(aws eks describe-addon --cluster-name ${CLUSTER_NAME} --addon-name vpc-cni --query "addon.status" --output text 2>/dev/null || echo "NOT_FOUND")

if [ "${VPC_CNI_STATUS}" != "NOT_FOUND" ]; then
  echo "VPC CNI addon status: ${VPC_CNI_STATUS}"
  echo "Force deleting VPC CNI addon..."
  aws eks delete-addon --cluster-name ${CLUSTER_NAME} --addon-name vpc-cni --preserve --region ${AWS_REGION} || echo "Failed to delete VPC CNI addon"
fi

# Create a new node group with the correct security group configuration
echo "Creating new node group with correct security group configuration..."
NG_CONFIG="/tmp/ng-config-$(date +%s).yaml"

cat > ${NG_CONFIG} <<EOL
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
      us-east-2a: { id: subnet-0403fbdc0a75620d6 }
      us-east-2b: { id: subnet-0dcb40d6b8fad2c03 }
      us-east-2c: { id: subnet-0d36418b808d97976 }
    public:
      us-east-2a: { id: subnet-08038efe886c31791 }
      us-east-2b: { id: subnet-0135b61262e48f4d6 }
      us-east-2c: { id: subnet-0fe7be30ec2528c4c }

managedNodeGroups:
  - name: ${CLUSTER_NAME}-ng-fixed
    minSize: 2
    maxSize: 4
    desiredCapacity: 2
    instanceType: t3.medium
    volumeSize: 20
    amiFamily: AmazonLinux2023
    tags:
      Environment: Demo
      Owner: $(whoami)
    iam:
      instanceRoleARN: arn:aws:iam::856940208208:role/DemosVPC-EksNodeInstanceRole
    securityGroups:
      attachIDs:
        - ${NODE_SG}
EOL

echo "Node group config:"
cat ${NG_CONFIG}

eksctl create nodegroup -f ${NG_CONFIG}

# Wait for node group to be active
echo "Waiting for node group to be active..."
aws eks wait nodegroup-active \
  --cluster-name ${CLUSTER_NAME} \
  --nodegroup-name ${CLUSTER_NAME}-ng-fixed \
  --region ${AWS_REGION}

# Install VPC CNI addon manually
echo "Installing VPC CNI addon manually..."
kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/v1.19.0/config/master/aws-k8s-cni.yaml

echo "Waiting for nodes to become ready..."
kubectl wait --for=condition=ready nodes --all --timeout=5m

echo "Cluster fix completed!"
rm -f ${NG_CONFIG}
