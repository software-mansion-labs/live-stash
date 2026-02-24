defmodule ShowcaseApp.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :string
      add :email, :string
      add :password, :string
      add :area, :string
      add :techs, {:array, :string}

      timestamps(type: :utc_datetime)
    end
  end
end
