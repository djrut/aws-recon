#!/usr/bin/env ruby
require 'aws-sdk-core'
require 'trollop'
require 'oj'

class AWSService
  def initialize(args={})
    @metadata     = args[:metadata]
    @clients      = args[:clients]

    @attributes       = @metadata[:attributes]
    @collection       = @metadata[:collection]
    @describe_method  = @metadata[:describe_method]
    @client           = @clients[@metadata[:client]] 
    @describe_output      = @client.send(@describe_method) 
    @totals           = Hash.new
  end

  def fetch
    @describe_output = @client.send(@describe_method)
  end

  def has_items?
    @describe_output[@collection].any?
  end

  def set_title(args={})
    status  = args[:status]    
    table   = args[:table]

    puts "DEBUG: #{@attributes}"

    if status
      table.title = "= SUMMARY for: " + @metadata[:name]
    else
      table.title = "= NO DATA for: " + @metadata[:name]
    end
  end

  def set_column_labels(args={})
    table   = args[:table]
    @attributes.each {|attribute| table.label.push(attribute[:column_name])}
  end

  def set_totals(args={})
    table  = args[:table]  

    @attributes.each do |attribute|
      if attribute[:count]
        table.sum.push(@totals[:count])
      elsif @totals[attribute[:target]]
        table.sum.push(@totals[attribute[:target]])
      else
        table.sum.push("N/A")
      end
    end
  end
end

class Table
  attr_accessor :title

  def initialize(args={})
    @col    = 0
    @row    = 0
    @title  = "Empty table"
    @header = Array.new
    @sum    = Array.new
    @matrix = Array.new
  end

  def next_col
    @col += 1
  end

  def next_row
    @row += 1
  end

  def push(args={})
    @matrix[@row][@col] = args[:data]
  end

  def pop
    @matrix[@row][@col]
  end

  def render
    puts @header.join(",") 
    @matrix.each {|item| puts item.join(",")}
    puts @sum.join(",")
  end
end


# Parse options
opts = Trollop::options do
  version "aws-recon v0.1 (c) 2015 Duncan Rutland"
  opt :region, "AWS Region to perform scan on", short: "-r", type: String, required: true
  opt :config, "Specify alternative configuration file", short: "-c", default: "services.json", type: String
  opt :profile, "Specify AWS credential profile name", short: "-p", type: String
  opt :role, "ARN for role to assume", short: "-R", type: String
  opt :extid, "External ID for STS Assume Role", short: "-x", type: String
  depends :role, :extid
  conflicts :profile, :role
  conflicts :profile, :extid
end

Trollop::die :config, "must exist" unless File.exist?(opts[:config]) if opts[:config]

# Set region
Aws.config.update({region: opts[:region]})

# Determine whether we are using role assumption or local .aws/credentials profile
if opts[:role] then
  creds = Aws::AssumeRoleCredentials.new({role_arn: opts[:role], role_session_name: "aws-recon", external_id: opts[:extid]})
elsif opts[:profile] then
  creds = Aws::SharedCredentials.new(profile_name: opts[:profile])
else
  creds = Aws::SharedCredentials.new(profile_name: "default")
end

# Apply appropriate credentials configuration
Aws.config.update({credentials: creds})

# Populate hash with AWS SDK client objects
clients   = { ec2: Aws::EC2::Client.new,
                  elb: Aws::ElasticLoadBalancing::Client.new,
                  rds: Aws::RDS::Client.new,
                  elasticache: Aws::ElastiCache::Client.new }

# Load service definitions
metadata  = Oj.load_file("services.json")

# Function definitions

def parse_data(args={})
  data        = args[:data]
  table       = args[:table]
  service     = args[:service]

  data.each do |datum|
    i         = 0 
    continue  = true

    # Iterate row by row until no more data to display
    while continue
      continue = false
      service.attributes.each do |attribute|
        case attribute[:type]
        when :scalar
          if i.zero?
            if attribute[:stub]
              output = datum[attribute[:stub]][attribute[:target]]
            else
              output = datum[attribute[:target]]
            end
          else
            output = ""
          end
        when :tags  
          tag = datum[attribute[:stub]][i]
          if tag
             output = tag.key + " = " + tag.value
             continue = true if i < datum[attribute[:stub]].size - 1
          end
        when :array
          parse_data({data: datum, table: table, service: service})
        end

        table.push(output.to_s)

        if attribute[:sum]
          service.sum[attribute[:target]] = 0 if service.sum[attribute[:target]].nil?
          service.sum[attribute[:target]] += output.to_i
        end
        table.next_col
      end
      i += 1
      puts "\n"
    end
    service.sum[:count] += 1
    table.next_row
  end
end

# Main loop
metadata[:services].each do |item|
  puts "Starting main loop for #{item}"
  service = AWSService.new({ metadata: item, clients: clients })
  output  = Table.new

  if service.has_items?
    service.set_title({status: true, table: output})
    print_column_labels({name: service.name, attributes: service.attributes})

    total_rows  = 0

    if service.name == "EC2"
      service.describe_output.reservations.each do |reservation|
        parse_data({ data: reservation.instances, service: service, table: output }) 
      end
    else
      parse_data({data: describe_output[collection], service: service, table: output}) 
    end
    service.set_totals({table: output})
    
    output.render
  else
    service.set_title({status: false, table: output})
  end
end
