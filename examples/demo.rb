require sprintf('%s/../%s', File.dirname(File.expand_path(__FILE__)), 'path_helper')

require 'rouster'
require 'rouster/tests'

@app = Rouster.new(:name => 'app', :sudo => true, :verbosity => 3)
@app.up()

# get list of packages
before_packages = @app.get_packages()

# install new package
@app.run('yum -y install httpd')
print @app.get_output()

# get list of packages
after_packages = @app.get_packages(false)

# look for files specific to new pacakge
p sprintf('delta of before/after packages: %s', after_packages.keys() - before_packages.keys())
p sprintf('/var/www exists: %s', @app.is_dir?('/var/www'))
p sprintf('/etc/httpd/conf/httpd.conf: %s', @app.file('/etc/httpd/conf/httpd.conf'))

# look for port state changes
httpd_off_ports = @app.get_ports()

@app.run('service httpd start')
httpd_on_ports = @app.get_ports()
p sprintf('while httpd is running, port 80 is: %s', @app.is_port_active?(80, 'tcp', true))
p sprintf('delta of before/after ports: %s', httpd_on_ports['tcp'].keys() - httpd_off_ports['tcp'].keys())

# look for groups/users created
p sprintf('apache group created? %s', @app.is_group?('apache'))
p sprintf('apache user created?  %s', @app.is_user?('apache'))

# look at is_process_running / is_service / is_service_running
is_service = @app.is_service?('httpd')
is_service_running = @app.is_service_running?('httpd')
is_process_running = @app.is_process_running?('httpd')
p sprintf('is_service?(httpd) %s', is_service)
p sprintf('is_service_running?(httpd) %s', is_service_running)
p sprintf('is_process_running?(httpd) %s', is_process_running)

@app.run('service httpd stop')
is_service_running = @app.is_service_running?('httpd')
p sprintf('is_service_running?(httpd) %s', is_service_running)
p sprintf('when httpd is stopped, port 80 is: %s', @app.is_port_active?(80))

# get a conf file, modify it, send it back, restart service
tmp_filename = sprintf('/tmp/httpd.conf.%s', Time.now.to_i)

@app.get('/etc/httpd/conf/httpd.conf', tmp_filename)

## this should be smoother..
@app._run(sprintf("sed -i 's/Listen 80/Listen 1234/' %s", tmp_filename))

@app.put(tmp_filename, '/etc/httpd/conf/httpd.conf')

@app.run('service httpd start')
is_service_running = @app.is_service_running?('httpd')
p sprintf('is_service_running?(httpd): %s', is_service_running)
p sprintf('after modification and restart, port 1234 is: %s', @app.is_port_active?('1234'))