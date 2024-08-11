#!/usr/bin/env bash

# see http://docs.aws.amazon.com/cli/latest/userguide/installing.html
# AWS CLI installation depends on OS

# Template verification
aws cloudformation validate-template --template-body file://_initialization.yaml

# we create the cloudformation template
aws cloudformation create-stack --stack-name ROOT-10-initialisation --template-body file://_initialization.yaml --parameters file://0_parameters.json --capabilities CAPABILITY_AUTO_EXPAND

# some options:
# [--template-url <value>]
# [--disable-rollback | --no-disable-rollback]
# [--rollback-configuration <value>]
# [--timeout-in-minutes <value>]
# [--notification-arns <value>]
# [--capabilities <value>]
# [--resource-types <value>]
# [--role-arn <value>]
# [--on-failure <value>]
# [--stack-policy-body <value>]
# [--stack-policy-url <value>]
# [--tags <value>]
# [--client-request-token <value>]
# [--enable-termination-protection | --no-enable-termination-protection]
# [--cli-input-json | --cli-input-yaml]
# [--generate-cli-skeleton <value>]

aws cloudformation delete-stack --stack-name ROOT-10-initialisation