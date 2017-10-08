defmodule ExBanking.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias ExBanking.Transaction

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Registry.ExBanking},
      {Transaction.Supervisor, []}
    ]
    opts = [strategy: :one_for_one, name: ExBanking.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
