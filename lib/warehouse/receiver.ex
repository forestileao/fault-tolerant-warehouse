defmodule Warehouse.Receiver do
  use GenServer

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    state = %{
      assingments: []
    }

    {:ok, state}
  end

  def receive_and_chunk(packages) do
    packages
    |> Enum.chunk_every(10)
    |> Enum.each(&receive_packages/1)
  end

  def receive_packages(packages) do
    GenServer.cast(__MODULE__, {:receive_packages, packages})
  end

  def handle_cast({:receive_packages, packages}, state) do
    IO.puts("received #{Enum.count(packages)} packages")

    {:ok, deliverator_pid} = Warehouse.Deliverator.start()
    Process.monitor(deliverator_pid)
    Warehouse.Deliverator.deliver_packages(deliverator_pid, packages)

    new_state = assign_packages(state, packages, deliverator_pid)

    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, deliverator, :normal}, state) do
    IO.puts("deliverator #{inspect(deliverator)} completed the mission and terminated")
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, deliverator, reason}, state) do
    IO.puts("deliverator #{inspect(deliverator)} went down. Details: #{inspect(reason)}")

    failed_assingments = filter_by_deliverator(deliverator, state.assingments)
    failed_packages = failed_assingments |> Enum.map(fn {package, _pid} -> package end)

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
