defmodule ScheduledJobs.CronTest do
  use ExUnit.Case, async: true

  alias ScheduledJobs.Cron

  defp dt(y, mo, d, h, mi) do
    {:ok, dt} = DateTime.new(Date.new!(y, mo, d), Time.new!(h, mi, 0), "Etc/UTC")
    dt
  end

  describe "parse/1 — structure" do
    test "rejects wrong field count" do
      assert {:error, _} = Cron.parse("* * * *")
      assert {:error, _} = Cron.parse("* * * * * *")
    end

    test "rejects non-integer fields" do
      assert {:error, _} = Cron.parse("foo * * * *")
    end

    test "rejects out-of-range values" do
      assert {:error, _} = Cron.parse("60 * * * *")
      assert {:error, _} = Cron.parse("* 24 * * *")
      assert {:error, _} = Cron.parse("* * 32 * *")
      assert {:error, _} = Cron.parse("* * * 13 *")
      assert {:error, _} = Cron.parse("* * * * 8")
    end

    test "accepts a plain string input error for non-binary" do
      assert {:error, _} = Cron.parse(nil)
    end
  end

  describe "matches?/2 — wildcards" do
    test "every minute matches anything" do
      {:ok, cron} = Cron.parse("* * * * *")
      assert Cron.matches?(cron, dt(2026, 9, 8, 3, 17))
      assert Cron.matches?(cron, dt(2026, 1, 1, 0, 0))
    end
  end

  describe "matches?/2 — lists and single values" do
    test "single minute/hour" do
      {:ok, cron} = Cron.parse("30 9 * * *")
      assert Cron.matches?(cron, dt(2026, 9, 8, 9, 30))
      refute Cron.matches?(cron, dt(2026, 9, 8, 9, 31))
      refute Cron.matches?(cron, dt(2026, 9, 8, 10, 30))
    end

    test "comma list" do
      {:ok, cron} = Cron.parse("0,15,30,45 * * * *")
      assert Cron.matches?(cron, dt(2026, 9, 8, 4, 15))
      assert Cron.matches?(cron, dt(2026, 9, 8, 4, 45))
      refute Cron.matches?(cron, dt(2026, 9, 8, 4, 20))
    end
  end

  describe "matches?/2 — ranges" do
    test "hour range (business hours)" do
      {:ok, cron} = Cron.parse("0 9-17 * * *")
      assert Cron.matches?(cron, dt(2026, 9, 8, 9, 0))
      assert Cron.matches?(cron, dt(2026, 9, 8, 17, 0))
      refute Cron.matches?(cron, dt(2026, 9, 8, 18, 0))
      refute Cron.matches?(cron, dt(2026, 9, 8, 8, 0))
    end
  end

  describe "matches?/2 — steps" do
    test "*/15 minutes" do
      {:ok, cron} = Cron.parse("*/15 * * * *")
      assert Cron.matches?(cron, dt(2026, 9, 8, 3, 0))
      assert Cron.matches?(cron, dt(2026, 9, 8, 3, 15))
      assert Cron.matches?(cron, dt(2026, 9, 8, 3, 45))
      refute Cron.matches?(cron, dt(2026, 9, 8, 3, 10))
    end

    test "range with step" do
      {:ok, cron} = Cron.parse("0-30/10 * * * *")
      assert Cron.matches?(cron, dt(2026, 9, 8, 3, 0))
      assert Cron.matches?(cron, dt(2026, 9, 8, 3, 10))
      assert Cron.matches?(cron, dt(2026, 9, 8, 3, 20))
      assert Cron.matches?(cron, dt(2026, 9, 8, 3, 30))
      refute Cron.matches?(cron, dt(2026, 9, 8, 3, 40))
    end
  end

  describe "matches?/2 — day-of-week" do
    test "0 and 7 both mean Sunday" do
      {:ok, cron0} = Cron.parse("0 0 * * 0")
      {:ok, cron7} = Cron.parse("0 0 * * 7")
      # 2026-09-06 is a Sunday
      sunday = dt(2026, 9, 6, 0, 0)
      monday = dt(2026, 9, 7, 0, 0)

      assert Cron.matches?(cron0, sunday)
      assert Cron.matches?(cron7, sunday)
      refute Cron.matches?(cron0, monday)
      refute Cron.matches?(cron7, monday)
    end

    test "weekday range Mon-Fri" do
      {:ok, cron} = Cron.parse("0 9 * * 1-5")
      # 2026-09-07 Mon .. 2026-09-11 Fri, 2026-09-12 Sat, 2026-09-06 Sun
      assert Cron.matches?(cron, dt(2026, 9, 7, 9, 0))
      assert Cron.matches?(cron, dt(2026, 9, 11, 9, 0))
      refute Cron.matches?(cron, dt(2026, 9, 12, 9, 0))
      refute Cron.matches?(cron, dt(2026, 9, 6, 9, 0))
    end
  end

  describe "matches?/2 — day-of-month/day-of-week OR quirk" do
    test "both restricted: OR semantics" do
      # 15th OR Friday at 09:00
      {:ok, cron} = Cron.parse("0 9 15 * 5")
      # 2026-09-15 is a Tuesday (not Friday) -> still matches via dom
      assert Cron.matches?(cron, dt(2026, 9, 15, 9, 0))
      # 2026-09-11 is a Friday (not the 15th) -> still matches via dow
      assert Cron.matches?(cron, dt(2026, 9, 11, 9, 0))
      # neither the 15th nor a Friday
      refute Cron.matches?(cron, dt(2026, 9, 12, 9, 0))
    end

    test "only dom restricted behaves as AND with wildcard dow" do
      {:ok, cron} = Cron.parse("0 9 15 * *")
      assert Cron.matches?(cron, dt(2026, 9, 15, 9, 0))
      refute Cron.matches?(cron, dt(2026, 9, 16, 9, 0))
    end

    test "only dow restricted behaves as AND with wildcard dom" do
      {:ok, cron} = Cron.parse("0 9 * * 5")
      assert Cron.matches?(cron, dt(2026, 9, 11, 9, 0))
      refute Cron.matches?(cron, dt(2026, 9, 12, 9, 0))
    end
  end

  describe "describe/1" do
    test "every minute" do
      {:ok, cron} = Cron.parse("* * * * *")
      assert Cron.describe(cron) == "every minute"
    end

    test "every N minutes" do
      {:ok, cron} = Cron.parse("*/15 * * * *")
      assert Cron.describe(cron) == "every 15 minutes"
    end

    test "every N hours" do
      {:ok, cron} = Cron.parse("0 */3 * * *")
      assert Cron.describe(cron) == "every 3 hours"
    end

    test "daily at HH:MM" do
      {:ok, cron} = Cron.parse("5 9 * * *")
      assert Cron.describe(cron) == "daily at 09:05"
    end

    test "weekly on days at HH:MM" do
      {:ok, cron} = Cron.parse("0 9 * * 1,3,5")
      assert Cron.describe(cron) == "weekly on Mon,Wed,Fri at 09:00"
    end

    test "falls back to raw expression for unrecognized shapes" do
      {:ok, cron} = Cron.parse("7 3 1 6 *")
      assert Cron.describe(cron) == "7 3 1 6 *"
    end
  end

  describe "valid?/1" do
    test "true for well-formed expressions" do
      assert Cron.valid?("*/5 * * * *")
    end

    test "false for malformed expressions" do
      refute Cron.valid?("not a cron")
    end
  end
end
