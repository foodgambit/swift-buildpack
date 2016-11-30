#!/usr/bin/env bash

# IBM WebSphere Application Server Liberty Buildpack
# Copyright 2016 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# node-inspector npm module not needed after 6.3.0, similar functionality is built-in to node
function inspector_builtin() {
  node_path=$1
  node_version=$($node_path/bin/node -v)
  if [[ "$node_version" =~ v(6\.([3-9]|[1-9][0-9]+)|([7-9]|[1-9][0-9]+)\.[0-9]+)\.[0-9]+ ]]; then
    return 0
  else
    return 1
  fi
}
