require 'Docker'
require 'rest-client'
require 'pry'
require 'Json'
require 'Nokogiri'
require 'test/unit'
require 'open-uri'

include Test::Unit::Assertions

GO_VERSION = ENV['GO_VERSION'] || (raise 'please provide the GO_VERSION environment variable')
IMAGE_PARAMS = { server: { path: File.expand_path('../gocd-docker/phusion/server'), tag: 'gocd-server-for-bc-test' },
                 agent: { path: File.expand_path('../gocd-docker/phusion/agent'), tag: 'gocd-agent' } }.freeze
LAST_SYNC_TIME = nil
PIPELINE_NAME = 'testpipeline'.freeze
@urls=nil
Docker.url='unix:///var/run/docker.sock'

desc 'clean all images'
task :clean do
  Docker::Container.all.each do |container|
    container.delete(:force => true)
  end
  Docker::Image.all.each do |image|
    image.remove(:force => true)
  end
end

desc 'create server and agent image'
task :init do
  IMAGE_PARAMS.each do |identifier, parameter|
    puts "Creating a #{identifier} image from test version #{GO_VERSION}"
    cd (parameter[:path]).to_s do
      sh("docker build --build-arg GO_VERSION=#{GO_VERSION} --build-arg DOWNLOAD_URL='https://download.go.cd/experimental/binaries' -t #{parameter[:tag]} .")
    end
  end
end

desc 'docker compose'
task :compose do
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

  wait_till_event_occurs_or_bomb 120, "Sync Failed" do
    response = RestClient.get("#{@urls['secondarygo'][:site_url]}/add-on/business-continuity/admin/dashboard.json")
    assert response.code == 200
    break if sync_successful?(JSON.parse(response.body,:symbolize_names => true))
  end
  response = RestClient.get("#{@urls['secondarygo'][:site_url]}/add-on/business-continuity/admin/dashboard.json")
  if LAST_SYNC_TIME.nil?
    LAST_SYNC_TIME = JSON.parse(response.body,:symbolize_names => true)[:primaryServerDetails][:lastConfigUpdateTime]
  else
    assert LAST_SYNC_TIME < JSON.parse(response.body,:symbolize_names => true)[:primaryServerDetails][:lastConfigUpdateTime]
  end

  puts "Sync successfull"
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
  wait_till_event_occurs_or_bomb 120, "Connect to : #{url}" do
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
          sleep 0.1
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

task default: [:clean, :init, :compose, :verify_setup, :setup_oauth_client, :verify_sync, :update_primary_state, :verify_sync]
