#!/bin/bash

# Exit on any error
set -e

# --- Configuration ---
TEMPLATE_ID="lt-0b785b9218c0db172"
REGION="ap-east-1"
# IMPORTANT: Update this path to your key on the Gentoo machine
KEY_NAME="/mnt/d/Syncthing/mobile/vpn/stargate-aws-hk.pem"
PLAYBOOK="playbook.yml"
PROFILE="my-stargate-profile"
INSTANCE_NAME=""
INSTANCE_ID=""

# --- Function to show usage ---
usage() {
    echo "Usage: $0 -n <instance-name> [-i <instance-id>] [-p <aws-profile>]"
    echo "  -n  Name for the new EC2 instance (mandatory)."
    echo "  -i  ID of an existing EC2 instance to use/start."
    echo "  -p  AWS CLI profile to use (defaults to '$PROFILE')."
    exit 1
}

# --- Parse Command Line Arguments ---
while getopts ":n:i:p:" opt; do
  case ${opt} in
    n )
      INSTANCE_NAME=$OPTARG
      ;;
    i )
      INSTANCE_ID=$OPTARG
      ;;
    p )
      PROFILE=$OPTARG
      ;;
    \? )
      usage
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument"
      usage
      ;;
  esac
done

# Check if instance name is provided
if [ -z "$INSTANCE_NAME" ]; then
    echo "Error: Instance name is a mandatory argument."
    usage
fi

# --- 1. Provision or Start EC2 instance ---
if [ -n "$INSTANCE_ID" ]; then
    echo "Checking for existing instance with ID: $INSTANCE_ID"
    INSTANCE_DETAILS=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --profile "$PROFILE" --query "Reservations[].Instances[]" --output json)

    if [ -z "$INSTANCE_DETAILS" ] || [ "$INSTANCE_DETAILS" == "[]" ]; then
        echo "Error: No instance found with ID: $INSTANCE_ID. Exiting."
        exit 1
    fi

    INSTANCE_STATE=$(echo "$INSTANCE_DETAILS" | jq -r '.[0].State.Name')
    echo "Instance found. Current state: $INSTANCE_STATE"

    if [ "$INSTANCE_STATE" == "stopped" ]; then
        echo "Starting instance $INSTANCE_ID..."
        aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --profile "$PROFILE" > /dev/null
    fi

    echo "Waiting for instance to be in 'running' state..."
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION" --profile "$PROFILE"

else
    echo "Provisioning new EC2 instance from template $TEMPLATE_ID in region $REGION..."
    INSTANCE_JSON=$(aws ec2 run-instances --launch-template LaunchTemplateId=$TEMPLATE_ID --region "$REGION" --profile "$PROFILE" --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]")

    INSTANCE_ID=$(echo "$INSTANCE_JSON" | jq -r '.Instances[0].InstanceId')
    echo "Instance $INSTANCE_ID created. Waiting for it to be in 'running' state..."

    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION" --profile "$PROFILE"
fi

echo "Instance is running."

# --- 2. Get public IP address ---
echo "Fetching public IP address..."
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" --profile "$PROFILE" --query "Reservations[].Instances[].PublicIpAddress" --output text)
echo "Public IP: $PUBLIC_IP"

# --- 3. Create Ansible inventory ---
echo "Creating temporary Ansible inventory file..."
cat > "$INVENTORY_FILE" << EOL
[star-gate]
$PUBLIC_IP ansible_user=ubuntu ansible_ssh_private_key_file=$KEY_NAME
EOL

# --- 4. Run Ansible playbook ---
echo "Running Ansible playbook..."
ansible-playbook -i "$INVENTORY_FILE" $PLAYBOOK

echo "Deployment complete."
