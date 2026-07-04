defmodule SapoCore.Assistant.Terminal do
  @moduledoc """
  Thin wrapper around ExPTY for running commands in a pseudo-terminal.
  (Ported from v1 `SapoHub.Projects.Terminal`.)

  Using a PTY means the child process sees a TTY and uses line-buffered
  output, so output streams in real time instead of appearing all at once
  when the process exits.

  Spawning sends these messages to the calling process:

      {:pty_data, data}   # chunk of output (stdout + stderr merged)
      {:pty_exit, code}   # process exited with exit code
  """

  @doc """
  Spawn `cmd` with `args` in a PTY. Returns `{:ok, pty_pid}` or
  `{:error, reason}`.

  Options:
    * `:cwd`  — working directory
    * `:cols` — terminal width  (default 220)
    * `:rows` — terminal height (default 50)
    * `:env`  — extra environment variables (map, merged with defaults)
  """
  def spawn(cmd, args, opts \\ []) do
    parent = self()
    cwd = opts[:cwd]
    cols = opts[:cols] || 220
    rows = opts[:rows] || 50

    # Start from the full service environment so vars like GIT_SSH_COMMAND
    # are inherited, then override only terminal-specific keys.
    env =
      System.get_env()
      |> Map.merge(%{
        "TERM" => "xterm-256color",
        "COLORTERM" => "truecolor",
        "LANG" => "en_US.UTF-8",
        "SHELL" => System.get_env("SHELL") || System.find_executable("bash") || "/bin/bash",
        "PATH" =>
          System.get_env("PATH") || "/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin"
      })
      |> Map.merge(opts[:env] || %{})

    pty_opts = [
      cols: cols,
      rows: rows,
      env: env,
      on_data: fn _mod, _pid, data -> send(parent, {:pty_data, data}) end,
      on_exit: fn _mod, _pid, code, _signal -> send(parent, {:pty_exit, code}) end
    ]

    pty_opts = if cwd, do: Keyword.put(pty_opts, :cwd, cwd), else: pty_opts

    ExPTY.spawn(cmd, args, pty_opts)
  end

  def write(pty_pid, data), do: ExPTY.write(pty_pid, data)
  def resize(pty_pid, cols, rows), do: ExPTY.resize(pty_pid, cols, rows)
  def kill(pty_pid, signal \\ 15), do: ExPTY.kill(pty_pid, signal)

  @doc """
  Clean PTY output for plain-text display: strips ANSI/VT escape sequences,
  control characters and carriage returns.
  """
  def clean_output(text) do
    text
    # OSC sequences: \e]...BEL or \e]...\e\\ (terminal title etc.)
    |> String.replace(~r/\e\][^\a]*(?:\a|\e\\)/, "")
    # CSI sequences: \e[ ... letter (colours, cursor, modes)
    |> String.replace(~r/\e\[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]/, "")
    # Character set designations: \e( \e) \e* \e+ followed by one byte
    |> String.replace(~r/\e[()#*+][A-Za-z0-9]/, "")
    # Single-char escape sequences: \e + one byte (e.g. \e7 \e8 \e= \e> \eM)
    |> String.replace(~r/\e[\x20-\x7E]/, "")
    # Strip remaining bare ESC bytes
    |> String.replace("\e", "")
    # Strip non-printable control characters (keep \n and \t)
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
    # Normalise \r\n → \n, then strip bare \r
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "")
  end
end
