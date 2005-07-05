
require 'test/unit'
require 'tutil'

$testIPackageDir ||= File.expand_path(File.dirname(__FILE__))

class TestImportPackage < Test::Unit::TestCase
    def setup
	# Ensure we run in test directory.
	Dir.chdir $testIPackageDir
	@pkg_dir = nil
    end
    def teardown
	assert_rant("autoclean")
	assert(Dir["*.{tgz,zip,t}"].empty?)
    end
    def check_contents(atype, archive, files, dirs = [], manifest_file = nil)
	old_pwd = Dir.pwd
	FileUtils.mkdir "u.t"
	FileUtils.cp archive, "u.t"
	FileUtils.cd "u.t"
	archive = File.basename archive
	unpack_archive atype, archive
	if @pkg_dir
	    assert(test(?d, @pkg_dir))
	    FileUtils.cd @pkg_dir
	end
	files.each { |f| assert(test(?f, f)) }
	dirs.each { |f| assert(test(?d, f)) }
	count = files.size + dirs.size
	# + 1 because of the archive file
	count += 1 unless @pkg_dir
	assert_equal(count, Dir["**/*"].size)
	if manifest_file
	    check_manifest(manifest_file, files)
	end
	yield if block_given?
    ensure
	FileUtils.cd old_pwd
	FileUtils.rm_r "u.t"
    end
    def check_manifest(file, entries)
	assert(test(?f, file))
	m_entries = IO.read(file).split("\n")
	assert_equal(entries.size, m_entries.size)
	entries.each { |f|
	    assert(m_entries.include?(f),
		"#{f} missing in manifest")
	}
    end
    def unpack_archive(atype, archive)
	case atype
	when :tgz
	    `tar -xzf #{archive}`
	when :zip
	    `unzip -q #{archive}`
	else
	    raise "can't unpack archive type #{atype}"
	end
    end
if Rant::Env.have_tar?
    def test_tgz_from_manifest
	assert_rant
	mf = %w(Rantfile sub/f1 sub2/f1 MANIFEST)
	dirs = %w(sub sub2)
	check_contents(:tgz, "t1.tgz", mf, dirs, "MANIFEST")
    end
    def test_tgz_sync_manifest
	assert_rant("t2.tgz")
	mf = %w(sub/f1 sub2/f1 m2.tgz.t)
	dirs = %w(sub sub2)
	check_manifest("m2.tgz.t", mf)
	check_contents(:tgz, "t2.tgz", mf, dirs, "m2.tgz.t")
	out, err = assert_rant("t2.tgz")
	assert(out.strip.empty?)
	#assert(err.strip.empty?)
	FileUtils.touch "sub/f5"
	out, err = assert_rant("t2.tgz")
	assert_match(/writing m2\.tgz\.t.*\n.*tar/m, out)
	check_contents(:tgz, "t2.tgz", mf + %w(sub/f5), dirs, "m2.tgz.t")
	timeout
	FileUtils.rm "sub/f5"
	out, err = assert_rant("t2.tgz")
	assert_match(/writing m2\.tgz\.t.*\n.*tar/m, out)
	check_contents(:tgz, "t2.tgz", mf, dirs, "m2.tgz.t")
	# test autoclean
	assert_rant("autoclean")
	assert(!test(?e, "m2.tgz.t"))
	# hmm.. the tgz will be removed by check_contents anyway...
	assert(!test(?e, "t2.tgz"))
    ensure
	FileUtils.rm_rf "sub/f5"
    end
    def test_tgz_files_array
	assert_rant("t3.tgz")
	mf = %w(Rantfile sub/f1)
	dirs = %w(sub)
	check_contents(:tgz, "t3.tgz", mf, dirs)
    end
    def test_tgz_version_and_dir
	assert_rant("pkg.t/t4-1.0.0.tgz")
	assert(test(?d, "pkg.t"))
	mf = %w(Rantfile sub/f1 sub2/f1 MANIFEST)
	dirs = %w(sub sub2)
	check_contents(:tgz, "pkg.t/t4-1.0.0.tgz", mf, dirs, "MANIFEST")
    ensure
	FileUtils.rm_rf "pkg.t"
    end
    def test_tgz_package_manifest
	assert(!test(?e, "pkg2.t"))
	assert_rant("pkg2.t.tgz")
	assert(?d, "pkg2.t")
	mf = %w(Rantfile sub/f1 sub2/f1 MANIFEST)
	dirs = %w(sub sub2)
	@pkg_dir = "pkg2.t"
	check_contents(:tgz, "pkg2.t.tgz", mf, dirs, "MANIFEST")
	assert(test(?d, "pkg2.t"))
	assert_rant("autoclean")
	assert(!test(?e, "pkg2.t"))
    end
end
if Rant::Env.have_zip?
    def test_zip_package_write_manifest
	assert(!test(?f, "CONTENTS"))
	assert_rant("pkg.t/pkg.zip")
	assert(test(?f, "CONTENTS"))
	mf = %w(deep/sub/sub/f1 CONTENTS)
	dirs = %w(deep deep/sub deep/sub/sub)
	@pkg_dir = "pkg"
	check_contents(:zip, "pkg.t/pkg.zip", mf, dirs, "CONTENTS")
	assert(test(?f, "CONTENTS"))
	assert_rant("autoclean")
	assert(!test(?f, "CONTENTS"))
    end
    def test_zip_with_basedir
	assert_rant(:fail, "zip.t/t4-1.0.0.zip")
	assert(!test(?d, "zip.t"))
	FileUtils.mkdir "zip.t"
	assert_rant("zip.t/t4-1.0.0.zip")
	mf = %w(Rantfile sub/f1 sub2/f1 MANIFEST)
	dirs = %w(sub sub2)
	check_contents(:zip, "zip.t/t4-1.0.0.zip", mf, dirs, "MANIFEST")
    ensure
	FileUtils.rm_rf "zip.t"
    end
    def test_zip_from_manifest
	assert_rant("t1.zip")
	mf = %w(Rantfile sub/f1 sub2/f1 MANIFEST)
	dirs = %w(sub sub2)
	check_contents(:zip, "t1.zip", mf, dirs, "MANIFEST")
    end
    def test_zip_sync_manifest
	assert_rant("t2.zip")
	mf = %w(sub/f1 sub2/f1 m2.zip.t)
	dirs = %w(sub sub2)
	check_manifest("m2.zip.t", mf)
	check_contents(:zip, "t2.zip", mf, dirs, "m2.zip.t")
    ensure
	FileUtils.rm_f "m2.zip.t"
    end
    def test_zip_filelist
	assert_rant("t3.zip")
	mf = %w(Rantfile sub/f1)
	dirs = %w(sub)
	check_contents(:zip, "t3.zip", mf, dirs)
    end
end
    def test_dummy
	assert(true)
    end
end
