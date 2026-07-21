defmodule MyPlate.Module do
  @moduledoc false
  use SapoKit.Module

  @impl true
  def id, do: :my_plate

  @impl true
  def title, do: "My Plate"

  @impl true
  def dashboard_tile(config) do
    %SapoKit.Tile{
      label: "My Plate",
      icon: "hero-clipboard-document-list",
      path: "/my-plate",
      style: config[:tile_style] || :standard,
      badge: fn -> to_string(MyPlate.count_active_tasks()) end
    }
  end

  @impl true
  def icon, do: "hero-clipboard-document-list"

  @impl true
  def dashboard_buttons(_config) do
    [
      %SapoKit.DashboardButton{
        id: "preview",
        label: "task preview — urgent tasks",
        component: MyPlateWeb.TaskPreview,
        size: :wide
      }
    ]
  end

  @impl true
  def statusline_items(_config) do
    [
      %SapoKit.StatuslineItem{
        id: "my_plate.due",
        label: "Tasks due",
        text: fn ->
          case MyPlate.count_due_today() do
            0 -> "0 due"
            n -> "#{n} due"
          end
        end,
        level: fn -> if MyPlate.count_due_today() > 0, do: :warn, else: :ok end,
        topics: ["my_plate:tasks"]
      }
    ]
  end

  @impl true
  def ui_routes do
    [
      %{path: "/my-plate", live_view: MyPlateWeb.Live.Index, action: :index},
      %{path: "/my-plate/:board_id", live_view: MyPlateWeb.Live.Index, action: :index}
    ]
  end

  @impl true
  def api_routes do
    [
      %{verb: :get, path: "/tasks", controller: MyPlateWeb.Api.TasksController, action: :index},
      %{verb: :post, path: "/tasks", controller: MyPlateWeb.Api.TasksController, action: :create},
      %{verb: :get, path: "/tasks/:id", controller: MyPlateWeb.Api.TasksController, action: :show},
      %{verb: :patch, path: "/tasks/:id", controller: MyPlateWeb.Api.TasksController, action: :update},
      %{verb: :delete, path: "/tasks/:id", controller: MyPlateWeb.Api.TasksController, action: :delete},
      %{verb: :post, path: "/tasks/:id/complete", controller: MyPlateWeb.Api.TasksController, action: :complete},
      %{verb: :post, path: "/tasks/:id/uncomplete", controller: MyPlateWeb.Api.TasksController, action: :uncomplete},
      %{verb: :post, path: "/tasks/:id/reorder", controller: MyPlateWeb.Api.TasksController, action: :reorder},
      %{verb: :get, path: "/recurring-tasks", controller: MyPlateWeb.Api.RecurringController, action: :index},
      %{verb: :post, path: "/recurring-tasks", controller: MyPlateWeb.Api.RecurringController, action: :create},
      %{verb: :patch, path: "/recurring-tasks/:id", controller: MyPlateWeb.Api.RecurringController, action: :update},
      %{verb: :delete, path: "/recurring-tasks/:id", controller: MyPlateWeb.Api.RecurringController, action: :delete}
    ]
  end

  @impl true
  def scheduler_hooks, do: [MyPlate.RecurringHook]

  @impl true
  def ai_context do
    """
    My Plate is the task manager. Active tasks: #{MyPlate.count_active_tasks()} \
    (#{MyPlate.count_due_today()} due today or overdue).
    Task priorities: high, medium, low. Recurrences: daily, weekly, monthly.
    Use `sapo tasks ...` / `sapo recurring ...` or the /api/tasks and
    /api/recurring-tasks endpoints.
    """
  end

  @impl true
  def assistant_system_prompt do
    """
    Task management lives in My Plate (`sapo tasks`, `sapo recurring`).
    When the user mentions something they need to do, offer to add it.
    """
  end

  @impl true
  def config_schema do
    [
      tile_style: [type: {:in, [:standard, :wide, :accent]}, default: :standard],
      default_remind_time: [type: :string, default: "09:00"]
    ]
  end
end
