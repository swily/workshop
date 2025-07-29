#!/bin/bash -e

export AWS_DEFAULT_REGION=us-east-2
export AWS_REGION=us-east-2
export CLUSTER_NAME=current-workshop
export OWNER=$(whoami)
export EXPIRATION=$(date -v +7d +%Y-%m-%d)

# Create a temporary cluster config file
CLUSTER_CONFIG="/tmp/cluster-config-$(date +%s).yaml"

cat > $CLUSTER_CONFIG <<EOL
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: us-east-2
  version: "1.31"
  tags:
    owner: ${OWNER}
    expiration: ${EXPIRATION}

managedNodeGroups:
  - name: ${CLUSTER_NAME}-ng
    minSize: 5
    maxSize: 8
    desiredCapacity: 5
    volumeSize: 20
    instanceTypes:
      - t3.medium
      - t3a.medium
      - t2.medium
    spot: true
    iam:
      instanceRoleARN: arn:aws:iam::856940208208:role/DemosVPC-EksNodeInstanceRole
    securityGroups:
      attachIDs:
        - sg-0a499ed85cbdf45c5
    # Only use public subnets for node group like the working cluster
    subnets:
      - subnet-0fe7be30ec2528c4c
      - subnet-08038efe886c31791
      - subnet-0135b61262e48f4d6
    amiFamily: AmazonLinux2023

vpc:
  id: vpc-0ae237bb717910ccc
  subnets:
    private:
      us-east-2a:
        id: subnet-0403fbdc0a75620d6
      us-east-2b:
        id: subnet-0dcb40d6b8fad2c03
      us-east-2c:
        id: subnet-0d36418b808d97976
    public:
      us-east-2a:
        id: subnet-08038efe886c31791
      us-east-2b:
        id: subnet-0135b61262e48f4d6
      us-east-2c:
        id: subnet-0fe7be30ec2528c4c

iam:
  serviceRoleARN: arn:aws:iam::856940208208:role/DemosVPC-EksServiceRole
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: digitalocean-dns
        namespace: default
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess
    # Add VPC CNI service account with necessary permissions like the working cluster
    - metadata:
        name: aws-node
        namespace: kube-system
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

# Create user accounts in new EKS cluster
iamIdentityMappings:
  - arn: arn:aws:iam::856940208208:user/sam.whyte
    username: sam.whyte
    groups:
      - system:masters
  - arn: arn:aws:iam::856940208208:user/jessykah.bird
    username: jessykah.bird
    groups:
      - system:masters
  - arn: arn:aws:iam::856940208208:user/don
    username: don.darwin
    groups:
      - system:masters
  - arn: arn:aws:iam::856940208208:user/dan.muret@gremlin.com
    username: dan.muret
    groups:
      - system:masters
  - arn: arn:aws:iam::856940208208:user/jason.heller
    username: jason.heller
    groups:
      - system:masters
EOL

echo "Creating cluster with config:"
cat $CLUSTER_CONFIG

eksctl create cluster -f $CLUSTER_CONFIG

# Wait for cluster to be active
echo "Waiting for cluster to be active..."
aws eks wait cluster-active --name ${CLUSTER_NAME} --region ${AWS_REGION}

echo "Cluster creation complete!"
rm -f $CLUSTER_CONFIG

# Update kubeconfig to point to the new cluster
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}

echo "Kubeconfig updated to point to the new cluster: ${CLUSTER_NAME}"

# Get the cluster security group ID
echo "Getting cluster security group ID..."
CLUSTER_SG_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)
echo "Cluster security group ID: ${CLUSTER_SG_ID}"

# Get the node security group ID
NODE_SG_ID="sg-0a499ed85cbdf45c5"
echo "Node security group ID: ${NODE_SG_ID}"

# Ensure proper security group rules exist for bidirectional communication
echo "Adding security group ingress rules for bidirectional communication..."

# Allow cluster security group to communicate with node security group
aws ec2 authorize-security-group-ingress \
  --group-id ${NODE_SG_ID} \
  --protocol all \
  --port 0-65535 \
  --source-group ${CLUSTER_SG_ID} \
  --region ${AWS_REGION} || echo "Rule already exists or couldn't be added"

# Allow node security group to communicate with cluster security group
aws ec2 authorize-security-group-ingress \
  --group-id ${CLUSTER_SG_ID} \
  --protocol all \
  --port 0-65535 \
  --source-group ${NODE_SG_ID} \
  --region ${AWS_REGION} || echo "Rule already exists or couldn't be added"

echo "Security group rules added."
echo "You can now use kubectl to interact with your new cluster"
