defmodule Journal.Auth.Patient do
  @moduledoc """
  Schema for patient records linking users to professionals.

  This schema establishes the relationship between users (patients) and
  professionals (nutritionists). One user can have multiple patient records,
  one per professional relationship.

  ## Fields
  - `user_id`: Reference to the user (required, foreign key to users.id)
  - `professional_id`: Reference to the professional (required)
  - `inserted_at`: Timestamp when record was created
  - `updated_at`: Timestamp when record was last updated

  ## Constraints
  - Unique composite constraint on (user_id, professional_id) ensures
    one patient record per user-professional pair
  - Foreign key constraint on user_id with CASCADE delete
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "patients" do
    belongs_to :user, Journal.Auth.User
    field :professional_id, :integer

    timestamps(type: :utc_datetime)
  end

  @required_fields [:user_id, :professional_id]
  @optional_fields []

  @doc """
  Creates a changeset for a patient.

  ## Examples

      iex> changeset = Patient.changeset(%Patient{}, %{user_id: 1, professional_id: 1})
      iex> changeset.valid?
      true

      iex> changeset = Patient.changeset(%Patient{}, %{})
      iex> changeset.valid?
      false
  """
  def changeset(patient, attrs) do
    patient
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:user_id, greater_than: 0)
    |> validate_number(:professional_id, greater_than: 0)
    |> unique_constraint([:user_id, :professional_id], name: :patients_user_professional_unique_idx)
  end
end
