# frozen_string_literal: true

require "rubygems/package"
require "tmpdir"
require "rbconfig"

# 仅验证发布文件与解析后的依赖，避免从工作区加载代码。
artifact = File.expand_path(ARGV.fetch(0))
spec = Gem::Package.new(artifact).spec
abort "Unexpected package" unless spec.name == "ctx_driver"
abort "Unexpected package contents" if spec.files.any? { |path| path.start_with?("spec/", "test/", "storage/", "tmp/") || path.end_with?(".log", ".gem") }
Dir.mktmpdir("gem-install-") do |home|
  env = ENV.to_h.keys.grep(/\A(?:BUNDLE_|RUBY)/).to_h { |key| [ key, nil ] }
  env.merge!("GEM_HOME" => home, "GEM_PATH" => home, "RUBYOPT" => nil, "RUBYLIB" => nil)
  ruby = RbConfig.ruby
  system(env, ruby, "-S", "gem", "install", artifact, "--no-document", exception: true)
  check = <<~RUBY
    require "ctx_driver"
    abort "Unexpected eager dependency" if defined?(Rails) || defined?(Net::Connector)
    loaded = Gem.loaded_specs.fetch("ctx_driver")
    abort "Loaded checkout instead of package" unless File.realpath(loaded.full_gem_path).start_with?(File.realpath(ENV.fetch("GEM_HOME")) + "/")
    abort "Version mismatch" unless loaded.version.to_s == #{spec.version.to_s.inspect}
    Dir[File.join(loaded.full_gem_path, "examples/**/*.rb")].sort.each { |path| load path unless File.basename(path) == "connector.rb" }
  RUBY
  system(env, ruby, "-e", check, chdir: home, exception: true)
  # 单独安装可选连接器，避免离线烟测借用开发工作区的旧依赖掩盖适配错误。
  system(env, ruby, "-S", "gem", "install", "net-connector", "--version", ">= 0.13.0", "--no-document", exception: true)
  integration = <<~RUBY
    require "ctx_driver"
    loaded = Gem.loaded_specs.fetch("ctx_driver")
    load File.join(loaded.full_gem_path, "examples/connector.rb")
  RUBY
  system(env, ruby, "-e", integration, chdir: home, exception: true)
end
