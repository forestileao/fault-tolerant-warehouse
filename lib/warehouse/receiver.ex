defmodule Warehouse.Receiver do
  alias Warehouse.DeliveratorPool
  alias Warehouse.Deliverator
  use GenServer
  @batch_size 20

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    state = %{
      assingments: [],
      batch_size: @batch_size,
      packages_buffer: [],
      delivered_packages: [],
    }

    {:ok, state}
  end

  def receive_packages(packages) do
    GenServer.cast(__MODULE__, {:receive_packages, packages})
  end

  def handle_cast({:receive_packages, packages}, state) do
    IO.puts("received #{Enum.count(packages)} packages")

    state = case DeliveratorPool.available_deliverator do
      {:ok, deliverator} ->
        IO.puts("deliverator #{inspect(deliverator)} acquired, assingning batch")
        {package_batch, remaining_packages} = Enum.split(packages, @batch_size)
        new_state = assign_packages(state, package_batch, deliverator)
        Process.monitor(deliverator)
        DeliveratorPool.flag_deliverator_busy(deliverator)
        Deliverator.deliver_packages(deliverator, package_batch)

        if Enum.count(remaining_packages) > 0 do
          receive_packages(remaining_packages)
        end
        new_state
      {:error, message} ->
        IO.puts("#{message}")
        IO.puts("buffering #{Enum.count(packages)} packages ")
        state
    end

    {:noreply, state}
  end

  def handle_info({:deliverator_idle, deliverator}, state) do
    IO.puts("deliverator #{inspect(deliverator)} completed the mission")
    DeliveratorPool.flag_deliverator_idle(deliverator)
    {next_batch, remaining_packages} = Enum.split(state.packages_buffer, @batch_size)
    if Enum.count(next_batch) > 0 do
      receive_packages(next_batch)
    end
    state = %{state | packages_buffer: remaining_packages}
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, deliverator, reason}, state) do
    IO.puts("deliverator #{inspect(deliverator)} went down. Details: #{inspect(reason)}")

    failed_assingments = filter_by_deliverator(deliverator, state.assingments)
    failed_packages = failed_assingments |> Enum.map(fn {package, _pid} -> package end)

    DeliveratorPool.remove_deliverator(deliverator)

    new_assingments = state.assingments -- failed_assingments
    state = %{state | assingments: new_assingments}
    receive_packages(failed_packages)
    {:noreply, state}
  end

  def handle_info({:package_delivered, package}, state) do
    IO.puts("Package #{inspect(package)} was delivered!")

    delivered_assingment =
      state.assingments
      |> Enum.find(nil, fn({assigned_package, _pid}) -> assigned_package == package end)

    assingments = List.delete(state.assingments, delivered_assingment)
    delivered_packages = [package | state.delivered_packages]
    state = %{state | assingments: assingments, delivered_packages: delivered_packages}
    {:noreply, %{state | assingments: assingments}}
  end

  defp assign_packages(state, packages, deliverator) do
    new_assignments = packages |> Enum.map(fn package -> {package, deliverator} end)
    assingments = state.assingments ++ new_assignments

    %{state | assingments: assingments}
  end

  defp filter_by_deliverator(deliverator, assignments) do
    assignments
    |> Enum.filter(fn {_package, package_deliverator} -> package_deliverator == deliverator end)
  end
end
