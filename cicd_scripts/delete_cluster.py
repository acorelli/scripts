import argparse
import os
import sys
import time

try:
  import boto3
except ImportError as ie:
  print(f'Error importing modules: {ie}')
  print('Please make sure you have run `pip install -r requirements.txt`')
  sys.exit(1)
  
import launch_utils

def stop_and_delete_cluster(logger, params):
  """
  Deletes the cluster/service associated with params['cluster_name']

  Args:
    logger (logger): the logger object
    params (dict): the configuration/env params with username/cluster_name/etc

  Returns:
    returns 0 on success, or -1 on failure
  """
  # Cluster/Service/Task client
  ecs = boto3.client('ecs', region_name='{{aws_region}}')
  # clean clusters
  cluster_name = params["cluster_name"]
  clusters = []
  try:
    response = ecs.describe_clusters(
      clusters=[cluster_name],
      include=['TAGS']
    )
    clusters = response['clusters']
    logger.debug(response)
  except Exception as e:
    logger.error(f'Error describing clusters: {e}')
    return -1
  
  if len(clusters):
    cluster = response['clusters'][0]
    logger.debug(f'{cluster["clusterName"]} {cluster["tags"]}')
    if {'key': 'keep_alive', 'value': 'true'} in cluster['tags']:
      if params["force"]:
        logger.info(f'Force stopping: {cluster["clusterName"]}')
      else:
        logger.warning(f'{cluster["clusterName"]} has keepAlive enabled. Use --force to override.')  
        return -1
    
    service_arns = []
    try:
      response = ecs.list_services(
        cluster=cluster_name,
        launchType='FARGATE'
      )
      service_arns = response['serviceArns']
      logger.debug(response)
      logger.info(f'Service ARNs: {service_arns}')
    except Exception as e:
      logger.error(f'Error listing services: {e}')
      return -1
    
    for service in service_arns:
      try:
        logger.info(f'Deleting service: {service}')
        response = ecs.delete_service(
          cluster=cluster_name,
          service=service,
          force=True
        )
        logger.debug(response)
      except Exception as e:  
        logger.error(f'Error deleting {service}: ', e)
        return -1
    
    try:
      logger.info(f'Deleting cluster: {cluster_name}')
      response = ecs.delete_cluster(
        cluster=cluster_name
      )
      logger.debug(response)
    except ecs.exceptions.ClusterContainsTasksException as e:
      # Wait for tasks to stop, then delete the cluster
      logger.info(f'Waiting for {cluster_name} tasks to stop')
      try:
        while True:
          response = ecs.list_tasks(cluster=cluster_name)
          if len(response['taskArns']) == 0:
            logger.info('All tasks stopped. Deleting cluster')
            break
          time.sleep(5)
        response = ecs.delete_cluster(
          cluster=cluster_name
        )
        logger.debug(response)
      except Exception as e:
        logger.error('Error while waiting for tasks to stop: ', e)
        return -1
    except Exception as e:
      logger.error('Error deleting cluster: ', e)
      return -1
      
  else:
    logger.warning(f'No clusters found matching {cluster_name}')
  
  # cluster deleted; proceed with cleanup
  cleanup_task_definitions(logger, params)
  
  return 0

def cleanup_task_definitions(logger, params):
  """
  Deregisters/deletes task definitions associated with the params['cluster_name']

  Args:
    logger (logger): the logger object
    params (dict): the configuration/env params with username/cluster_name/etc
  
  Returns:
    returns 0 on success, or -1 on failure
  """
  # Cluster/Service/Task client
  ecs = boto3.client('ecs', region_name='{{aws_region}}')
  
  cluster_name = params["cluster_name"]
  task_definitions = []  
  # clean task definitions
  try:
    response = ecs.list_task_definitions(
      familyPrefix=cluster_name
    )
    task_definitions = response['taskDefinitionArns']
    logger.info(f'Task Definitions: {task_definitions}')
    logger.debug(response)
  except Exception as e:
    logger.error(f'Error listing task definitions: {e}')
    return -1
  
  if len(task_definitions):
    logger.info(f'Task Definitions: {task_definitions}')
    error = False
    for task in task_definitions:
      try:
        logger.info(f'Deregistering {task}')
        response = ecs.deregister_task_definition(
          taskDefinition=task
        )
        logger.debug(response)
      except Exception as e:
        logger.error(f'Error deregistering task definition: {e}')
        return -1
    
    try:
      logger.info(f'Deleting task definitions: {task_definitions}')
      # ecs.delete_task_definitions has a max of 10 at a time
      for i in range(0, len(task_definitions), 10):
        # get batch slice
        batch = task_definitions[i:i+10]
        response = ecs.delete_task_definitions(
          taskDefinitions=batch
        )
        logger.debug(response)
    except Exception as e:
      logger.error(f'Error deleting task definitions: {e}')
      return -1
  return 0

