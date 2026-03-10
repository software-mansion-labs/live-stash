defmodule LiveStash.Settings do
  @moduledoc false

  @enforce_keys [
    :mode,
    :reconnected?,
    :secret,
    :security_mode,
    :ttl
  ]

  defstruct [
    :mode,
    :reconnected?,
    :secret,
    :security_mode,
    :ttl
  ]

  @type t :: %__MODULE__{
          mode: :client | :server,
          reconnected?: boolean(),
          secret: binary(),
          security_mode: :sign | :encrypt,
          ttl: integer()
        }

  @default_opts [
    mode: :server,
    ttl: 5 * 60 * 1000,
    security_mode: :sign
  ]

  def new(user_opts, reconnected?, evaluated_secret) do
    opts = Keyword.merge(@default_opts, user_opts)

    %__MODULE__{
      mode: Keyword.fetch!(opts, :mode),
      security_mode: Keyword.fetch!(opts, :security_mode),
      ttl: Keyword.fetch!(opts, :ttl),
      reconnected?: reconnected?,
      secret: evaluated_secret
    }
  end
end
