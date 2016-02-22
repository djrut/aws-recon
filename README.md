## Overview

aws-recon is a simple Ruby utility designed to provide a quick means of discovering and displaying an AWS service configuration summary, in either a columnar or comma-separated format. 

Currently supported services are:

- EC2 (incl. Reserved instances)
- EBS
- VPC
- IAM
- ELB
- RDS
- ElastiCache
- CloudFormation
- OpsWorks

Note: In it's current form, this tool is not designed to provide deeper insights, relationship mapping, optimization advice and other such logic. There are a number of tools in the market that provide this functionality.

## Example output

~~~
~/projects/aws-recon # bin/aws-recon.rb -r us-west-2 --service-group compute storage network database

= SUMMARY for: EC2

ID             Type           State          AZ             EBS Optimized? Tags
-------------- -------------- -------------- -------------- -------------- -----------------------------------------------------------
i-1b334ac2     t2.micro       stopped        us-west-2a     false          Name =
i-267953ff     m3.medium      running        us-west-2a     false          Name =
i-dd7ef51b     m1.small       running        us-west-2a     false
-------------- -------------- -------------- -------------- -------------- -----------------------------------------------------------
3              N/A            N/A            N/A            N/A            N/A

= NO DATA for: Reserved Instances


= SUMMARY for: EBS
                                                                                          Attachments
ID             Size (GB)      State          Volume Type    IOPS           Encrypted?     Instance ID    Device         Attach State   Tags
-------------- -------------- -------------- -------------- -------------- -------------- -------------- -------------- -------------- -----------------------------------------------------------
vol-d6221e18   8              in-use         standard                      false          i-dd7ef51b     /dev/sda1      attached
vol-1f9497de   1              in-use         gp2            3              true           i-1b334ac2     /dev/sdf       attached
vol-b0aead71   8              in-use         gp2            24             false          i-1b334ac2     /dev/xvda      attached
vol-1acf0eda   8              in-use         gp2            24             true           i-267953ff     /dev/sda1      attached
-------------- -------------- -------------- -------------- -------------- -------------- -------------- -------------- -------------- -----------------------------------------------------------
4              25             N/A            N/A            51             N/A            N/A            N/A            N/A            N/A

= SUMMARY for: VPC

ID             State          CIDR           Tenancy        Default?       Tags
-------------- -------------- -------------- -------------- -------------- -----------------------------------------------------------
vpc-1fef787a   available      10.0.0.0/16    default        false          Name = dirigible-behemothaur
vpc-4bff762e   available      172.31.0.0/16  default        true
vpc-7685f813   available      10.1.0.0/16    default        false          Name = yoleus
                                                                           Environment = Production
-------------- -------------- -------------- -------------- -------------- -----------------------------------------------------------
3              N/A            N/A            N/A            N/A            N/A

= NO DATA for: ELB


= NO DATA for: RDS


= NO DATA for: ElastiCache Clusters


= NO DATA for: ElastiCache Replication Groups
~~~

## Usage 

```
ws-recon v1.0 (c) 2016 Duncan Rutland
Options:
  -r, --region=<s>            AWS Region to perform scan on
  -c, --config-file=<s>       Specify alternative configuration file (default: data/services.json)
  -f, --output-format=<s>     Specify output format ["console", "csv"] (default: console)
  -g, --service-group=<s+>    Specify which service group(s) to display (default: Compute, Network)
  -p, --profile=<s>           Specify AWS credential profile name
  -R, --role=<s>              ARN for role to assume
  -x, --extid=<s>             External ID for STS Assume Role
  -D, --enable-debug          Enable debugging output
  -v, --version               Print version and exit
  -h, --help                  Show this message
```

## Pre-Reqs

 * [Ruby](https://www.ruby-lang.org/en/downloads/), preferably version 2.2.2 or later
 * [bundler](http://bundler.io/), version 1.9.4 or later

## Installation

- Clone this repo `git clone https://github.com/djrut/aws-recon.git`
- From the directory that you cloned the repo to, run: `bundle install`

## Running it
```
bin/aws-recon.rb --region <region> 
```
