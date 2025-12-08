defmodule Journal.Meals.MealEntryTest do
  use ExUnit.Case, async: true
  use Journal.DataCase

  alias Journal.Meals.MealEntry

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      attrs = %{
        patient_id: 1,
        date: ~D[2024-01-15],
        meal_type: :breakfast,
        original_description: "Oatmeal with berries"
      }

      changeset = MealEntry.changeset(%MealEntry{}, attrs)

      assert changeset.valid?
      assert changeset.changes.patient_id == 1
      assert changeset.changes.date == ~D[2024-01-15]
      assert changeset.changes.meal_type == :breakfast
      assert changeset.changes.original_description == "Oatmeal with berries"
    end

    test "valid changeset with optional fields" do
      attrs = %{
        patient_id: 1,
        date: ~D[2024-01-15],
        meal_type: :lunch,
        original_description: "Grilled chicken salad",
        protein_g: Decimal.new("30.5"),
        carbs_g: Decimal.new("15.2"),
        fat_g: Decimal.new("10.0"),
        calories_kcal: 250,
        weight_g: 300
      }

      changeset = MealEntry.changeset(%MealEntry{}, attrs)

      assert changeset.valid?
    end

    test "invalid when required fields are missing" do
      attrs = %{}

      changeset = MealEntry.changeset(%MealEntry{}, attrs)

      refute changeset.valid?
      assert %{patient_id: ["can't be blank"], date: ["can't be blank"],
               meal_type: ["can't be blank"], original_description: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when original_description is empty" do
      attrs = %{
        patient_id: 1,
        date: ~D[2024-01-15],
        meal_type: :breakfast,
        original_description: ""
      }

      changeset = MealEntry.changeset(%MealEntry{}, attrs)

      refute changeset.valid?
      assert %{original_description: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid when original_description exceeds 1024 characters" do
      long_description = String.duplicate("a", 1025)

      attrs = %{
        patient_id: 1,
        date: ~D[2024-01-15],
        meal_type: :breakfast,
        original_description: long_description
      }

      changeset = MealEntry.changeset(%MealEntry{}, attrs)

      refute changeset.valid?
      assert %{original_description: ["should be at most 1024 character(s)"]} = errors_on(changeset)
    end

    test "valid when original_description is exactly 1024 characters" do
      description = String.duplicate("a", 1024)

      attrs = %{
        patient_id: 1,
        date: ~D[2024-01-15],
        meal_type: :breakfast,
        original_description: description
      }

      changeset = MealEntry.changeset(%MealEntry{}, attrs)

      assert changeset.valid?
    end

    test "invalid when patient_id is zero" do
      attrs = %{
        patient_id: 0,
        date: ~D[2024-01-15],
        meal_type: :breakfast,
        original_description: "Test meal"
      }

      changeset = MealEntry.changeset(%MealEntry{}, attrs)

      refute changeset.valid?
      assert %{patient_id: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "invalid when patient_id is negative" do
      attrs = %{
        patient_id: -1,
        date: ~D[2024-01-15],
        meal_type: :breakfast,
        original_description: "Test meal"
      }

      changeset = MealEntry.changeset(%MealEntry{}, attrs)

      refute changeset.valid?
      assert %{patient_id: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "valid when patient_id is positive" do
      attrs = %{
        patient_id: 1,
        date: ~D[2024-01-15],
        meal_type: :breakfast,
        original_description: "Test meal"
      }

      changeset = MealEntry.changeset(%MealEntry{}, attrs)

      assert changeset.valid?
    end
  end

  describe "processing_changeset/1" do
    test "valid transition from pending to processing" do
      meal_entry = %MealEntry{status: :pending}

      changeset = MealEntry.processing_changeset(meal_entry)

      assert changeset.valid?
      assert changeset.changes.status == :processing
    end

    test "raises ArgumentError when status is not pending" do
      meal_entry = %MealEntry{status: :processing}

      assert_raise ArgumentError, ~r/Cannot transition from processing/, fn ->
        MealEntry.processing_changeset(meal_entry)
      end
    end

    test "raises ArgumentError when status is in_review" do
      meal_entry = %MealEntry{status: :in_review}

      assert_raise ArgumentError, ~r/Cannot transition from in_review/, fn ->
        MealEntry.processing_changeset(meal_entry)
      end
    end

    test "raises ArgumentError when status is confirmed" do
      meal_entry = %MealEntry{status: :confirmed}

      assert_raise ArgumentError, ~r/Cannot transition from confirmed/, fn ->
        MealEntry.processing_changeset(meal_entry)
      end
    end
  end

  describe "review_changeset/2" do
    test "valid transition from processing to in_review with valid nutritional data" do
      meal_entry = %MealEntry{status: :processing}
      estimation_attrs = %{
        protein_g: Decimal.new("25.5"),
        carbs_g: Decimal.new("30.0"),
        fat_g: Decimal.new("10.5"),
        calories_kcal: 300,
        weight_g: 250,
        ai_comment: "Estimated based on description"
      }

      changeset = MealEntry.review_changeset(meal_entry, estimation_attrs)

      assert changeset.valid?
      assert changeset.changes.status == :in_review
    end

    test "invalid when nutritional values are negative" do
      meal_entry = %MealEntry{status: :processing}
      estimation_attrs = %{
        protein_g: Decimal.new("-10.0"),
        carbs_g: Decimal.new("30.0"),
        fat_g: Decimal.new("10.5"),
        calories_kcal: 300,
        weight_g: 250
      }

      changeset = MealEntry.review_changeset(meal_entry, estimation_attrs)

      refute changeset.valid?
      assert %{protein_g: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "invalid when nutritional values exceed maximum" do
      meal_entry = %MealEntry{status: :processing}
      estimation_attrs = %{
        protein_g: Decimal.new("1001.0"),  # exceeds max of 1000
        carbs_g: Decimal.new("30.0"),
        fat_g: Decimal.new("10.5"),
        calories_kcal: 300,
        weight_g: 250
      }

      changeset = MealEntry.review_changeset(meal_entry, estimation_attrs)

      refute changeset.valid?
      assert %{protein_g: ["must be less than or equal to 1000"]} = errors_on(changeset)
    end

    test "raises ArgumentError when status is not processing" do
      meal_entry = %MealEntry{status: :pending}
      estimation_attrs = %{protein_g: Decimal.new("25.5")}

      assert_raise ArgumentError, ~r/Cannot transition from pending/, fn ->
        MealEntry.review_changeset(meal_entry, estimation_attrs)
      end
    end
  end

  describe "confirm_changeset/1" do
    test "valid transition from in_review to confirmed" do
      meal_entry = %MealEntry{status: :in_review}

      changeset = MealEntry.confirm_changeset(meal_entry)

      assert changeset.valid?
      assert changeset.changes.status == :confirmed
    end

    test "raises ArgumentError when status is not in_review" do
      meal_entry = %MealEntry{status: :pending}

      assert_raise ArgumentError, ~r/Cannot transition from pending/, fn ->
        MealEntry.confirm_changeset(meal_entry)
      end
    end
  end

  describe "override_changeset/2" do
    test "detects overridden fields correctly" do
      meal_entry = %MealEntry{
        protein_g: Decimal.new("20.0"),
        carbs_g: Decimal.new("30.0"),
        fat_g: Decimal.new("10.0"),
        calories_kcal: 250,
        weight_g: 200
      }

      attrs = %{
        "protein_g" => Decimal.new("25.0"),
        "carbs_g" => Decimal.new("30.0"),  # unchanged
        "fat_g" => Decimal.new("12.0")
      }

      changeset = MealEntry.override_changeset(meal_entry, attrs)

      assert changeset.valid?
      assert get_change(changeset, :has_manual_override, false) == true

      overridden = get_change(changeset, :overridden_fields, %{})
      assert Map.has_key?(overridden, "protein_g")
      assert Map.has_key?(overridden, "fat_g")
      refute Map.has_key?(overridden, "carbs_g")  # not changed
    end

    test "handles zero values correctly" do
      meal_entry = %MealEntry{
        protein_g: Decimal.new("20.0"),
        carbs_g: Decimal.new("30.0")
      }

      attrs = %{
        "protein_g" => Decimal.new("0.0"),  # zero is a valid override
        "carbs_g" => Decimal.new("30.0")
      }

      changeset = MealEntry.override_changeset(meal_entry, attrs)

      assert changeset.valid?
      assert get_change(changeset, :has_manual_override, false) == true

      overridden = get_change(changeset, :overridden_fields, %{})
      assert Map.has_key?(overridden, "protein_g")
      assert overridden["protein_g"]["override"] == Decimal.new("0.0")
    end

    test "handles both atom and string keys in attrs" do
      meal_entry = %MealEntry{protein_g: Decimal.new("20.0")}

      # Test with atom keys
      attrs_atom = %{protein_g: Decimal.new("25.0")}
      changeset_atom = MealEntry.override_changeset(meal_entry, attrs_atom)

      # Test with string keys
      attrs_string = %{"protein_g" => Decimal.new("25.0")}
      changeset_string = MealEntry.override_changeset(meal_entry, attrs_string)

      assert changeset_atom.valid?
      assert changeset_string.valid?
      assert get_change(changeset_atom, :overridden_fields, %{}) == get_change(changeset_string, :overridden_fields, %{})
    end

    test "sets has_manual_override to false when no fields are overridden" do
      meal_entry = %MealEntry{
        protein_g: Decimal.new("20.0"),
        carbs_g: Decimal.new("30.0")
      }

      attrs = %{
        "protein_g" => Decimal.new("20.0"),  # same value
        "carbs_g" => Decimal.new("30.0")     # same value
      }

      changeset = MealEntry.override_changeset(meal_entry, attrs)

      assert changeset.valid?
      # When no fields are overridden, has_manual_override may not appear in changes
      # if the current value is already false, so we check the final value
      has_override = get_change(changeset, :has_manual_override) || Map.get(meal_entry, :has_manual_override)
      assert has_override == false

      overridden = get_change(changeset, :overridden_fields, %{})
      assert overridden == %{}
    end

    test "invalid when override values are negative" do
      meal_entry = %MealEntry{protein_g: Decimal.new("20.0")}
      attrs = %{"protein_g" => Decimal.new("-5.0")}

      changeset = MealEntry.override_changeset(meal_entry, attrs)

      refute changeset.valid?
      assert %{protein_g: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "invalid when override values exceed maximum" do
      meal_entry = %MealEntry{calories_kcal: 500}
      attrs = %{"calories_kcal" => 10001}  # exceeds max of 10000

      changeset = MealEntry.override_changeset(meal_entry, attrs)

      refute changeset.valid?
      assert %{calories_kcal: ["must be less than or equal to 10000"]} = errors_on(changeset)
    end

    test "preserves original values in overridden_fields map" do
      meal_entry = %MealEntry{
        protein_g: Decimal.new("20.0"),
        carbs_g: Decimal.new("30.0")
      }

      attrs = %{
        "protein_g" => Decimal.new("25.0"),
        "carbs_g" => Decimal.new("35.0")
      }

      changeset = MealEntry.override_changeset(meal_entry, attrs)

      overridden = get_change(changeset, :overridden_fields, %{})
      assert overridden["protein_g"]["original"] == Decimal.new("20.0")
      assert overridden["protein_g"]["override"] == Decimal.new("25.0")
      assert overridden["carbs_g"]["original"] == Decimal.new("30.0")
      assert overridden["carbs_g"]["override"] == Decimal.new("35.0")
    end

    test "handles string values in attrs for decimal fields" do
      meal_entry = %MealEntry{protein_g: Decimal.new("20.0")}
      attrs = %{"protein_g" => "25.5"}

      changeset = MealEntry.override_changeset(meal_entry, attrs)

      assert changeset.valid?
      overridden = get_change(changeset, :overridden_fields, %{})
      assert Map.has_key?(overridden, "protein_g")
    end

    test "handles string values in attrs for integer fields" do
      meal_entry = %MealEntry{calories_kcal: 250}
      attrs = %{"calories_kcal" => "300"}

      changeset = MealEntry.override_changeset(meal_entry, attrs)

      assert changeset.valid?
      overridden = get_change(changeset, :overridden_fields, %{})
      assert Map.has_key?(overridden, "calories_kcal")
    end

    test "handles nil values in meal_entry" do
      meal_entry = %MealEntry{protein_g: nil}
      attrs = %{"protein_g" => Decimal.new("25.0")}

      changeset = MealEntry.override_changeset(meal_entry, attrs)

      assert changeset.valid?
      overridden = get_change(changeset, :overridden_fields, %{})
      assert Map.has_key?(overridden, "protein_g")
      assert overridden["protein_g"]["original"] == nil
    end

    test "handles missing keys in attrs" do
      meal_entry = %MealEntry{
        protein_g: Decimal.new("20.0"),
        carbs_g: Decimal.new("30.0")
      }
      attrs = %{}

      changeset = MealEntry.override_changeset(meal_entry, attrs)

      assert changeset.valid?
      overridden = get_change(changeset, :overridden_fields, %{})
      assert overridden == %{}
    end
  end

  describe "meal_types/0" do
    test "returns list of valid meal types" do
      assert MealEntry.meal_types() == [:breakfast, :lunch, :snack, :dinner]
    end
  end

  describe "statuses/0" do
    test "returns list of valid statuses" do
      assert MealEntry.statuses() == [:pending, :processing, :in_review, :confirmed]
    end
  end
end
