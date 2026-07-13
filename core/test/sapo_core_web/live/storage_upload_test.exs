defmodule SapoCoreWeb.StorageUploadTest do
  # Regression test for the crash found via `journalctl` on `test`:
  # `consume_uploaded_entry/3`'s return value was being assigned back to
  # `socket`, so the next call (`load/1`) got a bogus non-socket argument
  # and crashed the LiveView process (ArgumentError / KeyError depending on
  # which line hit first). This drives the real upload pipeline end to end
  # through Phoenix.LiveViewTest, the same way the browser does, without
  # relying on browser automation (which can't drive a real file picker in
  # this sandboxed environment).
  use SapoCoreWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "uploading a file via the storage LiveView does not crash and lists the file", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/storage/storage/uploads")

    view |> element("button[phx-click=toggle_upload]") |> render_click()

    png =
      Base.decode64!(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
      )

    file =
      file_input(view, "form", :files, [
        %{
          last_modified: 1_594_171_879_000,
          name: "upload_test.png",
          content: png,
          size: byte_size(png),
          type: "image/png"
        }
      ])

    assert render_upload(file, "upload_test.png") =~ "100"

    html = render(view)
    assert html =~ "upload_test.png"
    refute html =~ "no longer exists"

    # The view process must still be alive — if the bug regresses, the
    # GenServer crashes here and this call raises/exits.
    assert Process.alive?(view.pid)
  end
end
