%%--------------------------------------------------------------------
%% Copyright (c) 2015-2016 Feng Lee <feng@emqtt.io>.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emq_plugin_apinf).

-include_lib("emqttd/include/emqttd.hrl").

-export([load/1, unload/0]).

%% Hooks functions

-export([on_client_connected/3, on_client_disconnected/3]).

-export([on_client_subscribe/4, on_client_unsubscribe/4]).

-export([on_session_created/3, on_session_subscribed/4, on_session_unsubscribed/4, on_session_terminated/4]).

-export([on_message_publish/2, on_message_delivered/4, on_message_acked/4]).

% Custom functions
% tuple_to_string(Log) ->
%   lists:flatten(io_lib:format("~p", [Log])).

% write_to_mongo(Log) ->
%   Database = <<"mqtt">>,
%   Collection = <<"analytics">>,
%   {ok, Connection} = mc_worker_api:connect([{database, Database}]),
%   mc_worker_api:insert(Connection, Collection, Log).

write_to_es(Log) ->
  esio:start(),
  % TODO: Move ES host URL to config file
  {ok, Sock} = esio:socket("http://192.168.43.171:9200/"),
  Id = uuid:to_string(uuid:uuid1()),
  esio:put(Sock, "urn:es:mqt:analytics:" ++ Id, Log),
  esio:close(Sock).
% --- Custom functions

%% Called when the plugin application start
load(Env) ->
    emqttd:hook('client.connected', fun ?MODULE:on_client_connected/3, [Env]),
    emqttd:hook('client.disconnected', fun ?MODULE:on_client_disconnected/3, [Env]),
    emqttd:hook('client.subscribe', fun ?MODULE:on_client_subscribe/4, [Env]),
    emqttd:hook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4, [Env]),
    emqttd:hook('session.created', fun ?MODULE:on_session_created/3, [Env]),
    emqttd:hook('session.subscribed', fun ?MODULE:on_session_subscribed/4, [Env]),
    emqttd:hook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4, [Env]),
    emqttd:hook('session.terminated', fun ?MODULE:on_session_terminated/4, [Env]),
    emqttd:hook('message.publish', fun ?MODULE:on_message_publish/2, [Env]),
    emqttd:hook('message.delivered', fun ?MODULE:on_message_delivered/4, [Env]),
    emqttd:hook('message.acked', fun ?MODULE:on_message_acked/4, [Env]).

on_client_connected(ConnAck, Client = #mqtt_client{client_id = ClientId}, _Env) ->
    io:format("client ~s connected, connack: ~w~n", [ClientId, ConnAck]),
    Log = #{
      type => <<"on_client_connected">>,
      date => erlang:localtime()
    },
    write_to_es(Log),
    {ok, Client}.

on_client_disconnected(Reason, _Client = #mqtt_client{client_id = ClientId}, _Env) ->
    io:format("client ~s disconnected, reason: ~w~n", [ClientId, Reason]),
    Log = #{
      type => <<"on_client_disconnected">>,
      date => erlang:localtime()
    },
    write_to_es(Log),
    ok.

on_client_subscribe(ClientId, Username, TopicTable, _Env) ->
    io:format("client(~s/~s) will subscribe: ~p~n", [Username, ClientId, TopicTable]),
    Log = #{
      type => <<"on_client_subscribe">>,
      date => erlang:localtime(),
      username => Username,
      topic_table => TopicTable
    },
    write_to_es(Log),
    {ok, TopicTable}.

on_client_unsubscribe(ClientId, Username, TopicTable, _Env) ->
    io:format("client(~s/~s) unsubscribe ~p~n", [ClientId, Username, TopicTable]),
    Log = #{
      type => <<"on_client_unsubscribe">>,
      date => erlang:localtime(),
      username => Username,
      topic_table => TopicTable
    },
    write_to_es(Log),
    {ok, TopicTable}.

on_session_created(ClientId, Username, _Env) ->
    Log = #{
      type => <<"on_session_created">>,
      date => erlang:localtime(),
      username => Username
    },
    write_to_es(Log),
    io:format("session(~s/~s) created.", [ClientId, Username]).

on_session_subscribed(ClientId, Username, {Topic, Opts}, _Env) ->
    io:format("session(~s/~s) subscribed: ~p~n", [Username, ClientId, {Topic, Opts}]),
    Log = #{
      type => <<"on_session_subscribed">>,
      date => erlang:localtime(),
      username => Username,
      topic_and_opts => #{
        topic => Topic,
        opts => Opts
      }
    },
    write_to_es(Log),
    {ok, {Topic, Opts}}.

on_session_unsubscribed(ClientId, Username, {Topic, Opts}, _Env) ->
    io:format("session(~s/~s) unsubscribed: ~p~n", [Username, ClientId, {Topic, Opts}]),
    Log = #{
      type => <<"on_session_unsubscribed">>,
      date => erlang:localtime(),
      username => Username,
      topic_and_opts => #{
        topic => Topic,
        opts => Opts
      }
    },
    write_to_es(Log),
    ok.

