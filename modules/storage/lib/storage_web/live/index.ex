defmodule StorageWeb.Live.Index do
  @moduledoc """
  Storage page: browse every opted-in module's files, delete any of them,
  and upload manual files (stored under this module's own `uploads/` dir).
  Mirrors SapoHub v1's storage page, adapted to v2's cross-module file API
  (`SapoKit.Storage.list_all/0` / `.delete/1`) instead of a single flat
  filesystem root.
  """
  use SapoKit.Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(query: "", confirm_delete: nil)
     |> allow_upload(:files,
       accept: :any,
       max_file_size: 2_000_000_000,
       max_entries: 10,
       auto_upload: true,
       progress: &handle_progress/3
     )
     |> load()}
  end

  defp load(socket) do
    assign(socket, files: Storage.list_files())
  end

  # ── Filtering ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, query: query)}
  end

  # ── Delete (two-step confirm, no native dialogs) ────────────────────────

  def handle_event("confirm_delete", %{"path" => path}, socket) do
    {:noreply, assign(socket, confirm_delete: path)}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, confirm_delete: nil)}
  end

  def handle_event("delete", %{"path" => path}, socket) do
    case Storage.delete_file(path) do
      :ok ->
        {:noreply, socket |> assign(confirm_delete: nil) |> load()}

      {:error, _} ->
        {:noreply,
         socket |> assign(confirm_delete: nil) |> put_flash(:error, "Could not delete #{path}")}
    end
  end

  # ── Upload ───────────────────────────────────────────────────────────────

  def handle_event("noop", _, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  defp handle_progress(:files, entry, socket) do
    if entry.done? do
      socket =
        consume_uploaded_entry(socket, entry, fn %{path: tmp} ->
          Storage.save_upload(tmp, entry.client_name)
        end)

      {:noreply, load(socket)}
    else
      {:noreply, socket}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp filtered(files, ""), do: files

  defp filtered(files, query) do
    q = String.downcase(query)
    Enum.filter(files, &String.contains?(String.downcase(&1.path), q))
  end

  defp download_href(path), do: "/api/storage/files/" <> URI.encode(path)

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_size(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  defp format_size(bytes), do: "#{Float.round(bytes / 1024 / 1024 / 1024, 2)} GB"

  defp format_mtime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp error_to_string(:too_large), do: "file too large"
  defp error_to_string(:too_many_files), do: "too many files at once"
  defp error_to_string(:not_accepted), do: "file type not accepted"
  defp error_to_string(err), do: to_string(err)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline
        crumb="storage"
        items={@statusline}
        right={"#{length(@files)} file#{if length(@files) == 1, do: "", else: "s"}"}
      />
      <SapoCoreWeb.Layouts.flash_group flash={@flash} />

      <main class="max-w-[860px] mx-auto px-4 py-8">
          <div
            class="rounded-[4px] border border-dashed border-[#242D31] hover:border-[#3C5934] bg-[#151B1E] px-4 py-5 mb-6 transition-colors"
            phx-drop-target={@uploads.files.ref}
          >
            <form phx-change="noop" phx-submit="noop" class="flex items-center gap-3">
              <label class="cursor-pointer px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934]">
                Browse files
                <.live_file_input upload={@uploads.files} class="hidden" />
              </label>
              <span class="font-mono text-[11.5px] text-[#86948F]">
                or drop files here — saved under storage/uploads
              </span>
            </form>

            <div :if={@uploads.files.entries != []} class="mt-4 space-y-2">
              <div
                :for={entry <- @uploads.files.entries}
                class="flex items-center gap-3 font-mono text-[11.5px]"
              >
                <span class="text-[#86948F] truncate flex-1">{entry.client_name}</span>
                <div class="w-24 h-1.5 rounded-full bg-[#0D1113] border border-[#242D31] overflow-hidden">
                  <div class="h-full bg-[#7FB069]" style={"width: #{entry.progress}%"}></div>
                </div>
                <span class="text-[#86948F] w-8 text-right">{entry.progress}%</span>
                <button
                  type="button"
                  phx-click="cancel_upload"
                  phx-value-ref={entry.ref}
                  class="text-[#86948F] hover:text-[#E05C5C]"
                >
                  ✕
                </button>
              </div>
              <p
                :for={err <- upload_errors(@uploads.files)}
                class="font-mono text-[11.5px] text-[#E05C5C]"
              >
                {error_to_string(err)}
              </p>
            </div>
          </div>

          <input
            type="text"
            value={@query}
            phx-change="filter"
            phx-keyup="filter"
            name="query"
            placeholder="filter by path…"
            class="w-full box-border mb-4 px-3 py-[9px] rounded-[4px] bg-[#151B1E] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none font-mono"
          />

          <div class="rounded-[4px] border border-[#242D31] divide-y divide-[#242D31] overflow-hidden">
            <div
              :for={file <- filtered(@files, @query)}
              class="flex items-center gap-3 px-3 py-2.5 bg-[#151B1E] font-mono text-[12px]"
            >
              <span class="flex-1 min-w-0 truncate text-[#E6ECE9]" title={file.path}>
                {file.path}
              </span>
              <span class="text-[#86948F] w-16 text-right shrink-0">{format_size(file.size)}</span>
              <span class="text-[#86948F] w-32 text-right shrink-0">{format_mtime(file.mtime)}</span>
              <a
                href={download_href(file.path)}
                download
                class="shrink-0 text-[#86948F] hover:text-[#7FB069]"
              >
                ⬇
              </a>
              <button
                :if={@confirm_delete != file.path}
                type="button"
                phx-click="confirm_delete"
                phx-value-path={file.path}
                class="shrink-0 text-[#86948F] hover:text-[#E05C5C]"
              >
                ✕
              </button>
              <button
                :if={@confirm_delete == file.path}
                type="button"
                phx-click="delete"
                phx-value-path={file.path}
                class="shrink-0 font-mono text-[11px] text-[#E05C5C] hover:underline"
              >
                confirm?
              </button>
              <button
                :if={@confirm_delete == file.path}
                type="button"
                phx-click="cancel_delete"
                class="shrink-0 font-mono text-[11px] text-[#86948F] hover:underline"
              >
                cancel
              </button>
            </div>

            <p
              :if={filtered(@files, @query) == []}
              class="px-3 py-6 text-center font-mono text-[12px] text-[#86948F]"
            >
              {if @files == [], do: "No files yet.", else: "No files match your filter."}
            </p>
          </div>
      </main>
    </div>
    """
  end
end
