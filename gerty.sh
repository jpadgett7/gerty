#!/bin/bash

source secret.sh

if [ -z "$GERTY_TOKEN" ]
then
    echo "Please note that Gerty cannot update the SIG-Game status site without a GitHub Token"
else
    export HUBOT_STATUS_GITHUB_TOKEN=$GERTY_TOKEN
fi

HUBOT_STATUS_REPO_NAME="status" \
    HUBOT_STATUS_REPO_OWNER="siggame" \
    FILE_BRAIN_PATH=./ \
    BIND_ADDRESS="localhost" \
    HUBOT_AUTH_ADMIN="1" \
    bin/hubot -a shell -n gerty
