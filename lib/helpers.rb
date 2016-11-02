##########################################################################
# Copyright 2016 ThoughtWorks, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################

require 'rest-client'
require 'pry'
require 'Json'
require 'Nokogiri'
require 'test/unit'
require 'open-uri'

include Test::Unit::Assertions

def synced?
  wait_till_event_occurs_or_bomb 120, "Sync Failed" do
    response = RestClient.get("#{@urls['secondarygo'][:site_url]}/add-on/business-continuity/admin/dashboard.json")
    assert response.code == 200
    break if sync_successful?(JSON.parse(response.body,:symbolize_names => true))
  end
  true
end

def sync_successful? (response)
  (response[:primaryServerDetails].select{|key,value| value[:md5] == response[:standbyServerDetails][key] if value.is_a?(Hash)}.size == 7) && (response[:oauthSetupStatus] == 'success') && (response[:syncErrors].empty?)
end

def check_pipeline_status
  begin
    Timeout.timeout(180) do
      while(true) do
        sleep 5
        runs = JSON.parse(open("#{@urls['primarygo'][:site_url]}/api/dashboard",'Accept' => 'application/vnd.go.cd.v1+json').read)
        if runs["_embedded"]["pipeline_groups"][0]["_embedded"]["pipelines"][0]["_embedded"]["instances"][0]["_embedded"]["stages"][0]["status"]  == 'Passed'
          puts 'Pipeline completed with success'
          break
        end
      end
    end
  rescue Timeout::Error => e
    raise 'Pipeline was not built successfully'
  end
end


def wait_to_start(url)
  wait_till_event_occurs_or_bomb 180, "Connect to : #{url}" do
      begin
        break if running?(url)
      rescue Errno::ECONNREFUSED
        sleep 5
      end
    end
end

def wait_till_event_occurs_or_bomb(wait_time, message)
      Timeout.timeout(wait_time) do
        loop do
          yield if block_given?
          sleep 5
        end
      end
    rescue Timeout::Error
      raise "The event did not occur - #{message}. Wait timed out"
end


def running?(url)
  begin
    ping(url).code == 200
  rescue => e
    false
  end
end

def ping(url)
  RestClient.get("#{url}")
end
