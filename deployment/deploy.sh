#!/bin/bash

# Usage: ./deploy.sh <environment>
# In Git Bash, run: bash ./deployment/deploy.sh <environment>

ENV=$1

if [ "$ENV" != "dev" ] && [ "$ENV" != "prod" ]; then
    echo "Environment must be 'dev' or 'prod'"
    exit 1
fi

# Load environment variables (excluding arrays)
eval $(jq -r 'with_entries(select(.value | type != "array")) | to_entries | .[] | "export \(.key)=\(.value)"' deployment/environments/$ENV/env.json)

# Load arrays and format them for AWS CLI
SUBNET_IDS=$(jq -r '.SUBNET_IDS | join(",")' deployment/environments/$ENV/env.json)
SECURITY_GROUP_IDS=$(jq -r '.SECURITY_GROUP_IDS | join(",")' deployment/environments/$ENV/env.json)

# Debug: Print loaded variables
echo "Loaded variables:"
echo "SUBNET_IDS: ${SUBNET_IDS}"
echo "SECURITY_GROUP_IDS: ${SECURITY_GROUP_IDS}"
echo "VPC_ID: ${VPC_ID}"
echo "CLUSTER_NAME: ${CLUSTER_NAME}"

# AWS account setup with debug output
echo "Setting up AWS account..."
echo "Getting AWS account ID..."
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"

echo "Getting AWS region..."
export AWS_REGION=$(aws configure get region)
echo "AWS_REGION: ${AWS_REGION}"

echo "Setting up ECR repository URL..."
export ECR_REPOSITORY_URL=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/dagster
echo "ECR_REPOSITORY_URL: ${ECR_REPOSITORY_URL}"

# Add verbose output for ECR login
echo "Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPOSITORY_URL || {
    echo "Failed to log into ECR"
    exit 1
}

echo "Building Docker image..."
docker build -t dagster:$ENV-latest \
    --build-arg ENVIRONMENT=$ENV \
    -f deployment/docker/Dockerfile . || {
    echo "Failed to build Docker image"
    exit 1
}

docker tag dagster:$ENV-latest $ECR_REPOSITORY_URL:$ENV-latest
docker push $ECR_REPOSITORY_URL:$ENV-latest

# Create ECS cluster if it doesn't exist 
# aws ecs create-cluster --cluster-name $CLUSTER_NAME

# Create CloudWatch log groups
# aws logs create-log-group --log-group-name "//ecs/dagster-$ENV/webserver" || true
# aws logs create-log-group --log-group-name "//ecs/dagster-$ENV/daemon" || true

# Print role information
echo "Checking IAM roles..."
echo "Task Execution Role ARN: arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole"

# Try to get role information
echo "Current role details:"
aws iam get-role --role-name ecsTaskExecutionRole || echo "ecsTaskExecutionRole not found"

# Before registering task definitions, print the JSON
echo "Webserver Task Definition JSON:"
WEBSERVER_JSON=$(envsubst < deployment/task-definitions/webserver.json)
echo "$WEBSERVER_JSON" | jq '.'

echo "Daemon Task Definition JSON:"
DAEMON_JSON=$(envsubst < deployment/task-definitions/daemon.json)
echo "$DAEMON_JSON" | jq '.'

echo "User Code Task Definition JSON:"
USER_CODE_JSON=$(envsubst < deployment/task-definitions/user-code.json)
echo "$USER_CODE_JSON" | jq '.'

# Debug: Print important variables
echo "Debug: Important variables"
echo "AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
echo "AWS_REGION: ${AWS_REGION}"
echo "ECR_REPOSITORY_URL: ${ECR_REPOSITORY_URL}"
# echo "ENV: ${ENV}"





# # Update services by forcing a redployment of existing tasks/services
# # Good for when you need to restart a task when they are "stuck"
# aws ecs update-service \
#     --cluster $CLUSTER_NAME \
#     --service dagster-webserver-${ENV} \
#     --force-new-deployment

# aws ecs update-service \
#     --cluster $CLUSTER_NAME \
#     --service dagster-daemon-${ENV} \
#     --force-new-deployment

# # Wait for services to stabilize
# echo "Waiting for services to stabilize..."
# aws ecs wait services-stable \
#     --cluster $CLUSTER_NAME \
#     --services dagster-webserver-${ENV} dagster-daemon-${ENV}

# echo "Deployment completed successfully!"






# Update services by registering configuration changes 
# Maintains existing tasks until new task definitions
# This is good for code or configuration changes
update_services() {
    local env=$1
    local cluster_name=$2
    
    echo "Updating ECS services..."
    
    # Register new task definitions
    echo "Registering new task definitions..."
    aws ecs register-task-definition --cli-input-json "$(envsubst < deployment/task-definitions/webserver.json)"
    aws ecs register-task-definition --cli-input-json "$(envsubst < deployment/task-definitions/daemon.json)"
    aws ecs register-task-definition --cli-input-json "$(envsubst < deployment/task-definitions/user-code.json)"
    
    # Update services
    echo "Updating webserver service..."
    aws ecs update-service \
        --cluster $cluster_name \
        --service dagster-webserver-${env} \
        --task-definition dagster-webserver-${env}
        
    echo "Updating daemon service..."
    aws ecs update-service \
        --cluster $cluster_name \
        --service dagster-daemon-${env} \
        --task-definition dagster-daemon-${env}
        
    echo "Waiting for services to stabilize..."
    aws ecs wait services-stable \
        --cluster $cluster_name \
        --services dagster-webserver-${env} dagster-daemon-${env}
}

