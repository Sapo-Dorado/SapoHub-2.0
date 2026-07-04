defmodule SapoKit.HTTP do
  @moduledoc """
  Core HTTP client facade (one shared pool for the whole hub).

  Modules use this instead of bundling their own HTTP client — fewer deps
  to merge when composing external modules, one place for pool tuning.

  Options are `Req` options (`:json`, `:body`, `:headers`, `:form_multipart`,
  `:receive_timeout`, ...). Returns `{:ok, %{status: integer, body: term,
  headers: list}}` or `{:error, reason}`.
  """

  @type response :: %{status: non_neg_integer(), body: term(), headers: list()}

  @spec request(atom(), String.t(), keyword()) :: {:ok, response()} | {:error, term()}
  def request(method, url, opts \\ []) do
    impl().request(method, url, opts)
  end

  @spec get(String.t(), keyword()) :: {:ok, response()} | {:error, term()}
  def get(url, opts \\ []), do: request(:get, url, opts)

  @spec post(String.t(), keyword()) :: {:ok, response()} | {:error, term()}
  def post(url, opts \\ []), do: request(:post, url, opts)

  defp impl, do: Application.fetch_env!(:sapo_module_kit, :http)
end
