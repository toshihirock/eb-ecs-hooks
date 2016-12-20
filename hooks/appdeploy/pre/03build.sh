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

EB_CONFIG_APP_CURRENT=$(/opt/elasticbeanstalk/bin/get-config container -k app_deploy_dir)
EB_SUPPORT_FILES=$(/opt/elasticbeanstalk/bin/get-config container -k support_files_dir)
EB_CONFIG_DOCKER_IMAGE_STAGING=$(/opt/elasticbeanstalk/bin/get-config container -k staging_image)
EB_CONFIG_DOCKER_STAGING_IMAGE_FILE=$(/opt/elasticbeanstalk/bin/get-config container -k staging_image_file)

cd $EB_CONFIG_APP_CURRENT

# Dockerrun.aws.json verson checking
# right now only one valid version "1"
if [ -f Dockerrun.aws.json ]; then
	[ "`cat Dockerrun.aws.json | jq -r .AWSEBDockerrunVersion`" = "1" ] || error_exit "Invalid Dockerrun.aws.json version, abort deployment" 1
fi

# if we don't have a Dockerfile, generate a simple one with FROM and EXPOSE only
if [ ! -f Dockerfile ]; then
	if [ ! -f Dockerrun.aws.json ]; then
		error_exit "Dockerfile and Dockerrun.aws.json are both missing, abort deployment" 1
	fi

	IMAGE=`cat Dockerrun.aws.json | jq -r .Image.Name`
	PORT=`cat Dockerrun.aws.json | jq -r .Ports[0].ContainerPort`

	touch Dockerfile
	echo "FROM $IMAGE" >> Dockerfile
	echo "EXPOSE $PORT" >> Dockerfile
fi

# download auth credentials for private repo

S3_BUCKET=`cat Dockerrun.aws.json | jq -r .Authentication.Bucket`
S3_KEY=`cat Dockerrun.aws.json | jq -r .Authentication.Key`
if [ -n "$S3_BUCKET" ] && [ "$S3_BUCKET" != "null" ]; then
	$EB_SUPPORT_FILES/download_auth.py "$S3_BUCKET" "$S3_KEY"
	[ $? -eq 0 ] || error_exit "Failed to download authentication credentials $S3_KEY from $S3_BUCKET" 1
fi

FROM_IMAGE=`cat Dockerfile | grep -i ^FROM | head -n 1 | awk '{ print $2 }' | sed $'s/\r//'`

if [ -z $FROM_IMAGE ] || [ "$FROM_IMAGE" = "null" ]; then
	error_exit "No Docker image specified in either Dockerfile or Dockerrun.aws.json. Abort deployment." 1
fi

# if the image is in an ECR repo, authenticate with ECR
ECR_IMAGE_PATTERN="^([a-zA-Z0-9][a-zA-Z0-9_-]*)\\.dkr\\.ecr\\.([a-zA-Z0-9][a-zA-Z0-9_-]*)\\.amazonaws\\.com(\\.cn)?/.*"
if [[ $FROM_IMAGE =~ $ECR_IMAGE_PATTERN ]]; then
	ECR_REGISTRY_ID=${BASH_REMATCH[1]}
	ECR_REGION=${BASH_REMATCH[2]}

	ECR_LOGIN_RESPONSE=`aws ecr get-login --registry-ids $ECR_REGISTRY_ID --region $ECR_REGION 2>&1`
	[ $? -eq 0 ] || error_exit "Failed to authenticate with ECR for registry '$ECR_REGISTRY_ID' in '$ECR_REGION'" 1

	# output of aws ecr get-login should be a "docker login" command, simply invoke it
	echo $ECR_LOGIN_RESPONSE | grep -q "^docker login" || error_exit "Invalid response from 'aws ecr get-login', expecting a 'docker login' command, was: '$ECR_LOGIN_RESPONSE'."
	eval $ECR_LOGIN_RESPONSE
fi

# update "FROM" image
NEED_PULL=`cat Dockerrun.aws.json | jq -r .Image.Update`
if [ "$NEED_PULL" != "false" ]; then
	# when no tags are specified, pull the latest
	if ! echo $FROM_IMAGE | grep -q ':'; then
		FROM_IMAGE="$FROM_IMAGE:latest"
	fi

	RETRY_COUNT=1
	while [ $RETRY_COUNT -ge 0 ]; do
		HOME=/root docker pull "$FROM_IMAGE" 2>&1 | tee /tmp/docker_pull.log

		DOCKER_PULL_EXIT_CODE=${PIPESTATUS[0]}
		if [ $DOCKER_PULL_EXIT_CODE -eq 0 ]; then
			trace "Successfully pulled $FROM_IMAGE"
			break
		else
			if [ $RETRY_COUNT -gt 0 ]; then
				((RETRY_COUNT--))
				warn "Failed to pull Docker image $FROM_IMAGE, retrying..."
				continue
			fi
			LOG_TAIL=`cat /tmp/docker_pull.log | tail -c 200`
			rm -f /root/.dockercfg
			error_exit "Failed to pull Docker image $FROM_IMAGE: $LOG_TAIL. Check snapshot logs for details." $DOCKER_PULL_EXIT_CODE
		fi
	done
fi

RETRY_COUNT=1
while [ $RETRY_COUNT -ge 0 ]; do
	HOME=/root docker build -t $EB_CONFIG_DOCKER_IMAGE_STAGING . 2>&1 | tee /tmp/docker_build.log

	DOCKER_BUILD_EXIT_CODE=${PIPESTATUS[0]}
	if [ $DOCKER_BUILD_EXIT_CODE -eq 0 ]; then
		trace "Successfully built $EB_CONFIG_DOCKER_IMAGE_STAGING"
		break
	else
		if [ $RETRY_COUNT -gt 0 ]; then
			((RETRY_COUNT--))
			warn "Failed to build Docker image $EB_CONFIG_DOCKER_IMAGE_STAGING, retrying..."
			continue
		fi
		LOG_TAIL=`cat /tmp/docker_build.log | tail -c 150`
		rm -f /root/.dockercfg
		error_exit "Failed to build Docker image $EB_CONFIG_DOCKER_IMAGE_STAGING: $LOG_TAIL. Check snapshot logs for details." $DOCKER_BUILD_EXIT_CODE
	fi
done

# no need for the auth file to hang around
rm -f /root/.dockercfg

EB_CONFIG_DOCKER_IMAGE_ID_STAGING=`docker images | grep ^$EB_CONFIG_DOCKER_IMAGE_STAGING | awk '{ print $3 }'`
echo $EB_CONFIG_DOCKER_IMAGE_ID_STAGING > $EB_CONFIG_DOCKER_STAGING_IMAGE_FILE
