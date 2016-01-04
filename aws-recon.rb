#!/usr/bin/env ruby
require 'aws-sdk-core'
require 'trollop'
require 'oj'

# Constants
DEBUG = false

class AWSService
  attr_accessor :name, :attributes, :describe_output, :totals

  def initialize(args={})
    @metadata         = args[:metadata]
    @clients          = args[:clients]

    @name             = @metadata[:name]
    @attributes       = @metadata[:attributes]
    @collection       = @metadata[:collection_name]
    @describe_method  = @metadata[:describe_method]
    @client           = @clients[@metadata[:client]] 
    @describe_output  = @client.send(@describe_method) 
    @totals           = { count: 0 }
  end

  def fetch_collection
    @describe_output = @client.send(@describe_method)
    return @describe_output[@collection]
  end

  def has_items?
    @describe_output[@collection].any?
  end

  def num_items
    @describe_output[@collection].size
  end

  def set_title(args={})
    status  = args[:status]    
    table   = args[:table]

    if status
      table.title = "= SUMMARY for: " + @metadata[:name]
    else
      table.title = "= NO DATA for: " + @metadata[:name]
    end
  end

  def set_totals(args={})
    table  = args[:table]  

    @attributes.each do |attribute|
      if attribute[:count]
        table.footer.push(@totals[:count])
      elsif @totals[attribute[:target]]
        table.footer.push(@totals[attribute[:target]])
      else
        table.footer.push("N/A")
      end
    end
  end
end

class Table
  attr_accessor :title, :header, :footer, :tabs
  MAX_ROWS = 128

  def initialize(args={})
    @num_rows = args[:rows] || MAX_ROWS
    @col    = 0
    @row    = 0
    @head   = 0
    @tail   = 0
    @title  = "Empty table"
    @header = Array.new
    @tabs   = Array.new
    @footer = Array.new
    @matrix = Array.new(@num_rows) { Array.new }
  end

  def next_col
    @col += 1
  end

  def next_row
    @row += 1
    @tail = [@row,@tail].max
    puts "[DEBUG] Table.next_row: setting row = #{@row} tail = #{@tail}" if DEBUG 
  end

  def new_row
    puts "[DEBUG] Table.new_row: old head = #{@head} old tail = #{@tail}" if DEBUG
    @head = @tail + 1
    @row  = @head
    @tail = @head
    @col  = 0
    puts "[DEBUG] Table.new_row: new head = #{@head} new tail = #{@tail}" if DEBUG
  end

  def reset_row
    @row = @head
  end

  def push(args={})
    puts "DEBUG [Table.push]: data = #{args[:data]}, row = #{@row}, col = #{@col}" if DEBUG
    @matrix[@row][@col] = args[:data]
  end

  def pop
    @matrix[@row][@col]
  end

  def render
    printf "\n"
    printf @title

    printf "\n"
    @tabs.each_with_index do |tab,index|
      printf "%-#{tab}s", @header[index]
    end

    printf "\n"
    @tabs.each_with_index do |tab,index|
      printf "%-#{tab}s", "-" * @header[index].size
    end

    printf "\n"
    @matrix.each do |row|
      if !row.empty?
        @tabs.each_with_index do |tab, index|
          printf "%-#{tab}s", row[index]
        end
        printf "\n"
      end
    end

    @tabs.each_with_index do |tab,index|
      printf "%-#{tab}s", "-" * @header[index].size
    end

    printf "\n"
    @tabs.each_with_index do |tab,index|
      printf "%-#{tab}s", @footer[index]
    end
    printf "\n"
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
  opt :debug, "Enable debugging output", short: "-D", default: false, type: :boolean 
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

DEBUG = true if opts[:debug]

# Apply appropriate credentials configuration
Aws.config.update({credentials: creds})

