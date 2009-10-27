require 'fileutils'
require 'duby/transform'
require 'duby/ast'
require 'duby/typer'
require 'duby/compiler'
begin
  require 'bitescript'
rescue LoadError
  $: << File.dirname(__FILE__) + '/../../bitescript/lib'
  require 'bitescript'
end
require 'duby/jvm/compiler'
require 'duby/jvm/typer'
Dir[File.dirname(__FILE__) + "/duby/plugin/*"].each {|file| require "#{file}" if file =~ /\.rb$/}
require 'jruby'

module Duby
  VERSION = '0.0.1'
  
  def self.run(*args)
    DubyImpl.new.run(*args)
  end
  
  def self.compile(*args)
    DubyImpl.new.compile(*args)
  end
  
  def self.parse(*args)
    DubyImpl.new.parse(*args)
  end
end

class DubyImpl
  def run(*args)
    ast = parse(*args)

    main_cls = nil
    compile_ast(ast) do |outfile, builder|
      bytes = builder.generate
      name = builder.class_name.gsub(/\//, '.')
      cls = JRuby.runtime.jruby_class_loader.define_class(name, bytes.to_java_bytes)
      proxy_cls = JavaUtilities.get_proxy_class(name)
      # TODO: using first main; find correct one
      if proxy_cls.respond_to? :main
        main_cls ||= proxy_cls
      end
    end
  
    if main_cls
      main_cls.main(args.to_java(:string))
    else
      puts "No main found"
    end
  end
  
  def compile(*args)
    process_flags!(args)
    
    expand_files(args).each do |duby_file|
      if duby_file == '-e'
        @filename = '-e'
        next
      elsif @filename == '-e'
        ast = parse('-e', duby_file)
      else
        ast = parse(duby_file)
      end
      exit 1 if @error

      compile_ast(ast) do |filename, builder|
        filename = "#{@dest}#{filename}"
        FileUtils.mkdir_p(File.dirname(filename))
        bytes = builder.generate
        File.open(filename, 'w') {|f| f.write(bytes)}
      end
      @filename = nil
    end
  end

  def parse(*args)
    process_flags!(args)
    @filename = args.shift

    if @filename == '-e'
      @filename = 'dash_e'
      src = args[0]
    else
      src = File.read(@filename)
    end
    Duby::AST.type_factory = Duby::JVM::Types::TypeFactory.new(@filename)
    ast = Duby::AST.parse_ruby(src, @filename)
    @transformer = Duby::Transform::Transformer.new
    ast = @transformer.transform(ast, nil)
    @transformer.errors.each do |ex|
      raise ex.cause || ex if @verbose
      puts "#@filename:#{ex.position.start_line+1}: #{ex.message}"
    end
    @error = @transformer.errors.size > 0
    ast
  end

  def compile_ast(ast, &block)
    typer = Duby::Typer::JVM.new(@filename)
    typer.infer(ast)
    begin
      typer.resolve(true)
    ensure
      typer.errors.each do |ex|
        puts ex.message
        puts ex.backtrace if @verbose
      end
    end

    compiler = @compiler_class.new(@filename)
    ast.compile(compiler, false)
    compiler.generate(&block)
  end

  def process_flags!(args)
    while args.length > 0
      case args[0]
      when '-V'
        Duby::Typer.verbose = true
        Duby::AST.verbose = true
        Duby::Compiler::JVM.verbose = true
        @verbose = true
        args.shift
      when '-java'
        require 'duby/jvm/source_compiler'
        @compiler_class = Duby::Compiler::JavaSource
        args.shift
      when '-d'
        args.shift
        @dest = File.join(args.shift, '')
      when '-p'
        args.shift
        plugin = args.shift
        require "duby/plugin/#{plugin}"
      when '-I'
        args.shift
        $: << args.shift
      else
        break
      end
    end
    @compiler_class ||= Duby::Compiler::JVM
  end
  
  def expand_files(files)
    expanded = []
    files.each do |filename|
      if File.directory?(filename)
        Dir[File.join(filename, '*')].each do |child|
          if File.directory?(child)
            files << child
          elsif child =~ /\.duby$/
            expanded << child
          end
        end
      else
        expanded << filename
      end
    end
    expanded
  end
end

if __FILE__ == $0
  Duby.run(ARGV[0], *ARGV[1..-1])
end