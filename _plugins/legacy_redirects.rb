# frozen_string_literal: true

# Redirect legacy Minimal Mistakes URLs to current Chirpy paths.
#
# Old site permalink: /:year/:month/:day/:title/
# New site permalink: /posts/:title/
#
# Old pagination:      /page/:num/
# New pagination:      /page:num/
#
# Also covers:
# - unpadded month/day variants (e.g. /2024/1/03/...)
# - deleted historical posts → /archives/
# - common legacy/root paths (wiki, atom.xml, /posts/, /search/)

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

    STATIC_REDIRECTS = {
      "wiki" => "/archives/",
      "search" => "/",
      "posts" => "/",
      "atom.xml" => "/feed.xml"
    }.freeze

    def generate(site)
      generate_post_redirects(site)
      generate_deleted_post_redirects(site)
      generate_pagination_redirects(site)
      generate_static_redirects(site)
    end

    private

    def generate_post_redirects(site)
      site.posts.docs.each do |post|
        next if post.relative_path.end_with?("template.md")

        slug = post_slug(post)
        target_url = post.url
        add_dated_redirects(site, post.date.year, post.date.month, post.date.day, slug, target_url)
      end
    end

    def generate_deleted_post_redirects(site)
      deleted = site.data["deleted_posts"]
      return unless deleted.is_a?(Array)

      deleted.each do |entry|
        year = entry["year"].to_i
        month = entry["month"].to_i
        day = entry["day"].to_i
        slug = entry["slug"].to_s
        next if slug.empty?

        add_dated_redirects(site, year, month, day, slug, "/archives/")
      end
    end

    def generate_pagination_redirects(site)
      per_page = site.config.fetch("paginate", 10).to_i
      post_count = site.posts.docs.count { |post| !post.relative_path.end_with?("template.md") }
      total_pages = (post_count.to_f / per_page).ceil

      (2..total_pages).each do |page_num|
        site.pages << LegacyRedirectPage.new(site, "page/#{page_num}", "/page#{page_num}/")
      end
    end

    def generate_static_redirects(site)
      STATIC_REDIRECTS.each do |path, target|
        if path.end_with?(".xml")
          dir = File.dirname(path)
          dir = "" if dir == "."
          site.pages << LegacyRedirectPage.new(site, dir, target, File.basename(path))
        else
          site.pages << LegacyRedirectPage.new(site, path, target)
        end
      end
    end

    def add_dated_redirects(site, year, month, day, slug, target_url)
      # Cover zero-padded and unpadded month/day mixes that old links may use.
      date_dirs = [
        format("%04d/%02d/%02d", year, month, day),
        format("%04d/%d/%02d", year, month, day),
        format("%04d/%02d/%d", year, month, day),
        format("%04d/%d/%d", year, month, day)
      ].uniq

      date_dirs.each do |date_dir|
        site.pages << LegacyRedirectPage.new(site, "#{date_dir}/#{slug}", target_url)
        site.pages << LegacyRedirectPage.new(site, date_dir, target_url, "#{slug}.html")
      end
    end

    def post_slug(post)
      File.basename(post.basename_without_ext).sub(/\A\d{4}-\d{1,2}-\d{1,2}-/, "")
    end
  end
end
