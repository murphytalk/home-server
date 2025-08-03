# deploy.ps1

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$instanceName
)

# Variables
$templateId = "lt-0b785b9218c0db172"
$region = "ap-east-1"
$keyName = "D:\Syncthing\mobile\vpn\stargate-aws-hk.pem"
$playbook = "playbook.yml"

# 1. Provision EC2 instance
Write-Host "Provisioning EC2 instance from template $templateId in region $region..."
$instance = aws ec2 run-instances --launch-template LaunchTemplateId=$templateId --region $region --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instanceName}]" | ConvertFrom-Json

$instanceId = $instance.Instances[0].InstanceId
Write-Host "Instance $instanceId created. Waiting for it to be in 'running' state..."

aws ec2 wait instance-running --instance-ids $instanceId --region $region
Write-Host "Instance is running."

# 2. Get public IP address
Write-Host "Fetching public IP address..."
$instanceDetails = aws ec2 describe-instances --instance-ids $instanceId --region $region | ConvertFrom-Json
$publicIp = $instanceDetails.Reservations[0].Instances[0].PublicIpAddress
Write-Host "Public IP: $publicIp"

# 3. Create Ansible inventory
Write-Host "Creating Ansible inventory file..."
$inventoryContent = @"
[star-gate]
$publicIp ansible_user=ubuntu ansible_ssh_private_key_file=$keyName
"@
$inventoryContent | Out-File -FilePath "hosts" -Encoding utf8

# 4. Run Ansible playbook
Write-Host "Running Ansible playbook..."
ansible-playbook -i hosts $playbook

Write-Host "Deployment complete."