# Use it in your script
update_services $ENV $CLUSTER_NAME







# ## INITIAL DEPLOYMENT
# # Register task definitions
# echo "Registering webserver task definition..."
# aws ecs register-task-definition --cli-input-json "$WEBSERVER_JSON"

# echo "Registering daemon task definition..."
# aws ecs register-task-definition --cli-input-json "$DAEMON_JSON"

# # Create ALB
# echo "Creating Application Load Balancer..."
# ALB_NAME="dagster-${ENV}-alb"
# TARGET_GROUP_NAME="dagster-${ENV}-tg"

# # Convert comma-separated subnet string to array format
# SUBNET_ARRAY=$(echo $SUBNET_IDS | tr ',' ' ')
# echo "Subnets: $SUBNET_ARRAY"

# # Create target group (with fixed health check path)
# echo "Creating target group..."
# aws elbv2 create-target-group \
#     --name $TARGET_GROUP_NAME \
#     --protocol HTTP \
#     --port 3000 \
#     --vpc-id $VPC_ID \
#     --target-type ip \
#     --health-check-path "//health" \
#     --health-check-interval-seconds 30 \
#     --health-check-timeout-seconds 5 \
#     --healthy-threshold-count 2 \
#     --unhealthy-threshold-count 2 || true

# # Create ALB with proper subnet format
# echo "Creating load balancer..."
# aws elbv2 create-load-balancer \
#     --name $ALB_NAME \
#     --subnets $(echo $SUBNET_ARRAY) \
#     --security-groups $SECURITY_GROUP_IDS \
#     --scheme internet-facing \
#     --type application || true

# # Wait for ALB to be active
# echo "Waiting for ALB to be active (this typically takes 2-5 minutes)..."
# aws elbv2 wait load-balancer-available --names $ALB_NAME

# # Get ALB ARN
# ALB_ARN=$(aws elbv2 describe-load-balancers \
#     --names $ALB_NAME \
#     --query 'LoadBalancers[0].LoadBalancerArn' \
#     --output text)

# # Get target group ARN
# TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
#     --names $TARGET_GROUP_NAME \
#     --query 'TargetGroups[0].TargetGroupArn' \
#     --output text)

# # Create listener to connect ALB to target group
# echo "Creating ALB listener..."
# aws elbv2 create-listener \
#     --load-balancer-arn $ALB_ARN \
#     --protocol HTTP \
#     --port 80 \
#     --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN || true

# # Wait a bit for the listener to be ready
# echo "Waiting for listener to be ready..."
# sleep 10

# # Create ECS service with ALB
# echo "Creating ECS service..."
# if [ ! -z "$TARGET_GROUP_ARN" ]; then
#     # First, check if service exists
#     if aws ecs describe-services --cluster $CLUSTER_NAME --services dagster-webserver-${ENV} --query 'services[0].status' --output text 2>/dev/null; then
#         echo "Service exists, deleting it first..."
#         aws ecs update-service \
#             --cluster $CLUSTER_NAME \
#             --service dagster-webserver-${ENV} \
#             --desired-count 0
            
#         aws ecs delete-service \
#             --cluster $CLUSTER_NAME \
#             --service dagster-webserver-${ENV} \
#             --force
        
#         echo "Waiting for service to be deleted (this may take a few minutes)..."
#         aws ecs wait services-inactive \
#             --cluster $CLUSTER_NAME \
#             --services dagster-webserver-${ENV}
#     fi
    
#     echo "Creating new service..."
#     aws ecs create-service \
#         --cluster $CLUSTER_NAME \
#         --service-name dagster-webserver-${ENV} \
#         --task-definition dagster-webserver-${ENV} \
#         --desired-count $DESIRED_TASKS \
#         --launch-type FARGATE \
#         --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$SECURITY_GROUP_IDS],assignPublicIp=ENABLED}" \
#         --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=webserver,containerPort=3000"
# else
#     echo "Error: Target group ARN not found"
#     exit 1
# fi

# # Create daemon service
# aws ecs create-service \
#     --cluster $CLUSTER_NAME \
#     --service-name dagster-daemon-${ENV} \
#     --task-definition dagster-daemon-${ENV} \
#     --desired-count $DESIRED_TASKS \
#     --launch-type FARGATE \
#     --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_IDS],securityGroups=[$SECURITY_GROUP_IDS],assignPublicIp=ENABLED}"

# # Get the ALB DNS name (with error handling)
# echo "Getting ALB DNS name..."
# ALB_DNS=$(aws elbv2 describe-load-balancers --names $ALB_NAME --query 'LoadBalancers[0].DNSName' --output text)
# if [ "$ALB_DNS" != "None" ] && [ ! -z "$ALB_DNS" ]; then
#     echo "Dagster will be available at: http://$ALB_DNS"
# else
#     echo "Error: Could not get ALB DNS name"
#     exit 1
# fi

# echo "Deployment to $ENV environment completed!"