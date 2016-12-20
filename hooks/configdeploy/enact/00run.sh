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

set -e

EB_CONFIG_DOCKER_IMAGE_STAGING=$(/opt/elasticbeanstalk/bin/get-config container -k staging_image)
EB_CONFIG_DOCKER_IMAGE_STAGING_FILE=$(/opt/elasticbeanstalk/bin/get-config container -k staging_image_file)
EB_CONFIG_DOCKER_IMAGE_CURRENT_FILE=$(/opt/elasticbeanstalk/bin/get-config container -k deploy_image_file)

# mark current as staging
EB_CONFIG_DOCKER_IMAGE_ID_CURRENT=`cat $EB_CONFIG_DOCKER_IMAGE_CURRENT_FILE`
docker tag -f $EB_CONFIG_DOCKER_IMAGE_ID_CURRENT $EB_CONFIG_DOCKER_IMAGE_STAGING
cp $EB_CONFIG_DOCKER_IMAGE_CURRENT_FILE $EB_CONFIG_DOCKER_IMAGE_STAGING_FILE

# go through docker run again, picking up config updates
/opt/elasticbeanstalk/hooks/appdeploy/enact/00run.sh
