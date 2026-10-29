# frozen_string_literal: true

require_relative "lib/ctx_driver/version"

Gem::Specification.new do |spec|
  spec.name = "ctx_driver"
  spec.version = CtxDriver::VERSION
  spec.authors = [ "Gatework contributors" ]
  spec.summary = "Collect network commands with isolated failure evidence."
  spec.description = "Sequential declared command execution over injected sessions, with immutable receipts, failure classification and source digests."
  spec.homepage = "https://github.com/gatework/ctx_driver"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.6"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "#{spec.homepage}#readme",
    "allowed_push_host" => "https://rubygems.org",
    "rubygems_mfa_required" => "true"
  }
  # 显式限定打包文件，排除设备回显、凭据、测试夹具和构建产物。
  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "examples/**/*.rb", "docs/**/*.md", "README*.md", "CHANGELOG.md", "LICENSE"].sort }
  spec.require_paths = [ "lib" ]

  spec.add_dependency "ctx_parser", ">= 0.3.0", "< 0.4"
  spec.add_dependency "digest"
  spec.add_dependency "time"
end
