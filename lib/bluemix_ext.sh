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

install_ibm_node() {
  local version="$1"
  local dir="$2"

  # Resolve node version using 'node-version-resolver' within the buildpack if resolution is needed
  if needs_resolution "$version"; then
    echo "Resolving node version ${version:-(latest stable)} via 'node-version-resolver'"
    version=$($BP_DIR/bin/node $BP_DIR/lib/node-version-resolver/index.js "$version")
  fi

  if [[ ${FIPS_MODE,,} == "true" ]]; then
    # The FIPS-enabled IBM SDK for Node.js must be in the cache
    fips_file=$BP_DIR/admin_cache/node/v$version/fips-node-v$version-linux-x64.tar.*
    verify_fips $fips_file
    echo "Installing FIPS-enabled IBM SDK for Node.js ($version) from cache"
    tar xf $fips_file -C /tmp
  elif [ -f $BP_DIR/admin_cache/node/v$version/node-v$version-linux-x64.tar.* ]; then
    # Try fetch IBM node runtime from admin cache
    echo "Installing IBM SDK for Node.js ($version) from cache"
    tar xf $BP_DIR/admin_cache/node/v$version/node-v$version-linux-x64.tar.* -C /tmp
  else
    # Download node from Heroku's S3 mirror of nodejs.org/dist
    echo "Downloading and installing node $version..."
    node_url="https://s3pository.heroku.com/node/v$version/node-v$version-linux-x64.tar.gz"
    curl $node_url --silent --fail --retry 5 --retry-max-time 15 -o - | tar xzf - -C /tmp >/dev/null 2>&1 || (echo "Unable to download node $version; does it exist?" && false)
  fi

  rm -rf $dir/*
  mv /tmp/node-v$version-linux-x64/* $dir
  chmod +x $dir/bin/*
}

verify_fips () {
  local fips_file="$1"
  if [ ! -f $fips_file ]; then
    FIPS_VERSIONS=""
    for i in `ls $BP_DIR/admin_cache/node`; do
      if [ -f $BP_DIR/admin_cache/node/$i/fips-* ]; then
        FIPS_VERSIONS=$FIPS_VERSIONS" $i"
      fi
    done
    warning "FIPS_MODE is enabled, but the specified node version ($version) is not FIPS-enabled" "Current FIPS-enabled versions: [$FIPS_VERSIONS ]"
    exit 1
  fi
  if [ "$BLUEMIX_APP_MGMT_ENABLE" != "" ]; then
    warning "Setting FIPS_MODE and BLUEMIX_APP_MGMT_ENABLE at the same time is not supported" "To use FIPS_MODE, unset BLUEMIX_APP_MGMT_ENABLE"
    exit 1
  fi
  if [ "$ENABLE_BLUEMIX_DEV_MODE" != "" ]; then
    warning "FIPS_MODE and development mode are not supported at the same time" "To use FIPS_MODE, unset ENABLE_BLUEMIX_DEV_MODE"
    exit 1
  fi
}

install_app_management() {
  # Install App Management
  if ! [[ ${BLUEMIX_APP_MGMT_INSTALL,,} == "false" ]]; then
    if ! [[ ${INSTALL_BLUEMIX_APP_MGMT,,} == "false" ]]; then
      status "Installing App Management"
      source $BP_DIR/bin/app_management.sh
      status "Installed App Management???????????"
      # We may have to tweak the different handlers... see the handlers for node and liberty and compare them
      # we may need a subset of all of these handlers for an MVP...
    fi
  fi
}

npm_install() {
  module=$1
  version=$2

  cd $BUILD_DIR
  # actually using BUILD_DIR/vendor/node/bin/npm, which is set on PATH
  if [ -z $version ]; then
    npm install $module --unsafe-perm --quiet --userconfig $BUILD_DIR/.npmrc 2>&1 | output "$LOG_FILE"
  else
    npm install $module@"$version" --unsafe-perm --quiet --userconfig $BUILD_DIR/.npmrc 2>&1 | output "$LOG_FILE"
  fi
}

add_header_to_bootscript(){
  header=$1
  header_for=$2
  boot_js_file=$($BP_DIR/bin/find_boot_script $BUILD_DIR)
  if [ "$boot_js_file" != "" ]; then
    echo "Found start script: $boot_js_file" | output "$LOG_FILE"
    add_header $BUILD_DIR/$boot_js_file "${header}"
  else
    info "WARN: Failed to add 'require' headers to your start script for ${header_for}."
    info "WARN: Specify your start script in 'package.json' or 'Procfile'."
  fi
}

add_header(){
  file=$1
  header=$2
  filename="$(basename $file)"
  info "Add header to $filename: $header"
  # check for any shebangs in the start script, insert require headers after the last shebang
  # if no shebangs exist, it inserts at the top of the file
  line=$(($(echo $(sed -n '/^#!/ =' $file) | sed -e 's/.*\(.\)$/\1/') + 1))
  sed -i "${line}i $header" $file
}

warn_npmrc_registry_override() {
  local build_dir=${1:-}
  # if environment var is set && .npmrc exists && .npmrc includes registry, show warning
  if [ -z "$NPM_CONFIG_REGISTRY" ] || [ -z "$npm_config_registry" ]; then
    if [ -e "$build_dir/.npmrc" ]; then
      if grep -iq '^\s*registry\s*\=\s*.*' $build_dir/.npmrc; then
        info "WARN: 'registry' in the app's '.npmrc' file is overridden by NPM_CONFIG_REGISTRY"
      fi
    fi
  fi
}
