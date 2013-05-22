require sprintf('%s/../../%s', File.dirname(File.expand_path(__FILE__)), 'path_helper')
require 'rouster/deltas'

class Rouster

  def is_dir?(dir)
    begin
      res = self.run(sprintf('ls -ld %s', dir))
    rescue Rouster::RemoteExecutionError
      # noop, process output instead of exit code
    end

    if res.match(/No such file or directory/)
      false
    elsif res.match(/Permission denied/)
      @log.info(sprintf('is_dir?(%s) output[%s], try with sudo', dir, res)) unless self.uses_sudo?
      false
    else
      #true
      parse_ls_string(res)
    end
  end

  def is_executable?(filename, level='u')

    res = is_file?(filename)

    if res
      array = res[:executable?]

      case level
        when 'u', 'U', 'user'
          array[0]
        when 'g', 'G', 'group'
          array[1]
        when 'o', 'O', 'other'
          array[2]
        else
          raise InternalError.new(sprintf('unknown level[%s]'))
      end

    else
      false
    end

  end

  def is_file?(file)
    begin
      res = self.run(sprintf('ls -l %s', file))
    rescue Rouster::RemoteExecutionError
      # noop, process output
    end

    if res.match(/No such file or directory/)
      @log.info(sprintf('is_file?(%s) output[%s], try with sudo', file, res)) unless self.uses_sudo?
      false
    elsif res.match(/Permission denied/)
      false
    else
      #true
      parse_ls_string(res)
    end

  end

  def is_group?(group)
    groups = self.get_groups()
    groups.has_key?(group)
  end

  def is_in_file?(file, regex, scp=false)

    res = nil

    if scp
      # download the file to a temporary directory
      # not implementing as part of MVP
    end

    begin
      command = sprintf("grep -c '%s' %s", regex, file)
      res     = self.run(command)
    rescue Rouster::RemoteExecutionError
      false
    end

    if res.nil?.false? and res.grep(/^0/)
      false
    else
      true
    end

  end

  def is_in_path?(filename)
    begin
      self.run(sprintf('which %s', filename))
    rescue Rouster::RemoteExecutionError
      false
    end

    true
  end

  def is_package?(package, use_cache=true)
    packages = self.get_packages(use_cache)
    packages.has_key?(package)
  end

  def is_readable?(filename, level='u')

    res = is_file?(filename)

    if res
      array = res[:readable?]

      case level
        when 'u', 'U', 'user'
          array[0]
        when 'g', 'G', 'group'
          array[1]
        when 'o', 'O', 'other'
          array[2]
        else
          raise InternalError.new(sprintf('unknown level[%s]'))
      end

    else
      false
    end

  end

  def is_service?(service, use_cache=true)
    services = self.get_services(use_cache)
    services.has_key?(service)
  end

  def is_service_running?(service, use_cache=true)
    services = self.get_services(use_cache)

    if services.has_key?(service)
      services[service].eql?('running')
    end
  end

  def is_user?(user, use_cache=true)
    users = self.get_users(use_cache)
    users.has_key?(user)
  end

  def is_writeable?(filename, level='u')

    res = is_file?(filename)

    if res
      array = res[:writeable?]

      case level
        when 'u', 'U', 'user'
          array[0]
        when 'g', 'G', 'group'
          array[1]
        when 'o', 'O', 'other'
          array[2]
        else
          raise InternalError.new(sprintf('unknown level[%s]'))
      end

    else
      false
    end

  end

  # non-test, helper methods
  def parse_ls_string(string)
    # ht avaghti

    res = Hash.new()

    tokens = string.split(/\s+/)

    # eww - do better here
    modes = [ tokens[0][1..3], tokens[0][4..6], tokens[0][7..9] ]
    mode  = 0

    # can't use modes.size here (or could, but would have to -1)
    for i in 0..2 do
      value   = 0
      element = modes[i]

      for j in 0..2 do
        chr = element[j].chr
        case chr
          when 'r'
            value += 4
          when 'w'
            value += 2
          when 'x', 't'
            # is 't' really right here? copying Salesforce::Vagrant
            value += 1
          when '-'
            # noop
          else
            raise InternalError.new(sprintf('unexpected character[%s]', chr))
        end

      end

      mode = sprintf('%s%s', mode, value)
    end

    res[:mode]  = mode
    res[:owner] = tokens[2]
    res[:group] = tokens[3]
    res[:size]  = tokens[4]

    res[:directory?]  = tokens[0][0].chr.eql?('d')
    res[:file?]       = ! res[:directory?]
    res[:executable?] = [ tokens[0][3].chr.eql?('x'), tokens[0][6].chr.eql?('x'), tokens[0][9].chr.eql?('x') || tokens[0][9].chr.eql?('t') ]
    res[:readable?]   = [ tokens[0][2].chr.eql?('w'), tokens[0][5].chr.eql?('w'), tokens[0][8].chr.eql?('w') ]
    res[:writeable?]  = [ tokens[0][1].chr.eql?('r'), tokens[0][4].chr.eql?('r'), tokens[0][7].chr.eql?('r') ]

    res
  end

end
