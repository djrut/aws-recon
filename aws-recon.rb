require 'aws-sdk'
COL_WIDTH = 20

Aws.config.update({
  region: "us-west-2",
  credentials: Aws::SharedCredentials.new(profile_name: "default"),
})

def newline
  printf "\n"
end

def print_section_header(category = "Undefined")
  newline
  puts "=============================="
  puts "= Summary for: #{category}"
  puts "=============================="
end


def print_column_labels(labels)
  labels.each {|label| printf "%-#{COL_WIDTH}s", label}
  newline  
  labels.each {|label| printf "%-#{COL_WIDTH}s", "-" * label.size}
  newline
end

def print_data(data)
  data.each {|datum| printf "%-#{COL_WIDTH}s", datum.to_s.slice(0,COL_WIDTH-1)}
  newline
end

# Show EC2 summary data

ec2 = Aws::EC2::Client.new

print_section_header("EC2")
print_column_labels(["Reservation ID", "Instance ID", "Instance Type", "Instance State", "Availability Zone", "EBS Optimized?", "Tags"])

total_instances = 0
ec2.describe_instances.reservations.each do |reservation|
  reservation.instances.each do |instance|
    print_data([reservation.reservation_id,
                instance.instance_id,
                instance.instance_type,
                instance.state.name,
                instance.placement.availability_zone,
                instance.ebs_optimized,
                instance.tags])
    total_instances += 1
  end
end

puts "\nTotal EC2 Instances = #{total_instances}\n"

# Show EBS summary data

print_section_header("EBS")
print_column_labels(["Volume ID", "Size (GB)", "State", "Volume Type", "IOPS", "Encrypted?", "Tags"])

total_volumes = 0
total_size = 0

ec2.describe_volumes.volumes.each do |volume|
  print_data([volume.volume_id,
              volume.size,
              volume.state,
              volume.volume_type,
              volume.iops,
              volume.encrypted,
              volume.tags])
  total_volumes += 1
  total_size += volume.size
end

puts "\nTotal EBS Volumes = #{total_volumes}\n"
puts "\nTotal EBS Capacity = #{total_size}GB\n"

# Show VPC summary data

print_section_header("VPC")
print_column_labels(["VPC ID", "State", "CIDR", "Tenancy", "Default?", "Tags"])

total_vpcs = 0
ec2.describe_vpcs.vpcs.each do |vpc|
   print_data([vpc.vpc_id,
               vpc.state,
               vpc.cidr_block,
               vpc.instance_tenancy,
               vpc.is_default,
               vpc.tags])
   total_vpcs += 1
end

puts "\nTotal VPCs = #{total_vpcs}"

# Show ELB summary data

elb = Aws::ElasticLoadBalancing::Client.new

print_section_header("ELB")
print_column_labels(["Name", "VPC", "Instances", "AZs", "Scheme"])

total_elbs = 0
elb.describe_load_balancers.load_balancer_descriptions.each do |elb|
   print_data([elb.load_balancer_name,
               elb.vpc_id,
               elb.instances,
               elb.availability_zones,
               elb.scheme])
   total_elbs += 1
end

puts "\nTotal ELBs = #{total_elbs}"







