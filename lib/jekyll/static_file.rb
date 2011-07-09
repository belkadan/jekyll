module Jekyll

  class StaticFile
    include Dependent

    # The cache of last modification times [path] -> mtime.
    @@mtimes = Hash.new

    # Initialize a new StaticFile.
    #
    # site - The Site.
    # base - The String path to the <source>.
    # dir  - The String path between <source> and the file.
    # name - The String filename of the file.
    def initialize(site, base, dir, name)
      @site = site
      @base = base
      @dir  = dir
      @name = name
    end

    # Returns source file path.
    def path
      File.join(@base, @dir, @name)
    end

    # Obtain destination path.
    #
    # dest - The String path to the destination dir.
    #
    # Returns destination file path.
    def destination(dest)
      File.join(dest, @dir, @name)
    end

    # Returns last modification time for this file.
    def mtime
      File.stat(self.path).mtime
    end

    # Is source path modified?
    #
    # Returns true if modified since last write.
    def modified?(dest)
      if not @@mtimes[self.path]
        dest_path = self.destination(dest)
        return true if not File.exist?(dest_path)
        @@mtimes[self.path] = File.stat(dest_path).mtime
      end
      self.mtime > @@mtimes[self.path]
    end

    # Write the static file to the destination directory (if modified).
    #
    # dest - The String path to the destination dir.
    #
    # Returns false if the file was not modified since last time (no-op).
    def write(dest)
      dest_path = destination(dest)

      return false if not dirty?
      @@mtimes[path] = mtime

      FileUtils.mkdir_p(File.dirname(dest_path))
      FileUtils.cp(path, dest_path)

      true
    end

    # Reset the mtimes cache (for testing purposes).
    #
    # Returns nothing.
    def self.reset_cache
      @@mtimes = Hash.new
      nil
    end
  end

end
