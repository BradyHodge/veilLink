-module(main).
-export([start/0]).

start() ->
    case read_csv("config.csv") of
        {ok, Config} -> 
            lists:foreach(fun({Protocol, ListenPort, ForwardIP, ForwardPort}) ->
                spawn(fun() -> listen(Protocol, ListenPort, ForwardIP, ForwardPort) end)
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
        %% Format: protocol,listen_port,forward_ip,forward_port
        [BinProtocol, BinListenPort, BinForwardIP, BinForwardPort] ->
            Protocol = parse_protocol(string:trim(binary_to_list(BinProtocol))),
            case {Protocol, catch binary_to_integer(string:trim(BinListenPort)), 
                  catch binary_to_integer(string:trim(BinForwardPort))} of
                {Proto, ListenPort, ForwardPort} 
                  when Proto =/= unknown, is_integer(ListenPort), is_integer(ForwardPort) ->
                    {true, {Proto, ListenPort, binary_to_list(string:trim(BinForwardIP)), ForwardPort}};
                _ ->
                    false
            end;
        %% Legacy format: listen_port,forward_ip,forward_port (assumes TCP)
        [BinListenPort, BinForwardIP, BinForwardPort] ->
            case {catch binary_to_integer(string:trim(BinListenPort)), 
                  catch binary_to_integer(string:trim(BinForwardPort))} of
                {ListenPort, ForwardPort} when is_integer(ListenPort), is_integer(ForwardPort) ->
                    {true, {tcp, ListenPort, binary_to_list(string:trim(BinForwardIP)), ForwardPort}};
                _ ->
                    false
            end;
        _ -> false
    end.

parse_protocol("tcp") -> tcp;
parse_protocol("TCP") -> tcp;
parse_protocol("udp") -> udp;
parse_protocol("UDP") -> udp;
parse_protocol(_) -> unknown.

%% =============================================================================
%% TCP Implementation
%% =============================================================================

listen(tcp, ListenPort, ForwardIP, ForwardPort) ->
    io:format("Starting TCP listener on port ~p -> ~s:~p~n", [ListenPort, ForwardIP, ForwardPort]),
    case gen_tcp:listen(ListenPort, [binary, {active, false}, {packet, raw}, {reuseaddr, true}]) of
        {ok, ListenSocket} ->
            io:format("Successfully listening (TCP) on port ~p~n", [ListenPort]),
            accept(ListenSocket, ForwardIP, ForwardPort);
        Error ->
            io:format("TCP Listen error: ~p~n", [Error])
    end;

%% =============================================================================
%% UDP Implementation
%% =============================================================================

listen(udp, ListenPort, ForwardIP, ForwardPort) ->
    io:format("Starting UDP listener on port ~p -> ~s:~p~n", [ListenPort, ForwardIP, ForwardPort]),
    case gen_udp:open(ListenPort, [binary, {active, true}, {reuseaddr, true}]) of
        {ok, Socket} ->
            io:format("Successfully listening (UDP) on port ~p~n", [ListenPort]),
            %% Create ETS table to track client mappings
            TableName = list_to_atom("udp_clients_" ++ integer_to_list(ListenPort)),
            ets:new(TableName, [named_table, public, set]),
            udp_loop(Socket, ForwardIP, ForwardPort, TableName);
        Error ->
            io:format("UDP Listen error: ~p~n", [Error])
    end.

udp_loop(ListenSocket, ForwardIP, ForwardPort, ClientTable) ->
    receive
        {udp, ListenSocket, ClientIP, ClientPort, Data} ->
            %% Packet from a client - forward to destination
            handle_client_packet(ListenSocket, ClientIP, ClientPort, Data, 
                                 ForwardIP, ForwardPort, ClientTable),
            udp_loop(ListenSocket, ForwardIP, ForwardPort, ClientTable);
        
        {udp_handler_closed, Pid} ->
            %% Forward handler closed, clean up mapping
            ets:delete(ClientTable, Pid),
            udp_loop(ListenSocket, ForwardIP, ForwardPort, ClientTable);
        
        Other ->
            io:format("UDP: Unexpected message: ~p~n", [Other]),
            udp_loop(ListenSocket, ForwardIP, ForwardPort, ClientTable)
    end.

handle_client_packet(ListenSocket, ClientIP, ClientPort, Data, ForwardIP, ForwardPort, ClientTable) ->
    %% Check if we already have a forward socket for this client
    ClientKey = {ClientIP, ClientPort},
    case ets:match_object(ClientTable, {'_', ClientKey}) of
        [{ForwardPid, ClientKey}] ->
            %% Existing connection, send to the handler process
            ForwardPid ! {forward, Data};
        [] ->
            %% New client, spawn a handler process
            Parent = self(),
            Pid = spawn(fun() -> udp_forward_handler(ListenSocket, ClientIP, ClientPort, 
                                                      ForwardIP, ForwardPort, Parent) end),
            ets:insert(ClientTable, {Pid, ClientKey}),
            Pid ! {forward, Data}
    end.

udp_forward_handler(ListenSocket, ClientIP, ClientPort, ForwardIP, ForwardPort, Parent) ->
    %% Create our own forward socket - we are the controlling process
    case gen_udp:open(0, [binary, {active, true}]) of
        {ok, ForwardSocket} ->
            udp_forward_loop(ListenSocket, ClientIP, ClientPort, 
                            ForwardSocket, ForwardIP, ForwardPort, Parent);
        Error ->
            io:format("UDP: Failed to create forward socket: ~p~n", [Error]),
            Parent ! {udp_handler_closed, self()}
    end.

udp_forward_loop(ListenSocket, ClientIP, ClientPort, ForwardSocket, ForwardIP, ForwardPort, Parent) ->
    receive
        {forward, Data} ->
            %% Forward data from client to destination
            gen_udp:send(ForwardSocket, ForwardIP, ForwardPort, Data),
            udp_forward_loop(ListenSocket, ClientIP, ClientPort, 
                            ForwardSocket, ForwardIP, ForwardPort, Parent);
        {udp, ForwardSocket, _IP, _Port, Data} ->
            %% Response from destination - send back to client
            gen_udp:send(ListenSocket, ClientIP, ClientPort, Data),
            udp_forward_loop(ListenSocket, ClientIP, ClientPort, 
                            ForwardSocket, ForwardIP, ForwardPort, Parent);
        stop ->
            gen_udp:close(ForwardSocket),
            Parent ! {udp_handler_closed, self()}
    after 300000 -> %% 5 minute timeout for idle UDP "connections"
        gen_udp:close(ForwardSocket),
        Parent ! {udp_handler_closed, self()}
    end.

%% =============================================================================
%% TCP Functions (unchanged from original)
%% =============================================================================

accept(ListenSocket, ForwardIP, ForwardPort) ->
    {ok, ClientSocket} = gen_tcp:accept(ListenSocket),
    spawn(fun() -> forward(ClientSocket, ForwardIP, ForwardPort) end),
    accept(ListenSocket, ForwardIP, ForwardPort).

forward(ClientSocket, ForwardIP, ForwardPort) ->
    case gen_tcp:connect(ForwardIP, ForwardPort, [binary, {active, false}, {packet, raw}]) of
        {ok, ForwardSocket} ->
            Pid1 = spawn(fun() -> forward_loop(ClientSocket, ForwardSocket, "client->server") end),
            Pid2 = spawn(fun() -> forward_loop(ForwardSocket, ClientSocket, "server->client") end),
            receive
                {'EXIT', Pid1, _} -> ok;
                {'EXIT', Pid2, _} -> ok
            end;
        Error ->
            io:format("TCP Connection error: ~p~n", [Error]),
            gen_tcp:close(ClientSocket)
    end.

forward_loop(SourceSocket, DestinationSocket, Direction) ->
    process_flag(trap_exit, true),
    case gen_tcp:recv(SourceSocket, 0) of
        {ok, Data} ->
            case gen_tcp:send(DestinationSocket, Data) of
                ok ->
                    forward_loop(SourceSocket, DestinationSocket, Direction);
                Error ->
                    io:format("~s: Send error: ~p~n", [Direction, Error]),
                    cleanup(SourceSocket, DestinationSocket)
            end;
        {error, closed} ->
            cleanup(SourceSocket, DestinationSocket);
        Error ->
            io:format("~s: Receive error: ~p~n", [Direction, Error]),
            cleanup(SourceSocket, DestinationSocket)
    end.

cleanup(Socket1, Socket2) ->
    gen_tcp:close(Socket1),
    gen_tcp:close(Socket2).
