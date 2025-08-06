#!/bin/bash
# Comprehensive EKS Cluster Deletion Script
# This script combines the best approaches from multiple cleanup scripts to ensure complete EKS cluster deletion
# It handles:
# - Nodegroup cleanup (ASG scaling, instance termination)
# - Security group and network interface cleanup
# - Load balancer deletion (ELBs, ALBs/NLBs)
# - CloudFormation stack deletion
# - Multiple attempts at cluster deletion via different methods

set -e

# Default region
export AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-2}
export AWS_REGION=${AWS_REGION:-us-east-2}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -n|--name|--cluster-name)
      CLUSTER_NAME="$2"
      shift
      shift
      ;;
    -r|--region)
      AWS_REGION="$2"
      AWS_DEFAULT_REGION="$2"
      shift
      shift
      ;;
    -f|--force)
      FORCE_DELETE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  -n, --name, --cluster-name CLUSTER_NAME   Name of the EKS cluster to delete"
      echo "  -r, --region REGION                       AWS region (default: us-east-2)"
      echo "  -f, --force                               Skip confirmation prompt"
      echo "  -h, --help                                Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Check if cluster name is provided via command line or environment variable
if [ -z "${CLUSTER_NAME}" ]; then
  # If not provided as argument, check environment variable
  if [ -z "${CLUSTER_NAME}" ]; then
    echo "Error: Cluster name not provided"
    echo "Please specify using -n/--name option or set CLUSTER_NAME environment variable"
    exit 1
  fi
fi

# Validate AWS Account (optional, uncomment if needed)
# if [ $(aws sts get-caller-identity | jq -r .Account) -ne 856940208208 ]; then
#   echo "This script is intended to be run in the Gremlin Sales Demo AWS account."
#   echo "The current AWS credentials are not for this account. Please check your AWS CLI configuration."
#   exit 1
# fi

# Confirmation prompt unless force flag is set
if [ "$FORCE_DELETE" != "true" ]; then
  echo "WARNING: This will delete the EKS cluster '${CLUSTER_NAME}' in region '${AWS_REGION}'."
  echo "All associated resources will be permanently deleted."
  read -p "Are you sure you want to proceed? (y/N): " confirm
  if [[ "$confirm" != [yY] && "$confirm" != [yY][eE][sS] ]]; then
    echo "Operation cancelled."
    exit 0
  fi
fi

echo "=== Starting comprehensive deletion for cluster ${CLUSTER_NAME} in region ${AWS_REGION} ==="

# Function to check if cluster exists
cluster_exists() {
  aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null
  return $?
}

# Function to check if a CloudFormation stack exists
stack_exists() {
  local stack_name=$1
  aws cloudformation describe-stacks --stack-name ${stack_name} --region ${AWS_REGION} &>/dev/null
  return $?
}

# First run clean_cluster.sh if it exists in the same directory
CLEAN_CLUSTER_SCRIPT="$(dirname "$0")/clean_cluster.sh"
if [ -f "$CLEAN_CLUSTER_SCRIPT" ]; then
  echo "Running clean_cluster.sh to clean up cluster resources..."
  $CLEAN_CLUSTER_SCRIPT
fi

# Initial attempt to delete the cluster using eksctl
if cluster_exists; then
  echo "Attempting to delete cluster using eksctl..."
  eksctl delete cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --disable-nodegroup-eviction --force || echo "Standard eksctl deletion failed, proceeding with manual cleanup..."
fi

