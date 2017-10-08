defmodule ExBankingTest do
  use ExUnit.Case, async: false
  doctest ExBanking

  import ExBanking

  setup do
    init()
  end

  test "create_user 1" do
    assert create_user("user") == :ok
  end

  test "create_user 2" do
    create_user("user")
    assert create_user("user") == {:error, :user_already_exists}
  end

  test "create_user 3" do
    Enum.each(1..20, fn x -> assert create_user("user#{x}") == :ok end)
  end

  test "deposit get_balance withdraw 1" do
    create_user("user")
    assert deposit("user", 5, "RMB") == {:ok, 5}
    assert get_balance("user", "RMB") == {:ok, 5}
    assert deposit("user", 5, "RMB") == {:ok, 10}
    assert get_balance("user", "RMB") == {:ok, 10}
    assert withdraw("user", 3, "RMB") == {:ok, 7}
    assert get_balance("user", "RMB") == {:ok, 7}
    assert withdraw("user", 8, "RMB") == {:error, :not_enough_money}
    assert get_balance("user", "RMB") == {:ok, 7}
    assert withdraw("user", 2, "Dollar") == {:error, :not_enough_money}
    assert get_balance("user", "Dollar") == {:ok, 0}
    assert get_balance("user", "Pound") == {:ok, 0}
  end

  test "deposit get_balance withdraw 2" do
    assert deposit("user", 5, "RMB") == {:error, :user_does_not_exist}
    assert get_balance("user", "RMB") == {:error, :user_does_not_exist}
    assert withdraw("user", 5, "RMB") == {:error, :user_does_not_exist}
  end

  test "deposit get_balance withdraw 3" do
    assert deposit("user", -1, "RMB") == {:error, :wrong_arguments}
    assert withdraw("user", 0, "RMB") == {:error, :wrong_arguments}
  end

  test "deposit get_balance withdraw 4" do
    create_user("user1")
    s = self()
    Enum.each(1..15, fn n -> spawn(fn -> 
      data = deposit("user1", n, "RMB")
      send s, {self(), data}
    end) end)
    loop1(1, 0)
  end

  def loop1(n, m) do
    receive do
      {_, data} -> 
        IO.inspect data
        cond do
          n < 6 -> 
            assert data == {:error, :too_many_requests_to_user}
            loop1(n + 1, m)
          true -> 
            balance = m + (n - 5)
            assert data == {:ok, balance}
            loop1(n + 1, balance)
        end
      after 
        1000 ->
          :ok
    end
  end

  test "send 1" do
    create_user("user2")
    create_user("user3")
    deposit("user2", 5, "RMB")
    deposit("user3", 5, "RMB")
    assert send("user2", "user3", 2, "RMB") == {:ok, 3, 7}
    assert get_balance("user2", "RMB") == {:ok, 3}
    assert get_balance("user3", "RMB") == {:ok, 7}
    assert send("user3", "user2", 8, "RMB") == {:error, :not_enough_money}
    assert get_balance("user2", "RMB") == {:ok, 3}
    assert get_balance("user3", "RMB") == {:ok, 7}
  end

  test "send 2" do
    assert send("user2", "user3", 2, "RMB") == {:error, :receiver_does_not_exist}
    create_user("user3")
    assert send("user2", "user3", 2, "RMB") == {:error, :sender_does_not_exist}
  end

  test "send 3" do
    create_user("user4")
    create_user("user5")
    s = self()
    Enum.each(1..15, fn n -> spawn(fn ->
      data = 
        case rem(n, 4) do
          0  -> send("user4", "user5", n, "RMB")
          _ -> deposit("user4", n, "RMB")
         end 
      send s, {self(), data}
    end) end)
    loop2(1)
  end

  def loop2(n) do
    receive do
      {_, data} -> 
        IO.inspect data
        cond do
          n < 6 -> 
            assert (data == {:error, :too_many_requests_to_user} || data == {:error, :too_many_requests_to_sender})
            loop2(n + 1)
          true -> 
            assert Enum.any?([
              {:ok, 1},
              {:ok, 3},
              {:ok, 6},
              {:ok, 7},
              {:ok, 2, 4},
              {:ok, 13},
              {:ok, 20},
              {:ok, 21},
              {:ok, 12, 12},
              {:ok, 31}
            ], fn x -> x == data end)
            loop2(n + 1)
        end
      after 
        1000 ->
          :ok
    end
  end

  test "send 4" do
    create_user("user6")
    create_user("user7")
    deposit("user6", 40, "RMB")
    deposit("user7", 100, "RMB")
    s = self()
    Enum.each(1..15, fn n -> spawn(fn ->
      data = 
        case n == 5 || n == 13 do
          true  -> 
            Process.sleep(40 * n)
            send("user7", "user6", 4 * n, "RMB")
          false -> 
            Process.sleep(100 * n)
            withdraw("user6", n, "RMB")
         end 
      send s, {self(), data}
    end) end)
    loop3(0)
  end

  def loop3(n) do
    receive do
      {_, data} -> 
        IO.inspect data
        assert Enum.at([
          {:ok, 39},
          {:ok, 37},
          {:ok, 34},
          {:ok, 30},
          {:ok, 80, 50},
          {:ok, 44},
          {:ok, 37},
          {:ok, 29},
          {:ok, 20},
          {:ok, 10},
          {:error, :not_enough_money},
          {:error, :not_enough_money},
          {:ok, 28, 62},
          {:ok, 48},
          {:ok, 33}
        ], n) == data
        loop3(n + 1)
      after 
        1000 ->
          :ok
    end
  end

  test "send 5" do
    create_user("user8")
    create_user("user9")
    deposit("user8", 40, "RMB")
    deposit("user9", 100, "RMB")
    s = self()
    Enum.each(1..15, fn n -> spawn(fn ->
      data = 
        case rem(n, 7) do
          0  -> 
            Process.sleep(40)
            send("user9", "user8", 20, "RMB")
          _ -> 
            Process.sleep(80)
            withdraw("user8", 2, "RMB")
         end 
      send s, {self(), data}
    end) end)
    loop4(1)
  end

  def loop4(n) do
    receive do
      {_, data} -> 
        IO.inspect data
        cond do
          n < 4 ->
            assert data == {:error, :too_many_requests_to_user}
          n < 6 ->
            assert data == {:error, :too_many_requests_to_receiver}
          true ->
            assert data == {:ok, 40 - 2 * (n - 5)}
        end
        loop4(n + 1)
      after 
        1000 ->
          :ok
    end
  end
  
end
