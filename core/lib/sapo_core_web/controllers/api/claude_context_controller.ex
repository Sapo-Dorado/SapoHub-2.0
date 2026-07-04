defmodule SapoCoreWeb.Api.ClaudeContextController do
  @moduledoc false
  use SapoCoreWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, SapoCore.AiContext.global_context())
  end
end
