require 'rake'
require 'rake/testtask'
require 'java'
$: << './lib'
require 'duby'
require 'jruby/compiler'
require 'ant'

task :default => :test

Rake::TestTask.new :test do |t|
  t.libs << "lib"
  # This is hacky, I know
  t.libs.concat Dir["../bitescript*/lib"]
  t.test_files = FileList["test/**/*.rb"]
  java.lang.System.set_property("jruby.duby.enabled", "true")
end

task :init do
  mkdir_p 'dist'
  mkdir_p 'build'
end

task :clean do
  ant.delete :quiet => true, :dir => 'build'
  ant.delete :quiet => true, :dir => 'dist'
end

task :compile => :init do
  # build the Ruby sources
  puts "Compiling Ruby sources"
  JRuby::Compiler.compile_argv([
    '-t', 'build',
    '--javac',
    'src/org/jruby/duby/duby_command.rb'
  ])
  
  # build the Duby sources
  puts "Compiling Duby sources"
  Dir.chdir 'src' do
    classpath = Duby::Env.encode_paths([
        'javalib/jruby-complete.jar',
        'javalib/JRubyParser.jar',
        'dist/duby.jar',
        'build',
        '/usr/share/ant/lib/ant.jar'
      ])
    Duby.compile(
      '-c', classpath,
      '-d', '../build',
      'org/jruby/duby')
  end
end

task :jar => :compile do
  ant.jar :jarfile => 'dist/duby.jar' do
    fileset :dir => 'lib'
    fileset :dir => 'build'
    fileset :dir => '.', :includes => 'bin/*'
    fileset :dir => '../bitescript/lib'
    manifest do
      attribute :name => 'Main-Class', :value => 'org.jruby.duby.DubyCommand'
    end
  end
end

namespace :jar do
  task :complete => :jar do
    ant.jar :jarfile => 'dist/duby-complete.jar' do
      zipfileset :src => 'dist/duby.jar'
      zipfileset :src => 'javalib/jruby-complete.jar'
      zipfileset :src => 'javalib/JRubyParser.jar'
      manifest do
        attribute :name => 'Main-Class', :value => 'org.jruby.duby.DubyCommand'
      end
    end
  end
end