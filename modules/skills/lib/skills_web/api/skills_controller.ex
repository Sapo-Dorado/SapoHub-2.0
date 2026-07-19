defmodule SkillsWeb.Api.SkillsController do
  @moduledoc false
  use SapoKit.Web, :controller

  alias Skills.Skill

  def index(conn, _params) do
    json(conn, Enum.map(Skills.list_skills(), &serialize/1))
  end

  def show(conn, %{"id" => id}) do
    skill = Skills.get_skill!(id)

    detail =
      case Skills.skill_detail(skill) do
        {:ok, content} -> content
        {:error, reason} -> "(could not load detail: #{inspect(reason)})"
      end

    json(conn, Map.put(serialize(skill), :detail, detail))
  rescue
    Ecto.NoResultsError -> render_not_found(conn)
  end

  def create_marketplace(conn, params) do
    marketplace = params["marketplace"] || "claude-plugins-official"

    case Skills.add_marketplace_skill(params["name"], marketplace) do
      {:ok, skill} -> conn |> put_status(:created) |> json(serialize(skill))
      {:error, %Ecto.Changeset{} = changeset} -> render_changeset_errors(conn, changeset)
      {:error, output} -> conn |> put_status(:unprocessable_entity) |> json(%{error: output})
    end
  end

  def create_custom(conn, params) do
    case Skills.register_custom_skill(params["name"]) do
      {:ok, skill} ->
        conn |> put_status(:created) |> json(serialize(skill))

      {:error, :not_found} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "no custom/#{params["name"]}/SKILL.md found in storage — author it first"})

      {:error, %Ecto.Changeset{} = changeset} ->
        render_changeset_errors(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    id |> Skills.get_skill!() |> Skills.delete_skill()
    json(conn, %{ok: true})
  rescue
    Ecto.NoResultsError -> render_not_found(conn)
  end

  defp serialize(%Skill{} = s) do
    %{
      id: s.id,
      name: s.name,
      kind: s.kind,
      marketplace: s.marketplace,
      inserted_at: s.inserted_at
    }
  end
end
