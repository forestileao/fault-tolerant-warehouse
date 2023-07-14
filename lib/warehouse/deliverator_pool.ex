defmodule Warehouse.DeliveratorPool do
  use GenServer
  alias Warehouse.{Deliverator}
  @max 20

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec init(any) :: {:ok, %{deliverators: [], max: 20}}
  def init(_) do
    state = %{
      deliverators: [],
      max: @max,
    }

    {:ok, state}
  end

  def available_deliverator do
    GenServer.call(__MODULE__, :fetch_available_deliverator)
  end

  def flag_deliverator_busy(deliverator) do
    GenServer.call(__MODULE__, {:flag_deliverator, :busy, deliverator})
  end

  def flag_deliverator_idle(deliverator) do
    GenServer.call(__MODULE__, {:flag_deliverator, :idle, deliverator})
  end

  def remove_deliverator(deliverator) do
    GenServer.call(__MODULE__, {:remove_deliverator, deliverator})
  end

  # Callbacks

  @doc """
    1. find idle deliverator from the pool
    2. if none found, check if number of deliverators is less than max
    3. if less than max, start a new deliverator, add to the pool as idle
    4. if over max, return {:error, message}
  """
  def handle_call(:fetch_available_deliverator, _from, state) do
    idle_deliverator =
      state.deliverators
      |> Enum.find(&match?({_deliverator, :idle}, &1))

    {status, message, state} = case idle_deliverator do
      nil ->
        if Enum.count(state.deliverators) >= @max do
          {:error, "deliverator pool maxed out"}
        else
          {:ok, deliverator} = Deliverator.start
          deliverator_entry = {deliverator, :idle}
          deliverators = [deliverator_entry | state.deliverators]
          state = %{state | deliverators: deliverators}
          {:ok, deliverator, state}
        end

      # found idle deliverator
      {deliverator, _status} -> {:ok, deliverator, state}

      response -> raise "unexpected format #{inspect(response)}"
    end

    {:reply, {status, message}, state}
  end

  def handle_call({:flag_deliverator, flag, deliverator}, _from, state) do
    deliverator_index =
      state.deliverators
      |> Enum.find_index(&match?({^deliverator, _}, &1))

    deliverators =
      state.deliverators
      |> List.replace_at(deliverator_index, {deliverator, flag})

    new_state = %{state | deliverators: deliverators}

    {:reply, :ok, new_state}
  end

  def handle_call({:remove_deliverator, deliverator}, _from, state) do
    deliverator_entry =
      state.deliverators
      |> Enum.find(&match?({^deliverator, _}, &1))

    deliverators = List.delete(state.deliverators, deliverator_entry)
    state = %{state | deliverators: deliverators}
    {:reply, :ok, state}
  end
end
