#!/usr/bin/env ruby
require 'aws-sdk-core'
require 'trollop'
require 'oj'

# Global variables
$debug = false

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
end

class Table
  attr_accessor :header, :footer, :tabs, :group
  MAX_ROWS = 128

  def initialize(args={})
    @num_rows = args[:rows] || MAX_ROWS
    @format   = args[:format]
    @col      = 0
    @row      = 0
    @head     = 0
    @tail     = 0
    @title    = "Empty table"
    @group    = String.new
    @header   = Array.new(2) { Array.new }
    @tabs     = Array.new
    @footer   = Array.new
    @matrix   = Array.new(@num_rows) { Array.new }
  end

  def self.formats
    ["console","csv"]
  end

  def next_col
    @col += 1
  end

  def next_row
    @row += 1
    @tail = [@row,@tail].max
  end

  def new_row
    @head = @tail + 1
    @row  = @head
    @tail = @head
    @col  = 0
  end

  def reset_row
    @row = @head
  end

  def push(args={})
    @matrix[@row][@col] = args[:data]
  end

  def pop
    @matrix[@row][@col]
  end

  def set_title(args={})
    status  = args[:status]    
    name    = args[:name]    

    if status
      @title = "= SUMMARY for: " + name
    else
      @title = "= NO DATA for: " + name
    end
  end

  def render(args={})
    format = args[:format] || :console

    printf "\n"
    printf @title

    # Render the header group row
    #
    printf "\n" if !@tabs.empty?
    @tabs.each_with_index do |tab,index|
      case @format
      when :console
        printf "%-#{tab}s", @header[0][index].to_s.slice(0, tab - 1)
      when :csv
        printf "%s,", @header[0][index]
      end
    end

    # Render the header attribute row
    #
    printf "\n" if !@tabs.empty?
    @tabs.each_with_index do |tab,index|
      case @format
      when :console
        printf "%-#{tab}s", @header[1][index].to_s.slice(0, tab - 1)
      when :csv
        printf "%s,", @header[1][index]
      end
    end

    # Render the header separation row
    #
    printf "\n" if !@tabs.empty?
    @tabs.each_with_index do |tab,index|
      case @format
      when :console
        printf "%-#{tab}s", "-" * (tab - 1)
      when :csv
        printf "%s,", "-" * @header[1][index].size
      end
    end

    # Render the main table contents
    #
    printf "\n"
    @matrix.each do |row|
      if !row.empty?
        @tabs.each_with_index do |tab, index|
          case @format
          when :console
            printf "%-#{tab}s", row[index].to_s.slice(0, tab - 1)
          when :csv
            printf "%s,", row[index]
          end
        end
        printf "\n"
      end
    end

    # Render the footer separation row
    #
    @tabs.each_with_index do |tab,index|
      case @format
      when :console
        printf "%-#{tab}s", "-" * (tab - 1)
      when :csv
        printf "%s,", "-" * (tab - 1)
      end
    end

    # Render the footer row
    #
    printf "\n" if !@tabs.empty?
    @tabs.each_with_index do |tab,index|
      case @format
      when :console
        printf "%-#{tab}s", @footer[index].to_s.slice(0, tab - 1)
      when :csv
        printf "%s,", @footer[index]
      end
    end
    printf "\n"
  end
end

# Parse options
opts = Trollop::options do
  version "aws-recon v0.1 (c) 2015 Duncan Rutland"
  opt :region, "AWS Region to perform scan on", short: "-r", type: :string, required: true
  opt :config, "Specify alternative configuration file", long: "--config-file", short: "-c", default: "services.json", type: :string
  opt :format, "Specify output format #{Table.formats}", long: "--output-format", short: "-f", default: "console", type: :string
  opt :group, "Specify which service group(s) to display", long: "--service-group", short: "-g", default: ["Compute","Network"], type: :strings
  opt :profile, "Specify AWS credential profile name", short: "-p", type: :string
  opt :role, "ARN for role to assume", short: "-R", type: :string
  opt :extid, "External ID for STS Assume Role", short: "-x", type: :string
  opt :debug, "Enable debugging output", long: "--enable-debug", short: "-D", default: false, type: :boolean 
  depends :role, :extid
  conflicts :profile, :role
  conflicts :profile, :extid
end

# Exit if supplied configuration does not exist
Trollop::die :config, "must exist" unless File.exist?(opts[:config]) if opts[:config]

# Load service definitions and populate directory hash
directory = Hash.new
metadata  = Oj.load_file("services.json")
metadata[:services].each do |service|
  directory[service[:name]] = service[:group].downcase
end

# Exit if a non-supported format is supplied
Trollop::die :format, "must be either #{Table.formats}" unless Table.formats.member?(opts[:format]) if opts[:format]

# Process group parameter and exit if not a valid group
opts[:group].map! {|item| item.downcase}

opts[:group].each do |group|
  Trollop::die :group, "must be one of the following: #{directory.values.uniq}" unless directory.values.uniq.member?(group)
end

