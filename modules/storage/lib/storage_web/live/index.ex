defmodule StorageWeb.Live.Index do
  @moduledoc """
  Storage page: a plain folder-tree browser over every opted-in module's
  storage (each module's dir lives directly under the storage root, so the
  top level is one folder per module). Uniform CRUD everywhere — create
  folders, upload, delete, and preview images/video/PDF inline — with no
  special treatment per module. Mirrors SapoHub v1's storage page, adapted
  to v2's cross-module storage root instead of a single flat filesystem.
  """
  use SapoKit.Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       query: "",
       show_new_folder: false,
       new_folder_name: "",
       show_upload: false,
       confirm_delete: nil,
       viewer: nil
     )
     |> allow_upload(:files,
       accept: :any,
       max_file_size: 2_000_000_000,
       max_entries: 10,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    path = params["path"] || []
    {:noreply, socket |> assign(path: path, viewer: nil) |> load()}
  end

  defp load(socket) do
    case Storage.list_dir(socket.assigns.path) do
      {:ok, %{dirs: dirs, files: files}} ->
        assign(socket, dirs: dirs, files: files)

      {:error, _} ->
        socket
        |> put_flash(:error, "That folder no longer exists")
        |> push_patch(to: folder_href([]))
    end
  end

  # ── Filtering ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, query: query)}
  end

  # ── New folder ───────────────────────────────────────────────────────────

  def handle_event("toggle_new_folder", _, socket) do
    {:noreply,
     assign(socket,
       show_new_folder: !socket.assigns.show_new_folder,
       show_upload: false,
       new_folder_name: ""
     )}
  end

  def handle_event("create_folder", %{"name" => name}, socket) do
    name = String.trim(name)

    cond do
      name == "" ->
        {:noreply, socket}

      String.contains?(name, "/") or String.contains?(name, "..") ->
        {:noreply, put_flash(socket, :error, "Invalid folder name")}

      true ->
        case Storage.create_folder(socket.assigns.path ++ [name]) do
          :ok ->
            {:noreply, socket |> assign(show_new_folder: false, new_folder_name: "") |> load()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not create folder #{name}")}
        end
    end
  end

  # ── Upload ───────────────────────────────────────────────────────────────

  def handle_event("noop", _, socket), do: {:noreply, socket}

  def handle_event("toggle_upload", _, socket) do
    {:noreply, assign(socket, show_upload: !socket.assigns.show_upload, show_new_folder: false)}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :files, ref)}
  end

  # ── Delete (two-step confirm, no native dialogs) ────────────────────────

  def handle_event("request_delete", %{"kind" => kind, "path" => path, "name" => name}, socket) do
    {:noreply, assign(socket, confirm_delete: %{kind: kind, path: path, name: name})}
  end

  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, confirm_delete: nil)}
  end

  def handle_event("delete", _, socket) do
    %{path: path} = socket.assigns.confirm_delete

    case Storage.delete_file(path) do
      :ok ->
        {:noreply, socket |> assign(confirm_delete: nil) |> load()}

      {:error, _} ->
        {:noreply,
         socket |> assign(confirm_delete: nil) |> put_flash(:error, "Could not delete #{path}")}
    end
  end

  # ── Viewer ───────────────────────────────────────────────────────────────

  def handle_event("view", %{"path" => path, "name" => name}, socket) do
    {:noreply,
     assign(socket, viewer: %{path: path, name: name, type: classify(name), url: file_href(path)})}
  end

  def handle_event("close_viewer", _, socket) do
    {:noreply, assign(socket, viewer: nil)}
  end

  defp handle_progress(:files, entry, socket) do
    if entry.done? do
      # `consume_uploaded_entry/3` returns whatever the callback's `{:ok, _}` /
      # `{:error, _}` tuple unwraps to — NOT the socket — so capture that
      # separately and keep using the original `socket` afterward.
      result =
        consume_uploaded_entry(socket, entry, fn %{path: tmp} ->
          case Storage.save_upload(tmp, entry.client_name, socket.assigns.path) do
            {:ok, api_path} -> {:ok, {:ok, api_path}}
            {:error, reason} -> {:ok, {:error, reason}}
          end
        end)

      socket =
        case result do
          {:ok, _api_path} ->
            load(socket)

          {:error, reason} ->
            put_flash(socket, :error, "Could not save #{entry.client_name}: #{inspect(reason)}")
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp filtered(entries, ""), do: entries

  defp filtered(entries, query) do
    q = String.downcase(query)
    Enum.filter(entries, &String.contains?(String.downcase(&1.name), q))
  end

  defp file_href(path), do: "/api/storage/files/" <> (path |> String.split("/") |> Enum.map_join("/", &URI.encode/1))

  defp folder_href([]), do: "/storage"
  defp folder_href(segments), do: "/storage/#{Enum.join(segments, "/")}"

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_size(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"

  defp format_size(bytes), do: "#{Float.round(bytes / 1024 / 1024 / 1024, 2)} GB"

  defp format_mtime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp classify(name) do
    case name |> Path.extname() |> String.downcase() do
      ext when ext in ~w(.png .jpg .jpeg .gif .webp .svg .bmp .avif) -> :image
      ext when ext in ~w(.mp4 .webm .mov .mkv .avi .m4v) -> :video
      ".pdf" -> :pdf
      _ -> :other
    end
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
        <%!-- Breadcrumb --%>
        <div class="flex items-center gap-1 font-mono text-[11.5px] mb-4 flex-wrap">
          <.link navigate={folder_href([])} class="text-[#86948F] hover:text-[#E6ECE9]">root</.link>
          <span :for={{seg, idx} <- Enum.with_index(@path)} class="flex items-center gap-1">
            <span class="text-[#86948F]">/</span>
            <.link
              :if={idx < length(@path) - 1}
              navigate={folder_href(Enum.take(@path, idx + 1))}
              class="text-[#86948F] hover:text-[#E6ECE9]"
            >{seg}</.link>
            <span :if={idx == length(@path) - 1} class="text-[#E6ECE9]">{seg}</span>
          </span>
        </div>

        <%!-- Actions --%>
        <div class="flex items-center gap-2 mb-4">
          <button
            :if={@path != []}
            phx-click="toggle_new_folder"
            class={"px-3 py-[7px] rounded-[4px] border font-mono text-[11.5px] transition-colors " <>
              if(@show_new_folder, do: "border-[#7FB069] text-[#E6ECE9]", else: "border-[#242D31] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934]")}
          >+ folder</button>
          <button
            :if={@path != []}
            phx-click="toggle_upload"
            class={"px-3 py-[7px] rounded-[4px] border font-mono text-[11.5px] transition-colors " <>
              if(@show_upload, do: "border-[#7FB069] text-[#E6ECE9]", else: "border-[#242D31] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934]")}
          >↑ upload</button>
          <input
            type="text"
            value={@query}
            phx-change="filter"
            phx-keyup="filter"
            name="query"
            placeholder="filter…"
            class="flex-1 box-border px-3 py-[7px] rounded-[4px] bg-[#151B1E] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none font-mono"
          />
        </div>

        <%!-- New folder panel --%>
        <form :if={@show_new_folder} phx-submit="create_folder" class="flex gap-2 mb-4">
          <input
            type="text"
            name="name"
            value={@new_folder_name}
            placeholder="folder name"
            autofocus
            class="flex-1 box-border px-3 py-[9px] rounded-[4px] bg-[#151B1E] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none font-mono"
          />
          <button
            type="submit"
            class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934]"
          >create</button>
          <button
            type="button"
            phx-click="toggle_new_folder"
            class="px-3 py-[7px] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9]"
          >cancel</button>
        </form>

        <%!-- Upload panel --%>
        <div :if={@show_upload} class="mb-4">
          <div
            class="rounded-[4px] border border-dashed border-[#242D31] hover:border-[#3C5934] bg-[#151B1E] px-4 py-5 transition-colors"
            phx-drop-target={@uploads.files.ref}
          >
            <form phx-change="noop" phx-submit="noop" class="flex items-center gap-3">
              <label class="cursor-pointer px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934]">
                Browse files
                <.live_file_input upload={@uploads.files} class="hidden" />
              </label>
              <span class="font-mono text-[11.5px] text-[#86948F]">
                or drop files here — saved into {if @path == [], do: "root", else: Enum.join(@path, "/")}
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
        </div>

        <%!-- Directory listing --%>
        <div class="rounded-[4px] border border-[#242D31] divide-y divide-[#242D31] overflow-hidden">
          <%!-- Subfolders --%>
          <div
            :for={dir <- filtered(@dirs, @query)}
            class="flex items-center gap-3 px-3 py-2.5 bg-[#151B1E] font-mono text-[12px] group"
          >
            <.link navigate={folder_href(@path ++ [dir.name])} class="flex items-center gap-3 flex-1 min-w-0">
              <span class="text-[#86948F] shrink-0">📁</span>
              <span class="text-[#E6ECE9] truncate">{dir.name}</span>
              <span class="text-[#86948F] shrink-0">{dir.count} {if dir.count == 1, do: "item", else: "items"}</span>
            </.link>
            <button
              :if={@path != []}
              phx-click="request_delete"
              phx-value-kind="dir"
              phx-value-path={dir.path}
              phx-value-name={dir.name}
              class="shrink-0 text-[#86948F] hover:text-[#E05C5C] opacity-0 group-hover:opacity-100 transition-opacity"
              title="Delete folder"
            >✕</button>
          </div>

          <%!-- Files --%>
          <div
            :for={file <- filtered(@files, @query)}
            class="flex items-center gap-3 px-3 py-2.5 bg-[#151B1E] font-mono text-[12px]"
          >
            <button
              :if={classify(file.name) != :other}
              phx-click="view"
              phx-value-path={file.path}
              phx-value-name={file.name}
              class="flex-1 min-w-0 text-left truncate text-[#E6ECE9] hover:text-[#7FB069]"
              title={file.name}
            >{file.name}</button>
            <span :if={classify(file.name) == :other} class="flex-1 min-w-0 truncate text-[#E6ECE9]" title={file.name}>
              {file.name}
            </span>
            <span class="text-[#86948F] w-16 text-right shrink-0">{format_size(file.size)}</span>
            <span class="text-[#86948F] w-32 text-right shrink-0">{format_mtime(file.mtime)}</span>
            <a href={"#{file_href(file.path)}?dl=1"} download class="shrink-0 text-[#86948F] hover:text-[#7FB069]">⬇</a>
            <button
              phx-click="request_delete"
              phx-value-kind="file"
              phx-value-path={file.path}
              phx-value-name={file.name}
              class="shrink-0 text-[#86948F] hover:text-[#E05C5C]"
            >✕</button>
          </div>

          <p
            :if={filtered(@dirs, @query) == [] and filtered(@files, @query) == []}
            class="px-3 py-6 text-center font-mono text-[12px] text-[#86948F]"
          >
            {cond do
              @dirs == [] and @files == [] and @path == [] -> "No modules have opted into storage."
              @dirs == [] and @files == [] -> "Empty."
              true -> "Nothing matches your filter."
            end}
          </p>
        </div>
      </main>
    </div>

    <%!-- Delete confirmation modal --%>
    <div
      :if={@confirm_delete}
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="cancel_delete"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/60" phx-click="cancel_delete"></div>
      <div class="relative rounded-[4px] bg-[#151B1E] border border-[#242D31] max-w-sm w-full p-6 space-y-4">
        <p class="font-mono text-sm text-[#E6ECE9]">
          Delete {if @confirm_delete.kind == "dir", do: "folder", else: "file"}
          <span class="text-[#7FB069]">"{@confirm_delete.name}"</span>?
          <span :if={@confirm_delete.kind == "dir"} class="text-[#86948F] text-xs block mt-1">
            All contents will be removed.
          </span>
        </p>
        <div class="flex gap-3">
          <button
            phx-click="delete"
            class="px-4 py-2 rounded-[4px] font-mono text-xs border border-[#E05C5C] text-[#E05C5C] hover:bg-[#E05C5C] hover:text-[#0D1113] transition-colors"
          >delete</button>
          <button
            phx-click="cancel_delete"
            class="px-4 py-2 rounded-[4px] font-mono text-xs border border-[#242D31] text-[#86948F] hover:text-[#E6ECE9] transition-colors"
          >cancel</button>
        </div>
      </div>
    </div>

    <%!-- Viewer modal --%>
    <div
      :if={@viewer}
      class="fixed inset-0 z-50 flex flex-col"
      phx-window-keydown="close_viewer"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/90" phx-click="close_viewer"></div>
      <div class="relative flex items-center justify-between px-4 py-3 font-mono text-[11.5px] text-[#86948F] shrink-0">
        <span class="truncate">{@viewer.name}</span>
        <div class="flex items-center gap-4 shrink-0">
          <a href={"#{@viewer.url}?dl=1"} download class="hover:text-[#7FB069]">download</a>
          <button phx-click="close_viewer" class="hover:text-[#E6ECE9]">✕ close</button>
        </div>
      </div>
      <div class="relative flex-1 flex items-center justify-center overflow-hidden p-4">
        <img :if={@viewer.type == :image} src={@viewer.url} class="max-w-full max-h-full object-contain" />
        <video :if={@viewer.type == :video} controls autoplay class="max-w-full max-h-full" src={@viewer.url}>
          Your browser does not support video playback.
        </video>
        <iframe :if={@viewer.type == :pdf} src={@viewer.url} class="w-full h-full border-0 bg-white"></iframe>
      </div>
    </div>
    """
  end
end
