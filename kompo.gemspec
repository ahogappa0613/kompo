# frozen_string_literal: true

require_relative "lib/kompo/version"

Gem::Specification.new do |spec|
  spec.name = "kompo"
  spec.version = Kompo::VERSION
  spec.authors = ["Sho Hirano"]
  spec.email = ["ahogappa@gmail.com"]

  spec.summary = "A tool to pack Ruby and Ruby scripts in one binary."
  spec.description = "A tool to pack Ruby and Ruby scripts in one binary. This tool is still under development."
  spec.homepage = "https://github.com/ahogappa0613/kompo"
  spec.required_ruby_version = ">= 2.6.0"
  spec.required_rubygems_version = ">= 3.3.11"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ahogappa0613/kompo"
  spec.metadata["changelog_uri"] = "https://github.com/ahogappa0613/kompo"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .circleci appveyor sample])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  spec.add_dependency "mini_portile2"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
