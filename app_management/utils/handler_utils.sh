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

handler=$1
param=$2
default=$3

INSTALL_DIR=$(cd `dirname $0`/../.. && pwd)

ruby <<-EORUBY
  APP_MGMT_DIR = File.join('$INSTALL_DIR', '.app-management').freeze
  \$LOAD_PATH.unshift File.expand_path(APP_MGMT_DIR, __FILE__)
  require 'utils/handler_utils.rb'
  config = Utils::HandlerUtils.get_configuration('$handler')
  puts config['$param'] || $default
EORUBY
