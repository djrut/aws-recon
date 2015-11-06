require 'aws-sdk'
  
def print_section_header(args={})
  title      = args[:title]
  puts "\n"
  puts "=============================="
  puts "= Summary for: #{title}"
  puts "=============================="
end

def print_column_labels(args={})
  name = args[:name]
  attributes = args[:attributes]
  attributes.each {|attribute| printf "%-#{attribute[:width]}s", attribute[:column]}
  puts "\n"  
  attributes.each {|attribute| printf "%-#{attribute[:width]}s", "-" * attribute[:column].size}
  puts "\n" 
end

def print_totals(args={})
  attributes = args[:attributes]
  totals = args[:totals]
  puts "\n"  

  attributes.each {|attribute| printf "%-#{attribute[:width]}s", "-" * attribute[:column].size}

  printf "\n"

  attributes.each do |attribute|
    if totals[attribute[:target]]
      printf "%-#{attribute[:width]}s",totals[attribute[:target].to_sym] 
    else
      printf "%-#{attribute[:width]}s","-"
    end
  end
  printf "\n"
  attributes.each {|attribute| printf "%-#{attribute[:width]}s","N/A" * attribute[:column].size}
end

def print_data(args={})
  data   = args[:data]
  attributes = args[:attributes]

  sum = {}
  sum[:count] = 0

  data.each do |datum|
    i = 0 
    continue = true
    while continue
      continue = false
      attributes.each do |attribute|
        case attribute[:type]
        when :unary
          if i == 0  
            if attribute[:stub]
              output = datum[attribute[:stub]].send(attribute[:target]).to_s
            else
              output = datum.send(attribute[:target]).to_s
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
          item = datum[attribute[:stub]][i]
          if item
             output = item.send(attribute[:target]).to_s
             continue = true if i < datum[attribute[:stub]].size - 1
          end
        else
        end
        printf "%-#{attribute[:width]}s", output.slice(0,attribute[:width]-1) unless output.nil?

        if attribute[:sum]
          sum[attribute[:target].to_sym] = 0 if sum[attribute[:target].to_sym].nil?
          sum[attribute[:target].to_sym] += output.to_i
        end
      end
      i += 1
      puts "\n"
    end
    sum[:count] += 1
  end
  return sum
end

Aws.config.update({
  region: "us-west-2",
  credentials: Aws::SharedCredentials.new(profile_name: "default"),
})

###############################################################################
# EC2
###############################################################################

section_name    = "EC2"
ec2_attributes  = [ {column: "ID",              type: :unary,                     target: "instance_id",        width: 20},
                    {column: "Type",            type: :unary,                     target: "instance_type",      width: 15},
                    {column: "State",           type: :unary, stub: "state",      target: "name",               width: 15},
                    {column: "AZ",              type: :unary, stub: "placement",  target: "availability_zone",  width: 15},
                    {column: "EBS Optimized?",  type: :unary,                     target: "ebs_optimized",      width: 15},
                    {column: "Tags",            type: :tags,  stub: "tags", width: 60}]

ec2_client      = Aws::EC2::Client.new
description        = ec2_client.describe_instances

print_section_header({title: section_name})
print_column_labels({name: section_name, attributes: ec2_attributes})

total_rows=0
description.reservations.each do |reservation|
  totals = print_data({data: reservation.instances, attributes: ec2_attributes}) 
  total_rows += totals[:count]
end

puts "\nTotal EC2 Instances = #{total_rows}\n"

###############################################################################
# EBS
###############################################################################

section_name    = "EBS"
ebs_attributes  = [ {column: "ID",              type: :unary,                     target: "volume_id",        width: 15},
                    {column: "Size (GB)",       type: :unary,                     target: "size",             width: 15, sum: true},
                    {column: "State",           type: :unary,                     target: "state",            width: 15},
                    {column: "Volume Type",     type: :unary,                     target: "volume_type",      width: 15},
                    {column: "IOPS",            type: :unary,                     target: "iops",             width: 15, sum: true},
                    {column: "Encrypted?",      type: :unary,                     target: "encrypted",        width: 15},
                    {column: "Attachments",     type: :list,  stub: "attachments",                   target: "instance_id",      width: 15},
                    {column: "Device",          type: :list,  stub: "attachments",                   target: "device",      width: 15},
                    {column: "Attach State",    type: :list,  stub: "attachments",                   target: "state",      width: 15},
                    {column: "Tags",            type: :tags,  stub: "tags", width: 60}]

description        = ec2_client.describe_volumes

print_section_header({title: section_name})
print_column_labels({name: section_name, attributes: ebs_attributes})

totals = print_data({data: description.volumes, attributes: ebs_attributes}) 

print_totals({attributes: ebs_attributes, totals: totals})

puts "\nTotal EBS Volumes = #{totals[:count]}"

## Show VPC summary data
#
#print_section_header("VPC")
#print_column_labels(["VPC ID", "State", "CIDR", "Tenancy", "Default?", "Tags"])
#
#total_vpcs = 0
#ec2.describe_vpcs.vpcs.each do |vpc|
#   print_data([vpc.vpc_id,
#               vpc.state,
#               vpc.cidr_block,
#               vpc.instance_tenancy,
#               vpc.is_default,
#               vpc.tags])
#   total_vpcs += 1
#end
#
#puts "\nTotal VPCs = #{total_vpcs}"

# Show ELB summary data
#
#elb = Aws::ElasticLoadBalancing::Client.new
#
#print_section_header("ELB")
#print_column_labels(["Name", "VPC", "Instances", "AZs", "Scheme"])
#
#total_elbs = 0
#elb.describe_load_balancers.load_balancer_descriptions.each do |elb|
#   print_data([elb.load_balancer_name,
#               elb.vpc_id,
#               elb.instances,
#               elb.availability_zones,
#               elb.scheme])
#   total_elbs += 1
#end
#
#puts "\nTotal ELBs = #{total_elbs}"
