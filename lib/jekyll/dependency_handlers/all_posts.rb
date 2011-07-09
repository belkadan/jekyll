module Jekyll
  class AllPostsDependencyHandler < DependencyHandler
    safe true
    
    def handle(name, page, site)
      return false unless name == '*'

      site.posts.each do |post|
        page.add_dependency(post)
      end

      true
    end
  end
end