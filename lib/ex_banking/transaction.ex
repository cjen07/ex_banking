defmodule ExBanking.Transaction do

  alias ExBanking.Transaction
  use GenServer

  defstruct [:user, :count, :data, :actions, :flag, :frozen]

  def start_link([user, data]) do
    state = %Transaction{user: user, data: data, count: 0, actions: [], flag: false, frozen: %{}}
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
    IO.puts "GenServer #{user} is terminated"
    :ok
  end

  def terminate(reason, state) do
    IO.inspect reason
    IO.inspect state
    :ok
  end

  def handle_call(request, from, state) do
    if state.count == 10 do
      {new_actions, {{type, body}, new_from}} = 
        Enum.sort([{request, from} | state.actions], fn x1, x2 -> elem(x1, 1) < elem(x2, 1) end)
        |> (fn x -> {Enum.drop(x, -1), Enum.at(x, 10)} end).()
      reply = 
        case type do
          :send -> 
            :too_many_requests_to_sender
          :receive -> 
            {_, user, amount, currency, from2} = body
            feedback(from2, user, {:error, :too_many_requests_to_receiver}, amount, currency)
            :too_many_requests_to_receiver
          _ -> 
            :too_many_requests_to_user
        end
      GenServer.reply(new_from, {:error, reply})
      new_state = %{state | actions: new_actions, flag: false}
      {:noreply, new_state, 50}
    else
      new_actions = Enum.sort([{request, from} | state.actions], fn x1, x2 -> elem(x1, 1) < elem(x2, 1) end)
      new_count = state.count + 1;
      new_state = %{state | count: new_count, actions: new_actions, flag: false}
      {:noreply, new_state, 50}
    end
  end

  def handle_cast(:halt, state) do
    if state.count == 0 && state.flag && state.frozen == %{} do
      {:stop, :normal, state}
    else
      new_state = %{state | flag: false}
      {:noreply, new_state, 0}
    end
  end

  def handle_cast({:feedback, from2, reply, amount, currency}, state) do
    %{data: data, frozen: frozen} = state
    case reply do
      {:ok, b} ->
        x = Map.get(data, currency)
        
        GenServer.reply(from2, {:ok, x, b})
        z = Map.get(frozen, currency)
        new_frozen =
          cond do
            z == amount -> Map.delete(frozen, currency)
            true -> Map.update!(frozen, currency, fn x -> x - amount end)
          end
        new_state = %{state | frozen: new_frozen}
        {:noreply, new_state, 0}
      _ ->
        GenServer.reply(from2, reply)
        z = Map.get(frozen, currency)
        new_frozen =
          cond do
            z == amount -> Map.delete(frozen, currency)
            true -> Map.update!(frozen, currency, fn x -> x - amount end)
          end
        new_data = Map.update!(data, currency, fn x -> x + amount end)
        new_state = %{state | data: new_data, frozen: new_frozen}
        {:noreply, new_state, 0}
    end
  end

  def handle_info(:timeout, state) do
    case state.actions == [] do
      true ->
        current = self()
        spawn(fn ->
          Process.sleep(1000)
          GenServer.cast(current, :halt)
        end)
        new_state = %{state | flag: true}
        {:noreply, new_state, :hibernate}
      false ->
        {request, from} = hd state.actions
        case request do
          {:deposit, {_, amount, currency}} ->
            deposit(state, from, amount, currency)
          {:withdraw, {_, amount, currency}} -> 
            withdraw(state, from, amount, currency)
          {:get_balance, {_, currency}} ->  
            get_balance(state, from, currency)
          {:send, {_, to_user, amount, currency}} ->
            send(state, from, to_user, amount, currency)
          {:receive, {_, from_user, amount, currency, from2}} ->
            receive(state, from, from_user, amount, currency, from2)
        end
    end
  
  end

  defp reply_and_return(state, from, reply, count, new_data, actions) do
    GenServer.reply(from, reply)
    new_state = %{state | count: count - 1, data: new_data, actions: Enum.drop(actions, 1)}
    {:noreply, new_state, 100}
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

  defp send(state, from, to_user, amount, currency) do
    %{count: count, data: data, actions: actions, frozen: frozen} = state
    x = Map.get(data, currency)
    cond do
      x == nil || x < amount -> 
        reply_and_return(state, from, {:error, :not_enough_money}, count, data, actions)
      true -> 
        new_data = Map.update!(data, currency, fn x -> x - amount end)
        new_frozen = Map.update(frozen, currency, amount, fn x -> x + amount end)
        new_state = %{state | data: new_data, frozen: new_frozen, count: count - 1, actions: Enum.drop(actions, 1)}
        spawn(fn -> forward(to_user, {:receive, {to_user, state.user, amount, currency, from}}) end)
        {:noreply, new_state, 100}
    end
  end

  defp receive(state, from, from_user, amount, currency, from2) do
    %{count: count, data: data, actions: actions} = state
    {new_data, reply} = 
      case Map.get(data, currency) do
        nil -> {Map.put(data, currency, amount), {:ok, amount}}
        x -> {Map.update!(data, currency, fn x -> x + amount end), {:ok, x + amount}}
      end
    feedback(from2, from_user, reply, amount, currency)
    reply_and_return(state, from, reply, count, new_data, actions)
  end

  defp forward(user, request) do
    [{_, data}] = ExBanking.user_lookup(user)
    ExBanking.do_handle(user, data, request)
  end

  defp feedback(from2, user, reply, amount, currency) do
    [{pid, _}] = Transaction.whereis(user)
    GenServer.cast(pid, {:feedback, from2, reply, amount, currency})
  end


end