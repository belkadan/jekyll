module Jekyll
  module Dependent
    def add_dependency (d)
      unless d.nil?
        if self.dirty?
          d.mark_used
        elsif d.marked_dirty?
          self.dependent_dirty
        else
          @dependencies = [] unless @dependencies
          @dependencies << d
          d.add_dependent(self)
        end
      end
    end

    def dirty?
      @dirty
    end

    def mark_dirty
      return if @marked_dirty
      @marked_dirty = true
      self.dependent_dirty
      @dependent.each(&:dependent_dirty) if @dependent
    end

    def used?
      @used
    end

    def mark_used
      @used = true
    end

    def add_dependent (d)
      @dependent = [] unless @dependent
      @dependent << d
    end

    def dependent_dirty
      @dirty = true
      self.mark_used
      @dependencies.each(&:mark_used) if @dependencies
    end

    def marked_dirty?
      @marked_dirty
    end
  end
end