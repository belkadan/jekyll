module Jekyll
  class DependencyHandler < Plugin
    class Dependency
      include Dependent
      
      def initialize(*dependencies)
        dependencies.each do |d|
          self.add_dependency(d)
        end
      end
      
      alias_method :<<, :add_dependency
      
      def dependent_dirty
        super
        mark_dirty
      end

      def mark_used
        @dependencies.each(&:mark_used) if @dependencies
      end
    end
    
    def handle(name, site)
      nil
    end
  end
end