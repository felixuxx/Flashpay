#!/bin/bash

KEY=$(jq -r .key)
echo -n "{\"$KEY\":\"$1\"}"
exit 42
