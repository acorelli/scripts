import argparse
import base64
import logging
import os
import subprocess
import sys

try:
  import boto3
except ImportError as ie:
  print(f'Error importing modules: {ie}')
  print('Please make sure you have run `pip install -r requirements.txt`')
  sys.exit(1)
  
import launch_utils

def launch_cluster(logger, params):
  """
  Helper function to call functions in order
  
  Args:
    logger (logger): the logger object
    params (dict): the configuration/env params with username/cluster_name/etc
  """
  create_ECR_repo(logger, params)
  create_cluster(logger, params)
  register_task_definition(logger, params)
  create_service(logger, params)

# Create ECR repo
def create_ECR_repo(logger, params):
  """
  Creates an ECR repo, builds the docker container image, and pushes it
  
  Args:
    logger (logger): the logger object
    params (dict): the configuration/env params with username/cluster_name/etc
  """
  ecr_repo = params["ecr_repo"]
  ecr_uri = params["ecr_uri"]
  local_container = params["local_container"]

  ecr = boto3.client('ecr', region_name='{{aws_region}}')
  try:
    response = ecr.create_repository(
      repositoryName=ecr_repo
    )
    logger.info(f'Repository created: {ecr_repo}')
    logger.debug(response)
  except ecr.exceptions.RepositoryAlreadyExistsException:
    logger.info(f'Repository {ecr_repo} already exists')
  except Exception as e:
    logger.critical(f'Error occured while creating ECR repository: {e}')
    sys.exit()
  
  # Tag and Push docker to ECR
  try:
    session = boto3.Session(region_name='{{aws_region}}', profile_name='default')
    client = session.client('ecr', region_name='{{aws_region}}')
    
    response = client.get_authorization_token()
    
    logger.debug(response)
    
    username, password = base64.b64decode(response['authorizationData'][0]['authorizationToken']).decode().split(':')
    login_cmd_str = f'docker login --username AWS --password {password} {ecr_uri}'
    subprocess.run(login_cmd_str, shell=False, check=True)
    
    build_cmd_str = f'docker build -t {local_container} .'
    subprocess.run(build_cmd_str, shell=False, check=True)
    
    tag_cmd_str = f'docker tag {local_container} {ecr_uri}/{ecr_repo}:latest'
    subprocess.run(tag_cmd_str, shell=False, check=True)
    
    push_cmd_str = f'docker push {ecr_uri}/{ecr_repo}:latest'
    subprocess.run(push_cmd_str, shell=False, check=True)
  except Exception as e:
    logger.critical(f'Error occured while tagging/pushing Docker image: {e}')
    sys.exit()


# Create the Cluster
def create_cluster(logger, params):
  """
  Creates the cluster and sets its tags

  Args:
    logger (logger): the logger object
    params (dict): the configuration/env params with username/cluster_name/etc
  """
  tags = params["tags"]
  cluster_name = params["cluster_name"]

  ecs = boto3.client('ecs', region_name='{{aws_region}}')
  
  try:
    response = ecs.create_cluster(
      tags=tags,
      clusterName = cluster_name
    )
    logger.info(f'Cluster created: {cluster_name}')
    logger.debug(response)
  except Exception as e:
    logger.critical(f'Error occured while creating cluster: {e}')
    sys.exit()

# Create the task definition
def register_task_definition(logger, params):
  """
  Create/register a task definition with the specified roles/tags/etc
  
  Args:
    logger (logger): the logger object
    params (dict): the configuration/env params with username/cluster_name/etc
  """

  ecs = boto3.client('ecs', region_name='{{aws_region}}')
  
  tags = params["tags"]
  task_family_name = params["task_family_name"]
  task_role_arn = params["task_role_arn"]
  task_execution_role_arn = params["task_execution_role_arn"]
  container_name = params["container_name"]
  image_uri = params["image_uri"]
  
  try:
    response = ecs.register_task_definition(
      tags=tags,
      family=task_family_name,
      taskRoleArn=task_role_arn,
      executionRoleArn=task_execution_role_arn,
      networkMode='awsvpc',
      requiresCompatibilities=['FARGATE'],
      cpu='512',
      memory='1GB',
      containerDefinitions=[
        {
        'name': container_name,
        'image': image_uri,
        'essential': True,
        'logConfiguration': {
          'logDriver': 'awslogs',
          'options': {
            'awslogs-group': '/ecs/{{project_name}}',
            'awslogs-region': '{{aws_region}}',
            'awslogs-stream-prefix': 'ecs'
          }
        },
        'portMappings': [
          {
            'containerPort': 80,
            'hostPort': 80,
            'protocol': 'tcp'
          }
        ],
        'cpu': 0
      }
      ]
    )
    logger.info(f'Task definition registered: {task_family_name}')
    logger.debug(response)
  except Exception as e:
    logger.critical(f'Error occured while creating task definition: {e}')
    sys.exit()

# Create the Service
def create_service(logger, params):
  """
  Create a service with the task defintion
  
  Args:
    logger (logger): the logger object
    params (dict): the configuration/env params with username/cluster_name/etc
  """

  ecs = boto3.client('ecs', region_name='{{aws_region}}')
  
  tags = params["tags"]
  cluster_name = params["cluster_name"]
  service_name = params["service_name"]
  task_family_name = params["task_family_name"]
  subnet = params["subnet"]
  security_group = params["security_group"]
  
  try:
    response = ecs.create_service(
      tags=tags,
      cluster=cluster_name,
      serviceName=service_name,
      taskDefinition=task_family_name,
      desiredCount=1,
      launchType='FARGATE',
      networkConfiguration={
        'awsvpcConfiguration': {
        'subnets': [
          subnet
        ],
        'assignPublicIp': 'DISABLED',
        'securityGroups': [
          security_group
        ]
      }
      }
    )
    logger.info(f'Service created: {service_name}')
    logger.debug(response)
  except Exception as e:
    # Check if service already exists
    if "Creation of service was not idempotent" in str(e):
      try:
        # update to use latest task version
        response = ecs.update_service(
          cluster=cluster_name,
          service=service_name,
          taskDefinition=task_family_name,
  		propagateTags='SERVICE'
        )
        logger.info(f'Updated Service: {service_name}')
      except Exception as e:
        logger.error(f'Error occured while updating service: {e}')
    else:
      logger.critical(f'Error occured while creating service: {e}')
      sys.exit()


if __name__ == "__main__":
  parser = argparse.ArgumentParser(description="Script for Launcing an ECS Cluster/Service/Task from an ECR Image from a Docker container")
  parser.add_argument('--keep-alive', action='store_true', help="Keep task alive. Use 'stop -f' to stop it")
  parser.add_argument('-t', '--test', action='store_true', help='Run in test mode')
  parser.add_argument('-v', '--verbose', action='count', help='Show more debugging messages')
  args = parser.parse_args()

  logger = launch_utils.config_logger(args)

  if args.test:
    logger.info('Running in test mode')

  params = launch_utils.get_params(logger, args)

  if args.test:
    logger.info('Test mode exiting')
    sys.exit(0)

  launch_cluster(logger, params)