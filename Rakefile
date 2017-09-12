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

require 'docker'
require 'rest-client'
require 'pry'
require 'json'
require 'nokogiri'
require 'test/unit'
require 'open-uri'
require_relative 'lib/helpers.rb'

include Test::Unit::Assertions

RELEASES_JSON_URL = ENV['RELEASES_JSON_URL'] || 'https://download.go.cd/experimental/releases.json'.freeze
BINARIES_DOWNLOAD_URL = ENV['BINARIES_DOWNLOAD_URL'] || 'https://download.go.cd/experimental/binaries'.freeze

IMAGE_PARAMS = { server: { path: File.expand_path('../gocd-server'), tag: 'gocd-server-for-bc-test' },
                 agent: { path: File.expand_path('../gocd-agent'), tag: 'gocd-agent' } }.freeze
PIPELINE_NAME = 'testpipeline'.freeze

@last_sync_time = nil
@urls=nil
Docker.url='unix:///var/run/docker.sock'

desc 'clean all images'
task :clean do
  Docker::Container.all.each do |container|
    container.delete(:force => true)
  end
  sh ("docker rm -f $(docker ps -qa) || true")
  Docker::Image.all.each do |image|
    image.remove(:force => true)
  end
  Docker::Volume.all.each do |vol|
    vol.remove(:force => true) if vol.info['Mountpoint'].nil?
  end
  sh("docker volume rm $(docker volume ls -qf dangling=true) || true" )
end

desc 'create server and agent image'
task :init do
  json = JSON.parse(open(RELEASES_JSON_URL).read)
  version, release = json.select {|x| x['go_version'] == ENV['GO_VERSION']}.sort {|a, b| a['go_build_number'] <=> b['go_build_number']}.last['go_full_version'].split('-')
  GO_VERSION = "#{version}-#{release}".freeze
  IMAGE_PARAMS.each do |identifier, parameter|
    puts "Creating a #{identifier} image from test version #{GO_VERSION}"
    t = identifier.to_s == 'agent' ? 'gocd-agent-centos-7:build_image' : 'build_image'
    cd (parameter[:path]).to_s do
      sh("GOCD_VERSION=#{version} GOCD_FULL_VERSION=#{GO_VERSION} GOCD_#{identifier.to_s.upcase}_DOWNLOAD_URL='#{BINARIES_DOWNLOAD_URL}/#{GO_VERSION}/generic/go-#{identifier.to_s}-#{GO_VERSION}.zip' TAG=#{parameter[:tag]} rake #{t}")
    end
  end
end

desc 'docker compose'
task :compose do
  sh('chmod 777 dependencies/go-primary/init.sh')
  sh('chmod 777 dependencies/go-secondary/init.sh')
  sh('docker-compose up -d')
end

desc 'verify agent registered to server'
task :verify_setup do
   puts "Waiting for the primary/secondary server to start......."
   @urls = %w(primarygo secondarygo).each_with_object({}) do |service, url|
            url[service] = Hash.new
            container_ports = Docker::Container.all.collect {|container| container.info['Ports'] if container.info['Labels']['com.docker.compose.service'].include?service}
            container_ports.each do |ports|
              if !ports.nil?
                ports.each do |port|
                  url[service].merge!("site_url": "http://localhost:#{port['PublicPort']}/go") if port['PrivatePort'] == 8153
                  url[service].merge!("secure_site_url": "https://localhost:#{port['PublicPort']}/go") if port['PrivatePort'] == 8154
                end
              end
            end
            url
          end

    wait_to_start("#{@urls['primarygo'][:site_url]}/admin/agent")
    wait_to_start("#{@urls['secondarygo'][:site_url]}/add-on/business-continuity/admin/dashboard")
    puts "Successfully started the primary and secondary servers"
end

desc 'setup oAuth client on primary server'
task :setup_oauth_client do
  client_name = JSON.parse(open("#{@urls['secondarygo'][:site_url]}/add-on/business-continuity/admin/dashboard.json").read)['syncErrors'][0].split("'")[1]
  new_oauth = RestClient::Request.execute(
                  method: :GET,
                  url: "#{@urls['primarygo'][:secure_site_url]}/oauth/admin/clients/new",
                  :verify_ssl => false)
  authenticity_token = Nokogiri::HTML(new_oauth.body).xpath("//input[@name='authenticity_token']/@value").to_s
  begin
    RestClient::Request.execute(
                    method: :POST ,
                    url: "#{@urls['primarygo'][:secure_site_url]}/oauth/admin/clients",
                    :payload => {"client[name]" => client_name, "client[redirect_uri]" => "#{@urls['secondarygo'][:site_url]}/add-on/business-continuity/admin/setup", "authenticity_token" => "#{authenticity_token}"},
                    :cookies => new_oauth.cookies, :verify_ssl => false)
  rescue RestClient::ExceptionWithResponse => err
    assert err.response.code == 302
    err.response.follow_redirection
  end
  puts "oAuth client setup on the primary server"
end

desc 'setup oAuth and verify sync on secondary server'
task :verify_sync do
  response = RestClient.get("#{@urls['secondarygo'][:site_url]}/add-on/business-continuity/admin/setup")
  assert response.code == 200
  if synced?
    response = RestClient.get("#{@urls['secondarygo'][:site_url]}/add-on/business-continuity/admin/dashboard.json")
    @last_sync_time = JSON.parse(response.body,:symbolize_names => true)[:primaryServerDetails][:lastConfigUpdateTime]
  end
  puts "Initial Sync successfull"
end

desc 'Create a pipeline on primary and wait for it to pass and then verify sync is successfull'
task :update_primary_state do
  url = "#{@urls['primarygo'][:site_url]}/api/admin/pipelines"
  sh(%Q{curl -sL -w "%{http_code}" -X POST  -H "Accept: application/vnd.go.cd.v3+json" -H "Content-Type: application/json" --data "@pipeline.json" #{url} -o /dev/null})
  url = "#{@urls['primarygo'][:site_url]}/api/pipelines/#{PIPELINE_NAME}/unpause"
  sh(%Q{curl -sL -w "%{http_code}" -X POST  -H "Accept:application/vnd.go.cd.v1+text" -H "CONFIRM:true" #{url} -o /dev/null})
  url = "#{@urls['primarygo'][:site_url]}/api/pipelines/#{PIPELINE_NAME}/schedule"
  sh(%Q{curl -sL -w "%{http_code}" -X POST -H "Accept:application/vnd.go.cd.v1+text" -H "CONFIRM:true" #{url} -o /dev/null})
  check_pipeline_status
end

desc 'verify sync on secondary server after an update on primary server - Check for timestamp'
task :verify_sync_with_timestamp do
  if synced?
    response = RestClient.get("#{@urls['secondarygo'][:site_url]}/add-on/business-continuity/admin/dashboard.json")
    assert @last_sync_time < JSON.parse(response.body,:symbolize_names => true)[:primaryServerDetails][:lastConfigUpdateTime]
  end
  puts "Sync after primary server changes successfull"
end

task :default do
  begin #:clean, :init,
    [:clean, :init, :compose, :verify_setup, :setup_oauth_client, :verify_sync, :update_primary_state, :verify_sync_with_timestamp].each {|t|
      Rake::Task["#{t}"].invoke
    }
  rescue => e
    raise "BC testing failed. Error message #{e.message}"
  ensure
    Rake::Task["clean"].reenable
    Rake::Task["clean"].invoke
  end
end
