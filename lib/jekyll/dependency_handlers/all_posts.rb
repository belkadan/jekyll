module Jekyll
  class AllPostsDependencyHandler < DependencyHandler
    safe true
    
    def handle(name, site)
      Dependency.new(*site.posts) if name == '*'
    end
  end
end