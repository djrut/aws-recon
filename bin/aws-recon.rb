#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'
require 'aws-sdk-core'
require 'trollop'
require 'oj'
require './lib/AwsRecon.rb'

# Global variables
#
$debug          = false
$default_config = "data/services.json"

# Function definitions
#
def print_debug(args={})
  source  = args[:source]
  message = args[:message]
  puts "[DEBUG] #{source}: #{message}"
end

# Parse options
#
opts = Trollop::options do
  version "aws-recon v1.0 (c) 2016 Duncan Rutland"
  opt :region, "AWS Region to perform scan on", short: "-r", type: :string, required: true
  opt :config, "Specify alternative configuration file", long: "--config-file", short: "-c", default: "#{$default_config}", type: :string
  opt :format, "Specify output format #{AwsRecon::Table.formats}", long: "--output-format", short: "-f", default: "console", type: :string
  opt :group, "Specify which service group(s) to display", long: "--service-group", short: "-g", default: ["Compute","Network"], type: :strings
  opt :all, "Display data for all available service groups (equivalent to \"-g all\")", long: "--all", short: "-A", type: :flag
  opt :notags, "Disable display of tags for all services", long: "--no-tags", short: "-N", type: :flag
  opt :profile, "Specify AWS credential profile name", short: "-p", type: :string
  opt :role, "ARN for role to assume", short: "-R", type: :string
  opt :extid, "External ID for STS Assume Role", short: "-x", type: :string
  opt :debug, "Enable debugging output", long: "--enable-debug", short: "-D", default: false, type: :boolean 
  depends :role, :extid
  conflicts :profile, :role
  conflicts :profile, :extid
end

$debug  = true if opts[:debug]

# Exit if supplied configuration does not exist
#
if opts[:config]
  Trollop::die :config, "configuration path #{opts[:config]} does not exist!" unless File.exist?(opts[:config])
  #Trollop::die :config, "configuration path #{opts[:config]} is not a directory!" unless File.directory?(opts[:config])
end

# Load service definitions and populate directory hash
#
directory = Hash.new
metadata  = Oj.load_file(opts[:config])
metadata[:services].each do |service|
  directory[service[:name]] = service[:group].downcase
end

# Exit if a non-supported format is supplied
#
Trollop::die :format, "must be either #{AwsRecon::Table.formats}" unless AwsRecon::Table.formats.member?(opts[:format]) if opts[:format]

# Process group parameter and exit if not a valid group
#

opts[:group].map! {|item| item.downcase}

opts[:group] = directory.values.uniq if opts[:group].join == "all" || opts[:all]

opts[:group].each do |group|
  Trollop::die :group, "must be composed of one or more of the following: #{directory.values.uniq}" unless directory.values.uniq.member?(group)
end

# Populate array of services to process based on group settings
services = Array.new
metadata[:services].each do |item|
  services.push(item) if opts[:group].member?(item[:group].downcase)
end

# Set region
# Determine whether we are using role assumption or local .aws/credentials profile
#
begin
  Aws.config.update(region: opts[:region])
  if opts[:role] then
    creds = Aws::AssumeRoleCredentials.new( role_arn:          opts[:role],
                                            role_session_name: "aws-recon",
                                            external_id:       opts[:extid] )
  elsif opts[:profile] then
    creds = Aws::SharedCredentials.new(profile_name: opts[:profile])
  else
    creds = Aws::SharedCredentials.new(profile_name: "default")
  end
  # Apply appropriate credentials configuration
  Aws.config.update(credentials: creds)
rescue Aws::Errors::NoSuchProfileError => error
  puts "Profile configuration update failed: #{error.message}"
  exit 1
rescue Aws::STS::Errors::AccessDenied => error
  puts "Role assumption failed: #{error.message}"
  exit 1
end

# Populate hash with AWS SDK client objects
clients   = { ec2:            Aws::EC2::Client.new,
              iam:            Aws::IAM::Client.new,
              elb:            Aws::ElasticLoadBalancing::Client.new,
              rds:            Aws::RDS::Client.new,
              elasticache:    Aws::ElastiCache::Client.new,
              cloudformation: Aws::CloudFormation::Client.new,
              opsworks:       Aws::OpsWorks::Client.new }

# Main loop - iterate through AWS services within scope 
services.each do |item|
  print_debug(source: "#{__method__}", message: "Processing service #{item}") if $debug

  service     = AwsRecon::Service.new( metadata:  item,
                                       clients:   clients,
                                       notags:    opts[:notags] )

  output      = AwsRecon::Table.new( format: opts[:format].to_sym,
                                     notags: opts[:notags] )

  print_debug(source: "#{__method__}", message: "Service =  #{service}") if $debug
  if service.has_items?
    output.set_header(attributes:  service.attributes)

    output.set_title( status: true,
                      name:   service.name )

    if service.name =~ /EC2/
      service.data.each do |reservation|
        reservation.instances.each do |item|
          print_debug(source: "#{__method__}", message: "Item = #{item}") if $debug

          service.parse_datum( datum:      item,
                               attributes: service.attributes,
                               table:      output )

          output.new_row
        end
      end
    else
      service.data.each do |item|
        print_debug(source: "#{__method__}", message: "Item = #{item}") if $debug

        service.parse_datum( datum:      item,
                             attributes: service.attributes,
                             table:      output )

        output.new_row
      end
    end

    output.set_footer( attributes:  service.attributes,
                       totals:      service.totals )
  else
    print_debug(source: "#{__method__}", message: "Service has no items to process!") if $debug

    output.set_title( status: false,
                      name:   service.name )
  end
  output.render
end
