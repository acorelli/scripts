import argparse
import base64
import getpass
import logging
import os
import uuid
import subprocess
import sys

try:
  import boto3
  from dotenv import load_dotenv
  from dotenv import dotenv_values
  from git import Repo
except ImportError as ie:
  print(f'Error importing modules: {ie}')
  print('Please make sure you have run `pip install -r requirements.txt`')
  sys.exit(1)

def config_logger(args={'verbose': 1}):
  """
  Creates/configures a python logging object
  
  Args:
    args (dict): set the 'verbose' key value to set logging level in the console
                 0: WARNING or higher
                 1: INFO
                 2+: DEBUG

  Returns:
    returns the configured logger object
  """
  logger = logging.getLogger(__name__)
  logger.setLevel(logging.DEBUG)
  
  script_dir = os.path.dirname(os.path.abspath(__file__))
  console_handler = logging.StreamHandler()
  file_handler = logging.FileHandler( os.path.join(script_dir, 'cicd_log.txt'))
  
  console_handler.setLevel(logging.WARNING)
  file_handler.setLevel(logging.DEBUG)
  formatter = logging.Formatter(fmt='[%(asctime)s.%(msecs)03d %(levelname)s]: %(message)s', datefmt='%H:%M:%S')
  
  console_handler.setFormatter(formatter)
  file_handler.setFormatter(formatter)
  
  logger.addHandler(console_handler)
  logger.addHandler(file_handler)

  if args.test:
    console_handler.setLevel(logging.INFO)

  if args.verbose is not None:
    if args.verbose == 1:
      console_handler.setLevel(logging.INFO)
    elif args.verbose > 1:
      console_handler.setLevel(logging.DEBUG)

  return logger
  
  
def get_params(logger, args):
  """
  Load the .env file an pack it into a params dict object
  
  Args:
    logger (logger): the logger object
    args (argparse object): the args passed in by the user to configure extra options
  
  Returns:
    A dict with the env/params
  """
  if not logger:
    logger = config_logger()
  
  load_dotenv()
  
  env = {}
  
  # Configure project name/tag values
  cwd = os.getcwd()
  while '.git' not in os.listdir(cwd) and cwd != "C:/":
    cwd = os.path.dirname(cwd)
  
  repo = Repo(cwd)
  project_name = os.getenv('PROJECT_NAME').replace(" ", "_").lower()
  if project_name is None:
    project_name = os.path.basename(cwd).replace(" ", "_").lower()
    
  if os.getenv('SHOW_PARENT_PATH'):
    parent_name = os.path.dirname(cwd)
    parent_name = os.path.basename(parent_name)+"-"
  else:
    parent_name = ""
  branch_name = repo.active_branch.name
  
  # read a unique identifier from file, or generate and store one
  random_uuid = os.getenv('CURRENT_UUID')
  if random_uuid is None:
    random_uuid = uuid.uuid4()
    with open(".env", 'a')  as f:
      f.write(f'\nCURRENT_UUID={random_uuid}')
  else:
    # To-do: Need to add options to delete/deregister old service/cluster
    pass
    
  cluster_name = (f'{parent_name}{project_name}-{branch_name}-{random_uuid}').replace(" ", "_")
  logger.info(cluster_name)
  
  # Load parameters or prompt for input
  ecr_uri = os.getenv('ECR_URI')
  if ecr_uri is None:
    # this part unfortunately can't be packed into the default value
    ecr_uri = input("Enter image URI: ")
  
  container_name = os.getenv('CONTAINER_NAME')
  if container_name is None:
    container_name = project_name
  
  # default to them being named the same as the cluster
  task_family_name = os.getenv('TASK_FAMILY_NAME', cluster_name)
  service_name = os.getenv('SERVICE_NAME', cluster_name)
  
  subnet = os.getenv('SUBNET')
  if subnet is None:
    subnet = input("Enter VPC Subnet: ")
  
  security_group = os.getenv('SECURITY_GROUP')
  if security_group is None:
    security_group = input("Enter Security Group: ")
  
  task_role_arn = os.getenv('TASK_ROLE_ARN')
  if task_role_arn is None:
    task_role_arn = input("Enter Task Role ARN: ")
  
  task_execution_role_arn = os.getenv('TASK_EXECUTION_ROLE_ARN')
  if task_execution_role_arn is None:
    task_execution_role_arn = input("Enter Task Execution Role ARN: ")
  
  project_version = os.getenv('PROJECT_VERSION', 'latest')
  
  local_container = f'{container_name}:{project_version}'
  ecr_repo = f'{service_name}'
  image_uri = f'{ecr_uri}/{ecr_repo}:latest'.lower()
  
  local_username = getpass.getuser()
  
  tags = [{'key': 'creator', 'value': local_username}]
  
  
  params = {
    'cluster_name': cluster_name,
    'project_name': project_name,
    'project_version': project_version,
    'ecr_uri': ecr_uri,
    'ecr_repo': ecr_repo,
    'container_name': container_name,
    'task_family_name': task_family_name,
    'service_name': service_name,
    'subnet': subnet,
    'security_group': security_group,
    'task_role_arn': task_role_arn,
    'task_execution_role_arn': task_execution_role_arn,
    'image_uri': image_uri,
    'local_container': local_container,
    'local_username': local_username,
    'tags': tags
  }
  
  # check for -f/--force
  if hasattr(args, 'force'):
    logger.debug('Enabling --force mode')
    params["force"] = args.force
  
  # update if user provided -c/--cluster
  if hasattr(args, 'cluster') and args.cluster is not None:
    logger.debug(f'Updating params["cluster_name"] to {args.cluster}')
    params["cluster_name"] = args.cluster
  
  # update for -k/--keep-alive
  if hasattr(args, 'keep_alive'):
    logger.debug(f'Appending keep_alive tag to params["tags"]')
    params["tags"].append({'key': 'keep_alive', 'value': str(args.keep_alive).lower()})
  
  # log values
  log_params(params, logger)
  
  return params
  
def log_params(params, logger):
  """
  Prints the params values in an easier to read format
  
  Args:
    params (dict): the params dict
    params (dict): the configuration/env params with username/cluster_name/etc
  """
  for key in params:
    line = str(key) + ':' + ' '*(40-len(str(key))) + str(params[key])
    logger.info(line)
  #logger.info(f'Project Name:           {params["project_name"]}')
  #logger.info(f'Project Version:        {params["project_version"]}')
  #logger.info(f'ECR_URI:                {params["ecr_uri"]}')
  #logger.info(f'Cluster Name:           {params["cluster_name"]}')
  #logger.info(f'Container Name:         {params["container_name"]}')
  #logger.info(f'Task Family Name:       {params["task_family_name"]}')
  #logger.info(f'Service Name:           {params["service_name"]}')
  #logger.info(f'Subnet:                 {params["subnet"]}')
  #logger.info(f'Security Group:         {params["security_group"]}')
  #logger.info(f'Task Role:              {params["task_role_arn"]}')
  #logger.info(f'Task Execution Role:    {params["task_execution_role_arn"]}')
  #logger.info(f'Image URI:              {params["image_uri"]}')
  #logger.info(f'Local Container:        {params["local_container"]}')
  #logger.info(f'Local Username:         {params["local_username"]}')
  #logger.info(f'Tags:                   {params["tags"]}')