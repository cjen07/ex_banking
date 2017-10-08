defmodule ExBanking.Transaction do

  alias ExBanking.Transaction
  use GenServer

  defstruct [:user, :count, :data, :actions, :flag]

  def start_link([user, data]) do
    state = %Transaction{user: user, data: data, count: 0, actions: :queue.new(), flag: false}
    GenServer.start_link(__MODULE__, state, name: via_tuple(user))
  end

  def whereis(user) do
    Registry.lookup(Registry.ExBanking, user)
  end

  def via_tuple(user) do
    {:via, Registry, {Registry.ExBanking, user}}
  end

  def init(state) do
    {:ok, state}
  end

  def terminate(:normal, state) do
    user = state.user
    data = state.data
    :ets.insert(ExBanking, {user, data})
    :ok
  end

  def handle_call(request, from, state) do
    if state.count == 10 do
      {:reply, {:error, :too_many_requests_to_user}, state, 0}
    else
      new_actions = :queue.cons({request, from}, state.actions)
      new_count = state.count + 1;
      new_state = %{state | count: new_count, actions: new_actions, flag: false}
      {:noreply, new_state, 0}
    end
  end

  def handle_cast(:halt, state) do
    if state.count == 0 && state.flag do
      {:stop, :normal, state}
    else
      new_state = %{state | flag: false}
      {:noreply, new_state, 0}
    end
  end

  def handle_info(:timeout, state) do
    case :queue.is_empty(state.actions) do
      true ->
        current = self()
        spawn(fn ->
          Process.sleep(1000)
          GenServer.cast(current, :halt)
        end)
        new_state = %{state | flag: true}
        {:noreply, new_state, :hibernate}
      false ->
        {request, from} = :queue.last(state.actions)
        case request do
          {:deposit, {_, amount, currency}} ->
            deposit(state, from, amount, currency)
          {:withdraw, {_, amount, currency}} -> 
            withdraw(state, from, amount, currency)
          {:get_balance, {_, currency}} ->  
            get_balance(state, from, currency)
          _ ->
            :ok
        end
    end
  
  end

  defp reply_and_return(state, from, reply, count, new_data, actions) do
    # Process.sleep(100)
    GenServer.reply(from, reply)
    new_state = %{state | count: count - 1, data: new_data, actions: :queue.liat(actions)}
    {:noreply, new_state, 0}
  end

  defp deposit(state, from, amount, currency) do
    %{count: count, data: data, actions: actions} = state
    {new_data, reply} = 
      case Map.get(data, currency) do
        nil -> {Map.put(data, currency, amount), {:ok, amount}}
        x -> {Map.update!(data, currency, fn x -> x + amount end), {:ok, x + amount}}
      end
    reply_and_return(state, from, reply, count, new_data, actions)
  end

  defp withdraw(state, from, amount, currency) do
    %{count: count, data: data, actions: actions} = state
    x = Map.get(data, currency)
    {new_data, reply} =
      cond do
        x == nil || x < amount -> {data, {:error, :not_enough_money}}
        true -> {Map.update!(data, currency, fn x -> x - amount end), {:ok, x - amount}}
      end
    reply_and_return(state, from, reply, count, new_data, actions)
  end

  defp get_balance(state, from, currency) do
    %{count: count, data: data, actions: actions} = state
    {new_data, reply} = 
      case Map.get(data, currency) do
        nil -> {data, {:ok, 0}}
        x -> {data, {:ok, x}}
      end
    reply_and_return(state, from, reply, count, new_data, actions)
  end


end