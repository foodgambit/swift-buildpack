# Encoding: utf-8
# IBM SDK for Node.js Buildpack
# Copyright 2014-2015 the original author or authors.
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

require 'json'

class BootScriptFinder
  def initialize(app_dir)
    @app_dir = app_dir
  end

  def find_boot_script
    procfile_file = @app_dir + 'Procfile'
    package_json_file = @app_dir + 'package.json'

    boot_js_file_name = nil

    if (File.exist?(procfile_file))
      procfile_content = ''
      File.open(procfile_file,'r') do |file|
        while line = file.gets
          procfile_content += line
        end
      end
      if (matched = /web:\s+(.+)/.match(procfile_content))
        start_cmd = matched[1]
      end
    else
      start_cmd = 'npm start'
    end

    if (File.exist?(package_json_file))
      package_json = JSON.parse(File.read(package_json_file))
    end

    # check "node xxx"
    boot_js_file_name = check_node_command(start_cmd, package_json)

    # if not found, check "npm start"
    if (boot_js_file_name == nil && start_cmd =~ /npm\s+start/)
      if (package_json && package_json['scripts'] && package_json['scripts']['start'])
        boot_js_file_name = check_node_command(package_json['scripts']['start'], package_json)
      else
        boot_js_file_name = 'server.js'
      end
    end

    if (boot_js_file_name == nil || !File.exists?(@app_dir + boot_js_file_name))
      raise
    end

    return boot_js_file_name
  end

  private

  def resolve_boot_js_file_name(name)
    if (name !~ /\S+\.js\b/) && ( !File.exists?(@app_dir + name) || File.directory?(@app_dir+name) )
      name += '.js'
    end
    return name
  end

  def check_node_command(start_cmd, package_json)
    boot_js_file_name = nil
    if start_cmd.is_a?(String)
    	start_cmd.gsub!(/(\s-\S*)/,'')
    end
    if (matched = /node\s+(\S+)/.match(start_cmd) || /node-hc\s+(\S+)/.match(start_cmd))
      boot_js_file_name = matched[1]
      # if start command is "node .", look for the "main" in package.json
      if (boot_js_file_name == '.')
        if (package_json && package_json['main'])
          # the value of main maybe "app" or "app.js"
          boot_js_file_name = resolve_boot_js_file_name(package_json['main'])
        else
          # if "main" is not specified, use "index.js"
          boot_js_file_name = 'index.js'
        end
      else  # start command is "node app.js", or "node app"
        boot_js_file_name = resolve_boot_js_file_name(boot_js_file_name)
      end
    end
    return boot_js_file_name
  end

end