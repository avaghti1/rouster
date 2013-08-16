require sprintf('%s/%s', File.dirname(File.expand_path(__FILE__)), 'path_helper')
require 'rubygems'
require 'rake/testtask'

task :default do
  sh 'ruby test/basic.rb'
end

task :examples do
  Dir['examples/**/*.rb'].each do |example|
	  sh "ruby #{example}"
	end
end

task :buildgem do
  sh 'gem build rouster.gemspec'
end

task :demo do
  sh 'ruby examples/demo.rb'
end

Rake::TestTask.new do |t|
  t.name = 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/test_*.rb']
  t.verbose = true
end

Rake::TestTask.new do |t|
  t.name = 'unit'
  t.libs << 'lib'
  t.test_files = FileList['test/unit/**/test_*.rb']
  t.verbose = true
end

Rake::TestTask.new do |t|
  t.name = 'functional'
  t.libs << 'lib'
  t.test_files = FileList['test/functional/**/test_*.rb']
  t.verbose = true
end