# Set region
Aws.config.update({region: opts[:region]})

# Determine whether we are using role assumption or local .aws/credentials profile
if opts[:role] then
  creds = Aws::AssumeRoleCredentials.new(role_arn: opts[:role],
                                         role_session_name: "aws-recon",
                                         external_id: opts[:extid])
elsif opts[:profile] then
  creds = Aws::SharedCredentials.new(profile_name: opts[:profile])
else
  creds = Aws::SharedCredentials.new(profile_name: "default")
end

$debug  = true if opts[:debug]

# Apply appropriate credentials configuration
Aws.config.update(credentials: creds)

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

  puts "+ DEBUG [parse_table_attributes]: Parsing  attributes array #{attributes}" if $debug

  attributes.each do |attribute|
    puts "++ DEBUG [parse_table_attributes]: Parsing attribute #{attribute}" if $debug
    case attribute[:type]
    when :scalar, :boolean, :tags
      table.tabs.push(attribute[:column_width])
      table.header[0].push(table.group)
      table.header[1].push(attribute[:column_name])
      table.group = ""
    when :collection
      table.group = attribute[:name]
      parse_table_attributes( table:      table,
                              attributes: attribute[:attributes] )
    end
  end
end

def set_totals(args={})
  table       = args[:table]  
  attributes  = args[:attributes]
  totals      = args[:totals]

  attributes.each do |attribute|
    case attribute[:type]
    when :scalar, :boolean, :tags
      if attribute[:count]
        table.footer.push(totals[:count].to_s)
      elsif totals[attribute[:target]]
        table.footer.push(totals[attribute[:target]].to_s)
      else
        table.footer.push("N/A")
      end
    when :collection
      set_totals( table:      table,
                  attributes: attribute[:attributes],
                  totals:     totals )
    end
  end
end

def parse_datum(args={})
  datum       = args[:datum]
  table       = args[:table]
  service     = args[:service]
  attributes  = args[:attributes]
  output      = String.new

  puts "+ DEBUG [parse_datum]: Parsing datum #{datum}" if $debug
  puts "+ DEBUG [parse_datum]: Parsing #{attributes.size} attributes from #{attributes}" if $debug

  attributes.each do |attribute|
    puts "++ DEBUG [parse_datum]: Parsing attribute #{attribute}" if $debug

    table.reset_row if attribute[:root_node]

    case attribute[:type]
    when :scalar
      if attribute[:stub]
        output = datum[attribute[:stub]][attribute[:target]]
      else
        output = datum[attribute[:target]]
      end
      table.push(data: output.to_s)
    when :boolean
      if datum[attribute[:target]]
        output = "true"
      else
        output = "false"
      end
      table.push(data: output.to_s)
    when :tags  
      tags = datum[attribute[:stub]]
      tags.each do |tag|
        output = tag.key + " = " + tag.value
        table.push(data: output.to_s)
        table.next_row
      end
    when :collection
      datum[attribute[:collection_name]].each do |item|
        puts "++++ DEBUG [parse_datum]: Parsing item #{item}" if $debug
        parse_datum( datum:      item,
                     attributes: attribute[:attributes],
                     table:      table,
                     service:    service )

        table.next_row if attribute[:leaf_node]
      end
    end

    if attribute[:sum]
      service.totals[attribute[:target]] = 0 if service.totals[attribute[:target]].nil?
      service.totals[attribute[:target]] += output.to_i
    end
  table.next_col
  end
end

# Populate array of services to process based on group settings
services = Array.new
metadata[:services].each do |item|
  services.push(item) if opts[:group].member?(item[:group].downcase)
end

# Main loop - iterate through AWS services within scope 
services.each do |item|
  puts "\n[DEBUG] main: Processing service #{item}" if $debug
  service = AWSService.new( metadata:  item,
                            clients:   clients )          # Create a new AWSService object to contain metadata and client object

  output  = Table.new(format: opts[:format].to_sym)         # Fresh table object to build output

  if service.has_items?                                     # First check if the service has any items to process
    parse_table_attributes(table:       output,
                           attributes:  service.attributes) # Populate column labels into the table object

    output.set_title( status: true,
                      name:   service.name )        # Set the title for table

    if service.name == "EC2"
      service.describe_output.reservations.each do |reservation|
        reservation.instances.each do |item|
          parse_datum( datum:      item,
                       attributes: service.attributes,
                       service:    service,
                       table:      output ) 

          service.totals[:count] += 1
          output.new_row
        end
      end
    else
      service.fetch_collection.each do |item|
        puts "\nDEBUG [main]: Item = #{item}" if $debug
        parse_datum( datum:      item,
                     attributes: service.attributes,
                     service:    service,
                     table:      output ) 

        service.totals[:count] += 1
        output.new_row
      end
    end

    set_totals(table:       output,
               attributes:  service.attributes,
               totals:      service.totals)
  else
    puts "\n[DEBUG] main: Service has no items to process!" if $debug
    output.set_title( status: false,
                      name:   service.name )
  end
  output.render
end
