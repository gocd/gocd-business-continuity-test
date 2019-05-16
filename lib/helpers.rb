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
require 'json'
require 'nokogiri'
require 'test/unit'
require 'open-uri'

include Test::Unit::Assertions

def synced?
  wait_till_event_occurs_or_bomb 120, "Sync Failed" do
    response = RestClient::Request.execute(
        url: secondary_url('/add-on/business-continuity/admin/dashboard.json', false),
        method: :GET,
        user: 'bc_token',
        password: 'badger'
    )
    assert response.code == 200
    break if sync_successful?(JSON.parse(response.body, :symbolize_names => true))
  end
  true
end

def sync_successful? (response)
  (response[:primaryServerDetails].select {|key, value| value[:md5] == response[:standbyServerDetails][key] if value.is_a?(Hash)}.size == 6) && (response[:syncErrors].empty?)
end

def check_pipeline_status
  begin
    Timeout.timeout(180) do
      while (true) do
        sleep 5
        response = RestClient::Request.execute(
            url: primary_url('/api/dashboard', false),
            method: :GET,
            user: 'admin',
            password: 'badger',
            :headers => {accept: 'application/vnd.go.cd.v2+json'}
        )
        
        runs = JSON.parse(response.body)
        begin
          status = runs["_embedded"]["pipelines"][0]["_embedded"]["instances"][0]["_embedded"]["stages"][0]["status"]
        rescue StandardError
          p 'Pipeline still not started building, Waiting...'
        end
        if status == 'Passed'
          puts 'Pipeline completed with success'
          break
        end

        p "Pipeline status #{status}"
      end
    end
  rescue Timeout::Error => e
    raise 'Pipeline was not built successfully'
  end
end


def wait_to_start(url)
  wait_till_event_occurs_or_bomb 300, "Connect to : #{url}" do
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

def success str
  puts "[32m=>[0m #{str}"
end

def info str
  puts "[36m=>[0m #{str}"
end

def abort(str)
  puts "[31m=>[0m #{str}"
  raise ArgumentError
end

def env(key)
  value = ENV[key].to_s.strip
  if value == ''
    abort("Environment variable #{key} must be specified.")
  end
  value
end

def basic_auth(password, username)
  unless username.nil? && password.nil?
    "-u'#{username}:#{password}'"
  else
  ''
  end
end

def curl_get(url, username, password, content_type)
  info "executing curl request #{url} with basic_auth(#{username},#{password})"
  sh(%Q{curl #{basic_auth(password, username)} -sL -w "%{http_code}" -H "#{content_type}" -H "Content-Type: application/json" #{url} -o /dev/null})
end

def curl_post(url, username, password, content_type, data)
  sh(%Q{curl #{basic_auth(password, username)} -sL -w "%{http_code}" -X POST -H "CONFIRM:true" -H "Accept:#{content_type}" -H "Content-Type: application/json" -H "X-GoCD-Confirm" --data #{data} #{url} -o /dev/null})
end
