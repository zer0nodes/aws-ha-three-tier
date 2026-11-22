param(
    [string]$Region = "eu-north-1",
    [string]$Project = "aws-ha-three-tier"
)

$tag = "Name=tag:Project,Values=$Project"

$checks = [ordered]@{
    "NAT gateways (not deleted)"     = "ec2", "describe-nat-gateways", "--query", "NatGateways[?State!='deleted'].NatGatewayId"
    "Elastic IPs"                    = "ec2", "describe-addresses", "--query", "Addresses[].PublicIp"
    "Load balancers"                 = "elbv2", "describe-load-balancers", "--query", "LoadBalancers[].LoadBalancerName"
    "RDS DB instances"               = "rds", "describe-db-instances", "--query", "DBInstances[].DBInstanceIdentifier"
    "EC2 instances (not terminated)" = "ec2", "describe-instances", "--filters", "Name=instance-state-name,Values=pending,running,shutting-down,stopping,stopped", "--query", "Reservations[].Instances[].InstanceId"
    "VPCs"                           = "ec2", "describe-vpcs", "--filters", $tag, "--query", "Vpcs[].VpcId"
    "EBS volumes"                    = "ec2", "describe-volumes", "--filters", $tag, "--query", "Volumes[].VolumeId"
    "Launch templates"               = "ec2", "describe-launch-templates", "--filters", $tag, "--query", "LaunchTemplates[].LaunchTemplateName"
    "Auto Scaling groups"            = "autoscaling", "describe-auto-scaling-groups", "--query", "AutoScalingGroups[?starts_with(AutoScalingGroupName, '$Project')].AutoScalingGroupName"
    "Target groups"                  = "elbv2", "describe-target-groups", "--query", "TargetGroups[?starts_with(TargetGroupName, '$Project')].TargetGroupName"
    "RDS subnet groups"              = "rds", "describe-db-subnet-groups", "--query", "DBSubnetGroups[?starts_with(DBSubnetGroupName, '$Project')].DBSubnetGroupName"
    "RDS manual snapshots"           = "rds", "describe-db-snapshots", "--snapshot-type", "manual", "--query", "DBSnapshots[?starts_with(DBInstanceIdentifier, '$Project')].DBSnapshotIdentifier"
    "RDS retained automated backups" = "rds", "describe-db-instance-automated-backups", "--query", "DBInstanceAutomatedBackups[?starts_with(DBInstanceIdentifier, '$Project')].DBInstanceIdentifier"
    "RDS-managed secrets"            = "secretsmanager", "list-secrets", "--query", "SecretList[?starts_with(Name, 'rds!db')].Name"
    "IAM roles"                      = "iam", "list-roles", "--query", "Roles[?starts_with(RoleName, '$Project')].RoleName"
    "IAM instance profiles"          = "iam", "list-instance-profiles", "--query", "InstanceProfiles[?starts_with(InstanceProfileName, '$Project')].InstanceProfileName"
    "CloudWatch dashboards"          = "cloudwatch", "list-dashboards", "--dashboard-name-prefix", $Project, "--query", "DashboardEntries[].DashboardName"
    "CloudWatch alarms"              = "cloudwatch", "describe-alarms", "--alarm-name-prefix", $Project, "--query", "MetricAlarms[].AlarmName"
    "Target tracking alarms"         = "cloudwatch", "describe-alarms", "--alarm-name-prefix", "TargetTracking-$Project", "--query", "MetricAlarms[].AlarmName"
    "SNS topics"                     = "sns", "list-topics", "--query", "Topics[?contains(TopicArn, ':$Project')].TopicArn"
}

$notes = [ordered]@{
    "RDS automated snapshots, deleted by RDS a few minutes after the instance" = "rds", "describe-db-snapshots", "--snapshot-type", "automated", "--query", "DBSnapshots[?starts_with(DBInstanceIdentifier, '$Project')].DBSnapshotIdentifier"
    "SNS subscriptions pending confirmation, deleted by SNS after 48 hours"     = "sns", "list-subscriptions", "--query", "Subscriptions[?contains(TopicArn, ':$Project')].SubscriptionArn"
    "Tagging API entries, which can outlive deleted resources by hours"        = "resourcegroupstaggingapi", "get-resources", "--tag-filters", "Key=Project,Values=$Project", "--query", "ResourceTagMappingList[].ResourceARN"
}

function Get-Leftover([string[]]$Arguments) {
    $out = & aws @Arguments --region $Region --output text 2>&1
    if ($LASTEXITCODE) { throw "$out" }
    -split "$out" | Where-Object { $_ -and $_ -ne "None" }
}

$identity = aws sts get-caller-identity --region $Region --query Arn --output text 2>&1
if ($LASTEXITCODE) {
    "Cannot call AWS: $identity" -replace '\b\d{12}\b', '<account>'
    exit 1
}

"Project $Project, region $Region"
$failed = 0
foreach ($name in $checks.Keys) {
    try {
        $left = @(Get-Leftover $checks[$name])
    } catch {
        "ERROR  ${name}: $_" -replace '\b\d{12}\b', '<account>'
        $failed++
        continue
    }
    if ($left.Count) {
        "LEFT   ${name}: $($left -join ', ')" -replace '\b\d{12}\b', '<account>'
        $failed++
    } else {
        "CLEAN  $name"
    }
}
foreach ($name in $notes.Keys) {
    try { $count = @(Get-Leftover $notes[$name]).Count } catch { $count = "?" }
    if ($count) { "NOTE   ${name}: $count" }
}
if ($failed) {
    "Not clean: $failed of $($checks.Count) checks found resources or failed."
    exit 1
}
"Clean: all $($checks.Count) checks are empty."
exit 0
