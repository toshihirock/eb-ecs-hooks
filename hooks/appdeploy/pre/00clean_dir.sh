#!/bin/bash
#==============================================================================
# Copyright 2012 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Amazon Software License (the "License"). You may not use
# this file except in compliance with the License. A copy of the License is
# located at
#
#       http://aws.amazon.com/asl/
#
# or in the "license" file accompanying this file. This file is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
# implied. See the License for the specific language governing permissions
# and limitations under the License.
#==============================================================================

. /opt/elasticbeanstalk/hooks/common.sh

# no clean up if there isn't a running container to avoid re-pulling cached images
# https://docs.docker.com/reference/commandline/ps/
RUNNING_DOCKER_CONTAINERS=$(docker ps -a -q -f status=running)

if [ -n "$RUNNING_DOCKER_CONTAINERS" ]; then
	save_docker_image_names
	docker rm `docker ps -aq` > /dev/null 2>&1
	docker rmi `docker images -aq` > /dev/null 2>&1
	restore_docker_image_names
fi

# set -e after clean up commands because rmi will have exceptions that in-use images cannot be deleted
set -e

EB_CONFIG_APP_CURRENT=$(/opt/elasticbeanstalk/bin/get-config container -k app_deploy_dir)
EB_CONFIG_DOCKER_LOG_HOST_DIR=$(/opt/elasticbeanstalk/bin/get-config container -k host_log_dir)

rm -rf $EB_CONFIG_APP_CURRENT
mkdir -p $EB_CONFIG_APP_CURRENT

mkdir -p $EB_CONFIG_DOCKER_LOG_HOST_DIR
# need chmod since customer app may run as non-root and the user they run as is undeterminstic
chmod 777 $EB_CONFIG_DOCKER_LOG_HOST_DIR
