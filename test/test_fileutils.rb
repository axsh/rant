
require 'test/unit'
require 'rant/rantlib'
require 'tutil'

class TestFileUtils < Test::Unit::TestCase
    include Rant::Sys

    def setup
    end
    def teardown
    end

    def test_ruby
	op = capture_stdout do
	    ruby('-e ""') { |succ, stat|
		assert(succ)
		assert_equal(stat, 0)
	    }
	end
	assert(op =~ /\-e/i,
	    "Sys should print command with arguments to $stdout")
    end
    def test_split_path
	pl = split_path("/home/stefan")
	assert_equal(pl.size, 3,
	    "/home/stefan should get split into 3 parts")
	assert_equal(pl[0], "/")
	assert_equal(pl[1], "home")
	assert_equal(pl[2], "stefan")
	pl = split_path("../")
	assert_equal(pl.size, 1,
	    '../ should be "split" into one element')
	assert_equal(pl[0], "..")
    end
end
