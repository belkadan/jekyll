module Jekyll
  begin
    require 'lazy'
    class TypedPromise < Lazy::Promise
      def initialize(type, &block)
        super(&block)
        @type = type
      end
      def class
        @type
      end
      def is_a?(klass)
        @type.ancestors.include?(klass)
      end
    end
  rescue LoadError
    class TypedPromise
      def self.new(*unused_args)
        yield
      end
    end
  end
end