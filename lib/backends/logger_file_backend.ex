defmodule Logger.Backends.JSONFile do
  use GenEvent

  @type path      :: String.t
  @type file      :: :file.io_device
  @type inode     :: File.Stat.t
  @type format    :: String.t
  @type level     :: Logger.level
  @type metadata  :: [atom]

  def init({__MODULE__, name}) do
    {:ok, configure(name, [])}
  end

  def handle_call({:configure, opts}, %{name: name}) do
    {:ok, :ok, configure(name, opts)}
  end

  def handle_call(:path, %{path: path} = state) do
    {:ok, {:ok, path}, state}
  end

  def handle_event({level, _gl, {Logger, msg, ts, md}}, %{level: min_level} = state) do
    if is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt do
      log_event(level, msg, ts, md, state)
    else
      {:ok, state}
    end
  end

  # helper functions
  defp log_event(_level, _msg, _ts, _md, %{path: nil} = state) do
    {:ok, state}
  end

  defp log_event(level, msg, ts, md, %{path: path, io_device: nil} = state) when is_binary(path) do
    case open_log(path) do
      {:ok, io_device, inode} ->
        log_event(level, msg, ts, md, %{state | io_device: io_device, inode: inode})
      _other ->
        {:ok, state}
    end
  end

  defp log_event(level, msg, ts, md, %{path: path, io_device: io_device, inode: inode} = state) when is_binary(path) do
    if !is_nil(inode) and inode == inode(path) do
      IO.write(io_device, format_event(level, msg, ts, md, state))
      {:ok, state}
    else
      log_event(level, msg, ts, md, %{state | io_device: nil, inode: nil})
    end
  end

  defp open_log(path) do
    case (path |> Path.dirname |> File.mkdir_p) do
      :ok ->
        case File.open(path, [:append, :utf8]) do
          {:ok, io_device} -> {:ok, io_device, inode(path)}
          other -> other
        end
      other -> other
    end
  end

  defp format_event(level, msg, ts, _md, _state) do
    Poison.encode!(%{msg: msg,
                     ts: format_time_to_rcf3339(ts),
                     level: level
                    }) <> "\n"
  end

  defp inode(path) do
    case File.stat(path) do
      {:ok, %File.Stat{inode: inode}} -> inode
      {:error, _} -> nil
    end
  end

  defp configure(name, opts) do
    env = Application.get_env(:logger, name, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, name, opts)

    level         = Keyword.get(opts, :level)
    metadata      = Keyword.get(opts, :metadata, [])
    path          = Keyword.get(opts, :path)

    %{
      name: name,
      path: path,
      io_device: nil,
      inode: nil,
      level: level,
      metadata: metadata
     }
  end

  defp format_time_to_rcf3339({{year, month, day}, {hour, minute, second, _millisec}}) do
    "#{year}-#{rcf3339_format_value month}-#{rcf3339_format_value day}T#{rcf3339_format_value hour}:#{rcf3339_format_value minute}:#{rcf3339_format_value second}Z"
  end

  defp rcf3339_format_value(value) when is_integer(value) and value < 10 and value >= 1 do
    "0#{value}"
  end

  defp rcf3339_format_value(value) when is_integer(value) and value > 9 do
    "#{value}"
  end
end