# Check if cluster still exists after initial deletion attempt
if cluster_exists; then
  echo "Standard cluster deletion failed. Proceeding with aggressive cleanup..."
  
  # Step 1: Find all nodegroups for the cluster
  echo "Finding nodegroups for cluster ${CLUSTER_NAME}..."
  NODEGROUPS=$(aws eks list-nodegroups --cluster-name ${CLUSTER_NAME} --query "nodegroups[*]" --output text 2>/dev/null || echo "")
  
  if [ -n "$NODEGROUPS" ]; then
    echo "Found nodegroups: $NODEGROUPS"
    
    # Step 2: For each nodegroup, handle cleanup
    for NG in $NODEGROUPS; do
      echo "=== Processing nodegroup $NG ==="
      
      # Step 2.1: Find problematic security groups
      echo "Finding security groups for nodegroup $NG..."
      SG_ID=$(aws eks describe-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name $NG --query "nodegroup.health.issues[?code=='Ec2SecurityGroupDeletionFailure'].resourceIds[0]" --output text 2>/dev/null || echo "")
      
      if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
        echo "No problematic security group found, trying alternative method..."
        SG_ID=$(aws eks describe-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name $NG --query "nodegroup.remoteAccess.sourceSecurityGroups[0]" --output text 2>/dev/null || echo "")
      fi
      
      # Step 2.2: Get the ASG for the nodegroup
      echo "Finding Auto Scaling Group for nodegroup $NG..."
      ASG_NAME=$(aws eks describe-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name $NG --query "nodegroup.resources.autoScalingGroups[0].name" --output text 2>/dev/null || echo "")
      
      if [ -n "$ASG_NAME" ] && [ "$ASG_NAME" != "None" ]; then
        echo "Found Auto Scaling Group: $ASG_NAME"
        
        # Set ASG capacity to 0
        echo "Setting ASG capacity to 0..."
        aws autoscaling update-auto-scaling-group --auto-scaling-group-name $ASG_NAME --min-size 0 --max-size 0 --desired-capacity 0 || echo "Failed to update ASG"
        
        # Get instances in ASG and terminate them
        echo "Finding instances in ASG..."
        INSTANCES=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --query "AutoScalingGroups[0].Instances[*].InstanceId" --output text)
        
        if [ -n "$INSTANCES" ]; then
          echo "Found instances: $INSTANCES"
          for INSTANCE in $INSTANCES; do
            echo "Terminating instance $INSTANCE..."
            aws ec2 terminate-instances --instance-ids $INSTANCE || echo "Failed to terminate instance $INSTANCE"
          done
          
          # Wait for instances to terminate
          echo "Waiting for instances to terminate..."
          aws ec2 wait instance-terminated --instance-ids $INSTANCES || echo "Failed to wait for instances to terminate"
        fi
        
        # Try to delete the ASG
        echo "Attempting to delete Auto Scaling Group $ASG_NAME..."
        aws autoscaling delete-auto-scaling-group --auto-scaling-group-name $ASG_NAME --force-delete || echo "Failed to delete ASG"
      fi
      
      # Step 2.3: Handle security group cleanup if found
      if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
        echo "Found security group: $SG_ID"
        
        # Find network interfaces using the security group
        echo "Finding network interfaces associated with security group $SG_ID..."
        NETWORK_INTERFACES=$(aws ec2 describe-network-interfaces --filters "Name=group-id,Values=$SG_ID" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
        
        if [ -n "$NETWORK_INTERFACES" ]; then
          echo "Found network interfaces: $NETWORK_INTERFACES"
          for NI in $NETWORK_INTERFACES; do
            echo "Processing network interface $NI..."
            ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --network-interface-ids $NI --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text 2>/dev/null || echo "")
            
            if [ -n "$ATTACHMENT_ID" ] && [ "$ATTACHMENT_ID" != "None" ]; then
              echo "Detaching network interface attachment $ATTACHMENT_ID..."
              aws ec2 detach-network-interface --attachment-id $ATTACHMENT_ID --force || echo "Failed to detach network interface"
              
              # Wait for detachment
              echo "Waiting for detachment to complete..."
              sleep 10
            fi
            
            echo "Deleting network interface $NI..."
            aws ec2 delete-network-interface --network-interface-id $NI || echo "Failed to delete network interface"
          done
        fi
        
        # Try to delete the security group
        echo "Attempting to delete security group $SG_ID..."
        aws ec2 delete-security-group --group-id $SG_ID || echo "Failed to delete security group"
      fi
      
      # Step 2.4: Try to delete the nodegroup via CloudFormation
      echo "Attempting to delete nodegroup $NG via CloudFormation..."
      NODEGROUP_STACK="eksctl-${CLUSTER_NAME}-nodegroup-${NG}"
      if stack_exists "$NODEGROUP_STACK"; then
        aws cloudformation delete-stack --stack-name $NODEGROUP_STACK || echo "Failed to delete nodegroup stack"
      else
        echo "Nodegroup stack $NODEGROUP_STACK not found or already deleted"
      fi
      
      # Step 2.5: Try to delete the nodegroup via EKS API
      echo "Attempting to delete nodegroup $NG via EKS API..."
      aws eks delete-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name $NG || echo "Failed to delete nodegroup via EKS API"
    done
  fi
  
  # Step 3: Find and delete load balancers associated with the cluster
  echo "=== Finding and deleting load balancers associated with the cluster ==="
  
  # Classic ELBs
  ELBS=$(aws elb describe-load-balancers --query "LoadBalancerDescriptions[?contains(LoadBalancerName, '${CLUSTER_NAME}')].LoadBalancerName" --output text)
  if [ -n "$ELBS" ]; then
    echo "Found classic ELBs: $ELBS"
    for ELB in $ELBS; do
      echo "Deleting classic ELB $ELB..."
      aws elb delete-load-balancer --load-balancer-name $ELB || echo "Failed to delete ELB $ELB"
    done
  fi
  
  # ALBs/NLBs
  LBARNS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, '${CLUSTER_NAME}')].LoadBalancerArn" --output text)
  if [ -n "$LBARNS" ]; then
    echo "Found ALBs/NLBs: $LBARNS"
    for LB in $LBARNS; do
      echo "Deleting ALB/NLB $LB..."
      aws elbv2 delete-load-balancer --load-balancer-arn $LB || echo "Failed to delete ALB/NLB"
    done
  fi
  
  # Step 4: Find and delete cluster security group
  echo "=== Finding and deleting cluster security groups ==="
  CLUSTER_SG_ID=$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text 2>/dev/null || echo "")
  
  if [ -n "$CLUSTER_SG_ID" ] && [ "$CLUSTER_SG_ID" != "None" ]; then
    echo "Found cluster security group: $CLUSTER_SG_ID"
    
    # Find network interfaces using the security group
    echo "Finding network interfaces associated with cluster security group $CLUSTER_SG_ID..."
    NETWORK_INTERFACES=$(aws ec2 describe-network-interfaces --filters "Name=group-id,Values=$CLUSTER_SG_ID" --query "NetworkInterfaces[*].NetworkInterfaceId" --output text)
    
    if [ -n "$NETWORK_INTERFACES" ]; then
      echo "Found network interfaces: $NETWORK_INTERFACES"
      for NI in $NETWORK_INTERFACES; do
        echo "Processing network interface $NI..."
        ATTACHMENT_ID=$(aws ec2 describe-network-interfaces --network-interface-ids $NI --query "NetworkInterfaces[0].Attachment.AttachmentId" --output text 2>/dev/null || echo "")
        
        if [ -n "$ATTACHMENT_ID" ] && [ "$ATTACHMENT_ID" != "None" ]; then
          echo "Detaching network interface attachment $ATTACHMENT_ID..."
          aws ec2 detach-network-interface --attachment-id $ATTACHMENT_ID --force || echo "Failed to detach network interface"
          
          # Wait for detachment
          echo "Waiting for detachment to complete..."
          sleep 10
        fi
        
        echo "Deleting network interface $NI..."
        aws ec2 delete-network-interface --network-interface-id $NI || echo "Failed to delete network interface"
      done
    fi
    
    # Try to delete the security group
    echo "Attempting to delete cluster security group $CLUSTER_SG_ID..."
    aws ec2 delete-security-group --group-id $CLUSTER_SG_ID || echo "Failed to delete cluster security group"
  fi
  
  # Step 5: Try to delete the cluster again
  echo "=== Attempting to delete cluster again ==="
  aws eks delete-cluster --name ${CLUSTER_NAME} || echo "Failed to delete cluster via EKS API"
  
  # Step 6: Find and delete CloudFormation stacks
  echo "=== Finding CloudFormation stacks for cluster ${CLUSTER_NAME} ==="
  CF_STACKS=$(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE DELETE_FAILED --query "StackSummaries[?contains(StackName, '${CLUSTER_NAME}')].StackName" --output text)
  
  if [ -n "$CF_STACKS" ]; then
    echo "Found CloudFormation stacks: $CF_STACKS"
    for STACK in $CF_STACKS; do
      echo "Deleting CloudFormation stack $STACK..."
      aws cloudformation delete-stack --stack-name $STACK
      echo "Initiated deletion of stack $STACK. This may take several minutes."
    done
    
    echo "CloudFormation stack deletions initiated. Check AWS console to confirm complete removal."
  else
    echo "No CloudFormation stacks found for cluster ${CLUSTER_NAME}"
  fi
fi

# Final check if cluster still exists
if cluster_exists; then
  echo "WARNING: Cluster ${CLUSTER_NAME} still exists after cleanup attempts."
  echo "You may need to manually delete resources from the AWS console."
else
  echo "SUCCESS: Cluster ${CLUSTER_NAME} has been deleted."
fi

echo "=== Cluster deletion process completed ==="
echo "Check the AWS console to verify all resources have been cleaned up."
