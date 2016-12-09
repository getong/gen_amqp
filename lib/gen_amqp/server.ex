defmodule GenAMQP.Server do
  @moduledoc """
  Defines the behaviour for servers connected through RabbitMQ
  """

  defmacro __using__(opts) do
    event = opts[:event]
    size = Keyword.get(opts, :size, 3)

    quote do
      require Logger
      use Supervisor

      @behaviour GenAMQP.Server.Behaviour

      # Public API

      def start_link() do
        Supervisor.start_link(__MODULE__, [], name: __MODULE__)
      end

      def init(_) do
        children =
          Enum.map(1..unquote(size), fn(num) ->
            id = "#{__MODULE__.Worker}_#{num}"
            worker(__MODULE__.Worker, [id], id: id, restart: :transient, shutdown: 1)
          end)

        Logger.info("Starting #{__MODULE__}")
        supervise(children, strategy: :one_for_one)
      end

      defmodule Worker do
        use GenServer
        alias GenAMQP.Conn

        @exec_module __MODULE__
          |> Atom.to_string
          |> String.split(".")
          |> (fn(enum) ->
            size = length(enum)
            List.delete_at(enum, size - 1)
          end).()
          |> Enum.join(".")
          |> String.to_atom

        def start_link(name) do
          GenServer.start_link(__MODULE__, [name])
        end

        def init(name) do
          Process.flag(:trap_exit, true)
          Logger.info("Starting #{name}")
          conn_name = String.to_atom("#{name}.Conn")
          {:ok, conn_pid} = Supervisor.start_child(GenAMQP.Supervisor, [conn_name])
          :ok = Conn.subscribe(conn_name, unquote(event))
          {:ok, %{consumer_tag: nil, conn_name: conn_name, conn_pid: conn_pid}}
        end

        def handle_info({:basic_deliver, payload, meta}, %{conn_name: conn_name} = state) do
          try do
            case apply(@exec_module, :execute, [payload]) do
              {:reply, resp} ->
                reply(conn_name, meta, resp)
              _ -> nil
            end
          catch
            :exit, reason ->
              resp = Poison.encode!(%{
                status: :error,
                code: 0,
                message: reason
              })
              reply(conn_name, meta, resp)
          end
          {:noreply, state}
        end

        def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
          {:noreply, %{state | consumer_tag: consumer_tag}}
        end

        defp reply(_conn_name, %{reply_to: :undefined, correlation_id: :undefined} = meta, resp), do: nil

        defp reply(conn_name, %{reply_to: _, correlation_id: _} = meta, resp) do
          Conn.response(conn_name, meta, resp)
        end

        def terminate(reason, %{conn_pid: conn_pid} = _state) do
          #TODO set logs
          :ok = Supervisor.terminate_child(GenAMQP.Supervisor, conn_pid)
          Logger.error("Terminate #{__MODULE__}")
          Logger.error(reason)
        end
      end
    end
  end

  defmodule Behaviour do
    @moduledoc """
    Behaviour to implement by the servers
    """

    @callback execute(String.t) :: {:reply, String.t} | :noreply
  end
end
