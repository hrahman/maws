require 'maws/command'
require 'maws/elb_command'
require 'maws/trollop'

class ElbRemove < ElbCommand
  def description
    "elb-remove - remove specified EC2 instances from specified ELBs"
  end

  def run!
    ec2s = instances.specified.with_service(:ec2)
    elbs = instances.specified.with_service(:elb)

    elbs.each {|elb| elb.remove_instances(ec2s)}
  end
end
