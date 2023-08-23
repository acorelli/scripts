import argparse
import getpass
import os
import sys

script_dir = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(script_dir, 'cicd_scripts'))

from cicd_scripts import launch_utils
from cicd_scripts.delete_cluster import delete_cluster
from cicd_scripts.delete_cluster import delete_all_clusters
from cicd_scripts.launch_cluster import launch_cluster

if __name__ == "__main__":
  parser = argparse.ArgumentParser(description="Script for Launcing an ECS Cluster/Service/Task from an ECR Image from a Docker container")
  
  subparsers = parser.add_subparsers(dest='command')
  
  parser_start = subparsers.add_parser('start', help='start a task')
  parser_stop = subparsers.add_parser('stop', help='stop a task')
  parser_stopall = subparsers.add_parser('stopall', help='stop all tasks')
  
  for subparser in [parser_start, parser_stop, parser_stopall]:
    subparser.add_argument('-t', '--test', action='store_true', help='Run in test mode')
    subparser.add_argument('-v', '--verbose', action='count', help='Show debug messages')
    
  parser_start.add_argument('-k', '--keep-alive', action='store_true', help='add tag to keep this task alive. requires the --force option to stop it')
  
  parser_stop.add_argument('-c', '--cluster', help="Name of Cluster to stop")
  
  for subparser in [parser_stop, parser_stopall]:
    subparser.add_argument('-f', '--force', action='store_true', help='force stop task')
    
  args = parser.parse_args()
  
  if args.command is None:
    args = parser.parse_args(['start'])
  
  logger = launch_utils.config_logger(args)
  params = launch_utils.get_params(logger, args)
  
  # add keep_alive/force support
  
  if args.test:
    print('Test run exiting')
    sys.exit(0)
  
  if args.command == 'start':
    launch_cluster(logger, params)
  elif args.command == 'stop':
    delete_cluster(logger, params)
  elif args.command == 'stopall':
    delete_all_clusters(logger, params)
  else:
    print('Unknown command')
    sys.exit(1)