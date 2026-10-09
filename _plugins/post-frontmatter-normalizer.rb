# frozen_string_literal: true
#
# post-frontmatter-normalizer.rb
#
# 作用：在 Jekyll 渲染之前，把文章的 Front Matter 修正成 Chirpy 能正确解析的形状。
#
# 为什么需要它
# ------------
# Obsidian 的 GitHub Publisher 插件会把图片写成下面这些「看起来像 YAML、其实不是」的形式：
#
#   image: path:/assets/img/posts/cover.jpg      # -> 被解析成一个字符串，不是哈希
#   image:                                       # -> 被解析成空哈希
#     path:
#
# Chirpy 的主题模板（_layouts/home.html、_layouts/post.html、_includes/head.html）里有：
#
#   {% assign src = post.image.path | default: post.image %}
#
# 当 image 是一个哈希但缺少 path 时，`post.image.path` 取不到值，`default` 就会退回到
# 整个哈希对象，于是渲染出 `src="/{"path"=>nil}"` 这种垃圾 URL，首页封面就变成裂图；
# htmlproofer 也会因为 `/{` 这种路径直接让 CI 挂掉。
#
# 这个插件把这些情况统一成一个规范的哈希：
#
#   image:
#     path: /assets/img/posts/cover.jpg
#     alt: ""
#
# 另外还会：
#   * 去掉路径里多余的空白、反斜杠、重复斜杠
#   * 把本地路径转成小写（GitHub Publisher 上传到 Linux 时会把文件名改成小写，
#     本地写上大写就会 404）
#   * 把中文/空格等字符做 URL 编码，避免链接失效
#   * 路径为空（即"有 image: 但没填值"）时直接删掉 image 键，让模板走「无封面」分支
#   * 顺手剔除 pb-publish / pb-type 这些只给发布插件看的键
#
# 这样无论你在 Obsidian 里怎么填，构建都不会再炸。