on_session_terminated(ClientId, Username, Reason, _Env) ->
    io:format("session(~s/~s) terminated: ~p.", [ClientId, Username, Reason]),
    Log = #{
      type => <<"on_session_terminated">>,
      date => erlang:localtime(),
      username => Username,
      reason => Reason
    },
    write_to_es(Log).

%% transform message and return
on_message_publish(Message = #mqtt_message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};

on_message_publish(Message, _Env) ->
    io:format("publish ~s~n", [emqttd_message:format(Message)]),
    #mqtt_message{
      from = {_, UsernameFrom},
      qos = Qos,
      retain = Retain,
      dup = Dup,
      topic = Topic
    } = Message,
    % Log = {
    %   <<"type">>,<<"on_message_publish">>,
    %   <<"date">>,erlang:timestamp(),
    %   <<"message">>,{
    %     <<"id">>, MsgId,
    %     <<"pktid">>, PktId,
    %     <<"from">>, {
    %       <<"client_id">>, ClientIdFrom,
    %       <<"username">>, UsernameFrom
    %     },
    %     <<"qos">>, Qos,
    %     <<"retain">>, Retain,
    %     <<"dup">>, Dup,
    %     <<"topic">>, Topic
    %   }
    % },
    % write_to_mongo(Log),
    Log = #{
      type => <<"on_message_publish">>,
      date => erlang:localtime(),
      message => #{
        from => UsernameFrom,
        qos => Qos,
        retain => Retain,
        topic => Topic,
        dup => Dup
      }
    },
    write_to_es(Log),
    {ok, Message}.

on_message_delivered(ClientId, Username, Message, _Env) ->
    io:format("delivered to client(~s/~s): ~s~n", [Username, ClientId, emqttd_message:format(Message)]),
    #mqtt_message{
      from = {_, UsernameFrom},
      qos = Qos,
      retain = Retain,
      dup = Dup,
      topic = Topic
    } = Message,
    % Log = {
    %   <<"type">>, <<"on_message_delivered">>,
    %   <<"date">>, erlang:timestamp(),
    %   <<"client_id">>, ClientId,
    %   <<"username">>, Username,
    %   <<"message">>, {
    %     <<"id">>, MsgId,
    %     <<"pktid">>, PktId,
    %     <<"from">>, {
    %       <<"client_id">>, ClientIdFrom,
    %       <<"username">>, UsernameFrom
    %     },
    %     <<"qos">>, Qos,
    %     <<"retain">>, Retain,
    %     <<"dup">>, Dup,
    %     <<"topic">>, Topic
    %   }
    % },
    % write_to_mongo(Log),
    Log = #{
      type => <<"on_message_delivered">>,
      date => erlang:localtime(),
      username => Username,
      message => #{
        from => UsernameFrom,
        qos => Qos,
        retain => Retain,
        topic => Topic,
        dup => Dup
      }
    },
    write_to_es(Log),
    {ok, Message}.

on_message_acked(ClientId, Username, Message, _Env) ->
    io:format("client(~s/~s) acked: ~s~n", [Username, ClientId, emqttd_message:format(Message)]),
    #mqtt_message{
      from = {_, UsernameFrom},
      qos = Qos,
      retain = Retain,
      dup = Dup,
      topic = Topic
    } = Message,
    % Log = {
    %   <<"type">>, <<"on_message_acked">>,
    %   <<"date">>, erlang:timestamp(),
    %   <<"client_id">>, ClientId,
    %   <<"username">>, Username,
    %   <<"message">>, {
    %     <<"id">>, MsgId,
    %     <<"pktid">>, PktId,
    %     <<"from">>, {
    %       <<"client_id">>, ClientIdFrom,
    %       <<"username">>, UsernameFrom
    %     },
    %     <<"qos">>, Qos,
    %     <<"retain">>, Retain,
    %     <<"dup">>, Dup,
    %     <<"topic">>, Topic
    %   }
    % },
    % write_to_mongo(Log),
    Log = #{
      type => <<"on_message_acked">>,
      date => erlang:localtime(),
      username => Username,
      message => #{
        from => UsernameFrom,
        qos => Qos,
        retain => Retain,
        topic => Topic,
        dup => Dup
      }
    },
    write_to_es(Log),
    {ok, Message}.

%% Called when the plugin application stop
unload() ->
    emqttd:unhook('client.connected', fun ?MODULE:on_client_connected/3),
    emqttd:unhook('client.disconnected', fun ?MODULE:on_client_disconnected/3),
    emqttd:unhook('client.subscribe', fun ?MODULE:on_client_subscribe/4),
    emqttd:unhook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4),
    emqttd:unhook('session.subscribed', fun ?MODULE:on_session_subscribed/4),
    emqttd:unhook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4),
    emqttd:unhook('message.publish', fun ?MODULE:on_message_publish/2),
    emqttd:unhook('message.delivered', fun ?MODULE:on_message_delivered/4),
    emqttd:unhook('message.acked', fun ?MODULE:on_message_acked/4).
