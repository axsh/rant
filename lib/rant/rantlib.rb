
require 'getoptlong'
require 'rant/env'
require 'rant/rantfile'
require 'rant/fileutils'

class Array
    def arglist
	self.shell_pathes.join(' ')
    end

    def shell_pathes
	if ::Rant::Env.on_windows?
	    self.collect { |entry|
		entry = entry.tr("/", "\\")
		if entry.include? ' '
		    '"' + entry + '"'
		else
		    entry
		end
	    }
	else
	    self.collect { |entry|
		if entry.include? ' '
		    "'" + entry + "'"
		else
		    entry
		end
	    }
	end
    end
end

module Rant end

module Rant::Lib
    
    # Parses one string (elem) as it occurs in the array
    # which is returned by caller.
    # E.g.:
    #	p parse_caller_elem "/usr/local/lib/ruby/1.8/irb/workspace.rb:52:in `irb_binding'"
    # prints:
    #   {:method=>"irb_binding", :ln=>52, :file=>"/usr/local/lib/ruby/1.8/irb/workspace.rb"} 
    def parse_caller_elem elem
	parts = elem.split(":")
	rh = {	:file => parts[0],
		:ln => parts[1].to_i
	     }
	meth = parts[2]
	if meth && meth =~ /\`(\w+)'/
	    meth = $1
	end
	rh[:method] = meth
	rh
    end

    module_function :parse_caller_elem
end

module Rant
    VERSION	= '0.1.9'

    # Those are the filenames for rantfiles.
    # Case doens't matter!
    RANTFILES	= [	"rantfile",
			"rantfile.rb",
			"rant",
			"rant.rb"
		  ]

    CONFIG_FN	= 'config'

    class RantAbortException < StandardError
    end

    class RantDoneException < StandardError
    end

    @@rantapp = nil

    class << self

	# Run a new rant application in the current working directory.
	# This has the same effect as running +rant+ from the
	# commandline. You can give arguments as you would give them
	# on the commandline.  If no argument is given, ARGV will be
	# used.
	#
	# This method returns 0 if the rant application was
	# successfull and 1 on failure. So if you need your own rant
	# startscript, it could look like:
	#
	#	exit Rant.run
	#
	# This runs rant in the current directory, using the arguments
	# given to your script and the exit code as suggested by the
	# rant application.
	#
	# Or if you want rant to always be quiet with this script,
	# use:
	#
	#	exit Rant.run("--quiet", ARGV)
	#
	# Of course, you can invoke rant directly at the bottom of
	# your rantfile, so you can run it directly with ruby.
	def run(first_arg=nil, *other_args)
	    other_args = other_args.flatten
	    args = first_arg.nil? ? ARGV.dup : ([first_arg] + other_args)
	    if @@rantapp && !@@rantapp.done?
		@@rantapp.args.replace(args.flatten)
		@@rantapp.run
	    else
		app = Rant::RantApp.new(args)
		app.run
	    end
	end

	def rantapp
	    ensure_rantapp
	    @@rantapp
	end
	def rantapp=(app)
	    @@rantapp = app
	end
    end

    # "Clear" the current Rant application. After this call,
    # Rant has the same state as immediately after startup.
    def reset
	@@rantapp = nil
    end

    def ensure_rantapp
	# the new app registers itself with
	# Rant.rantapp=
	Rant::RantApp.new unless @@rantapp
    end
    private :ensure_rantapp

    # Define a basic task.
    def task targ, &block
	ensure_rantapp
	@@rantapp.task(targ, &block)
    end

    # Define a file task.
    def file targ, &block
	ensure_rantapp
	@@rantapp.file(targ, &block)
    end

    # Add code and/or prerequisites to existing task.
    def enhance targ, &block
	Rant.rantapp.enhance(targ, &block)
    end

    def show(*args)
	Rant.rantapp.show(*args)
    end

    def desc(*args)
	Rant.rantapp.desc(*args)
    end

    # Create a path.
    def directory targ, &block
	ensure_rantapp
	@@rantapp.directory(targ, &block)
    end

    # Look in the subdirectories, given by args,
    # for rantfiles.
    def subdirs *args
	ensure_rantapp
	@@rantapp.subdirs(*args)
    end

    def load_rantfile rantfile
	ensure_rantapp
	@@rantapp.load_rantfile(rantfile)
    end

    def [](opt)
	Rant.rantapp[opt]
    end

    def []=(opt, val)
	Rant.rantapp[opt] = val
    end

    def abort_rant
	if @@rantapp
	    @@rantapp.abort
	else
	    $stderr.puts "rant aborted!"
	    exit 1
	end
    end

    module_function :task, :file, :show, :desc, :subdirs
    module_function :ensure_rantapp, :abort_rant

end	# module Rant

class Rant::RantApp
    include Rant::Console

    # The RantApp class has no own state.

    OPTIONS	= [
	[ "--help",	"-h",	GetoptLong::NO_ARGUMENT,
	    "Print this help and exit."				],
	[ "--version",	"-V",	GetoptLong::NO_ARGUMENT,
	    "Print version of Rant and exit."			],
	[ "--verbose",	"-v",	GetoptLong::NO_ARGUMENT,
	    "Print more messages to stderr."			],
	[ "--quiet",	"-q",	GetoptLong::NO_ARGUMENT,
	    "Don't print commands."			],
	[ "--directory","-C",	GetoptLong::REQUIRED_ARGUMENT,
	    "Run rant in DIRECTORY."				],
	[ "--rantfile",	"-f",	GetoptLong::REQUIRED_ARGUMENT,
	    "Process RANTFILE instead of standard rantfiles.\n" +
	    "Multiple files may be specified with this option"	],
	[ "--force-run","-a",	GetoptLong::REQUIRED_ARGUMENT,
	    "Force TARGET to be run, even if it isn't required.\n"],
	[ "--targets",	"-T",	GetoptLong::NO_ARGUMENT,
	    "Show a list of all described targets and exit."	],
    ]

    # Arguments, usually those given on commandline.
    attr_reader :args
    # A list of all Rantfiles used by this app.
    attr_reader :rantfiles
    # A list of target names to be forced (run even
    # if not required). Each of these targets will be removed
    # from this list after the first run.
    #
    # Forced targets will be run before other targets.
    attr_reader :force_targets
    # A list with all tasks.
    attr_reader :tasks
    # A list of all registered plugins.
    attr_reader :plugins

    def initialize *args
	@args = args.flatten
	@rantfiles = []
	Rant.rantapp = self
	@opts = {
	    :verbose	=> 0,
	    :quiet	=> false,
	}
	@arg_rantfiles = []	# rantfiles given in args
	@arg_targets = []	# targets given in args
	@force_targets = []
	@ran = false
	@done = false
	@tasks = []
	@plugins = []

	@task_show = nil
	@task_desc = nil

	@orig_pwd = nil

	@block_task_mkdir = lambda { |t|
	    ::Rant::FileUtils.mkdir t.name
	}

    end

    def [](opt)
	@opts[opt]
    end

    def []=(opt, val)
	case opt
	when :directory
	    self.rootdir = val
	else
	    @opts[opt] = val
	end
    end

    def rootdir
	@opts[:directory].dup
    end

    def rootdir=(newdir)
	if @ran
	    raise "rootdir of rant application can't " +
		"be changed after calling `run'"
	end
	@opts[:directory] = newdir.dup
	rootdir	# return a dup of the new rootdir
    end

    def ran?
	@ran
    end

    def done?
	@done
    end

    # Returns 0 on success and 1 on failure.
    def run
	@ran = true
	# remind pwd
	@orig_pwd = Dir.pwd
	# Process commandline.
	process_args
	# Set pwd.
	if @opts[:directory]
	    @opts[:directory] != @orig_pwd && ::Rant::FileUtils.cd(rootdir)
	else
	    @opts[:directory] = @orig_pwd
	end
	# read rantfiles
	load_rantfiles
	# Notify plugins before running tasks
	@plugins.each { |plugin| plugin.rant_start }
	if @opts[:targets]
	    show_descriptions
	end
	# run tasks
	run_tasks
	raise Rant::RantDoneException
    rescue Rant::RantDoneException
	@done = true
	# Notify plugins
	@plugins.each { |plugin| plugin.rant_done }
	return 0
    rescue Rant::RantAbortException
	$stderr.puts "rant aborted!"
	return 1
    rescue
	err_msg $!.message, $!.backtrace
	$stderr.puts "rant aborted!"
	return 1
    ensure
	# TODO: exception handling!
	@plugins.each { |plugin| plugin.rant_plugin_stop }
	@plugins.each { |plugin| plugin.rant_quit }
	# restore pwd
	Dir.pwd != @orig_pwd && ::Rant::FileUtils.cd(@orig_pwd)
    end

    def show *args
	@task_show = *args.join("\n")
    end

    def desc *args
	@task_desc = args.join("\n")
    end

    def task targ, &block
	prepare_task(targ, block) { |name,pre,blk|
	    Rant::Task.new(self, name, pre, &blk)
	}
    end

    def file targ, &block
	prepare_task(targ, block) { |name,pre,blk|
	    Rant::FileTask.new(self, name, pre, &blk)
	}
    end

    # Add block and prerequisites to the task specified by the
    # name given as only key in targ.
    # If there is no task with the given name, generate a warning
    # and a new file task.
    def enhance targ, &block
	prepare_task(targ, block) { |name,pre,blk|
	    t = select_task { |t| t.name == name }
	    if t
		t.enhance(pre, &blk)
		return t
	    end
	    warn_msg "enhance \"#{name}\": no such task",
		"Generating a new file task with the given name."
	    Rant::FileTask.new(self, name, pre, &blk)
	}
    end

    # An eventuelly given block will be called after creation of the
    # last directory element.
    def directory path, &block
	cinf = Rant::Lib.parse_caller_elem(caller[1])
	path = normalize_task_arg(path, cinf[:file], cinf[:ln])
	dirs = ::Rant::FileUtils.split_path(path)
	if dirs.empty?
	    # TODO: warning
	    return nil
	end
	ld = nil
	path = nil
	task_block = @block_task_mkdir
	dirs.each { |dir|
	    if block && dir.equal?(dirs.last)
		task_block = lambda { |t|
		    @block_task_mkdir[t]
		    block[t]
		}
	    end
	    path = path.nil? ? dir : File.join(path, dir)
	    prepare_task({path => (ld || [])},
		    task_block) { |name,pre,blk|
		Rant::FileTask.new(self, name, pre, &blk)
	    }
	    ld = dir
	}
    end

    def load_rantfile rantfile
	rf, is_new = rantfile_for_path(rantfile)
	return false unless is_new
	load_file rf
	true
    end

    # Search the given directories for Rantfiles.
    def subdirs *args
	args.flatten!
	cinf = Rant::Lib::parse_caller_elem(caller[1])
	ln = cinf[:ln] || 0
	file = cinf[:file]
	args.each { |arg|
	    if arg.is_a? Symbol
		arg = arg.to_s
	    elsif arg.respond_to? :to_str
		arg = arg.to_str
	    end
	    unless arg.is_a? String
		abort(pos_text(file, ln),
		    "in `subdirs' command: arguments must be strings")
	    end
	    loaded = false
	    rantfiles_in_dir(arg).each { |f|
		loaded = true
		rf, is_new = rantfile_for_path(f)
		if is_new
		    load_file rf
		end
	    }
	    unless loaded || quiet?
		warn_msg(pos_text(file, ln) + "; in `subdirs' command:",
		    "No Rantfile in subdir `#{arg}'.")
	    end
	}
    rescue SystemCallError => e
	abort(pos_text(file, ln),
	    "in `subdirs' command: " + e.message)
    end

    def abort *msg
	err_msg(msg) unless msg.empty?
	raise Rant::RantAbortException
    end

    def help
	puts "rant [-f RANTFILE] [OPTIONS] targets..."
	puts
	puts "Options are:"
	OPTIONS.each { |lopt, sopt, mode, desc|
	    optstr = ""
	    arg = nil
	    if mode == GetoptLong::REQUIRED_ARGUMENT
		if desc =~ /(\b[A-Z_]{2,}\b)/
		    arg = $1
		end
	    end
	    if lopt
		optstr << lopt
		if arg
		    optstr << " " << arg
		end
		optstr = optstr.ljust(30)
	    end
	    if sopt
		optstr << "   " unless optstr.empty?
		optstr << sopt
		if arg
		    optstr << " " << arg
		end
	    end
	    puts "  " + optstr
	    puts "      " + desc.split("\n").join("\n      ")
	}
	raise Rant::RantDoneException
    end

    def show_descriptions
	tlist = select_tasks { |t| t.description }
	if tlist.empty?
	    msg "No described targets."
	    raise Rant::RantDoneException
	end
	prefix = "rant "
	infix = "  # "
	name_length = 0
	tlist.each { |t|
	    if t.name.length > name_length
		name_length = t.name.length
	    end
	}
	name_length < 7 && name_length = 7
	cmd_length = prefix.length + name_length
	tlist.each { |t|
	    print(prefix + t.name.ljust(name_length) + infix)
	    dt = t.description.sub(/\s+$/, "")
	    puts dt.sub("\n", "\n" + ' ' * cmd_length + infix + "  ")
	}
	raise Rant::RantDoneException
    end
		
    # Increase verbosity.
    def more_verbose
	@opts[:verbose] += 1
	@opts[:quiet] = false
    end
    
    def verbose
	@opts[:verbose]
    end

    def quiet?
	@opts[:quiet]
    end

    def pos_text file, ln
	t = "in file `#{file}'"
	if ln && ln > 0
	    t << ", line #{ln}"
	end
	t + ": "
    end

    def msg *args
	verbose_level = args[0]
	if verbose_level.is_a? Integer
	    super(args[1..-1]) if verbose_level <= verbose
	else
	    super
	end
    end

    ###### public methods regarding plugins ##########################
    # Every plugin instance has to register itself with this method.
    # The first argument has to be the plugin object. Currently, no
    # other arguments are used.
    def plugin_register(*args)
	plugin = args[0]
	unless plugin.respond_to? :rant_plugin?
	    abort("Invalid plugin register:", plugin.inspect, caller)
	end
	@plugins << plugin
	msg 2, "Plugin `#{plugin.rant_plugin_name}' registered."
	plugin.rant_plugin_init
    end
    # The preferred way for a plugin to report a warning.
    def plugin_warn(*args)
	warn_msg(*args)
    end
    # The preferred way for a plugin to report an error.
    def plugin_err(*args)
	err_msg(*args)
    end

    # Get the plugin with the given name or nil. Yields the plugin
    # object if block given.
    def plugin_named(name)
	@plugins.each { |plugin|
	    if plugin.rant_plugin_name == name
		yield plugin if block_given?
		return plugin
	    end
	}
	nil
    end
    ##################################################################

    # All targets given on commandline, including those given
    # with the -a option. The list will be in processing order.
    def cmd_targets
	@force_targets + @arg_targets
    end

    private
    def have_any_task?
	not @rantfiles.all? { |f| f.tasks.empty? }
    end

    def run_tasks
	unless have_any_task?
	    abort("No tasks defined for this rant application!")
	end
	# Target selection strategy:
	# Run tasks specified on commandline, if not given:
	# run default task, if not given:
	# run first defined task.
	target_list = @force_targets + @arg_targets
	# The target list is a list of strings, not Task objects!
	if target_list.empty?
	    have_default = @rantfiles.any? { |f|
		f.tasks.any? { |t| t.name == "default" }
	    }
	    if have_default
		target_list << "default"
	    else
		first = nil
		@rantfiles.each { |f|
		    unless f.tasks.empty?
			first = f.tasks.first.name
		    end
		}
		target_list << first
	    end
	end
	# Now, run all specified tasks in all rantfiles,
	# rantfiles in reverse order.
	rev_files = @rantfiles.reverse
	force = false
	matching_tasks = 0
	target_list.each do |target|
	    matching_tasks = 0
	    if @force_targets.include?(target)
		force = true
		@force_targets.delete(target)
	    else
		force = false
	    end
	    (select_tasks { |t| t.name == target }).each { |t|
		matching_tasks += 1
		begin
		    t.run if force || t.needed?
		rescue Rant::TaskFail => e
		    # TODO: Report failed dependancy.
		    abort("Task `#{e.message}' fail.")
		end
	    }
	    if matching_tasks == 0
		abort("Don't know how to build `#{target}'.")
	    end
	end
    end

    # Returns a list with all tasks for which yield
    # returns true.
    def select_tasks
	selection = []
	@rantfiles.reverse.each { |rf|
	    rf.tasks.each { |t|
		selection << t if yield t
	    }
	}
	selection
    end
    public :select_tasks

    # Get the first task for which yield returns true. Returns nil if
    # yield never returned true.
    def select_task
	@rantfiles.reverse.each { |rf|
	    rf.tasks.each { |t|
		return t if yield t
	    }
	}
	nil
    end

    def load_rantfiles
	# Take care: When rant isn't invoked from commandline,
	# some "rant code" could already have run!
	# We run the default Rantfiles only if no tasks where
	# already defined and no Rantfile was given in args.
	new_rf = []
	@arg_rantfiles.each { |rf|
	    if test(?f, rf)
		new_rf << rf
	    else
		abort("No such file: " + rf)
	    end
	}
	if new_rf.empty? && !have_any_task?
	    # no Rantfiles given in args, no tasks defined,
	    # so let's look for the default files
	    new_rf = rantfiles_in_dir
	end
	new_rf.map! { |path|
	    rf, is_new = rantfile_for_path(path)
	    if is_new
		load_file rf
	    end
	    rf
	}
	if @rantfiles.empty?
	    abort("No Rantfile in current directory (" + Dir.pwd + ")",
		"looking for " + Rant::RANTFILES.join(", ") +
		"; case doesn't matter.")
	end
    end

    def load_file rantfile
	msg 1, "loading #{rantfile.path}"
	begin
	    # load with absolute path to avoid require problems
	    load rantfile.absolute_path
	rescue NameError => e
	    abort("Name error when loading `#{rantfile.path}':",
	    e.message, e.backtrace)
	rescue LoadError => e
	    abort("Load error when loading `#{rantfile.path}':",
	    e.message, e.backtrace)
	rescue ScriptError => e
	    abort("Script error when loading `#{rantfile.path}':",
	    e.message, e.backtrace)
	end
	unless @rantfiles.include?(rantfile)
	    @rantfiles << rantfile
	end
    end
    private :load_file

    # Get all rantfiles in dir.
    # If dir is nil, look in current directory.
    # Returns always an array with the pathes (not only the filenames)
    # to the rantfiles.
    def rantfiles_in_dir dir=nil
	files = []
	Dir.entries(dir || Dir.pwd).each { |entry|
	    path = (dir ? File.join(dir, entry) : entry)
	    if test(?f, path)
		Rant::RANTFILES.each { |rname|
		    if entry.downcase == rname
			files << path
			break
		    end
		}
	    end
	}
	files
    end

    def process_args
	# WARNING: we currently have to fool getoptlong,
	# by temporory changing ARGV!
	# This could cause problems.
	old_argv = ARGV
	ARGV.replace(@args.dup)
	cmd_opts = GetoptLong.new(*OPTIONS.collect { |lst| lst[0..-2] })
	cmd_opts.quiet = true
	cmd_opts.each { |opt, value|
	    case opt
	    when "--verbose": more_verbose
	    when "--quiet"
		@opts[:quiet] = true
		@opts[:verbose] = -1
	    when "--version"
		$stdout.puts "rant #{Rant::VERSION}"
		raise Rant::RantDoneException
	    when "--help"
		help
	    when "--directory"
		@opts[:directory] = value
	    when "--rantfile"
		@arg_rantfiles << value
	    when "--force-run"
		@force_targets << value
	    when "--targets"
		@opts[:targets] = true
	    end
	}
    rescue GetoptLong::Error => e
	abort(e.message)
    ensure
	rem_args = ARGV.dup
	ARGV.replace(old_argv)
	rem_args.each { |ra|
	    if ra =~ /(^[^=]+)=([^=]+)$/
		ENV[$1] = $2
	    else
		@arg_targets << ra
	    end
	}
    end

    def prepare_task targ, block
	clr = caller[2]

	# Allow override of caller, usefull for plugins and libraries
	# that define tasks.
	if targ.is_a? Hash
	    targ.reject! { |k, v|
		case k
		when :__caller__
		    clr = v
		    true
		else
		    false
		end
	    }
	end

	ch = Rant::Lib::parse_caller_elem(clr)
	name = nil
	pre = []
	ln = ch[:ln] || 0
	file = ch[:file]
	
	# process and validate targ
	if targ.is_a? Hash
	    if targ.empty?
		abort(pos_text(file, ln),
		    "Empty hash as task argument, " +
		    "task name required.")
	    end
	    if targ.size > 1
		abort(pos_text(file, ln),
		    "Too many hash elements, " +
		    "should only be one.")
	    end
	    targ.each_pair { |k,v|
		name = normalize_task_arg(k, file, ln)
		pre = v
	    }
	    if pre.respond_to? :to_ary
		pre = pre.to_ary.dup
		pre.map! { |elem|
		    normalize_task_arg(elem, file, ln)
		}
	    else
		pre = [normalize_task_arg(pre, file, ln)]
	    end
	else
	    name = normalize_task_arg(targ, file, ln)
	end

	file, is_new = rantfile_for_path(file)
	nt = yield(name, pre, block)
	nt.rantfile = file
	nt.line_number = ln
	nt.description = @task_desc
	@task_desc = nil
	file.tasks << nt
	nt
    end

    # Tries to make a task name out of arg and returns
    # the valid task name. If not possible, calls abort
    # with an appropriate error message using file and ln.
    def normalize_task_arg(arg, file, ln)
	return arg if arg.is_a? String
	if arg.respond_to? :to_str
	    arg = arg.to_str
	elsif arg.is_a? Symbol
	    arg = arg.to_s
	else
	    abort(pos_text(file, ln),
		"Task name has to be a string or symbol.")
	end
	arg
    end

    # Returns a Rant::Rantfile object as first value
    # and a boolean value as second. If the second is true,
    # the rantfile was created and added, otherwise the rantfile
    # already existed.
    def rantfile_for_path path
	if @rantfiles.any? { |rf| rf.path == path }
	    file = @rantfiles.find { |rf| rf.path == path }
	    [file, false]
	else
	    file = Rant::Rantfile.new(path)
	    @rantfiles << file
	    [file, true]
	end
    end

end	# class Rant::RantApp
