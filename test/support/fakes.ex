defmodule LiveStash.Fakes do
  @moduledoc false

  alias Phoenix.LiveView.Socket

  defmodule MockEndpoint do
    @moduledoc false

    def config(:secret_key_base) do
      String.duplicate("abcdefghijklmnopqrstuvwxyz012345", 2)
    end
  end

  def socket(opts \\ []) do
    assigns = Keyword.get(opts, :assigns, %{})
    private = Keyword.get(opts, :private, %{})

    %Socket{
      endpoint: MockEndpoint,
      transport_pid: self(),
      assigns: assigns,
      private: private
    }
  end
end
