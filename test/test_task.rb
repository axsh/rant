
require 'test/unit'
require 'tutil'

$-w = true

class TestTask < Test::Unit::TestCase
    def setup
        @rant = Rant::RantApp.new
    end
    def test_version
	assert(Rant::VERSION.length >= 5)
    end
    def test_needed
	run = false
	t = Rant::Task.new(@rant, :non_existent) { run = true }
	assert(t.needed?,
	    "Rant::Task should always be 'needed?' before first invocation")
	assert(!run,
	    "Rant::Task shouldn't get run when 'needed?' is called")
    end
    def test_invoke
	run = false
	block = lambda { run = true }
	task = Rant::Task.new(@rant, :test_run, &block)
	task.invoke
	assert(run, "block should have been executed")
	assert(task.done?, "task is done")
	assert(!task.needed?,
	    "task is done, so 'needed?' should return false")
    end
    def test_fail
	block = lambda { |t| t.fail "this task abortet itself" }
	task = Rant::Task.new(@rant, :test_fail, &block)
	assert_raise(Rant::TaskFail,
	    "run should throw Rant::TaskFail if block raises Exception") {
	    task.invoke
	}
	assert(task.fail?)
	assert(task.invoked?, "although task failed, it was invoked")
    end
    def test_dependent
	r1 = r2 = false
	t1 = Rant::Task.new(@rant, :t1) { r1 = true }
	t2 = Rant::Task.new(@rant, :t2) { r2 = true }
	t1 << t2
	t1.invoke
	assert(r1)
	assert(r2, "t1 depends on t2, so t2 should have been run")
	assert(t1.done?)
	assert(t2.done?)
	assert(!t1.needed?)
	assert(!t2.needed?)
    end

    def test_dependency_fails
	t1 = Rant::Task.new(@rant, :t1) { true }
	t2 = Rant::Task.new(@rant, :t2) { |t| t.fail }
	t1 << t2
	assert_raise(Rant::TaskFail,
	    "dependency t2 failed, so t1 should fail too") {
	    t1.invoke
	}
	assert(t1.fail?,
	    "fail flag should be set for task if dependency fails")
	assert(t2.fail?,
	    "fail flag should be set for task if it fails")
    end

    def test_task
	run = false
	t = @rant.task :t do |t|
	    run = true
	end
	t.invoke
	assert(run)
    end

    def test_dep_on_self
	run = false
	t = @rant.task :t => "t" do |t|
	    run = true
	end
	th = Thread.new { t.invoke }
	# shouldn't take half a second...
	assert_equal(th.join(0.5), th,
	    "task should remove dependency on itself")
	assert(run,
	    "task should get run despite dependency on itself")
    end
    def test_circular_dependency
	t1r = false
	t2r = false
	t1 = @rant.task :t1 => :t2 do |t|
	    assert(t2r)
	    t1r = true
	end
	t2 = @rant.task :t2 => :t1 do |t|
	    t2r = true
	end
	out, err = capture_std do
	    th = Thread.new { t1.invoke }
	    assert_equal(th, th.join(0.5),
		"task should detect circular dependency")
	end
	assert(t1r)
	assert(t2r)
	assert_match(/\[WARNING\]/, err,
	    "Rant should print a warning to stderr about circular" +
	    "dependency")
    end
    def test_dep_on_self_in_deplist
	rl = []
	t1 = @rant.task :t1 do |t|
	    rl << t.name
	end
	t2 = @rant.task :t2 do |t|
	    rl << t.name
	end
	t3 = @rant.task :t3 => [:t1, :t3, :t2] do |t|
	    rl << t.name
	end
	th = Thread.new { t3.invoke }
	# shouldn't take half a second...
	assert_equal(th.join(0.5), th,
	    "task should remove dependency on itself from dependency list")
	assert_equal(rl, %w(t1 t2 t3),
	    "t3 was run and depends on [t1, t2] => run order: t1 t2 t3")
    end
    def test_enhance_gen_task
	app = Rant::RantApp.new
	enhance_run = false
	t_run = false
	t2_run = false
	app.gen Rant::Generators::Task, :t do |t|
	    t.needed { true }
	    t.act {
		assert(t2_run,
		    "enhance added `t2' as prerequisite")
		t_run = true
	    }
	end
	app.gen Rant::Generators::Task, :t2 do |t|
	    t.needed { true }
	    t.act { t2_run = true }
	end
	assert_nothing_raised("generated Task should be enhanceable") {
	    app.enhance :t => :t2 do
		enhance_run = true
	    end
	}
	assert_equal(0, app.run)
	assert(t_run)
    end
end
