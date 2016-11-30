#!/usr/bin/env ruby
# IBM SDK for Node.js Buildpack
# Copyright 2014 the original author or authors.
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

require 'utils/simple_logger'

module Utils

  # Returns the list of enabled handlers set in the environment
  def Utils.get_enabled_handlers
    if ENV['ENABLE_BLUEMIX_DEV_MODE'] == 'TRUE' || ENV['ENABLE_BLUEMIX_DEV_MODE'] == 'true'
      %w{devconsole inspector shell}
    elsif !ENV['BLUEMIX_APP_MGMT_ENABLE'].nil?
      ENV['BLUEMIX_APP_MGMT_ENABLE'].downcase.split('+').map(&:strip)
    else
      nil
    end
  end

end
