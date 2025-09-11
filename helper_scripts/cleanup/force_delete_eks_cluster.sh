#!/bin/bash -e

# Enhanced Comprehensive EKS Cluster Force Deletion Script
# This script handles stuck clusters, nodegroups, and associated AWS resources

export AWS_DEFAULT_REGION=${AWS_REGION:-us-east-2}
export AWS_REGION=${AWS_REGION:-us-east-2}

# Support both environment variable and command line argument
if [ -n "$1" ]; then
  CLUSTER_NAME="$1"
elif [ -z "${CLUSTER_NAME}" ]; then
  echo "Usage: $0 <cluster-name>"
  echo "Or set CLUSTER_NAME environment variable"
  exit 1
fi

# Account validation removed for cross-account compatibility
# Script now works with any AWS account

echo "🚨 FORCE DELETING EKS CLUSTER: ${CLUSTER_NAME} in region ${AWS_REGION}"
echo "This will aggressively remove all cluster resources including stuck nodegroups."
echo "Press Ctrl+C within 10 seconds to cancel..."
sleep 10

echo "Cleaning cluster resources for ${CLUSTER_NAME}..."
# Using clean_cluster.sh from the same directory
$(dirname "$0")/clean_cluster.sh

echo "Deleting cluster ${CLUSTER_NAME}..."
eksctl delete cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --disable-nodegroup-eviction --force

# Check if cluster deletion failed
if aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
  echo "Standard cluster deletion failed. Attempting aggressive cleanup..."
  
  # Step 1: Find all nodegroups for the cluster
  echo "Finding nodegroups for cluster ${CLUSTER_NAME}..."
  NODEGROUPS=$(aws eks list-nodegroups --cluster-name ${CLUSTER_NAME} --query "nodegroups[*]" --output text 2>/dev/null || echo "")
  
  if [ -n "$NODEGROUPS" ]; then
    echo "Found nodegroups: $NODEGROUPS"
    
    # Step 2: For each nodegroup, handle cleanup
    for NG in $NODEGROUPS; do
      echo "Processing nodegroup $NG..."
      
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
      aws cloudformation delete-stack --stack-name $NODEGROUP_STACK || echo "Failed to delete nodegroup stack"
      
      # Step 2.5: Try to delete the nodegroup via EKS API
      echo "Attempting to delete nodegroup $NG via EKS API..."
      aws eks delete-nodegroup --cluster-name ${CLUSTER_NAME} --nodegroup-name $NG || echo "Failed to delete nodegroup via EKS API"
    done
  fi
  
  # Step 3: Find and delete load balancers associated with the cluster
  echo "Finding and deleting load balancers associated with the cluster..."
  
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
  
  # Step 4: Try to delete the cluster again
  echo "Attempting to delete cluster again..."
  aws eks delete-cluster --name ${CLUSTER_NAME} || echo "Failed to delete cluster via EKS API"
  
  # Step 5: Find and delete CloudFormation stacks
  echo "Finding CloudFormation stacks for cluster ${CLUSTER_NAME}..."
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

echo "Cluster deletion process completed. Check the AWS console to verify all resources have been cleaned up."