module MaohonghuiBlog
  module FrontMatterNormalizer
    PB_KEYS = %w[pb-publish pb-type pb-image pb-cover].freeze

    # Front Matter 里出现这些值时，等同于「没有填」
    BLANK_VALUES = ["", "~", "-", "''", '""', "nil", "null", "undefined", "none"].freeze

    # URL 里允许直接出现的字符（其余做百分号编码）
    SAFE_URL_CHARS = /[^A-Za-z0-9\-._~\/%]/.freeze

    module_function

    # 判断一个值是不是「空的」
    def blank_value?(value)
      case value
      when nil then true
      when String then BLANK_VALUES.include?(value.strip.downcase)
      when Hash then value.empty? || value.values.all? { |v| blank_value?(v) }
      when Array then value.empty?
      else false
      end
    end

    # 把 image 字段里各种奇形怪状的值抽成一个路径字符串，抽不出来就返回 nil
    def extract_path(image)
      case image
      when nil
        nil
      when String
        value = image.strip
        return nil if blank_value?(value)

        # 情况一：被 YAML 解析成了哈希的字符串形式，例如 '{"path"=>"/a/b.jpg"}' 或 '{:path=>...}'
        if value.start_with?("{")
          # 注意：这里用 %r{...} 会出问题 —— 字符组里的 `}` 会被当成正则的结束括号，
          # 所以改用 %r!...! 作分隔符。
          matched = value.match(%r!path["']?\s*(?:=>|:)\s*["']([^"']+)["']!i) ||
                    value.match(%r!path["']?\s*(?:=>|:)\s*([^"'},\s]+)!i)
          return matched[1] if matched

          return nil # 是个空哈希，当作没有封面
        end

        # 情况二：'path:/xxx' 或 'path: /xxx'（GitHub Publisher 最常见的形式）
        # 先处理带引号的形式，这样路径里含空格也不会被截断。
        matched = value.match(/\Apath\s*:\s*(["'])(.+)\1\z/im) ||
                  value.match(/\Apath\s*:\s*(.+)\z/im)
        return matched[2].strip if matched && matched.size > 2
        return matched[1].strip if matched

        value
      when Hash
        # 正常的 image: { path: xxx } —— 同时也兼容写成大写的 Path / PATH
        raw = image["path"] || image[:path] ||
              image["Path"] || image[:Path] ||
              image["PATH"]
        return nil if blank_value?(raw)

        raw.to_s.strip
      else
        nil
      end
    end

    # 规范化路径：统一成「以 / 开头的绝对路径」或「原样的外链」
    def normalize_path(path)
      return nil if path.nil?

      cleaned = path.to_s.strip.tr("\\", "/")
      return nil if blank_value?(cleaned)

      # 外链（http://、https://、data: 等）必须原样保留。
      # 注意这一步一定要在「压缩重复斜杠」之前做，否则 https:// 会被压成
      # https:/ 而失去协议头，反而被当成站内相对路径加上前导斜杠。
      return cleaned if cleaned.match?(%r{\A[a-zA-Z][a-zA-Z0-9+.\-]*://}) || cleaned.start_with?("data:")

      cleaned = cleaned.gsub(%r{/{2,}}, "/")
      cleaned = cleaned.sub(%r{\A\./}, "")
      return nil if blank_value?(cleaned)

      # 补上开头的斜杠，变成绝对路径，避免站点部署在子目录时找不到图
      cleaned = "/#{cleaned}" unless cleaned.start_with?("/")

      # 只处理路径部分，查询串/锚点保留
      head, separator, tail = cleaned.partition(/[?#]/)
      head = head.downcase # Linux 区分大小写，统一小写最稳
      head = head.gsub(SAFE_URL_CHARS) { |char| char.bytes.map { |b| format("%%%02X", b) }.join }

      "#{head}#{separator}#{tail}"
    end

    # 规范化 alt（题注）。没填就保持空字符串，交给主题的默认值，避免出现 nil 或哈希
    def normalize_alt(value)
      return "" if blank_value?(value)
      return "" if value.is_a?(Hash) || value.is_a?(Array)

      value.to_s.strip
    end

    # ── 图片路径容错 ──────────────────────────────────────────────────────
    #
    # Obsidian 的 GitHub Publisher 有「Assets directory」和「Assets relative path」
    # 两个设置，正文里的 ![[图片.jpg]] 会被转成 /assets/img/posts/图片.jpg。
    # 但 Front Matter 里的 image.path 是**手写**的，很容易写成
    #   /assets/图片.jpg            （少了 img/posts）
    #   assets/img/posts/图片.jpg   （少了开头的斜杠）
    #   图片.jpg                    （只有文件名）
    # 这几种都会 404。
    #
    # 这里做一层兜底：如果按原路径找不到文件，就用**文件名**去 assets/ 目录里搜，
    # 搜到唯一一个就自动纠正。这样你在手机上怎么写都不会裂图。

    class << self
      # 延时构建「文件名 => 仓库内真实路径」的索引
      def asset_index(site)
        return @asset_index if defined?(@asset_index) && @asset_index && @asset_index_src == site.source

        index = {}
        assets_root = File.join(site.source, "assets")
        if File.directory?(assets_root)
          Dir.glob(File.join(assets_root, "**", "*")).each do |file|
            next unless File.file?(file)

            rel = "/" + file.sub(%r{\A#{Regexp.escape(site.source)}/?}, "").tr("\\", "/")
            key = File.basename(rel).downcase
            index[key] ||= []
            index[key] << rel
          end
        end

        @asset_index_src = site.source
        @asset_index = index
      end

      # 尝试把 path 修正成仓库里真实存在的文件
      def resolve_asset_path(path, site)
        return path if site.nil? || path.nil?

        exact = File.join(site.source, path.sub(%r{\A/}, ""))
        return path if File.file?(exact)

        index = asset_index(site)
        return path if index.empty?

        candidates = index[File.basename(path).downcase]
        return path if candidates.nil? || candidates.empty?

        if candidates.size == 1
          Jekyll.logger.info "FrontMatter:", "图片路径已自动纠正 #{path} -> #{candidates.first}"
          candidates.first
        else
          Jekyll.logger.warn "FrontMatter:",
                             "图片 #{path} 找不到，同名文件有多个，请写全路径：#{candidates.join(', ')}"
          path
        end
      end
    end

    # 对一篇文章的 data 做修正
    def apply!(data, site = nil)
      PB_KEYS.each { |key| data.delete(key) }

      return unless data.key?("image")

      original = data["image"]
      path = normalize_path(extract_path(original))
      path = resolve_asset_path(path, site) unless path.nil?

      if path.nil?
        # 有 image: 但没有有效路径 —— 直接移除，模板就会走「无封面」分支
        data.delete("image")
        return
      end

      alt =
        if original.is_a?(Hash)
          normalize_alt(original["alt"] || original[:alt])
        else
          ""
        end

      normalized = { "path" => path }
      normalized["alt"] = alt unless alt.empty?

      # 保留 lqip / no_bg 这类 Chirpy 支持的可选字段
      if original.is_a?(Hash)
        lqip = original["lqip"] || original[:lqip]
        normalized["lqip"] = lqip if lqip && !blank_value?(lqip)

        no_bg = original["no_bg"] || original[:no_bg]
        normalized["no_bg"] = no_bg unless no_bg.nil?
      end

      data["image"] = normalized
    end
  end
end

Jekyll::Hooks.register :posts, :post_init do |post|
  MaohonghuiBlog::FrontMatterNormalizer.apply!(post.data, post.site)
end

# 页面（_tabs 等）也顺手修一下，保证 head.html 生成社交预览图时不会出错
Jekyll::Hooks.register :pages, :post_init do |page|
  MaohonghuiBlog::FrontMatterNormalizer.apply!(page.data, page.site)
end
