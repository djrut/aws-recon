#!/usr/bin/env ruby
require 'aws-sdk-core'
require 'trollop'
require 'oj'

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
              elasticache: Aws::ElastiCache::Client.new
}

# Load service definitions
metadata  = Oj.load_file("services.json")

# Function definitions

def print_section_header(args={})
  title   = args[:title]
  status  = args[:status]    
  printf "\n"
  if status
    printf "= SUMMARY for: %-20s\n",title
  else
    printf "= NO DATA for: %-20s\n",title
  end
  printf "==============\n"
end

def print_column_labels(args={})
  name        = args[:name]
  attributes  = args[:attributes]
  printf "\n"
  attributes.each {|attribute| printf "%-#{attribute[:width]}s", attribute[:column]}
  printf "\n"
  attributes.each {|attribute| printf "%-#{attribute[:width]}s", "-" * attribute[:column].size}
  printf "\n"
end

def print_totals(args={})
  attributes  = args[:attributes]
  totals      = args[:totals]

  attributes.each {|attribute| printf "%-#{attribute[:width]}s", "-" * attribute[:column].size}

  printf "\n"

  attributes.each do |attribute|
    if attribute[:count]
      printf "%-#{attribute[:width]}s",totals[:count]
    elsif totals[attribute[:target]]
      printf "%-#{attribute[:width]}s",totals[attribute[:target]] 
    else
      printf "%-#{attribute[:width]}s","N/A"
    end
  end
  printf "\n"
  attributes.each {|attribute| printf "%-#{attribute[:width]}s","-" * attribute[:column].size}
  printf "\n"
end

def print_data(args={})
  data        = args[:data]
  attributes  = args[:attributes]

  sum = {}
  sum[:count] = 0

  data.each do |datum|
    i         = 0 
    continue  = true
    while continue
      continue = false
      attributes.each do |attribute|
        case attribute[:type]
        when :unary
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
        when :list  
          item = datum[attribute[:collection]][i]
          if item
            if attribute[:stub]
              output = item[attribute[:stub]][attribute[:target]]
            else
              output = item[attribute[:target]]
            end
            continue = true if i < datum[attribute[:collection]].size - 1
          end
        else
        end
        printf "%-#{attribute[:width]}s", output.to_s.slice(0,attribute[:width]-1)

        if attribute[:sum]
          sum[attribute[:target]] = 0 if sum[attribute[:target]].nil?
          sum[attribute[:target]] += output.to_i
        end
      end
      i += 1
      puts "\n"
    end
    sum[:count] += 1
  end
  return sum
end

# Main loop
metadata[:services].each do |service|
  section_name    = service[:name] 
  attributes      = service[:attributes]
  collection      = service[:collection]
  client          = clients[service[:client]]
  description     = client.send(service[:describe_method])

  if description[collection].any?
    print_section_header({status: true, title: section_name})
    print_column_labels({name: section_name, attributes: attributes})

    total_rows  = 0
    totals      = {}

    if section_name == "EC2"
      description.reservations.each do |reservation|
        totals = print_data({data: reservation.instances, attributes: attributes}) 
        total_rows += totals[:count]
      end
      totals[:count] = total_rows
    else
      totals = print_data({data: description[collection], attributes: attributes}) 
    end
    print_totals({attributes: attributes, totals: totals })
  else
    print_section_header({status: false, title: section_name})
  end
end
