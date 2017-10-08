defmodule ExBanking.Transaction.Supervisor do
  use Supervisor

  alias ExBanking.Transaction

  def start_link(_) do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def start_child(user, data) do
    child_spec = 
      Supervisor.child_spec({Transaction, [user, data]}, [restart: :temporary])
      
    Supervisor.start_child(__MODULE__, child_spec)
  end

  def terminate_child(pid) do
    Supervisor.terminate_child(__MODULE__, pid)
  end

  def init(_) do
    Supervisor.init([], strategy: :one_for_one)
  end

end