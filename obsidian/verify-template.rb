# frozen_string_literal: true
#
# 用「博客文章模板」的真实输出喂给规范化插件，确认生成的文章不会出问题。
# 用法: ruby obsidian/verify-template.rb

require "date"

$LOAD_PATH.unshift(File.expand_path("../_plugins", __dir__))

module Jekyll
  class Hooks
    def self.register(*); end
  end

  module Logger
    def self.info(*); end

    def self.warn(*); end

    def self.debug(*); end
  end
end

require "post-frontmatter-normalizer"
require "yaml"

F = MaohonghuiBlog::FrontMatterNormalizer
$failures = 0

def check(label, actual, expected)
  ok = actual == expected
  $failures += 1 unless ok
  puts format("  %-6s %-44s %s", ok ? "PASS" : "FAIL", label, actual.inspect)
  puts format("         %-44s expected %s", "", expected.inspect) unless ok
end

# 这些正是模板会生成的几种 image 写法
variants = {
  "模板默认（path 为空字符串）" => <<~YAML,
    image:
      path: ""
  YAML
  "只有 image: 后面跟注释" => <<~YAML,
    image:
      # alt: "封面说明"
  YAML
  "填了封面路径" => <<~YAML,
    image:
      path: /assets/img/posts/cover.jpg
      alt: "封面"
  YAML
  "完全没有 image 键" => <<~YAML,
    title: "x"
  YAML
  "Obsidian 生成的畸形一行写法" => <<~YAML,
    image: path:/assets/img/posts/cover.jpg
  YAML
}

puts "=" * 74
puts "模板各种 image 写法经过规范化后的结果"
puts "=" * 74

variants.each do |label, yaml|
  data = YAML.safe_load(yaml)
  data = {} if data.nil?
  before = data.key?("image") ? data["image"].inspect : "(无 image 键)"
  F.apply!(data)
  after = data.key?("image") ? data["image"].inspect : "(已删除 image 键 → 走无封面分支)"
  puts "\n  #{label}"
  puts "    解析后 : #{before}"
  puts "    规范化 : #{after}"

  # 关键断言：绝不能留下一个「没有可用 path 的哈希」
  if data.key?("image")
    path = data["image"].is_a?(Hash) ? data["image"]["path"] : nil
    check("image 存在时 path 必须是非空字符串", path.is_a?(String) && !path.empty?, true)
    check("path 不能以 { 开头（会导致 /{ 裂图）", path.to_s.start_with?("{"), false)
  end
end

puts
puts "=" * 74
puts "模拟一整篇文章渲染前的状态"
puts "=" * 74

full = <<~YAML
  title: "我的第一篇博客"
  date: 2026-10-08 19:02:40 +0800
  categories:
    - 随笔
  tags:
    - 日常
  description: ""
  image:
    path: ""
  pin: false
  toc: true
  comments: true
  math: false
  media_subpath: ""
  pb-publish: true
  pb-type: post
YAML

# date 会被 YAML 解析成 Time，safe_load 默认不允许，这里显式放行
data = YAML.safe_load(full, permitted_classes: [Time, Date, DateTime])
F.apply!(data)

check("pb-publish 被剔除", data.key?("pb-publish"), false)
check("pb-type 被剔除", data.key?("pb-type"), false)
check("空 image 被删除", data.key?("image"), false)
check("title 保留", data["title"], "我的第一篇博客")
check("categories 保留", data["categories"], ["随笔"])
check("media_subpath 是空串", data["media_subpath"], "")

puts
puts "=" * 74
puts $failures.zero? ? "全部通过 ✓" : "#{$failures} 个失败 ✗"
puts "=" * 74
exit($failures.zero? ? 0 : 1)
