# frozen_string_literal: true

# Redirect legacy Minimal Mistakes URLs to current Chirpy paths.
#
# Old site permalink: /:year/:month/:day/:title/
# New site permalink: /posts/:title/
#
# Old pagination:      /page/:num/
# New pagination:      /page:num/

module Jekyll
  module LegacyRedirectHtml
    module_function

    def redirect_html(target_url)
      <<~HTML
        <!DOCTYPE html>
        <html lang="zh-CN">
          <head>
            <meta charset="utf-8">
            <title>Redirecting…</title>
            <link rel="canonical" href="#{target_url}">
            <meta http-equiv="refresh" content="0; url=#{target_url}">
            <script>location.replace("#{target_url}");</script>
          </head>
          <body>
            <p>页面已迁移，正在跳转到 <a href="#{target_url}">#{target_url}</a> …</p>
          </body>
        </html>
      HTML
    end
  end

  class LegacyRedirectPage < Page
    def initialize(site, dir, target_url, name = "index.html")
      @site = site
      @base = site.source
      @dir = dir
      @name = name

      process(@name)
      self.data = {
        "sitemap" => false,
        "layout" => nil
      }
      self.content = LegacyRedirectHtml.redirect_html(target_url)
    end

    def destination(dest)
      File.join(dest, @dir, @name)
    end
  end

  class LegacyRedirectsGenerator < Generator
    safe true
    priority :lowest

    def generate(site)
      generate_post_redirects(site)
      generate_pagination_redirects(site)
    end

    private

    def generate_post_redirects(site)
      site.posts.docs.each do |post|
        next if post.relative_path.end_with?("template.md")

        slug = post_slug(post)
        date_dir = post.date.strftime("%Y/%m/%d")
        legacy_dir = "#{date_dir}/#{slug}"
        target_url = post.url

        site.pages << LegacyRedirectPage.new(site, legacy_dir, target_url)
        site.pages << LegacyRedirectPage.new(site, date_dir, target_url, "#{slug}.html")
      end
    end

    def post_slug(post)
      File.basename(post.basename_without_ext).sub(/\A\d{4}-\d{1,2}-\d{1,2}-/, "")
    end

    def generate_pagination_redirects(site)
      per_page = site.config.fetch("paginate", 10).to_i
      post_count = site.posts.docs.count { |post| !post.relative_path.end_with?("template.md") }
      total_pages = (post_count.to_f / per_page).ceil

      (2..total_pages).each do |page_num|
        site.pages << LegacyRedirectPage.new(site, "page/#{page_num}", "/page#{page_num}/")
      end
    end
  end
end
