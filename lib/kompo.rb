# frozen_string_literal: true

require "tmpdir"
require 'pathname'
require 'optparse'
require "fileutils"
require 'forwardable'
require_relative "kompo/version"

module Kompo
  class Error < StandardError; end

  class Option
    extend Forwardable
    attr_accessor :entrypoint, :output_name, :gemfile, :stdlib, :dest_dir, :ruby_src_path, :cache_bundle_path, :ruby_version, :compress, :context, :args
    delegate %i[on] => :@opt

    def initialize(dir = Dir.getwd, opt = OptionParser.new)
      @entrypoint = File.join(dir, 'main.rb')
      @output_name = File.basename(dir)
      @gemfile = true
      @stdlib = true
      @dest_dir = dir
      @ruby_src_path = nil
      @cache_bundle_path = nil
      @ruby_version = "v#{RUBY_VERSION.gsub('.', '_')}"
      @compress = false

      @context = dir
      @opt = opt
    end

    def build
      @opt.parse!(ARGV)

      @args = convert_absolute_path_for ARGV

      self
    end

    private

    def convert_absolute_path_for(args)
      args.map do |arg|
        if File.absolute_path?(arg)
          arg
        else
          Pathname.new(File.join(context, arg)).cleanpath.to_s
        end
      end
    end
  end

  class Tasks
    extend Forwardable
    attr_reader :task, :fs, :work_dir, :ruby_src_dir, :ruby_pc, :ruby_bin, :extinit_o, :encinit_o, :lib_ruby_static_dir, :bundle_setup, :bundle_ruby, :std_libs, :gem_libs

    delegate %i[entrypoint output_name gemfile stdlib dest_dir ruby_src_path cache_bundle_path ruby_version compress context args] => :@option
    delegate %i[komop_cli lib_kompo_dir] => :@fs

    def initialize(option, dir)
      @option = option
      @ruby_src_dir = File.expand_path(ruby_src_path || File.join(dir, 'ruby'))
      @work_dir = dir
      @fs = Fs.new

      @ruby_pc = File.join(ruby_src_path || File.join(dir, 'dest_dir', 'lib', 'pkgconfig'), 'ruby.pc')
      @ruby_bin = File.join(ruby_src_path || File.join(dir, 'dest_dir', 'bin'), 'ruby')
      @extinit_o = File.join(ruby_src_dir, 'ext', 'extinit.o')
      @encinit_o = File.join(ruby_src_dir, 'enc', 'encinit.o')
      @lib_ruby_static_dir = ruby_src_path || File.join(dir, 'dest_dir', 'lib')

      @std_libs = []
      @gem_libs = []
    end

    def valid?
      raise "kompo-cli not found. Please install 'kompo-cli'." unless komop_cli
      raise "libkompo_fs.a not found. Please install 'kompo-cli'." unless lib_kompo_dir
      raise "Entrypoint not found: '#{entrypoint}'. Please specify the entry file path with '-e' or '--entrypoint' option." unless File.exist?(entrypoint)

      true
    end

    def self.cd_work_dir(option)
      Dir.mktmpdir do |dir|
        task = new(option.build, dir)
        task.valid?
        FileUtils.cd(dir)

        yield task
      end
    end

    def clone_ruby_src
      if ruby_src_path.nil?
        command = ['git', '-C', "#{work_dir}", 'clone', '-b', "#{ruby_version}", '--single-branch', '--depth=1', 'https://github.com/ruby/ruby.git'].join(' ')
        exec_command command, 'git clone ruby.git'

        Dir.chdir(ruby_src_dir) do
          exec_command (File.exist?("#{ruby_src_dir}/autogen.sh") ? './autogen.sh' : "autoconf"), 'autoxxx'

          command = [
            './configure',
            "--prefix=#{work_dir}/dest_dir",
            "--disable-install-doc",
            "--disable-install-rdoc",
            "--disable-install-capi",
            "--with-static-linked-ext",
            "--with-ruby-pc=ruby.pc",
            "--with-ext=#{get_exts_dir}"
          ].join(' ')
          exec_command command, 'configure'

          exec_command ['make', 'install'].join(' '), 'build target version ruby'
        end
      end
    end

    def get_from_ruby_pc(option)
      command = [
        'pkg-config',
        "#{option}",
        "#{ruby_pc}"
      ].join(' ')

      exec_command(command, 'pkg-config', true)
    end

    def bundle_install
      if cache_bundle_path
        FileUtils.cp_r(cache_bundle_path, work_dir)
        @bundle_setup = File.join(cache_bundle_path, 'bundler', 'setup.rb')
        @bundle_ruby = File.join(cache_bundle_path, 'ruby')
      else
        File.write('./bundler', File.read(`which bundle`.chomp).split("\n").tap { _1[0] = "#!#{ruby_bin}" }.join("\n"))
        FileUtils.chmod(0755, './bundler')

        command = [
          './bundler',
          'install',
          '--standalone'
        ].join(' ')

        exec_command command, 'bundle install'

        @bundle_setup = File.join(work_dir, 'bundle', 'bundler', 'setup.rb')
        @bundle_ruby = File.join(work_dir, 'bundle', 'ruby')
      end
    end

    def fs_cli
      command = [
        komop_cli,
        context,
        args.join(' '),
        get_load_paths,
        "--entrypoint=#{entrypoint}",
      ].join(' ')

      exec_command command, 'kompo-cli'
    end

    def make_main_c
      require 'erb'

      exts = []
      Dir.glob(File.join(bundle_ruby, get_semantic_ruby_version, 'gems/**/extconf.rb')).each do |makefile_dir|
        dir_name = File.dirname(makefile_dir)
        makefile = File.join(dir_name, 'Makefile')
        if File.exist?(cargo_toml = File.join(dir_name, 'Cargo.toml'))
          command = [
            'cargo',
            'rustc',
            '--release',
            '--crate-type=staticlib',
            '--target-dir',
            'target',
            "--manifest-path=#{cargo_toml}",
          ].join(' ')
          exec_command command, 'cargo build'
          copy_targets = Dir.glob(File.join(dir_name, 'target/release/*.a'))
        else
          objs = File.read(makefile).scan(/OBJS = (.*\.o)/).join(' ')
          command = ['make', '-C', dir_name, objs, '--always-make'].join(' ')
          exec_command command, 'make'
          copy_targets = objs.split(' ').map { File.join(dir_name, _1) }
        end

        dir = FileUtils.mkdir_p('exts/' + File.basename(dir_name)).first
        FileUtils.cp(copy_targets, dir)
        prefix = File.read(makefile).scan(/target_prefix = (.*)/).join.delete_prefix('/')
        target_name = File.read(makefile).scan(/TARGET_NAME = (.*)/).join
        exts << [File.join(prefix, "#{target_name}.so").delete_prefix('/'), "Init_#{target_name}"]
      end

      File.write("main.c", ERB.new(File.read(File.join(__dir__, 'main.c.erb'))).result(binding))
    end

    def packing
      command = [
        'gcc',
        '-O3',
        '-Wall',
        'main.c',
        'exts/**/*.o',
        'fs.o',
        "#{lib_ruby_static_dir.nil? ? '' : '-L' + lib_ruby_static_dir}",
        "#{lib_kompo_dir.nil? ? '' : '-L' + lib_kompo_dir}",
        get_ruby_header,
        get_exts,
        '-lkompo',
        '-lruby-static',
        get_libs,
        '-o',
        output_name
      ].join(' ')

      exec_command command, 'Packing'
    end

    def copy_to_dest_dir
      command = ['cp', '-f', output_name, dest_dir].join(' ')
      exec_command command, 'Copy to dest dir'
    end

    private

    def exec_command(command, info = nil, ret = false)
      puts "exec: #{info}" if info
      puts command
      if ret
        ret = `#{command}`.chomp
        if $?.exited?
          ret
        else
          raise "Failed to execute command: #{command}"
        end
      else
        system command, exception: true
      end
    end

    def get_exts
      ["#{extinit_o}", "#{encinit_o}", *Dir.glob("#{ruby_src_dir}/ext/**/*.a"), *Dir.glob("#{ruby_src_dir}/enc/**/*.a")].join(' ')
    end

    def get_libs
      main_lib = get_mainlibs
      ext_libs = Dir.glob("#{ruby_src_dir}/ext/**/exts.mk").flat_map { File.read(_1).scan(/EXTLIBS = (.*)/) }.join(" ")
      gem_libs = Dir.glob("bundle/ruby/#{get_semantic_ruby_version}/gems/*/ext/*/Makefile").flat_map{ File.read(_1).scan(/LIBS = (.*)/)}.join(" ")
      dyn, static = eval("%W[#{main_lib} #{ext_libs} #{gem_libs}]").uniq
                                                                   .partition { _1 == "-lpthread" || _1 == "-ldl" || _1 == "-lm" || _1 == "-lc" }
      dyn.unshift "-Wl,-Bdynamic"
      static.unshift "-Wl,-Bstatic"

      static.join(" ") + " " + dyn.join(" ")
    end

    def get_ruby_header
      get_from_ruby_pc('--cflags')
    end

    def get_semantic_ruby_version
      get_from_ruby_pc('--variable=ruby_version')
    end

    def get_mainlibs
      get_from_ruby_pc('--variable=MAINLIBS')
    end

    def get_load_paths
      load_paths = []
      if gemfile
        load_paths += gem_libs
      end

      if stdlib
        load_paths += std_libs
      end

      load_paths
    end

    def get_exts_dir
      Dir.glob("#{ruby_src_dir}/**/extconf.rb")
         .reject { _1 =~ /-test-/ }
         .reject { _1 =~ /win32/ } # TODO
         .map { File.dirname(_1) }
         .map { _1.split("#{ruby_src_dir}/ext/")[1] }
         .join(',')
    end

    def std_libs
      return [] unless stdlib
      return @std_libs unless @std_libs.empty?

      command = ["#{ruby_bin}", '-e', "'puts $:'"].join(' ')

      @std_libs = exec_command(command, 'Check std_libs', true).split("\n")
    end

    def gem_libs
      return [] unless gemfile
      return @gem_libs unless @gem_libs.empty?

      FileUtils.cp_r(File.join(context, 'Gemfile'), work_dir)
      FileUtils.cp_r(File.join(context, 'Gemfile.lock'), work_dir)

      bundle_install

      command = [
        "#{ruby_bin}",
        '-r',
        "#{bundle_setup}",
        '-e',
        "'puts $:'"
      ].join(' ')

      @gem_libs = (exec_command(command, 'Check gem_libs', true).split("\n") - std_libs)
    end
  end

  class Fs
    attr_reader :komop_cli, :lib_kompo_dir

    def initialize
      @komop_cli = local_komop_cli || ENV['KOMPO_CLI']
      @lib_kompo_dir = local_lib_kompo_dir || ENV['LIB_KOMPO_DIR']
    end

    def local_komop_cli
      return nil if `which brew`.empty?

      path = `brew --prefix kompo-vfs`.chomp + '/bin/kompo-cli'
      if File.exist?(path)
        path
      else
        nil
      end
    end

    def local_lib_kompo_dir
      return nil if `which brew`.empty?

      path = `brew --prefix kompo-vfs`.chomp + '/lib'
      if File.exist?(path)
        path
      else
        nil
      end
    end
  end
end
