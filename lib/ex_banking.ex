defmodule ExBanking do

  alias ExBanking.Transaction

  def init() do
    case :ets.info(__MODULE__) do
      :undefined -> :ets.new(__MODULE__, [:ordered_set, :named_table, :public])
      _ -> :ok
    end
  end

  def z(current, n) do
    spawn(fn -> 
      data = deposit "cjen", n, "RMB"
      send current, {self(), data}
    end)
  end

  def create_user(user) do
    case user_lookup(user) do
      [] -> 
        :ets.insert(__MODULE__, {user, %{}})
        :ok
      _ -> {:error, :user_already_exists}
    end
  end

  def user_lookup(user), do: :ets.lookup(__MODULE__, user)
  def user_exists?(user), do: user_lookup(user) != []
  

  defp check_string_list(l), do: Enum.all?(l, &is_bitstring/1)
  defp check_number(n), do: is_number(n) && (n > 0)
  defp check_format({a, b}), do: check_string_list([a, b])
  defp check_format({a, b, c}), do: check_string_list([a, c]) && check_number(b)
  defp check_format({a, b, c, d}), do: check_string_list([a, b, d]) && check_number(c)

  def deposit(user, amount, currency), do: handle(:deposit, {user, amount, currency})
  def withdraw(user, amount, currency), do: handle(:withdraw, {user, amount, currency})
  def get_balance(user, currency), do: handle(:get_balance, {user, currency})
  def send(from_user, to_user, amount, currency), do: handle(:send, {from_user, to_user, amount, currency})

  def handle(f, args) do
    case check_format(args) do
      false -> {:error, :wrong_arguments}
      true ->
        user = elem(args, 0)
        if f == :send do
          cond do
            !user_exists?(elem(args, 1)) -> 
              {:error, :receiver_does_not_exist}
            true ->
              case user_lookup(user) do
                [] -> {:error, :sender_does_not_exist}
                [{_, data}] -> do_handle(user, data, {f, args})
              end
          end
        else
          case user_lookup(user) do
            [] -> {:error, :user_does_not_exist}
            [{_, data}] -> do_handle(user, data, {f, args})
          end
        end
    end 
  end

  def do_handle(user, data, request) do
    case Transaction.whereis(user) do
      [{pid, _}] ->
        pid
      _ ->
        case Transaction.Supervisor.start_child(user, data) do
          {:ok, pid} ->
            IO.puts "GenServer #{user} is started"
            pid
          {:error, {:already_started, pid}} ->
            pid
        end        
    end
    |> GenServer.call(request)
  end
end
