defmodule SapoCore.HTTP do
  @moduledoc """
  The hub's HTTP client (backing `SapoKit.HTTP`), built on Req with one
  shared Finch pool (`SapoCore.Finch`).
  """

  @spec request(atom(), String.t(), keyword()) ::
          {:ok, SapoKit.HTTP.response()} | {:error, term()}
  def request(method, url, opts \\ []) do
    opts = Keyword.merge([method: method, url: url, finch: SapoCore.Finch, retry: false], opts)

    case Req.request(opts) do
      {:ok, %Req.Response{status: status, body: body, headers: headers}} ->
        {:ok, %{status: status, body: body, headers: Enum.to_list(headers)}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
