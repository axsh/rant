
require 'rant/env'

class Rant::TaskFail < StandardError
end

class Rant::Rantfile < Rant::Path

    attr_reader :tasks
    
    def initialize(path)
	super
	@tasks = []
    end
end	# class Rant::Rantfile

class Rant::Task
    include Rant::Console

    class << self
	def fail msg = nil, clr = nil
	    clr ||= caller
	    raise Rant::TaskFail, msg, clr
	end
    end
    
    # Name of the task, this is always a string.
    attr_reader :name
    # A description for this task.
    attr_accessor :description
    # A reference to the application this task belongs to.
    attr_reader :app
    # The rantfile this task was defined in.
    # Should be a Rant::Rantfile instance.
    attr_accessor :rantfile
    # The linenumber in rantfile where this task was defined.
    attr_accessor :line_number
    
    def initialize(app, name, prerequisites = [], &block)
	@app = app || Rant.rantapp
	@name = name or raise ArgumentError, "name not given"
	@description = nil
	@pre = prerequisites || []
	@block = block
	@ran = false
	@fail = false
	@rantfile = nil
	@line_number = 0
    end

    def prerequisites
	@pre.collect { |pre|
	    if pre.is_a? String
		pre
	    elsif pre.is_a? ::Rant::Task
		pre.name
	    else
		pre.to_s
	    end
	}
    end

    # Add a prerequisite.
    def <<(pre)
	@pre << pre
    end

    # Cause task to fail. Equivalent to calling Task.fail.
    def fail msg = nil
	self.class.fail msg, caller
    end

    def ran?
	@ran
    end

    def fail?
	@fail
    end

    def done?
	ran? && !fail?
    end

    def needed?
	resolve_tasks
	each_task { |t| return true if t.needed? }
	!done?
    end

    # Enhance this task with the given dependencies and blk.
    def enhance(deps = [], &blk)
	@pre.concat deps if deps
	first_block = @block
	@block = lambda { |t|
	    first_block[t]
	    blk[t]
	}
    end

    # Raises a Rant::TaskFail exception on failure.
    def run
	@ran = true
	resolve_prerequisites
	ensure_tasks
	if @block
	    @fail = true
	    begin
		# A task run is considered as failed, if the called
		# block raises an exception.
		@block[self]
		@fail = false
	    rescue ::Rant::TaskFail => e
		m = e.message
		err_msg m if m && m != "Rant::TaskFail"
	    rescue ::Rant::CommandError => e
		err_msg e.message
	    rescue SystemCallError => e
		err_msg e.message
	    rescue
		err_msg $!.message, $!.backtrace
	    end
	    if @fail
		raise Rant::TaskFail, @name.to_s
	    end
	end
    end

    def ensure_tasks
	each_task { |t| t.run if t.needed?  }
    rescue Rant::TaskFail
	@fail = true
	raise
    end

    def resolve_prerequisites
	resolve_tasks
	each_non_task { |t|
	    err_msg "Unknown task `#{t.to_s}',",
		"referenced in `#{rantfile.path}', line #{@line_number}!"
	    raise Rant::TaskFail, @name.to_s
	}
    end

    def resolve_tasks
	@pre.map! { |t|
	    if t.is_a? Rant::Task
		t
	    else
		t = t.to_s if t.is_a? Symbol
		# Take care: selection is an array of tasks
		selection = @app.select_tasks { |st| st.name == t }
		selection.empty? ? t : selection
	    end
	}
	@pre.flatten!
    end

    def each_task
	@pre.each { |t|
	    yield(t) if t.is_a? Rant::Task
	}
    end

    def each_non_task
	@pre.each { |t|
	    yield(t) unless t.is_a? Rant::Task
	}
    end

    def hash
	@name.hash
    end

    def eql? other
	self.hash == other.hash
    end
end	# class Rant::Task

class Rant::FileTask < Rant::Task
    def initialize *args
	super
	if @name.is_a? Rant::Path
	    @path = @name
	    @name = @path.to_s
	else
	    @path = Rant::Path.new @name
	end
    end
    def path
	@path
    end
    def needed?
	return true unless @path.exist?
	resolve_prerequisites
	each_task { |t|
	    return true if t.needed?
	}
	ts = @path.mtime
	each_non_task { |ft|
	    return true if ft.mtime > ts
	}
	false
    end
    def resolve_prerequisites
	resolve_tasks
	resolve_pathes
    end
    def resolve_pathes
	@pre.map! { |t|
	    unless t.is_a? Rant::Task
		t = Rant::Path.new(t) unless t.is_a? Rant::Path
		unless t.exist?
		    @fail = true
		    err_msg "No such file `#{t.to_s}',",
			"referenced in `#{rantfile.path}'"
		    raise Rant::TaskFail, @name.to_s
		end
	    end
	    t
	}
    end
end	# class Rant::FileTask
