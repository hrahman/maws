require 'right_aws'


class AwsConnection
  attr_accessor :silent, :name_grouped_descriptions

  def initialize(keyid, key, options)
    @access_key_id = keyid
    @secret_key = key
    @options = options

    @params = {:region => @options.region, :logger => $right_aws_logger}
    @silent = false
    info "ZONE: #{@options.availability_zone}\n\n"
  end

  def ec2
    # The right_aws gem parses the EC2_URL environment variable if it is set. The EC2 CLI tools also use that variable
    # but expect the hostname to be region-specific (e.g., us-east-1.ec2.amazonaws.com) instead of generic
    # (e.g., ec2.amazonaws.com). To avoid conflicts, unset the variable here and use the right_aws default value.
    ENV["EC2_URL"] = nil

    @ec2 ||= RightAws::Ec2.new(@access_key_id, @secret_key, @params.dup)
  end

  def rds
    @rds ||= RightAws::RdsInterface.new(@access_key_id, @secret_key, @params.dup)
  end

  def elb
    @elb ||= RightAws::ElbInterface.new(@access_key_id, @secret_key, @params.dup)
  end

  def availability_zones
    @availability_zones ||= ec2.describe_availability_zones(:filters => {'region-name' => @options.region}).map{|description| description[:zone_name]}
  end

  def ec2_descriptions
    return @ec2_descriptions if @ec2_descriptions
    all_descriptions = ec2.describe_instances

    terminated, nonterminated = all_descriptions.partition {|d| d[:aws_state] == "terminated"}
    @ec2_descriptions = terminated + nonterminated

    info "        (EC2 #{@ec2_descriptions.count} total in the region)\n\n" unless @silent

    @ec2_descriptions
  end

  def rds_descriptions
    return @rds_descriptions if @rds_descriptions

    @rds_descriptions = rds.describe_db_instances
    info "        (RDS #{@rds_descriptions.count} total in the region)\n\n" unless @silent

    @rds_descriptions
  end

  def elb_descriptions
    return @elb_descriptions if @elb_descriptions

    @elb_descriptions = elb.describe_load_balancers
    info "        (ELB #{@elb_descriptions.count} total in the region)\n\n" unless @silent

    @elb_descriptions
  end

  def descriptions_for_service(service)
    service = service.to_sym
    case service
    when :ec2; ec2_descriptions
    when :rds; rds_descriptions
    when :elb; elb_descriptions
    end
  end

  def clear_cached_descriptions
    @rds_descriptions = nil
    @ec2_descriptions = nil
    @elb_descriptions = nil

    @name_grouped_descriptions = nil
  end

  def description_for_name(name, service_name)
    @name_grouped_descriptions ||= {}
    description =  @name_grouped_descriptions[service_name][name] if @name_grouped_descriptions[service_name]
    return description if description

    @name_grouped_descriptions[service_name] = {}
    if service_name.to_sym == :ec2
      ec2_descriptions.each do |description|
        @name_grouped_descriptions[service_name][Instance::EC2.description_name(description)] = description
      end
    elsif service_name.to_sym == :rds
      rds_descriptions.each do |description|
        @name_grouped_descriptions[service_name][Instance::RDS.description_name(description)] = description
      end
    elsif service_name.to_sym == :elb
      elb_descriptions.each do |description|
        @name_grouped_descriptions[service_name][Instance::ELB.description_name(description)] = description
      end
    end

    @name_grouped_descriptions[service_name][name]
  end

  def image_id_for_image_name(image_name)
    return if image_name.nil? || image_name.empty?
    images = @ec2.describe_images(:filters => { 'tag:Name' => image_name})
    if images.empty?
      error "No AMI with name '#{image_name}'"
    elsif images.count > 1
      error "Ambigous AMI name: '#{image_name}'. Several AMIs match it #{images.collect{|i| i[:aws_id]}.join(', ')}"
    else
      images.first[:aws_id]
    end
  end
end