############################################################

def clean_ECR(logger, params):
  """
  Deletes all ECR repo associated with params['cluster_name']

  Args:
    logger (logger): the logger object
    params (dict): the configuration/env params with username/cluster_name/etc
  """
  
  # ECR repo client
  ecr = boto3.client('ecr', region_name='{{aws_region}}')
  
  cluster_name = params["cluster_name"]
  repositories = []
  response = None
  try:
    response = ecr.describe_repositories(
      repositoryNames=[cluster_name]
    )
    logger.info(f'Repositories: {repositories}')
    logger.debug(response)
    repositories = response['repositories'][0]
  except ecr.exceptions.RepositoryNotFoundException as e:
    logger.warning(f'The repository {cluster_name} does not exist')
  except Exception as e:
    logger.error(f'Error describing repositories: {e}')
    
  if len(repositories):
    logger.info(f'Deleting repository: {cluster_name}')
    try:
      response = ecr.delete_repository(
        repositoryName=cluster_name,
        force=True
      )
      logger.debug(response)
    except Exception as e:
      logger.error(f'Error deleting repository: {e}')

def delete_cluster(logger, params):
  """
  Deletes the cluster specified by params['cluster_name']
  Will also deregister task definitons, and clean up the ECR repo

  Args:
    logger (logger): the logger object
    params (dict): the configuration/env params with username/cluster_name/etc
  """
  
  if stop_and_delete_cluster(logger, params) == 0:
    clean_ECR(logger, params)


def delete_all_clusters(logger, params):
  """
  Deletes all clusters with the tag: {'key': 'creator', 'value': username}

  Args:
    logger (logger): the logger object
    params (dict): the configuration/env params with username/cluster_name/etc
  """
  
  ecs = boto3.client('ecs', region_name='{{aws_region}}')
  
  response = []
  try:
    response = ecs.list_clusters()
    logger.debug(response)
    response = ecs.describe_clusters(
      clusters=response['clusterArns'],
      include=['TAGS']
    )
    logger.debug(response)
  except Exception as e:
    logger.error(f'Error listing clusters: {e}')

  clusters = []
  for cluster in response['clusters']:
    logger.debug(cluster['tags'])
    if {'key': 'creator', 'value': params['local_username']} in cluster['tags']:
      clusters.append(cluster)  
  logger.info(f'Identified the following clusters: {clusters}')
  
  for cluster in clusters:
    logger.info(f'Deleting Cluster: {cluster["clusterName"]}')
    params['cluster_name'] = cluster['clusterName']
    delete_cluster(logger, params)


if __name__ == "__main__":
  """
  Will delete the cluster/service/task definitions associated with
  the cluster name (default read from .env file)
  
  Args:
    -c, --cluster (string): the name of the cluster in ECS
    -f, --force (flag): enable force stop/delete mode
    -t, --test (flag): enable test run, will print debug info
    -v (-vv) (flag): enable more verbose debugging info in the console
  
  """
  parser = argparse.ArgumentParser(description="Script for deleting an ECS Cluster/Service/Task and the associated ECR image")
  parser.add_argument('-c', '--cluster', help="Name of Cluster to stop")
  parser.add_argument('-f', '--force', action='store_true', help="Force stop tasks with keepAlive enabled")
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

  delete_cluster(logger, params)