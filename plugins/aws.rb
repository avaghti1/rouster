#!/usr/bin/ruby
## rouster_aws.rb - provide helper functions for Rouster objects running on AWS/EC2

# TODO implement some caching of AWS data? allow control in instantiation of worker

require sprintf('%s/../%s', File.dirname(File.expand_path(__FILE__)), 'path_helper')

require 'fog'
require 'uri'

class Rouster

  attr_reader :ec2, :elb     # expose AWS workers
  attr_reader :instance_data # the result of the runInstances request

  def aws_get_url(url)
    # convenience method to run curls from inside the VM
    self.run(sprintf('curl -s %s', url))
  end

  # TODO should this be 'aws_ip'?
  def aws_get_ip (method = :internal, type = :public)
    # allowed methods: :internal (check meta-data inside VM), :aws (ask API)
    # allowed types:   :public, :private
    self.aws_describe_instance

    if method.equal?(:internal)
      key    = type.equal?(:public) ? 'public-ipv4' : 'local-ipv4'
      murl   = sprintf('http://169.254.169.254/latest/meta-data/%s', key)
      result = self.aws_get_url(murl)
    else
      key    = type.equal?(:public) ? 'ipAddress' : 'privateIpAddress'
      result = @instance_data[key]
    end

    result
  end

  def aws_get_userdata
    murl     = 'http://169.254.169.254/latest/user-data/'
    result   = self.aws_get_url(murl)

    if result.match(/\S=\S/)
      # TODO should we really be doing this?
      userdata = Hash.new()
      result.split("\n").each do |line|
        if line.match(/^(.*?)=(.*)/)
          userdata[$1] = $2
        end
      end
    else
      userdata = result
    end

    userdata
  end

  # return a hash containing meta-data items
  def aws_get_metadata
    murl   = 'http://169.254.169.254/latest/meta-data/'
    result = self.aws_get_url(murl)
    metadata = Hash.new()

    # TODO this isn't entirely right.. if the element ends in '/', it's actually another level of hash..
    result.split("\n").each do |element|
      metadata[element] = self.aws_get_url(sprintf('%s%s', murl, element))
    end

    metadata
  end

  def aws_get_hostname (method = :internal, type = :public)
    # allowed methods: :internal (check meta-data inside VM), :aws (ask API)
    # allowed types:   :public, :private
    self.aws_describe_instance

    result = nil

    if method.equal?(:internal)
      key    = type.equal?(:public) ? 'public-hostname' : 'local-hostname'
      murl   = sprintf('http://169.254.169.254/latest/meta-data/%s', key)
      result = self.aws_get_url(murl)
    else
      key    = type.equal?(:public) ? 'dnsName' : 'privateDnsName'
      result = @instance_data[key]
    end

    result
  end

  def aws_get_instance ()
    if ! @instance_data.nil? and @instance_data.has_key?('instanceId')
      return @instance_data['instanceId']
    else
      return @passthrough[:instance]
    end
  end

  def aws_get_ami ()
    if ! @instance_data.nil? and @instance_data.has_key?('ami')
      return @instance_data['ami']
    else
      return @passthrough[:ami]
    end
  end

  def aws_up
    # wait for machine to transition to running state and become sshable (TODO maybe make the second half optional)
    self.aws_connect

    require 'pry'

    status = self.status()
    if status.eql?('running')
      return self.aws_get_instance
    elsif status.eql?('terminated')
      # on Raiden, this means the instance isn't running
      binding.pry
    #elsif status.nil?
    else
      # not sure what this response is actually going to look like
      binding.pry
    end

    server  = @ec2.run_instances(
        self.passthrough[:ami],
        self.passthrough[:min_count],
        self.passthrough[:max_count],
        {
          'InstanceType'   => self.passthrough[:size],
          'KeyName'        => self.passthrough[:keypair],
          'SecurityGroup'  => self.passthrough[:security_groups],
          'UserData'       => self.passthrough[:userdata],

        },
    )

    @instance_data = server.data[:body]['instancesSet'][0]

    # wait until the machine starts
    ceiling    = 9
    sleep_time = 20
    0.upto(ceiling) do |try|
      status = self.aws_status

      @logger.debug(sprintf('describeInstances[%s]: [%s] [#%s]', self.aws_get_instance, status, try))

      if status.eql?('running') or status.eql?('16')
        @logger.info(sprintf('[%s] transitioned to state[%s]', self.aws_get_instance, self.aws_status))
        break
      end

      sleep sleep_time
    end

    # TODO raise if we're still not in running

    # TODO don't be this hacky
    self.aws_describe_instance # the server.data response doesn't include public hostname/ip
    @passthrough[:host] = @instance_data['dnsName']

    # wait until ssh is available
    0.upto(ceiling) do |try|
      @logger.info(sprintf('connecting via SSH[%s]: [#%s]', @passthrough[:host], try))
      begin
        self.connect_ssh_tunnel
        break
      rescue Errno::ECONNREFUSED => e
        @logger.debug(sprintf('failed to open tunnel[%s], trying again in %ss', e.message, sleep_time))
      end
      sleep sleep_time
    end

    self.aws_get_instance
  end

  def aws_destroy
    self.aws_connect

    server = @ec2.terminate_instances(self.aws_get_instance)

    self.aws_status
  end

  def aws_describe_instance(instance = aws_get_instance)

    self.aws_connect
    server   = @ec2.describe_instances('instance-id' => [ instance ])
    response = server.data[:body]['reservationSet'][0]['instancesSet'][0]

    if instance.eql?(self.aws_get_instance)
      @instance_data = response
    end

    response
  end

  def aws_status
    require 'pry'
    binding.pry
    self.aws_describe_instance
    @instance_data['instanceState']['name'].nil? ? @instance_data['instanceState']['code'] : @instance_data['instanceState']['name']
  end

  def aws_connect_to_elb (id, elbname, listeners = [{ 'InstancePort' => 22, 'LoadbalancerPort' => 22, 'InstanceProtocol' => 'TCP' }])
    self.elb_connect

    # allow either hash or array of hash specification for listeners
    listeners       = [ listeners ] unless listeners.is_a?(Array)
    required_params = [ 'InstancePort', 'LoadbalancerPort', 'InstanceProtocol' ]

    listeners.each do |l|
      required_params.each do |r|
        raise sprintf('listener[%s] does not include required parameter[%s]', l, r) unless l[r]
      end

    end

    binding.pry

    response = @elb.create_load_balancer(
      [], # availability zones not needed on raiden
      name,
      listeners
    )

    ## return DNSName
    binding.pry

  end

  def aws_bootstap (commands)
    self.aws_connect
    commands = (commands.is_a?(Array)) ? commands : [ commands ]

    commands.each do |command|
      @logger.debug(sprintf('about to run[%s]', command))

    end

    raise 'not implemented'
  end

  def aws_connect
    return @ec2 unless @ec2.nil?

    config = {
      :provider              => 'AWS',
      :region                => self.passthrough[:region],
      :aws_access_key_id     => self.passthrough[:key_id],
      :aws_secret_access_key => self.passthrough[:secret_key],
    }

    config[:endpoint] = self.passthrough[:ec2_endpoint] unless self.passthrough[:ec2_endpoint].nil?
    @ec2 = Fog::Compute.new(config)
  end

  def elb_connect
    return @elb unless @elb.nil?

    if self.passthrough[:elb_endpoint]
      endpoint = URI.parse(self.passthrough[:elb_endpoint])
    elsif self.passthrough[:ec2_endpoint]
      endpoint = URI.parse(self.passthrough[:ec2_endpoint])
    end

    config = {
      :host   => endpoint.host,
      :path   => endpoint.path,
      :port   => endpoint.port,
      :scheme => endpoint.scheme,

      :region                => self.passthrough[:region],
      :aws_access_key_id     => self.passthrough[:key_id],
      :aws_secret_access_key => self.passthrough[:secret_key],
    }

    @elb = Fog::AWS::ELB.new(config)
  end

end
