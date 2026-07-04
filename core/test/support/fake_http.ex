defmodule SapoCore.FakeHTTP do
  @moduledoc """
  Test double for `SapoCore.HTTP`. Captures requests into the calling test's
  mailbox (via a registered test pid) and replies with a canned response.
  """

  @pid_key {__MODULE__, :test_pid}
  @response_key {__MODULE__, :response}

  def install(test_pid, response \\ {:ok, %{status: 200, body: %{}, headers: []}}) do
    :persistent_term.put(@pid_key, test_pid)
    :persistent_term.put(@response_key, response)
    previous = Application.get_env(:sapo_core, :http_client)
    Application.put_env(:sapo_core, :http_client, __MODULE__)

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:sapo_core, :http_client)
        mod -> Application.put_env(:sapo_core, :http_client, mod)
      end
    end)
  end

  def respond_with(response), do: :persistent_term.put(@response_key, response)

  def request(method, url, opts) do
    send(:persistent_term.get(@pid_key), {:http, method, url, opts})
    :persistent_term.get(@response_key)
  end
end
