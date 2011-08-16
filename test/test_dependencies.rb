require 'helper'

class TestDependencies < Test::Unit::TestCase
  def setup_post(file)
    Post.new(@site, source_dir, '', file)
  end

  context "A post" do
    setup do
      @post = Post.allocate
    end

    should "initially be clean and unused" do
      assert !@post.dirty?
      assert !@post.used?
    end

    should "allow marking dirty" do
      @post.mark_dirty
      assert @post.dirty?
      assert @post.used?
    end

    should "allow marking used" do
      @post.mark_used
      assert @post.used?
      assert !@post.dirty?
    end

    context "in a dependency chain" do
      setup do
        @post2 = Post.allocate
        @post3 = Post.allocate
      end

      should "not pass 'used' down the chain" do
        @post.add_dependency @post2
        @post2.add_dependency @post3

        @post.mark_used

        assert !@post2.used?
        assert !@post3.used?
      end

      should "not pass 'used' down the chain after being marked used" do
        @post.mark_used

        @post.add_dependency @post2
        @post2.add_dependency @post3

        assert !@post2.used?
        assert !@post3.used?
      end

      should "not pass 'used' up the chain" do
        @post.add_dependency @post2
        @post2.add_dependency @post3

        @post3.mark_used
        assert !@post2.used?
        assert !@post.used?
      end

      should "not pass 'used' up the chain after being marked used" do
        @post3.mark_used

        @post.add_dependency @post2
        @post2.add_dependency @post3

        assert !@post2.used?
        assert !@post.used?
      end

      should "not pass 'dirty' down the chain" do
        @post.add_dependency @post2
        @post2.add_dependency @post3

        @post.mark_dirty
        assert !@post2.dirty?
        assert !@post3.dirty?
      end

      should "not pass 'dirty' down the chain after being marked dirty" do
        @post.mark_dirty

        @post.add_dependency @post2
        @post2.add_dependency @post3

        assert !@post2.dirty?
        assert !@post3.dirty?
      end

      should "mark immediate dependents dirty when dirty" do
        @post.add_dependency @post2
        @post2.add_dependency @post3

        @post3.mark_dirty
        assert @post2.dirty?
        assert !@post.dirty?
      end

      should "mark immediate dependents dirty after being marked dirty" do
        @post3.mark_dirty

        @post.add_dependency @post2
        @post2.add_dependency @post3

        assert @post2.dirty?
        assert !@post.dirty?
      end

      should "mark immediate dependencies used when dirty" do
        @post.add_dependency @post2
        @post2.add_dependency @post3

        @post.mark_dirty
        assert @post2.used?
        assert !@post3.used?
      end

      should "mark immediate dependencies used after being marked dirty" do
        @post.mark_dirty

        @post.add_dependency @post2
        @post2.add_dependency @post3

        assert @post2.used?
        assert !@post3.used?
      end
    end
  end

end