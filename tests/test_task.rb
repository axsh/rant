
require 'test/unit'
require 'rant/rantlib'

$-w = true

class TestTask < Test::Unit::TestCase
    def setup
    end
    def teardown
    end

    def test_version
	assert(Rant::VERSION.length >= 5)
    end

    def test_run
	run = false
	block = lambda { run = true }
	task = Rant::Task.new(nil, :test_run, &block)
	task.run
	assert(run, "block should have been executed")
	assert(task.done?, "task is done")
    end

    def test_fail
	block = lambda { |t| t.fail "this task abortet itself" }
	task = Rant::Task.new(nil, :test_fail, &block)
	assert_raise(Rant::TaskFail,
	    "run should throw Rant::TaskFail if block raises Exception") {
	    task.run
	}
	assert(task.fail?)
	assert(task.ran?, "although task failed, it was ran")
    end

    def test_dependant
	r1 = r2 = false
	t1 = Rant::Task.new(nil, :t1) { r1 = true }
	t2 = Rant::Task.new(nil, :t2) { r2 = true }
	t1 << t2
	t1.run
	assert(r1)
	assert(r2, "t1 depends on t2, so t2 should have been run")
	assert(t1.done?)
	assert(t2.done?)
    end

    def test_dependance_fails
	t1 = Rant::Task.new(nil, :t1) { true }
	t2 = Rant::Task.new(nil, :t2) { Rant::Task.fail }
	t1 << t2
	assert_raise(Rant::TaskFail,
	    "dependency t2 failed, so t1 should fail too") {
	    t1.run
	}
	assert(t1.fail?)
	assert(t2.fail?)
    end

    def test_task
	run = false
	t = Rant.task :t do |t|
	    run = true
	end
	t.run
	assert(run)
    end
end
