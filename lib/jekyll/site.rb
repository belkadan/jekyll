require 'set'

module Jekyll

  class Site
    attr_accessor :config, :layouts, :posts, :pages, :static_files,
                  :categories, :exclude, :source, :dest, :lsi, :pygments,
                  :permalink_style, :tags, :time, :future, :safe, :plugins, :limit_posts

    attr_accessor :converters, :generators, :dependency_handlers

    # Public: Initialize a new Site.
    #
    # config - A Hash containing site configuration details.
    def initialize(config)
      self.config          = config.clone

      self.safe            = config['safe']
      self.source          = File.expand_path(config['source'])
      self.dest            = File.expand_path(config['destination'])
      self.plugins         = File.expand_path(config['plugins'])
      self.lsi             = config['lsi']
      self.pygments        = config['pygments']
      self.permalink_style = config['permalink'].to_sym
      self.exclude         = config['exclude'] || []
      self.future          = config['future']
      self.limit_posts     = config['limit_posts'] || nil

      self.reset
      self.setup
    end

    # Public: Read, process, and write this Site to output.
    #
    # Returns nothing.
    def process
      self.reset
      self.read
      self.generate
      self.resolve_dependencies
      self.render
      self.cleanup
      self.write
    end

    # Reset Site details.
    #
    # Returns nothing
    def reset
      self.time            = if self.config['time']
                               Time.parse(self.config['time'].to_s)
                             else
                               Time.now
                             end
      self.layouts         = {}
      self.posts           = []
      self.pages           = []
      self.static_files    = []
      self.categories      = Hash.new { |hash, key| hash[key] = [] }
      self.tags            = Hash.new { |hash, key| hash[key] = [] }

      if !self.limit_posts.nil? && self.limit_posts < 1
        raise ArgumentError, "Limit posts must be nil or >= 1"
      end
    end

    # Load necessary libraries, plugins, converters, and generators.
    #
    # Returns nothing.
    def setup
      require 'classifier' if self.lsi

      # If safe mode is off, load in any Ruby files under the plugins
      # directory.
      unless self.safe
        Dir[File.join(self.plugins, "**/*.rb")].each do |f|
          require f
        end
      end

      self.converters = Jekyll::Converter.instantiate_all(self.config, !self.safe)
      self.generators = Jekyll::Generator.instantiate_all(self.config, !self.safe)
      self.dependency_handlers = Jekyll::DependencyHandler.instantiate_all(self.config, !self.safe)
    end

    # Read Site data from disk and load it into internal data structures.
    #
    # Returns nothing.
    def read
      self.read_layouts
      self.read_directories
    end

    # Read all the files in <source>/<dir>/_layouts and create a new Layout
    # object with each one.
    #
    # Returns nothing.
    def read_layouts(dir = '')
      base = File.join(self.source, dir, "_layouts")
      return unless File.exists?(base)
      entries = []
      Dir.chdir(base) { entries = filter_entries(Dir['*.*']) }

      entries.each do |f|
        name = f.split(".")[0..-2].join(".")
        self.layouts[name] = Layout.new(self, base, f)
      end
    end

    # Recursively traverse directories to find posts, pages and static files
    # that will become part of the site according to the rules in
    # filter_entries.
    #
    # dir - The String relative path of the directory to read.
    #
    # Returns nothing.
    def read_directories(dir = '')
      base = File.join(self.source, dir)
      entries = Dir.chdir(base) { filter_entries(Dir['*']) + Dir['.htaccess'] }

      self.read_posts(dir)

      entries.each do |f|
        f_abs = File.join(base, f)
        f_rel = File.join(dir, f)
        if File.directory?(f_abs)
          next if self.dest.sub(/\/$/, '') == f_abs
          read_directories(f_rel)
        elsif !File.symlink?(f_abs)
          first3 = File.open(f_abs) { |fd| fd.read(3) }
          if first3 == "---"
            # file appears to have a YAML header so process it as a page
            pages << Page.new(self, self.source, dir, f)
          else
            # otherwise treat it as a static file
            static_files << StaticFile.new(self, self.source, dir, f)
          end
        end
      end
    end

    # Read all the files in <source>/<dir>/_posts and create a new Post
    # object with each one.
    #
    # dir - The String relative path of the directory to read.
    #
    # Returns nothing.
    def read_posts(dir)
      base = File.join(self.source, dir, '_posts')
      return unless File.exists?(base)
      entries = Dir.chdir(base) { filter_entries(Dir['**/*']) }

      # first pass processes, but does not yet render post content
      entries.each do |f|
        if Post.valid?(f)
          post = Post.new(self, self.source, dir, f)

          if post.published && (self.future || post.date <= self.time)
            self.posts << post
            post.categories.each { |c| self.categories[c] << post }
            post.tags.each { |c| self.tags[c] << post }
          end
        end
      end

      self.posts.sort!
      self.categories.each_value(&:sort!)
      self.tags.each_value(&:sort!)

      # limit the posts if :limit_posts option is set
      self.posts = self.posts[-limit_posts, limit_posts] if limit_posts
    end

    # Run each of the Generators.
    #
    # Returns nothing.
    def generate
      self.generators.each do |generator|
        generator.generate(self)
      end
    end
    
    def resolve_dependencies
      if self.config['full'] then
        self.posts.each(&:mark_dirty)
        self.pages.each(&:mark_dirty)
        self.static_files.each(&:mark_dirty)
      else
        resolve_basic = Proc.new do |item|
          item.mark_dirty if item.modified?(self.dest)
          item.explicit_dependencies.each do |dep_name|
            dep_handled = self.dependency_handlers.find do |handler|
              handler.handle(dep_name, item, self)
            end
            if not dep_handled
              STDERR.puts "Warning: unknown dependency '#{dep_name}'"
              STDERR.puts "\t#{item.source}"
            end
          end
        end

        self.pages.each(&resolve_basic)

        self.posts.each do |post|
          resolve_basic.call(post)
          post.add_dependency(post.next)
          post.add_dependency(post.previous)
        end
      
        self.static_files.each do |file|
          file.mark_dirty if file.modified?(self.dest)
        end
      end
    end

    # Render the site to the destination.
    #
    # Returns nothing.
    def render
      payload = site_payload

      self.posts.each do |post|
        post.render(self.layouts, payload)
      end

      self.pages.each do |page|
        page.render(self.layouts, payload)
      end
    rescue Errno::ENOENT => e
      # ignore missing layout dir
    end

    # Remove orphaned files and empty directories in destination.
    #
    # Returns nothing.
    def cleanup
      # all files and directories in destination, including hidden ones
      dest_files = Set.new
      Dir.glob(File.join(self.dest, "**", "*"), File::FNM_DOTMATCH) do |file|
        dest_files << file unless file =~ /\/\.{1,2}$/
      end

      # files to be written
      files = Set.new
      self.posts.each do |post|
        files << post.destination(self.dest)
      end
      self.pages.each do |page|
        files << page.destination(self.dest)
      end
      self.static_files.each do |sf|
        files << sf.destination(self.dest)
      end

      # adding files' parent directories
      files_and_parents = Set.new
      files.each do |file|
        dir = File.dirname(file)
        while dir != file
          files_and_parents << file
          file = dir
          dir = File.dirname(file)
        end
      end

      obsolete_files = dest_files - files_and_parents

      FileUtils.rm_rf(obsolete_files.to_a)
    end

    # Write static files, pages, and posts.
    #
    # Returns nothing.
    def write
      self.posts.each do |post|
        post.write(self.dest) if post.dirty?
        puts post.destination('') if post.dirty? and self.config['debug']
      end
      self.pages.each do |page|
        page.write(self.dest) if page.dirty?
        puts page.destination('') if page.dirty? and self.config['debug']
      end
      self.static_files.each do |sf|
        sf.write(self.dest) if sf.dirty?
        puts sf.destination('') if sf.dirty? and self.config['debug']
      end
    end

    # The Hash payload containing site-wide data.
    #
    # Returns the Hash: { "site" => data } where data is a Hash with keys:
    #   "time"       - The Time as specified in the configuration or the
    #                  current time if none was specified.
    #   "posts"      - The Array of Posts, sorted chronologically by post date
    #                  and then title.
    #   "pages"      - The Array of all Pages.
    #   "html_pages" - The Array of HTML Pages.
    #   "categories" - The Hash of category values and Posts.
    #                  See Site#post_attr_hash for type info.
    #   "tags"       - The Hash of tag values and Posts.
    #                  See Site#post_attr_hash for type info.
    def site_payload
      {"site" => self.config.merge({
          "time"       => self.time,
          "posts"      => self.posts.reverse,
          "pages"      => self.pages,
          "html_pages" => self.pages.select(&:html?),
          "categories" => self.categories,
          "tags"       => self.tags})}
    end

    # Filter out any files/directories that are hidden or backup files (start
    # with "." or "#" or end with "~"), or contain site content (start with "_"),
    # or are excluded in the site configuration.
    #
    # entries - The Array of file/directory entries to filter.
    #
    # Returns the Array of filtered entries.
    def filter_entries(entries)
      entries = entries.reject do |e|
        ['.', '_', '#'].include?(e[0..0]) ||
        e[-1..-1] == '~' ||
        self.exclude.include?(e) ||
        File.symlink?(e)
      end
    end

    # Get the implementation class for the given Converter.
    #
    # klass - The Class of the Converter to fetch.
    #
    # Returns the Converter instance implementing the given Converter.
    def getConverterImpl(klass)
      matches = self.converters.select { |c| c.class == klass }
      if impl = matches.first
        impl
      else
        raise "Converter implementation not found for #{klass}"
      end
    end
  end
end
