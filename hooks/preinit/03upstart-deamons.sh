#!/bin/bash
#==============================================================================
# Copyright 2012 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Amazon Software License (the "License"). You may not use
# this file except in compliance with the License. A copy of the License is
# located at
#
#	   http://aws.amazon.com/asl/
#
# or in the "license" file accompanying this file. This file is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
# implied. See the License for the specific language governing permissions
# and limitations under the License.
#==============================================================================

set -e

. /opt/elasticbeanstalk/hooks/common.sh

EB_CONFIG_DOCKER_CURRENT_APP_FILE=$(/opt/elasticbeanstalk/bin/get-config container -k app_deploy_file)

# we will do the monitoring, disable docker's "-r" behavior
if is_rhel; then
	if ! grep -q 'other_args="-r=false"' /etc/sysconfig/docker; then
		echo 'other_args="-r=false"' >> /etc/sysconfig/docker
	fi
else
	error_exit "Unknown default configuration." 1
fi

# write the upstart script

cat > /etc/init/eb-docker.conf <<EOF
description "Elastic Beanstalk Default Docker Container"
author "Elastic Beanstalk"

start on started docker
stop on stopping docker

respawn

script
	# Wait for docker to finish starting up first.
	FILE=/var/run/docker.sock
	while [ ! -e \$FILE ]; do
		sleep 2
	done

	EB_CONFIG_DOCKER_CURRENT_APP=\`cat $EB_CONFIG_DOCKER_CURRENT_APP_FILE | cut -c 1-12\`

	if ! docker ps | grep \$EB_CONFIG_DOCKER_CURRENT_APP; then
		docker start \$EB_CONFIG_DOCKER_CURRENT_APP
	fi

	EB_CONFIG_DOCKER_PORT_FILE=\`/opt/elasticbeanstalk/bin/get-config container -k port_file\`
	EB_CONFIG_NGINX_UPSTREAM_IP=\`docker inspect \$EB_CONFIG_DOCKER_CURRENT_APP | jq -r .[0].NetworkSettings.IPAddress\`
	EB_CONFIG_NGINX_UPSTREAM_PORT=\`cat \$EB_CONFIG_DOCKER_PORT_FILE\`

	if ! cat /etc/nginx/conf.d/elasticbeanstalk-nginx-docker-upstream.conf | grep -q \$EB_CONFIG_NGINX_UPSTREAM_IP; then
		sed -i "s/server.*;/server \$EB_CONFIG_NGINX_UPSTREAM_IP:\$EB_CONFIG_NGINX_UPSTREAM_PORT;/" /etc/nginx/conf.d/elasticbeanstalk-nginx-docker-upstream.conf
		service nginx restart
	fi

	docker logs -f \$EB_CONFIG_DOCKER_CURRENT_APP >> /var/log/eb-docker/containers/eb-current-app/\$EB_CONFIG_DOCKER_CURRENT_APP-stdouterr.log 2>&1
	
	exec docker wait \$EB_CONFIG_DOCKER_CURRENT_APP
end script

post-stop script
	EB_CONFIG_DOCKER_CURRENT_APP=\`cat $EB_CONFIG_DOCKER_CURRENT_APP_FILE | cut -c 1-12\`

	if docker ps | grep \$EB_CONFIG_DOCKER_CURRENT_APP; then
		docker stop \$EB_CONFIG_DOCKER_CURRENT_APP
	fi
end script
EOF

cat > /etc/init/eb-docker-events.conf <<"EOF"
description "Elastic Beanstalk Docker Events Logger"
author "Elastic Beanstalk"

start on started docker
stop on stopping docker

console none
respawn

script
	exec >> /var/log/docker-events.log 2>&1
	exec docker events
end script
EOF
start_upstart_service eb-docker-events 2>&1 | grep -q running
