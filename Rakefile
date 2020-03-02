##########################################################################
# Copyright 2018 ThoughtWorks, Inc.
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
require 'fileutils'
require_relative 'lib/helpers.rb'

include Test::Unit::Assertions

RELEASES_JSON_URL = ENV['RELEASES_JSON_URL'] || 'https://download.go.cd/experimental/releases.json'.freeze
BINARIES_DOWNLOAD_URL = ENV['BINARIES_DOWNLOAD_URL'] || 'https://download.go.cd/experimental/binaries'.freeze
PIPELINE_NAME = 'testpipeline'.freeze
GO_VERSION = env('GO_VERSION')

@last_sync_time = nil
@urls = nil
Docker.url = 'unix:///var/run/docker.sock'

desc 'clean all images'
task :clean do
  Docker::Container.all.each do |container|
    container.delete(force: true)
  end
  sh 'docker rm -f $(docker ps -qa) || true'
  Docker::Image.all.each do |image|
    image.remove(force: true)
  end
  Docker::Volume.all.each do |vol|
    vol.remove(force: true) if vol.info['Mountpoint'].nil?
  end
  sh('docker volume rm $(docker volume ls -qf dangling=true) || true')
  success 'Volume mounts successfully deleted.'
end

task :clean_godata_dir do
  %w[go-primary go-secondary go-agent].each do |server_dir|
    %w[artifacts config db logs plugins].each do |dir|
      dir_name = "#{Dir.pwd}/dependencies/#{server_dir}/#{dir}"
      FileUtils.rm_rf(dir_name) if File.exist?(dir_name)
    end
  end
end

desc 'Pull the experimental server and agent image to be tested and tag it for bc test'
task :init do
  json = JSON.parse(open(RELEASES_JSON_URL).read)
  version, release = json.select { |x| x['go_version'] == GO_VERSION }.sort_by { |a| a['go_build_number'].to_i }.last['go_full_version'].split('-')
  GO_FULL_VERSION = "#{version}-#{release}".freeze
  info "Pulling GoCD server and agent image for version #{GO_FULL_VERSION}"
  sh "docker pull gocdexperimental/gocd-server-centos-8:v#{GO_FULL_VERSION}"
  sh "docker pull gocdexperimental/gocd-agent-alpine-3.9:v#{GO_FULL_VERSION}"
  sh "docker tag gocdexperimental/gocd-server-centos-8:v#{GO_FULL_VERSION} gocd-server:gocd-server-for-bc-test"
  sh "docker tag gocdexperimental/gocd-agent-alpine-3.9:v#{GO_FULL_VERSION} gocd-agent:gocd-agent-for-bc-test"
end

desc 'docker compose'
task :compose do
  sh('chmod 777 dependencies/go-primary/init.sh')
  sh('chmod 777 dependencies/go-secondary/init.sh')
  sh('chmod 777 dependencies/go-agent/init.sh')
  sh('docker-compose up -d')
end

desc 'verify agent registered to server'
task :verify_setup do
  info 'Waiting for the primary and secondary server to start.'
  @urls = %w[primarygo secondarygo].each_with_object({}) do |service, url|
    server_url = {}
    container_ports = Docker::Container.all.collect { |container| container.info['Ports'] if container.info['Labels']['com.docker.compose.service'].include? service }
    container_ports.each do |ports|
      next if ports.nil?
      ports.each do |port|
        info port
        server_url['site_url'] = "http://localhost:#{port['PublicPort']}/go" if port['PrivatePort'] == 8153
        server_url['secure_site_url'] = "https://localhost:#{port['PublicPort']}/go" if port['PrivatePort'] == 8154
      end
    end
    url[service] = server_url
    url
  end
  info "Server info: #{@urls}"
  wait_to_start(primary_url('/about', false))
  wait_to_start(secondary_url('', false))
  info 'Successfully started the primary and secondary servers.'
end

def primary_url(api_url, secure)
  (@urls['primarygo'][secure ? 'secure_site_url' : 'site_url']).to_s + api_url
end

def secondary_url(api_url, secure = false)
  (@urls['secondarygo'][secure ? 'secure_site_url' : 'site_url']).to_s + api_url
end

desc 'setup oAuth client on primary server'
task :setup_oauth_client do
  dashboard_json = RestClient::Request.execute(
    method: :GET,
    url: secondary_url('/add-on/business-continuity/admin/dashboard.json', false),
    user: 'admin',
    password: 'badger',
    cookies: new_oauth.cookies
  )

  client_name = JSON.parse(dashboard_json)['syncErrors'][0].split("'")[1]
  info "Client name #{client_name}"

  begin
    RestClient::Request.execute(
      method: :POST,
      url: primary_url('/oauth/admin/clients', true),
      payload: { 'client[name]' => client_name, 'client[redirect_uri]' => secondary_url('/add-on/business-continuity/admin/setup', false), 'authenticity_token' => authenticity_token.to_s },
      cookies: new_oauth.cookies, verify_ssl: false
    )
  rescue RestClient::ExceptionWithResponse => err
    assert err.response.code == 302
    err.response.follow_redirection
  end
  info 'oAuth client setup on the primary server.'
end

desc 'setup oAuth and verify sync on secondary server'
task :verify_sync do
  if synced?
    response = RestClient::Request.execute(
      url: secondary_url('/add-on/business-continuity/admin/dashboard.json', false),
      method: :GET,
      user: 'bc_token',
      password: 'badger'
    )
    @last_sync_time = JSON.parse(response.body, symbolize_names: true)[:primaryServerDetails][:lastConfigUpdateTime]
  end
  info 'Initial Sync successful.'
end

desc 'Create a pipeline on primary and wait for it to pass and then verify sync is successfull'
task :update_primary_state do
  info 'Creating new pipeline'
  curl_post(primary_url('/api/admin/pipelines', false), 'admin', 'badger', 'application/vnd.go.cd+json', '@pipeline.json')
  curl_post(primary_url("/api/pipelines/#{PIPELINE_NAME}/schedule", false), 'admin', 'badger', 'application/vnd.go.cd+json', '@pipeline.json')
  check_pipeline_status
end

desc 'verify sync on secondary server after an update on primary server - Check for timestamp'
task :verify_sync_with_timestamp do
  if synced?
    sleep 60
    response = RestClient::Request.execute(
      url: secondary_url('/add-on/business-continuity/admin/dashboard.json', false),
      method: :GET,
      user: 'bc_token',
      password: 'badger'
    )
    assert @last_sync_time < JSON.parse(response.body, symbolize_names: true)[:primaryServerDetails][:lastConfigUpdateTime]
  end
  puts 'Sync after primary server changes successful.'
end

task :default do
  begin
    %i[clean init compose verify_setup verify_sync update_primary_state verify_sync_with_timestamp].each do |t|
      Rake::Task[t.to_s].invoke
    end
  rescue StandardError => e
    raise "BC testing failed. Error message #{e.message}"
  ensure
    Rake::Task['clean'].reenable
    Rake::Task['clean'].invoke
  end
end
