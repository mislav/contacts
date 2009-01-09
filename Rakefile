require 'spec/rake/spectask'
require 'rake/rdoctask'

task :default => :spec

spec_opts = 'spec/spec.opts'
spec_glob = FileList['spec/**/*_spec.rb']
libs = ['lib', 'spec', 'vendor/fakeweb/lib']

desc 'Run all specs in spec directory'
Spec::Rake::SpecTask.new(:spec) do |t|
  t.libs = libs
  t.spec_opts = ['--options', spec_opts]
  t.spec_files = spec_glob
  # t.warning = true
end

namespace :spec do
  desc 'Analyze spec coverage with RCov'
  Spec::Rake::SpecTask.new(:rcov) do |t|
    t.libs = libs
    t.spec_files = spec_glob
    t.spec_opts = ['--options', spec_opts]
    t.rcov = true
    t.rcov_opts = lambda do
      IO.readlines('spec/rcov.opts').map { |l| l.chomp.split(" ") }.flatten
    end
  end
  
  desc 'Print Specdoc for all specs'
  Spec::Rake::SpecTask.new(:doc) do |t|
    t.libs = libs
    t.spec_opts = ['--format', 'specdoc', '--dry-run']
    t.spec_files = spec_glob
  end
  
  desc 'Generate HTML report'
  Spec::Rake::SpecTask.new(:html) do |t|
    t.libs = libs
    t.spec_opts = ['--format', 'html:doc/spec.html', '--diff']
    t.spec_files = spec_glob
    t.fail_on_error = false
  end
end

desc 'Generate RDoc documentation'
Rake::RDocTask.new(:rdoc) do |rdoc|
  rdoc.rdoc_files.add ['README.rdoc', 'MIT-LICENSE', 'lib/**/*.rb']
  rdoc.main = 'README.rdoc'
  rdoc.title = 'Ruby Contacts library'
  
  rdoc.rdoc_dir = 'doc'
  rdoc.options << '--inline-source'
  rdoc.options << '--charset=UTF-8'
end
