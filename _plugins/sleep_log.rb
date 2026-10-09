# frozen_string_literal: true
#
# sleep_log.rb  （习惯打卡）
#
# 把 Obsidian 里「习惯打卡」那篇笔记解析成网站要用的热力图数据。
#
# 为什么要有这个插件
# ------------------
# 打卡笔记是 Obsidian 里的一篇 Markdown，用 GitHub Publisher 发布到仓库，长这样：
#
#     # 习惯打卡
#
#     ## 早睡
#     - [x] 2026-10-08 23:30 07:30
#     - [x] 2026-10-07 01:10
#     - [ ] 2026-10-06
#
#     ## 锻炼
#     - [x] 2026-10-08
#     - [ ] 2026-10-07
#
# Jekyll 自带的 _data 只认 yaml/yml/json/csv/tsv，读不了 .md，所以用这个插件补上。
#
# ── 日期归属规则（重点）──────────────────────────────────────────────────
#
# 你的作息是「当天 20:00 到次日 10:00」，所以打卡不应该按自然日 0 点切分。
# 规则：**以次日 10:00 为界**。
#
#   10-08 23:30  →  算 10-08
#   10-09 01:10  →  算 10-08   （凌晨 1 点还是 8 号那晚）
#   10-09 09:59  →  算 10-08
#   10-09 10:00  →  算 10-09
#   10-09 20:30  →  算 10-09
#
# 也就是说：如果你在 10-08 那行里写了 01:10，插件会自动把它归到 10-08，
# 你不需要自己去想「这算哪天」。
#
# ── 更省事的做法 ────────────────────────────────────────────────────────
#
# 其实你连时间都不用写：直接点当天的复选框即可，插件记「这天打卡了」。
# 想记具体时间就在日期后面补 23:30，热力图悬停时能看到。

require "date"
require "pathname"