# Populate hash with AWS SDK client objects
clients   = { ec2:          Aws::EC2::Client.new,
              elb:          Aws::ElasticLoadBalancing::Client.new,
              rds:          Aws::RDS::Client.new,
              elasticache:  Aws::ElastiCache::Client.new }

# Load service definitions
metadata  = Oj.load_file("services.json")

# Function definitions

def parse_table_attributes(args={})
  table       = args[:table]
  attributes  = args[:attributes]

  puts "+ DEBUG [parse_table_attributes]: Parsing  attributes array #{attributes}" if DEBUG

  attributes.each do |attribute|
    puts "++ DEBUG [parse_table_attributes]: Parsing attribute #{attribute}" if DEBUG
    case attribute[:type]
    when :scalar, :tags
      table.header.push(attribute[:column_name])
      table.tabs.push(attribute[:column_width])
    when :collection
      parse_table_attributes(table: table, attributes: attribute[:attributes])
    end
  end
end

def parse_datum(args={})
  datum       = args[:datum]
  table       = args[:table]
  service     = args[:service]
  attributes  = args[:attributes]
  output      = nil

  puts "+ DEBUG [parse_datum]: Parsing datum #{datum}" if DEBUG
  puts "+ DEBUG [parse_datum]: Parsing #{attributes.size} attributes from #{attributes}" if DEBUG

  attributes.each do |attribute|
    puts "++ DEBUG [parse_datum]: Parsing attribute #{attribute}" if DEBUG

    table.reset_row if attribute[:root_node]

    case attribute[:type]
    when :scalar
      if attribute[:stub]
        output = datum[attribute[:stub]][attribute[:target]]
      else
        output = datum[attribute[:target]]
      end
      table.push(data: output.to_s) if output
    when :tags  
      tags = datum[attribute[:stub]]
      tags.each do |tag|
        output = tag.key + " = " + tag.value
        table.push(data: output) if output
        table.next_row
      end
    when :collection
      puts "+++ DEBUG [parse_datum]: Parsing #{datum[attribute[:collection_name]].size} items from array: #{datum[attribute[:collection_name]]}" if DEBUG
      datum[attribute[:collection_name]].each do |item|
        puts "++++ DEBUG [parse_datum]: Parsing item #{item}" if DEBUG
        parse_datum({ datum:      item,
                      attributes: attribute[:attributes],
                      table:      table,
                      service:    service})

        if attribute[:leaf_node] && datum[attribute[:collection_name]].size > 0
          puts "++++ DEBUG [parse_datum]: Current attribute is a leaf node... Incrementing row" if DEBUG
          table.next_row
        end
      end
    end

    if attribute[:sum]
      service.totals[attribute[:target]] = 0 if service.totals[attribute[:target]].nil?
      service.totals[attribute[:target]] += output.to_i
    end
  table.next_col
  end
end

# Main loop - iterate through AWS services as defined in services.json
metadata[:services].each do |item|

  # Create a new AWSService object to contain metadata and client object
  service = AWSService.new({ metadata:  item,
                             clients:   clients })

  output  = Table.new                                       # Fresh table object to build output

  if service.has_items?                                     # First check if the service has any items to process
    parse_table_attributes(table: output, attributes: service.attributes)                # Populate column labels into the table object
    service.set_title({status: true, table: output})        # Set the title for table

    if service.name == "EC2"
      service.describe_output.reservations.each do |reservation|
        reservation.instances.each do |item|
          parse_datum({ datum:      item,
                        attributes: service.attributes,
                        service:    service,
                        table:      output }) 

          service.totals[:count] += 1
          output.new_row
        end
      end
    else
      service.fetch_collection.each do |item|
        puts "\nDEBUG [main]: Item = #{item}" if DEBUG
        parse_datum({ datum:      item,
                      attributes: service.attributes,
                      service:    service,
                      table:      output }) 

        service.totals[:count] += 1
        output.new_row
      end
    end
    service.set_totals({table: output})
  else
    service.set_title({status: false, table: output})
  end
  output.render
end
