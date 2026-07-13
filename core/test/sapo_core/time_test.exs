defmodule SapoCore.TimeTest do
  use ExUnit.Case, async: false

  alias SapoCore.Time, as: SapoTime

  setup do
    previous = Application.get_env(:sapo_core, :display_timezone)
    on_exit(fn -> Application.put_env(:sapo_core, :display_timezone, previous) end)
    :ok
  end

  test "defaults to Etc/UTC and is a no-op shift" do
    Application.delete_env(:sapo_core, :display_timezone)
    assert SapoTime.display_timezone() == "Etc/UTC"

    now = DateTime.utc_now()
    assert SapoTime.local(now) == now
  end

  test "shifts a UTC datetime into the configured named zone" do
    Application.put_env(:sapo_core, :display_timezone, "America/Los_Angeles")

    # 2024-01-15 20:00 UTC is 12:00 PST (UTC-8, no DST in January).
    utc = DateTime.new!(~D[2024-01-15], ~T[20:00:00], "Etc/UTC")

    local = SapoTime.local(utc)
    assert local.time_zone == "America/Los_Angeles"
    assert local.zone_abbr == "PST"
    assert Calendar.strftime(local, "%H:%M") == "12:00"
  end

  test "DST is handled automatically via the named zone, not a fixed offset" do
    Application.put_env(:sapo_core, :display_timezone, "America/Los_Angeles")

    # Same UTC clock time, one date in standard time (PST, UTC-8) and one
    # in daylight time (PDT, UTC-7) — the offset/abbr must differ even
    # though the configured zone name is identical, because it's a real
    # IANA zone (with tzdata's DST transition rules) rather than a static
    # "PST" string. This is the whole point of storing UTC + a zone name
    # instead of a raw offset.
    winter = DateTime.new!(~D[2024-01-15], ~T[20:00:00], "Etc/UTC")
    summer = DateTime.new!(~D[2024-07-15], ~T[20:00:00], "Etc/UTC")

    assert SapoTime.local(winter).zone_abbr == "PST"
    assert Calendar.strftime(SapoTime.local(winter), "%H:%M") == "12:00"

    assert SapoTime.local(summer).zone_abbr == "PDT"
    assert Calendar.strftime(SapoTime.local(summer), "%H:%M") == "13:00"
  end

  test "format/2 renders in the configured zone" do
    Application.put_env(:sapo_core, :display_timezone, "America/Los_Angeles")
    utc = DateTime.new!(~D[2024-01-15], ~T[20:00:00], "Etc/UTC")

    assert SapoTime.format(utc, "%Y-%m-%d %H:%M") == "2024-01-15 12:00"
  end

  test "falls back to UTC (unchanged datetime) on an unknown zone name instead of raising" do
    Application.put_env(:sapo_core, :display_timezone, "Not/A_Real_Zone")
    now = DateTime.utc_now()

    assert SapoTime.local(now) == now
  end
end
