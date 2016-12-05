#!/usr/bin/env bash
# IBM SDK for Node.js Buildpack
# Copyright 2015 the original author or authors.
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

function installAgent() {
  status "installAgent 1"
  mkdir $BUILD_DIR/.app-management
  mkdir $BUILD_DIR/.app-management/scripts
  mkdir $BUILD_DIR/.app-management/utils
  mkdir $BUILD_DIR/.app-management/bin
  mkdir $BUILD_DIR/.app-management/handlers
  mkdir $BUILD_DIR/.app-management/mosquitto

  cp -r $BP_DIR/app_management/bin/* $BUILD_DIR/.app-management/bin
  cp $BP_DIR/app_management/bin/agent_api_version $BUILD_DIR/..
  cp $BP_DIR/app_management/scripts/* $BUILD_DIR/.app-management/scripts
  cp $BP_DIR/app_management/utils/* $BUILD_DIR/.app-management/utils
  cp -ra $BP_DIR/app_management/handlers/* $BUILD_DIR/.app-management/handlers
  # Note: $BUILD_DIR/.app-management/handlers/ will be pruned by setupHandlerBinaries() below
  cp $BP_DIR/app_management/initial_startup.rb $BUILD_DIR/vendor
  cp -r $BP_DIR/app_management/mosquitto/* $BUILD_DIR/.app-management/mosquitto
  cp $BP_DIR/app_management/env.json $BUILD_DIR/.app-management

  status "installAgent 2"

  chmod +x $BUILD_DIR/.app-management/bin/proxyAgent
  chmod +x $BUILD_DIR/.app-management/scripts/*
  chmod +x $BUILD_DIR/.app-management/utils/*
  chmod -R +x $BUILD_DIR/.app-management/handlers/
  chmod +x $BUILD_DIR/vendor/initial_startup.rb
  status "installAgent end"
}

function getOpts(){
  local start=$1
  # match all before and including the start script
  local dirtyOpts=$(echo $start | grep -oP "node\s[^-]\S*|.*node\s.*?\s[^-]\S*" | command head -n 1)
  # match anything starting with at least one '-' followed by any non-whitespace, then at least 1 space
  local opts=$(echo $dirtyOpts | grep -oP "(^[-]\S*|\s[-]+\S*)")
  echo $opts
}

function getArgs(){
  local start=$1
  local dirtyOpts=$(echo $start | grep -oP "node\s[^-]\S*|.*node\s.*?\s[^-]\S*" | command head -n 1)
  # get the second half (the args) by removing the dirty opts.
  local args="${start/$dirtyOpts/}"
  echo $args
}

function updateStartCommands() {
  # Update start command on start script (used by agent/initial startup)
  if test -f ${BUILD_DIR}/Procfile; then
    local start_command=$(sed -n -e '/^web:/p' ${BUILD_DIR}/Procfile | sed 's/^web: //')
    sed -i s#%COMMAND%#"${start_command}"# "${BUILD_DIR}"/.app-management/scripts/start

    # Use initial_startup to start application
    sed -i 's#web:.*#web: ./vendor/initial_startup.rb#' $BUILD_DIR/Procfile
  else
    sed -i s#%COMMAND%#"npm start"# "${BUILD_DIR}"/.app-management/scripts/start
    # Use initial_startup to start application
    touch $BUILD_DIR/Procfile
    echo "web: ./vendor/initial_startup.rb" > $BUILD_DIR/Procfile
  fi

  # Logic to preserve the opts and args for the start command.
  if [[ $start_command == *"node"* ]]; then
    opts=$(getOpts "$start_command")
    args=$(getArgs "$start_command")
  elif [ -f "${BUILD_DIR}/package.json" ]; then
    start_script=$(cat "$BUILD_DIR/package.json" | "$BP_DIR/vendor/jq" -r .scripts.start)
    if [[ -n $start_script ]] && [[ ! "$start_script" == "" ]]; then
      opts=$(getOpts "$start_script")
      args=$(getArgs "$start_script")
    fi
  fi

  # Update env vars used for dev mode
  echo "export BOOT_SCRIPT=${boot_js_file}" >> ${BUILD_DIR}/.profile.d/bluemix_env.sh
  echo "export NODE_EXECUTABLE=node" >> ${BUILD_DIR}/.profile.d/bluemix_env.sh
  echo "export NODE_OPTS=\"${opts}\"" >> ${BUILD_DIR}/.profile.d/bluemix_env.sh
  echo "export NODE_ARGS=\"${args}\"" >> ${BUILD_DIR}/.profile.d/bluemix_env.sh
}

# Sets up a Node runtime at `$BUILD_DIR/.app-management/node`. It will either be a simple
# symlink to `/home/vcap/app/vendor/node` or a copy of app_management's Node runtime.
function copyAppManagementNode() {
  local appmgmt_node_version=$(${BP_DIR}/app_management/node/bin/node -v)
  local runtime_node_version=$(${BUILD_DIR}/vendor/node/bin/node -v)
  [[ "$enabled_handlers" ]] || enabled_handlers=$($BP_DIR/lib/print_enabled_handlers.rb)

  # Determine if we must copy the whole Node runtime from the app_management folder, or
  # whether a symlink will suffice. The strategy is: if any handlers are enabled in the env,
  # and the Node version under which they were built differs from vendor/node, then we must
  # copy the runtime to ensure compatibility.
  local build_app_mgmt_dir=${BUILD_DIR}/.app-management
  if [[ "$enabled_handlers" != "" && "$appmgmt_node_version" != "$runtime_node_version" ]]; then
    cp -ra ${BP_DIR}/app_management/node ${build_app_mgmt_dir}
    info "  Installing common dependency: App Management Node runtime"
  else
    # Otherwise, we can get away with a symlink node -> ../vendor/node
    ( cd ${build_app_mgmt_dir} && ln -sf ../vendor/node node )
  fi

  # Fix up the npm symlink if it has lost its magic
  if [[ ! -L ${build_app_mgmt_dir}/node/bin/npm ]]; then
    ( cd ${build_app_mgmt_dir}/node/bin && ln -fs ../lib/node_modules/npm/bin/npm-cli.js npm )
  fi
}

# $1: list of handlers, separated by whitespace
# $2: a handler name
# Prints $2 if $2 appears in the list. Otherwise prints ""
function isHandlerEnabled() {
  for i in $1; do
    if [[ "$i" == "$2" ]]; then
      echo "$2"
      return
    fi
  done
  echo ""
}

# Prune the handlers in $BUILD_DIR: delete the node_modules folder of any handler
# that is not enabled in the environment. Copy the app_management Node runtime
# if necessary.
function setupHandlerBinaries() {
  [[ "$enabled_handlers" ]] || enabled_handlers=$($BP_DIR/lib/print_enabled_handlers.rb)
  local handlers_list=$(echo $enabled_handlers | sed 's/\s/, /g')
  if [ "$handlers_list" != "" ]; then
    info "The following utilities are configured to be enabled and will be installed now: $handlers_list"
  fi

  for dir in $BUILD_DIR/.app-management/handlers/start-*; do
    base=$(basename $dir) # start-foo
    name=${base#start-}   # foo
    if [[ $(isHandlerEnabled "$enabled_handlers" "$name") == "" ]]; then
      # foo is not enabled; delete its binaries
      if [[ -d $dir/node_modules ]]; then
        rm -rf $dir/node_modules
      fi
    else
      # foo is enabled; indicate to user that it got installed
      info "  Installing utility: $name"
    fi
  done

  # Copy the app management's bundled Node runtime if necessary
  copyAppManagementNode
}

function generateAppMgmtInfo() {
  local CONTAINER="warden"
  local SSH_ENABLED="false"
  local PROXY_SUPPORTED='["v1", "v2"]'

  # Generate app management info file. proxy_enabled is set during startup.
cat > $BUILD_DIR/.app-management/app_mgmt_info.json << EOL
{
  "container": "$CONTAINER",
  "ssh_enabled": $SSH_ENABLED,
  "proxy_enabled": false,
  "proxy_supported_version": $PROXY_SUPPORTED
}
EOL

}

function installBMCmodule() {
  npm_install $BP_DIR/resources/rmu/bluemix-management-client
  # create enhanced copy of boot script
  createEnhancedStart ${BUILD_DIR}/vendor 'require("bluemix-management-client");'
}

function createEnhancedStart() {
  folder=$1
  header=$2
  boot_enhanced="$(basename $boot_js_file).enhanced"
  touch ${folder}/${boot_enhanced}
  cp $BUILD_DIR/$boot_js_file ${folder}/${boot_enhanced}
  add_header ${folder}/${boot_enhanced} "${header}"
}

function installAppManagement() {
  # Find boot script file
  boot_js_file=$($BP_DIR/bin/find_boot_script $BUILD_DIR)

  if [ "$boot_js_file" == "" ]; then
    info "WARN: App Management cannot be installed because the start command cannot be found."
    info "To install App Management utilities, specify a start command for your Swift application in 'Procfile'."
  else
  #  if test -f $BUILD_DIR/package.json; then
  #  dependencies=$(cat $BUILD_DIR/package.json | $BP_DIR/vendor/jq -r .dependencies)
  #    if [[ $dependencies == *"bunyan"* ]] || [[ $dependencies == *"log4js"* ]] || [[ $dependencies == *"ibmbluemix"* ]]; then
  #      # Install RMU utilities
  #      installBMCmodule
  #    fi
  #  fi

    # Install Dev mode utilities
    installAgent && setupHandlerBinaries && updateStartCommands && generateAppMgmtInfo
    status "installAppManagement end"
  fi
}

installAppManagement
