# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

desc "Compile C++ extension"
task :compile do
  Dir.chdir("ext/opencv") do
    system("ruby extconf.rb", exception: true) unless File.exist?("Makefile")
    system("make", exception: true)
  end
end

Rake::TestTask.new(:test => :compile) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/test_*.rb"]
end

task default: :test