defmodule Journal.Meals.MealEntry do
  @moduledoc """
  Schema for meal entries in the patient's journal.

  Each meal entry represents a single meal logged by a patient, with optional
  AI-estimated nutritional information.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Journal.Helpers.NumberHelper

  @meal_types [:breakfast, :lunch, :snack, :dinner]
  @statuses [:pending, :processing, :in_review, :confirmed]
  @nutritional_fields [:protein_g, :carbs_g, :fat_g, :calories_kcal, :weight_g]

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
    |> validate_length(:original_description, min: 1, max: 1024)
    |> validate_number(:patient_id, greater_than: 0)
  end

  @doc """
  Creates a changeset for starting LLM processing.
  Transitions: pending → processing

  Raises `ArgumentError` if the meal entry is not in `:pending` status.
  """
  def processing_changeset(%{status: :pending} = meal_entry) do
    meal_entry
    |> change(status: :processing)
  end

  def processing_changeset(%{status: status}) do
    raise ArgumentError, "Cannot transition from #{status} to :processing. Expected status: :pending"
  end

  @doc """
  Creates a changeset for completing LLM estimation.
  Transitions: processing → in_review

  Raises `ArgumentError` if the meal entry is not in `:processing` status.
  """
  def review_changeset(%{status: :processing} = meal_entry, estimation_attrs) do
    meal_entry
    |> cast(estimation_attrs, @nutritional_fields ++ [:ai_comment])
    |> validate_nutritional_values()
    |> put_change(:status, :in_review)
  end

  def review_changeset(%{status: status}, _estimation_attrs) do
    raise ArgumentError, "Cannot transition from #{status} to :in_review. Expected status: :processing"
  end

  @doc """
  Creates a changeset for confirming a meal entry.
  Transitions: in_review → confirmed

  Raises `ArgumentError` if the meal entry is not in `:in_review` status.
  """
  def confirm_changeset(%{status: :in_review} = meal_entry) do
    meal_entry
    |> change(status: :confirmed)
  end

  def confirm_changeset(%{status: status}) do
    raise ArgumentError, "Cannot transition from #{status} to :confirmed. Expected status: :in_review"
  end

  @doc """
  Creates a changeset for manual override of nutritional values.

  Tracks which fields were overridden in the `overridden_fields` map
  for audit and transparency purposes.

  ## Parameters
    - `meal_entry` - The meal entry struct to override
    - `attrs` - Map with nutritional values to override (keys can be atoms or strings)

  ## Returns
    - `%Ecto.Changeset{}` - Changeset with overridden values and tracking information

  ## Examples

      iex> meal = %MealEntry{protein_g: Decimal.new("20.0")}
      iex> attrs = %{"protein_g" => Decimal.new("25.0")}
      iex> changeset = MealEntry.override_changeset(meal, attrs)
      iex> get_change(changeset, :overridden_fields)
      %{"protein_g" => %{"original" => Decimal.new("20.0"), "override" => Decimal.new("25.0")}}
  """
  def override_changeset(meal_entry, attrs) do
    overridden_fields = detect_overridden_fields(meal_entry, attrs)
    has_override = map_size(overridden_fields) > 0

    meal_entry
    |> cast(attrs, @nutritional_fields)
    |> validate_nutritional_values()
    |> force_change(:has_manual_override, has_override)
    |> force_change(:overridden_fields, overridden_fields)
  end

  @doc false
  # Detects which nutritional fields have been manually overridden.
  # Returns a map with field names as keys and maps containing original/override values.
  defp detect_overridden_fields(meal_entry, attrs) do
    @nutritional_fields
    |> Enum.reduce(%{}, fn field, acc ->
      old_value = Map.get(meal_entry, field)
      new_value_raw = get_attr_value(attrs, field)

      if NumberHelper.present?(new_value_raw) do
        new_value = normalize_value(new_value_raw, field)
        old_value_normalized = normalize_value(old_value, field)

        if NumberHelper.values_different?(new_value, old_value_normalized) do
          Map.put(acc, to_string(field), %{
            "original" => old_value,
            "override" => new_value
          })
        else
          acc
        end
      else
        acc
      end
    end)
  end

  @doc false
  # Gets attribute value handling both atom and string keys.
  defp get_attr_value(attrs, field) when is_atom(field) do
    Map.get(attrs, field) || Map.get(attrs, to_string(field))
  end

  @doc false
  # Normalizes a value to the appropriate type for comparison.
  # Decimal fields are normalized to Decimal, integer fields to integer.
  # Validates input before normalization.
  defp normalize_value(nil, _field), do: nil
  defp normalize_value(value, field) when field in [:protein_g, :carbs_g, :fat_g] do
    NumberHelper.normalize_to_decimal(value)
  end
  defp normalize_value(value, field) when field in [:calories_kcal, :weight_g] do
    NumberHelper.normalize_to_integer(value)
  end
  defp normalize_value(value, _field), do: value

  @doc false
  # Validates that nutritional values are non-negative and within reasonable ranges.
  defp validate_nutritional_values(changeset) do
    changeset
    |> validate_number(:protein_g, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000)
    |> validate_number(:carbs_g, greater_than_or_equal_to: 0, less_than_or_equal_to: 2000)
    |> validate_number(:fat_g, greater_than_or_equal_to: 0, less_than_or_equal_to: 1000)
    |> validate_number(:calories_kcal, greater_than_or_equal_to: 0, less_than_or_equal_to: 10000)
    |> validate_number(:weight_g, greater_than_or_equal_to: 0, less_than_or_equal_to: 100000)
  end

  @doc """
  Returns the list of valid meal types.

  ## Examples

      iex> Journal.Meals.MealEntry.meal_types()
      [:breakfast, :lunch, :snack, :dinner]
  """
  def meal_types, do: @meal_types

  @doc """
  Returns the list of valid status values.

  ## Examples

      iex> Journal.Meals.MealEntry.statuses()
      [:pending, :processing, :in_review, :confirmed]
  """
  def statuses, do: @statuses
end
