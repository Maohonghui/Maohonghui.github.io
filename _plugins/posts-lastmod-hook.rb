#!/usr/bin/env ruby
# frozen_string_literal: true
#
# posts-lastmod-hook.rb
#
# 用 git 提交历史给每篇文章补上「最近更新」时间。
#
# 原版直接用了反引号执行 git，一旦 git 不可用（浅克隆、没有 .git 目录、
# 沙箱里没有 git 命令）就会抛异常，把整个构建带崩。
# 这里改成不抛异常：拿不到就安静跳过，显示效果只是少一行「更新于」。

Jekyll::Hooks.register :posts, :post_init do |post|
  next if post.data['last_modified_at']

  begin
    path = post.path.to_s
    next if path.empty?

    count = `git rev-list --count HEAD -- "#{path}" 2>/dev/null`.to_s.strip
    next unless count.match?(/\A\d+\z/) && count.to_i > 1

    lastmod = `git log -1 --pretty="%ad" --date=iso -- "#{path}" 2>/dev/null`.to_s.strip
    next if lastmod.empty?

    post.data['last_modified_at'] = lastmod
  rescue StandardError => e
    Jekyll.logger.debug 'Lastmod:', "跳过 #{post.path}（#{e.class}）"
    nil
  end
end
