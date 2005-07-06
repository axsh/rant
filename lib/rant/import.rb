
# import.rb - Library for the rant-import command.
#
# Copyright (C) 2005 Stefan Lang <langstefan@gmx.at>

require 'getoptlong'
require 'rant/rantlib'

module Rant

    class RantImportDoneException < RantDoneException
    end

    class RantImportAbortException < RantAbortException
    end

    # This class is the implementation for the rant-import command.
    # Usage similar to RantApp class.
    class RantImport
	include Rant::Console

	LIB_DIR = File.expand_path(File.dirname(__FILE__))

	OPTIONS = [
	    [ "--help",		"-h",	GetoptLong::NO_ARGUMENT,
		"Print this help and exit."			],
	    [ "--version",	"-v",	GetoptLong::NO_ARGUMENT,
		"Print version of rant-import and exit."	],
	    [ "--quiet",	"-q",	GetoptLong::NO_ARGUMENT,
		"Operate quiet."				],
	    [ "--plugins",	"-p",	GetoptLong::REQUIRED_ARGUMENT,
		"Include PLUGINS (comma separated list)."	],
	    [ "--imports",	"-i",	GetoptLong::REQUIRED_ARGUMENT,
		"Include IMPORTS (comma separated list)."	],
	    [ "--force",		GetoptLong::NO_ARGUMENT,
		"Force overwriting of output file."		],
	    [ "--with-comments",	GetoptLong::NO_ARGUMENT,
		"Include comments from Rant sources."		],
	    [ "--reduce-whitespace", "-r",GetoptLong::NO_ARGUMENT,
		"Remove as much whitespace from Rant sources as possible." ],
	    [ "--auto",		"-a",	GetoptLong::NO_ARGUMENT,
		"Automatically try to determine imports and plugins.\n" +
		"Warning: loads Rantfile!"			],
	    [ "--rantfile",	"-f",	GetoptLong::REQUIRED_ARGUMENT,
		"Load RANTFILE. This also sets --auto!\n" +
		"May be given multiple times."			],
	]

	class << self
	    def run(first_arg=nil, *other_args)
		other_args = other_args.flatten
		args = first_arg.nil? ? ARGV.dup : ([first_arg] + other_args)
		new(args).run
	    end
	end

	# Arguments, usually those given on commandline.
	attr :args
	# Plugins to import.
	attr :plugins
	# Imports to import ;)
	attr :imports
	# Filename where the monolithic rant script goes to.
	attr :mono_fn
	# Skip comments? Defaults to true.
	attr_accessor :skip_comments
	# Remove whitespace from Rant sources? Defaults to false.
	attr_accessor :reduce_whitespace
	# Try automatic determination of imports and plugins?
	# Defaults to false.
	attr_accessor :auto

	def initialize(*args)
	    @args = args.flatten
	    @msg_prefix = "rant-import: "
	    @plugins = []
	    @imports = []
	    @mono_fn = nil
	    @force = false
	    @rantapp = nil
	    @core_imports = []
	    @lib_imports = []
	    @included_plugins = []
	    @included_imports = []
	    @skip_comments = true
	    @reduce_whitespace = false
	    @auto = false
	    @arg_rantfiles = []
	    @quiet = false
	end

	def run
	    process_args

	    if @auto
		rac_args = %w(--stop-after-load) + 
		    @arg_rantfiles.collect { |rf| "-f#{rf}" }
		rac_args << "-v" unless @quiet
		@rantapp = RantApp.new
		unless @rantapp.run(rac_args) == 0
		    abort("Auto-determination of required code failed.")
		end
		@imports.concat(@rantapp.imports)
		@plugins.concat(@rantapp.plugins.map { |p| p.name })
	    end
	    
	    if File.exist?(@mono_fn) && !@force
		abort("#{@mono_fn} exists. Rant won't overwrite this file.",
		    "Add --force to override this restriction.")
	    end
	    File.open(@mono_fn, "w") { |mf|
		mf << <<EOH
#!/usr/bin/env ruby

# #@mono_fn - Monolithic rant script, autogenerated by rant-import #{Rant::VERSION}.
#
# Copyright (C) 2005 Stefan Lang <langstefan@gmx.at>
#
# This program is free software.
# You can distribute/modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
EOH
		mf << mono_rant_core
		mf << mono_imports
		mf << mono_plugins
		mf << <<EOF

Rant::CODE_IMPORTS.concat %w(#{@included_imports.join(' ')}
    #{(@included_plugins.map do |i| "plugin/" + i end).join(' ')})

# Catch a `require "rant"', sad...
alias require_backup_by_rant require
def require libf
    if libf == "rant"
	self.class.instance_eval { include Rant }
    else
	begin
	    require_backup_by_rant libf
	rescue
	    raise $!, caller
	end
    end
end

Rant.run
EOF
	    }
	    msg "Done.",
		"Included imports: " + @included_imports.join(', '),
		"Included plugins: " + @included_plugins.join(', '),
		"Your monolithic rant was written to `#@mono_fn'!"
	    
	    done
	rescue RantImportDoneException
	    0
	rescue RantImportAbortException
	    $stderr.puts "rant-import aborted!"
	    1
	end

	def process_args
	    # WARNING: we currently have to fool getoptlong,
	    # by temporory changing ARGV!
	    # This could cause problems.
	    old_argv = ARGV.dup
	    ARGV.replace(@args.dup)
	    cmd_opts = GetoptLong.new(*OPTIONS.collect { |lst| lst[0..-2] })
	    cmd_opts.quiet = true
	    cmd_opts.each { |opt, value|
		case opt
		when "--version"
		    puts "rant-import #{Rant::VERSION}"
		    done
		when "--help": help
		when "--quiet": @quiet = true
		when "--force": @force = true
		when "--with-comments": @skip_comments = false
		when "--reduce-whitespace": @reduce_whitespace = true
		when "--imports"
		    @imports.concat(value.split(/\s*,\s*/))
		when "--plugins"
		    @plugins.concat(value.split(/\s*,\s*/))
		when "--auto"
		    @auto = true
		when "--rantfile"
		    @auto = true
		    @arg_rantfiles << value.dup
		end
	    }
	    rem_args = ARGV.dup
	    unless rem_args.size == 1 && !@mono_fn
		abort("Exactly one argument (besides options) required.",
		    "Type `rant-import --help' for usage.")
	    end
	    @mono_fn = rem_args.first if rem_args.first
	rescue GetoptLong::Error => e
	    abort(e.message)
	ensure
	    ARGV.replace(old_argv)
	end

	def done
	    raise RantImportDoneException
	end

	def help
	    puts "rant-import [OPTIONS] [-i IMPORT1,IMPORT2,...] [-p PLUGIN1,PLUGIN2...] MONO_RANT"
	    puts
	    puts "  Write a monolithic rant script to MONO_RANT."
	    puts
	    puts "Options are:"
	    print option_listing(OPTIONS)
	    done
	end

	def msg *args
	    super unless @quiet
	end

	def abort(*text)
	    err_msg(*text) unless text.empty?
	    raise RantImportAbortException
	end

	# Get a monolithic rant script (as string) containing only the
	# Rant core.
	def mono_rant_core
	    # Starting point is rant/rantlib.rb.
	    rantlib_f = File.join(LIB_DIR, "rantlib.rb")
	    begin
		rantlib = File.read rantlib_f
	    rescue
		abort("When trying to read `#{rantlib_f}': #$!",
		    "This file should contains the core of rant, so import is impossible.",
		    "Please check your rant installation!")
	    end
	    @core_imports << "rantlib"
	    resolve_requires rantlib
	end

	def mono_imports
	    rs = ""
	    @imports.each { |name|
		next if @included_imports.include? name
                lib_name = "import/#{name}"
                lib_fn = "#{lib_name}.rb"
		path = get_lib_rant_path lib_fn
		unless path
		    abort("No such import - #{name}")
		end
                @included_imports << name.dup
                unless @core_imports.include? lib_name
                    @core_imports << lib_name
                    msg "Including import `#{name}'", path
                    rs << resolve_requires(File.read(path))
                end
	    }
	    rs
	end

	def mono_plugins
	    rs = ""
	    @plugins.each { |name|
		lc_name = name.downcase
		next if @included_plugins.include? lc_name
                plugin_name = "plugin/#{lc_name}"
                plugin_fn = "#{plugin_name}.rb"
		path = get_lib_rant_path plugin_fn
		unless File.exist? path
		    abort("No such plugin - #{name}")
		end
		@included_plugins << lc_name
                unless @core_imports.include? plugin_name
                    @core_imports << plugin_name
                    msg "Including plugin `#{lc_name}'", path
                    rs << resolve_requires(File.read(path))
                end
	    }
	    rs
	end

	# +script+ is a string. This method resolves requires of rant/
	# code by directly inserting the code.
	def resolve_requires script
	    rs = ""
	    in_ml_comment = false
	    script.each { |line|
		if in_ml_comment
		    if line =~ /^=end/
			in_ml_comment = false
		    end
		    next if @skip_comments
		end
		# skip shebang line
		next if line =~ /^#! ?(\/|\\)?\w/
		# skip pure comment lines
		next if line =~ /^\s*#/ if @skip_comments
		if line =~ /^=begin\s/
		    in_ml_comment = true
		    next if @skip_comments
		end
		name = nil
		lib_file = nil
		if line =~ /\s*(require|load)\s+('|")rant\/(\w+)(\.rb)?('|")/
		    # Rant library code
		    name = $3
		elsif line =~ /\s*(require|load)\s+('|")rant\/(import\/\w+)(\.rb)?('|")/
		    # some "import" code
		    name = $3
		elsif line =~ /\s*(require|load)\s+('|")([^\2]+)\2[^r]*rant-import/
		    # a require which is explicitely labelled with rant-import
		    lib_file = $3
		end
		if name
		    next if @core_imports.include? name
		    path = get_lib_rant_path "#{name}.rb"
		    msg "Including `#{name}'", path
		    @core_imports << name
		    rs << resolve_requires(File.read(path))
		elsif lib_file
		    next if @lib_imports.include? lib_file
		    path = get_lib_path "#{lib_file}.rb"
		    msg "Including `#{lib_file}'", path
		    @lib_imports << lib_file
		    rs << resolve_requires(File.read(path))
		else
		    line.sub!(/^\s+/, '') if @reduce_whitespace
		    rs << line
		end
	    }
	    rs
	end

	private

	def get_lib_rant_path(fn)
	    path = File.join(LIB_DIR, fn)
	    return path if File.exist?(path)
	    $:.each { |lib_dir|
		path = File.join(lib_dir, "rant", fn)
		return path if File.exist?(path)
	    }
	    nil
	end

	def get_lib_path(fn)
	    $:.each { |lib_dir|
		path = File.join(lib_dir, fn)
		return path if File.exist?(path)
	    }
	    nil
	end

    end	# class RantImport
end	# module Rant
