
require 'test/unit'

# We require 'rant/rantlib' instead of 'rant',
# which would cause the rant.rb (which is ment as a Rantfile)
# to be loaded!
require 'rant/rantlib'
include Rant
include ::Rant::FileUtils

# Ensure we run in testproject directory.
dir = File.dirname(__FILE__)
cd(dir) unless Dir.pwd == dir

class TestProject2 < Test::Unit::TestCase
    def app *args
	@app = ::Rant::RantApp.new *args
    end
    def setup
    end
    def teardown
	assert_equal(app(%w(-f rant.rb -f buildfile clean)).run, 0)
	assert(Dir["r_f*"].empty?,
	    "r_f* files should have been removed by `clean'")
	assert(Dir["b_f*"].empty?,
	    "b_f* files should have been removed by `clean'")
	assert(Dir["sub1/s*f*"].empty?,
	    "sub1/s*f* files should have been removed by `clean'")
    end
    def test_use_first_task
	assert_equal(app.run, 0,
	    "run method of RantApp should return 0 on success")
	assert(File.exist?("r_f1"))
    end
    def test_deps
	assert_equal(app("r_f4").run, 0)
	assert(File.exist?("r_f4"))
	assert(File.exist?("r_f2"))
	assert(File.exist?("r_f1"))
	assert(!File.exist?("r_f3"))
    end
    def test_load_rantfile
	app("b_f2")
	assert(@app.load_rantfile("buildfile"),
	    "load_rantfile should return a true value on success")
	assert_equal(@app.run, 0)
	assert(File.exist?("b_f2"))
    end
    def test_subdirs
	assert_equal(app(%w(-f buildfile create_s1f1)).run, 0)
	assert(File.exist?("sub1/s1f1"))
    end
end