-module(main).
-export([start/0]).

start() ->
    case read_csv("config.csv") of
        {ok, Config} -> 
            lists:foreach(fun({ListenPort, ForwardIP, ForwardPort}) ->
                spawn(fun() -> listen(ListenPort, ForwardIP, ForwardPort) end)
            end, Config);
        {error, Reason} ->
            io:format("Error reading config file: ~p~n", [Reason])
    end.

read_csv(FileName) ->
    case file:read_file(FileName) of
        {ok, Binary} ->
            Lines = binary:split(Binary, <<"\n">>, [global]),
            Parsed = lists:filtermap(fun parse_csv_line/1, Lines),
            {ok, Parsed};
        {error, Reason} ->
            {error, Reason}
    end.

parse_csv_line(Line) ->
    case binary:split(Line, <<",">>, [global]) of
        [BinListenPort, BinForwardIP, BinForwardPort] ->
            case {binary_to_integer(BinListenPort), binary_to_integer(BinForwardPort)} of
                {ListenPort, ForwardPort} when is_integer(ListenPort), is_integer(ForwardPort) ->
                    {true, {ListenPort, binary_to_list(BinForwardIP), ForwardPort}};
                _ ->
                    false
            end;
        _ -> false
    end.

listen(ListenPort, ForwardIP, ForwardPort) ->
    io:format("Starting to listen on port ~p~n", [ListenPort]),
    case gen_tcp:listen(ListenPort, [binary, {active, false}, {packet, raw}, {reuseaddr, true}]) of
        {ok, ListenSocket} ->
            io:format("Successfully listening on port ~p~n", [ListenPort]),
            accept(ListenSocket, ForwardIP, ForwardPort);
        Error ->
            io:format("Listen error: ~p~n", [Error])
    end.

accept(ListenSocket, ForwardIP, ForwardPort) ->
    % io:format("Waiting for connection...~n"),
    {ok, ClientSocket} = gen_tcp:accept(ListenSocket),
    % io:format("Accepted new connection~n"),
    spawn(fun() -> forward(ClientSocket, ForwardIP, ForwardPort) end),
    accept(ListenSocket, ForwardIP, ForwardPort).

forward(ClientSocket, ForwardIP, ForwardPort) ->
    % io:format("Attempting to connect to ~p:~p~n", [ForwardIP, ForwardPort]),
    case gen_tcp:connect(ForwardIP, ForwardPort, [binary, {active, false}, {packet, raw}]) of
        {ok, ForwardSocket} ->
            % io:format("Successfully connected to forward destination~n"),
            Pid1 = spawn(fun() -> forward_loop(ClientSocket, ForwardSocket, "client->server") end),
            Pid2 = spawn(fun() -> forward_loop(ForwardSocket, ClientSocket, "server->client") end),
            receive
                {'EXIT', Pid1, _} -> ok;
                {'EXIT', Pid2, _} -> ok
            end;
        Error ->
            io:format("Connection error: ~p~n", [Error]),
            gen_tcp:close(ClientSocket)
    end.

forward_loop(SourceSocket, DestinationSocket, Direction) ->
    process_flag(trap_exit, true),
    % io:format("~s: Waiting to receive data...~n", [Direction]),
    case gen_tcp:recv(SourceSocket, 0) of
        {ok, Data} ->
            % io:format("~s: Received ~p bytes~n", [Direction, byte_size(Data)]),
            case gen_tcp:send(DestinationSocket, Data) of
                ok ->
                    % io:format("~s: Forwarded data successfully~n", [Direction]),
                    forward_loop(SourceSocket, DestinationSocket, Direction);
                Error ->
                    io:format("~s: Send error: ~p~n", [Direction, Error]),
                    cleanup(SourceSocket, DestinationSocket)
            end;
        {error, closed} ->
            % io:format("~s: Socket closed normally~n", [Direction]),
            cleanup(SourceSocket, DestinationSocket);
        Error ->
            io:format("~s: Receive error: ~p~n", [Direction, Error]),
            cleanup(SourceSocket, DestinationSocket)
    end.

cleanup(Socket1, Socket2) ->
    gen_tcp:close(Socket1),
    gen_tcp:close(Socket2).

