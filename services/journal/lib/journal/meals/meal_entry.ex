defmodule Journal.Meals.MealEntry do
  @moduledoc """
  Schema for meal entries in the patient's journal.

  Each meal entry represents a single meal logged by a patient, with optional
  AI-estimated nutritional information.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @meal_types [:breakfast, :lunch, :snack, :dinner]
  @statuses [:pending, :processing, :in_review, :confirmed]

  schema "meal_entries" do
    field :patient_id, :integer
    field :date, :date
    field :meal_type, Ecto.Enum, values: @meal_types
    field :original_description, :string
    field :protein_g, :decimal
    field :carbs_g, :decimal
    field :fat_g, :decimal
    field :calories_kcal, :integer
    field :weight_g, :integer
    field :ai_comment, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :has_manual_override, :boolean, default: false
    field :overridden_fields, :map, default: %{}
    field :source_recipe_id, :integer

    timestamps(type: :utc_datetime)
  end

  @required_fields [:patient_id, :date, :meal_type, :original_description]
  @optional_fields [
    :protein_g,
    :carbs_g,
    :fat_g,
    :calories_kcal,
    :weight_g,
    :ai_comment,
    :status,
    :has_manual_override,
    :overridden_fields,
    :source_recipe_id
  ]

  @doc """
  Creates a changeset for inserting a new meal entry.
  """
  def changeset(meal_entry, attrs) do
    meal_entry
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @doc """
  Creates a changeset for starting LLM processing.
  Transitions: pending → processing
  """
  def processing_changeset(meal_entry) do
    meal_entry
    |> change(status: :processing)
  end

  @doc """
  Creates a changeset for completing LLM estimation.
  Transitions: processing → in_review
  """
  def review_changeset(meal_entry, estimation_attrs) do
    meal_entry
    |> cast(estimation_attrs, [:protein_g, :carbs_g, :fat_g, :calories_kcal, :weight_g, :ai_comment])
    |> put_change(:status, :in_review)
  end

  @doc """
  Creates a changeset for confirming a meal entry.
  Transitions: in_review → confirmed
  """
  def confirm_changeset(meal_entry) do
    meal_entry
    |> change(status: :confirmed)
  end

  @doc """
  Creates a changeset for manual override of nutritional values.
  """
  def override_changeset(meal_entry, attrs) do
    overridden_fields = detect_overridden_fields(meal_entry, attrs)

    meal_entry
    |> cast(attrs, [:protein_g, :carbs_g, :fat_g, :calories_kcal, :weight_g])
    |> put_change(:has_manual_override, map_size(overridden_fields) > 0)
    |> put_change(:overridden_fields, overridden_fields)
  end

  defp detect_overridden_fields(meal_entry, attrs) do
    [:protein_g, :carbs_g, :fat_g, :calories_kcal, :weight_g]
    |> Enum.reduce(%{}, fn field, acc ->
      old_value = Map.get(meal_entry, field)
      new_value = Map.get(attrs, to_string(field)) || Map.get(attrs, field)

      if new_value && new_value != old_value do
        Map.put(acc, to_string(field), %{
          "original" => old_value,
          "override" => new_value
        })
      else
        acc
      end
    end)
  end

  # Public accessors for enum values
  def meal_types, do: @meal_types
  def statuses, do: @statuses
end
