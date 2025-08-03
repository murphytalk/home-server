# deploy.ps1

[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$instanceName,
    [string]$Profile = 'my-stargate-profile',
    [string]$InstanceId = ''
)

# Variables
$templateId = "lt-0b785b9218c0db172"
$region = "ap-east-1"
$keyName = "D:\Syncthing\mobile\vpn\stargate-aws-hk.pem"
$playbook = "playbook.yml"
$currentInstanceId = $InstanceId

# 1. Provision or Start EC2 instance
if (-not [string]::IsNullOrEmpty($currentInstanceId)) {
    Write-Host "Checking for existing instance with ID: $currentInstanceId"
    $instanceDetails = aws ec2 describe-instances --instance-ids $currentInstanceId --region $region --profile $Profile --query "Reservations[].Instances[]" | ConvertFrom-Json
    
    if ($null -eq $instanceDetails) {
        Write-Error "No instance found with ID: $currentInstanceId. Exiting."
        exit 1
    }

    $instanceState = $instanceDetails.State.Name
    Write-Host "Instance found. Current state: $instanceState"

    if ($instanceState -eq 'stopped') {
        Write-Host "Starting instance $currentInstanceId..."
        aws ec2 start-instances --instance-ids $currentInstanceId --region $region --profile $Profile
    }
    
    Write-Host "Waiting for instance to be in 'running' state..."
    aws ec2 wait instance-running --instance-ids $currentInstanceId --region $region --profile $Profile
    
} else {
    Write-Host "Provisioning new EC2 instance from template $templateId in region $region..."
    $instance = aws ec2 run-instances --launch-template LaunchTemplateId=$templateId --region $region --profile $Profile --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$instanceName}]" | ConvertFrom-Json
    
    $currentInstanceId = $instance.Instances[0].InstanceId
    Write-Host "Instance $currentInstanceId created. Waiting for it to be in 'running' state..."
    
    aws ec2 wait instance-running --instance-ids $currentInstanceId --region $region --profile $Profile
}

Write-Host "Instance is running."

# 2. Get public IP address
Write-Host "Fetching public IP address..."
$instanceDetails = aws ec2 describe-instances --instance-ids $currentInstanceId --region $region --profile $Profile | ConvertFrom-Json
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
python -m ansible.cli.playbook -i hosts $playbook

Write-Host "Deployment complete."
