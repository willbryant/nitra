require "bundler/gem_tasks"

task :default => :test
task :test do
  Dir['./spec/nitra/**/*.rb'].each { |file| require file}
end
