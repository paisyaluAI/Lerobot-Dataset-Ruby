# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "Lerobot-Dataset-Ruby"
  spec.version = "1.0.0"
  spec.authors = ["PaisyaluAI"]
  spec.email = ["h9265768hello@gmail.com"]

  spec.summary = "LeRobot dataset v3 reader and writer library for Ruby"
  spec.description = "A Ruby gem for reading and recording robotic dataset in LeRobot v3.0 format using OpenCV and Parquet."
  spec.homepage = "https://github.com/paisyaluAI/lerobot-dataset-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .github/]) ||
        f.end_with?(".mp4", ".o", ".so", "Makefile", "mkmf.log", "extconf.h")
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/opencv/extconf.rb"]

  spec.add_dependency "parquet", ">= 0.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
