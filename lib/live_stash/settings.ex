defmodule LiveStash.Settings do
  @moduledoc false

  @enforce_keys [
    :reconnected?,
    :secret
  ]

  defstruct [
    :reconnected?,
    :secret,
    mode: :server,
    security_mode: :sign,
    ttl: 5 * 60 * 1000
  ]

  @type t :: %__MODULE__{
          mode: :client | :server,
          reconnected?: boolean(),
          secret: binary(),
          security_mode: :sign | :encrypt,
          ttl: integer()
        }

  def new(user_opts, reconnected?, evaluated_secret) do
    attrs =
      user_opts
      |> Keyword.put(:reconnected?, reconnected?)
      |> Keyword.put(:secret, evaluated_secret)

    struct!(__MODULE__, attrs)
  end
end
