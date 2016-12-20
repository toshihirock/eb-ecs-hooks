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

. /opt/elasticbeanstalk/hooks/common.sh

if ! is_baked docker_packages; then
    echo "Running on unbaked AMI, installing packages."
	yum install -y docker docker-storage-setup jq nginx sqlite

	# RPM overrides
	EB_CONFIG_RPM_OVERRIDES=$(/opt/elasticbeanstalk/bin/get-config container -k rpm_overrides)
	if [ -n "$EB_CONFIG_RPM_OVERRIDES" ]; then
		for RPM in $EB_CONFIG_RPM_OVERRIDES; do
			rpm -i --force --nodeps $RPM
		done
	fi
fi

# enable cfn-hup and nginx on boot
chkconfig cfn-hup on
chkconfig nginx on