module MaohonghuiBlog
  module SleepLog
    # ## 早睡  /  ### 锻炼  —— 用来区分不同习惯
    HABIT_HEADING_RE = /^\s{0,3}\#{2,6}\s+(.+?)\s*$/

    # 真实的打卡行。两种写法都要认：
    #
    #   - [x] 2026-10-08 23:30 07:30      ← 日期在前（手写）
    #   - [x] 23:30 2026-10-08 07:30      ← 时间在前（Checkbox Time Tracker 自动插入）
    #   - [x] 2026-10-08                  ← 只有日期
    #   - [x] 23:30                       ← 只有时间（日期从行里别处找）
    #
    # 开头必须真的是列表项（可缩进），这是关键：
    # 笔记顶部的说明文字里会写「例如 - [x] 2026-10-08 23:30 这样」，
    # 如果不锚定行首，那句说明里的示例会被当成真实打卡数据解析进去。
    # `>` 引用块里的内容前面是 `>`，所以会被正确排除。
    CHECKBOX_RE = /^\s*(?:[-*+]|\d+\.)\s*\[([ xX✓✔])\]([^\n]*)$/

    # 从行尾里找日期和 HH:MM 时间，不依赖它们谁前谁后
    DATE_RE = /(\d{4}-\d{2}-\d{2})/
    TIME_RE = /(\d{1,2}:\d{2})/

    # 没写 ## 标题时，整篇归到这个默认习惯
    DEFAULT_HABIT = "打卡"

    # 习惯名 → 稳定的 ASCII 键。
    # 你在笔记里用中文写 ## 早睡，插件转成 sleep，模板再映射回中文显示，
    # 这样以后想改文案不用动笔记。
    HABIT_SLUGS = {
      "早睡" => "sleep",
      "睡觉" => "sleep",
      "睡眠" => "sleep",
      "sleep" => "sleep",
      "早起" => "earlyrise",
      "锻炼" => "workout",
      "运动" => "workout",
      "workout" => "workout",
      "阅读" => "reading",
      "读书" => "reading",
      "reading" => "reading",
      "背单词" => "vocab",
      "写作" => "writing",
      "冥想" => "meditation"
    }.freeze

    # 显示顺序：没列到的排后面
    HABIT_ORDER = %w[sleep workout reading earlyrise vocab writing meditation].freeze

    DEFAULT_FILE = "checkin.md"
    DEFAULT_DAYS = 91

    # 日期归属分界点：早于这个时刻算前一天
    DEFAULT_DAY_BOUNDARY = "10:00"

    module_function

    def habit_slug(name)
      cleaned = name.to_s.strip
      HABIT_SLUGS[cleaned] || HABIT_SLUGS[cleaned.downcase] || cleaned
    end

    def normalize_clock(raw)
      return nil if raw.nil?

      match = raw.to_s.strip.match(/\A(\d{1,2}):(\d{2})\z/)
      return nil unless match

      hour = match[1].to_i
      minute = match[2].to_i
      return nil unless hour.between?(0, 23) && minute.between?(0, 59)

      format("%02d:%02d", hour, minute)
    end

    def clock_to_minutes(clock)
      return nil if clock.nil?

      hour, minute = clock.split(":").map(&:to_i)
      return nil unless hour && minute

      hour * 60 + minute
    end

    # 把时间归到「哪一晚」。
    #
    # date  = 你写的那一行上的日期
    # clock = 入睡时间（可空）
    #
    # 规则：日期归属按「次日 boundary 点」切分。如果写的时间早于 boundary，
    # 说明是这一晚熬到了第二天早上，仍然算这一晚。
    #
    #   10-08 那行写 23:30 + boundary 10:00 → 23:30 >= 10:00 → 算 10-08
    #   10-09 那行写 01:10 + boundary 10:00 → 01:10 <  10:00 → 算 10-08
    #
    # 注意：第二种情况下，用户是把 01:10 写在了 10-09 那行（因为他是在 10-09 凌晨
    # 打的卡），归到 10-08 才是对的。
    def attribution_date(date, clock, boundary_minutes)
      return date if clock.nil? || boundary_minutes.nil?

      minutes = clock_to_minutes(clock)
      return date if minutes.nil?
      return date if minutes >= boundary_minutes

      (Date.parse(date) - 1).iso8601
    rescue ArgumentError, TypeError
      date
    end

    # 解析整篇笔记
    #
    # 返回 { "早睡" => { "2026-10-08" => { sleep_at:, wake_at: } }, ... }
    def parse(content, boundary_minutes = clock_to_minutes(DEFAULT_DAY_BOUNDARY))
      habits = {}
      current = nil

      content.each_line do |line|
        heading = line.match(HABIT_HEADING_RE)
        if heading
          name = heading[1].strip
          # 跳过「格式说明」这类非习惯的小标题
          name = nil if name.empty? || name.match?(/说明|格式|注意|用法|example/i)
          if name
            current = habit_slug(name)
            habits[current] ||= {}
          end
          next
        end

        match = line.match(CHECKBOX_RE)
        next if match.nil?

        checked = match[1].downcase == "x" || ["✓", "✔"].include?(match[1])
        next unless checked

        rest = match[2].to_s

        # 日期：优先取复选框后面那段里的日期；没有就退回整行找
        # （Checkbox Time Tracker 可能把时间插在日期前面）
        date_match = rest.match(DATE_RE) || line.match(DATE_RE)
        next if date_match.nil?

        date = date_match[1]

        # 校验日期真实存在，挡掉 2026-13-45 这种
        begin
          Date.parse(date)
        rescue ArgumentError, TypeError
          next
        end

        # 时间：把日期本身挖掉再找，避免把 "2026-10-08" 里的 10:08 之类误认成时间
        times_source = rest.gsub(date, " ")
        times = times_source.scan(TIME_RE).flatten.map { |t| normalize_clock(t) }.compact
        sleep_at = times[0]
        wake_at = times[1]

        key = current || DEFAULT_HABIT
        habits[key] ||= {}

        # 归到正确的那一晚
        attributed = attribution_date(date, sleep_at, boundary_minutes)

        # 两行可能归到同一晚（比如 10-02 写了 23:30，10-03 又写了 01:00，
        # 后者按「次日 10:00 为界」也属于 10-02 那晚）。
        # 取舍规则：
        #   1. 有时间的那条胜过只有打勾的（别让空值覆盖真实数据）
        #   2. 都有时间时，取后出现的（视为你后来补充的更正）
        existing = habits[key][attributed]
        habits[key][attributed] =
          if existing.nil?
            { "sleep_at" => sleep_at, "wake_at" => wake_at }
          elsif sleep_at.nil?
            existing # 新来的没时间，保留原有
          elsif existing["sleep_at"].nil?
            { "sleep_at" => sleep_at, "wake_at" => wake_at || existing["wake_at"] }
          else
            { "sleep_at" => sleep_at, "wake_at" => wake_at || existing["wake_at"] }
          end
      end

      # 去掉没有任何记录的习惯
      habits.reject { |_, entries| entries.empty? }
    end

    # 把 "23:30" 转成分，用于求平均（凌晨时间 +24h，保证平均有意义）
    def minutes_for_average(clock)
      return nil if clock.nil?

      minutes = clock_to_minutes(clock)
      return nil if minutes.nil?

      minutes < 12 * 60 ? minutes + (24 * 60) : minutes
    end

    def format_average(total_minutes)
      return nil if total_minutes.nil?

      rounded = total_minutes.round
      hour = (rounded / 60) % 24
      minute = rounded % 60
      format("%02d:%02d", hour, minute)
    end

    # 为一个习惯构建热力图数据
    def build_habit(name, entries, first_date, last_date, boundary_minutes)
      days = []
      cursor = first_date
      while cursor <= last_date
        key = cursor.iso8601
        entry = entries[key]

        days << {
          "date" => key,
          "done" => !entry.nil?,
          "sleep_at" => entry && entry["sleep_at"],
          "wake_at" => entry && entry["wake_at"]
        }
        cursor += 1
      end

      done_days = days.select { |d| d["done"] }

      # 连续天数：从最后一天往前数
      streak_current = 0
      days.reverse_each do |d|
        break unless d["done"]

        streak_current += 1
      end

      # 最长连续
      streak_best = 0
      running = 0
      days.each do |d|
        if d["done"]
          running += 1
          streak_best = running if running > streak_best
        else
          running = 0
        end
      end

      # 入睡时间统计（凌晨按 +24h 参与平均，避免平均出中午）
      sleep_minutes = done_days.map { |d| minutes_for_average(d["sleep_at"]) }.compact
      average_sleep = if sleep_minutes.empty?
                        nil
                      else
                        format_average(sleep_minutes.sum.to_f / sleep_minutes.size)
                      end

      # 最早 / 最晚（按同一套 +24h 口径比较）
      sorted = done_days.select { |d| d["sleep_at"] }
                        .sort_by { |d| minutes_for_average(d["sleep_at"]) }

      {
        "name" => name,
        "stats" => {
          "recorded_days" => done_days.size,
          "streak_current" => streak_current,
          "streak_best" => streak_best,
          "average_sleep" => average_sleep,
          "earliest_sleep" => sorted.first && sorted.first["sleep_at"],
          "latest_sleep" => sorted.last && sorted.last["sleep_at"]
        },
        "days" => days
      }
    end

    def build(site)
      config = site.config["checkin"] || site.config["sleep_log"] || {}
      rel_path = config["file"] || DEFAULT_FILE
      days_window = (config["days"] || DEFAULT_DAYS).to_i
      boundary = normalize_clock(config["day_boundary"]) || DEFAULT_DAY_BOUNDARY
      boundary_minutes = clock_to_minutes(boundary)

      absolute =
        if rel_path.to_s.empty?
          nil
        elsif Pathname.new(rel_path.to_s).absolute?
          rel_path.to_s
        else
          File.join(site.source, rel_path)
        end

      unless absolute && File.file?(absolute)
        Jekyll.logger.info "Checkin:", "跳过（找不到 #{rel_path}）"
        return nil
      end

      content = File.read(absolute, encoding: "UTF-8")
      habits = parse(content, boundary_minutes)

      if habits.empty?
        Jekyll.logger.info "Checkin:", "#{rel_path} 里还没有打勾的记录"
        return nil
      end

      # 统计区间：所有习惯里最晚的那天作为结束，往前取 days_window 天
      all_dates = habits.values.flat_map(&:keys).map { |d| Date.parse(d) rescue nil }.compact
      last_date = all_dates.max
      first_date = last_date - (days_window - 1)

      order = habits.keys.sort_by do |name|
        idx = HABIT_ORDER.index(name)
        idx.nil? ? HABIT_ORDER.size : idx
      end
      built = order.map { |name| build_habit(name, habits[name], first_date, last_date, boundary_minutes) }

      {
        "generated_at" => Time.now.strftime("%Y-%m-%d"),
        "window" => {
          "start" => first_date.iso8601,
          "end" => last_date.iso8601,
          "days" => days_window,
          # 热力图周一在第 0 行，所以第一列前面要空出几天
          "grid_offset" => first_date.wday.zero? ? 6 : first_date.wday - 1
        },
        "day_boundary" => boundary,
        "habits" => built
      }
    rescue StandardError => e
      Jekyll.logger.warn "Checkin:", "解析失败：#{e.class}: #{e.message}"
      nil
    end
  end
end

# pre_render 比主题生成数据更早，保证 Liquid 里一定能拿到 site.data['checkin']
Jekyll::Hooks.register :site, :pre_render do |site|
  data = MaohonghuiBlog::SleepLog.build(site)
  site.data["checkin"] = data unless data.nil?
end

# 旧名字保留成别名，避免早先写的测试/脚本引用不到
MaohonghuiBlog::Checkin = MaohonghuiBlog::SleepLog
