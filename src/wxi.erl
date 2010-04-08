%% @author Dmitry Golubovsky <golubovsky@gmail.com>
%% @version 0.1

-module(wxi).

-include("wxi.hrl").

-export([topFrame/5, addSelf/2, addSelf/3, textLabel/2, panel/2, comp/2, passEvent/2,
         map/1, maybe/1, mapState/2, button/2, modSizerFlags/2, panel/1, linkEvent/3,
         never/0, always/0, rcomp/2, grid/2, catchEvents/1, catchEvents/2]).

%% Functions for internal use by custom widgets.

%% @doc Compose a subordinate piece of GUI. List of widgets encodes parallel composition,
%% tuple of widgets encodes sequential composition. This function is intended to be called
%% from within the creation phase code of a widget having subordinates (e. g. panel).

comp(Sub, C = #context {}) -> if
    is_tuple(Sub) andalso size(Sub) == 1 -> (element(1, Sub))(C);
    is_tuple(Sub) -> sercomp(lists:reverse(tuple_to_list(Sub)), C, []);
    is_list(Sub) -> parcomp(Sub, C, []);
    true -> Sub(C)
end.

%% @doc Same as comp/2, but placement is reversed.

rcomp(Sub, C = #context {}) -> if
    is_tuple(Sub) andalso size(Sub) == 1 -> (element(1, Sub))(C);
    is_tuple(Sub) -> sercompr(lists:reverse(tuple_to_list(Sub)), C);
    is_list(Sub) -> parcomp(lists:reverse(Sub), C, []);
    true -> Sub(C)
end.

%% @doc Pass an event to the event link for this widget.

passEvent(R, D) -> if
    is_pid(D) -> D ! R, ok;
    is_function(D, 2) -> D(R, null), ok;
    true -> ok
end.

%% @doc Form a function which will pass events generated by this widget to its event link.

linkEvent(_, _, []) -> ok;

linkEvent(Src, Dst, Evts) -> if
    Dst == self() -> [wxEvtHandler:connect(Src, E) || E <- Evts];
    is_function(Dst, 2) -> [wxEvtHandler:connect(Src, E, [{callback, Dst}]) || E <- Evts];
    true -> ok
end.

%% @doc Add the wx widget to its parent wrt parent's sizer.

addSelf(P, W) -> addSelf(P, W, []).

%% @doc Add the wx widget to its parent wrt parent's sizer with sizer flags explicitly
%% specified.

addSelf(P, W, F) ->
    S = hasSizer(P),
    if S -> 
        wxSizer:add(wxWindow:getSizer(P), W, F), 
        ok;
       true -> ok
    end,
    wxWindow:fit(P),
    ok.


%% Functions to manipulate the context.

%% @doc Modify sizer flags in the context. All subordinate widgets will use the modified
%% context. This widget only allows normal order of subordinates placement although
%% orientation is inherited from the parent.

modSizerFlags(F, Sub) -> fun (C = #context {szflags = T}) ->
    Tm = lists:keymerge(1, F, T),
    comp(Sub, C#context {szflags = Tm})
end.

%% Basic widgets.

%% @doc Create a toplevel frame (window) with given title, dimensions, and sizer
%% orientation (either vertical or horizontal; wxBoxSizer will be used). This widget honors 
%% the sign of the orientation flag: negative values cause reverse order of placement 
%% (right to left for <tt>?wxHORIZONTAL</tt>, and bottom to top for <tt>?wxVERTICAL</tt>).


topFrame(Title, X, Y, Dir, Sub) ->
    Wx = wx:new(),
    {Frame, Udata} = wx:batch(fun () ->
        Fr = wxFrame:new(Wx, ?wxID_ANY, Title, [{size, {X, Y}}]),
        Sz = wxBoxSizer:new(abs(Dir)),
        wxWindow:setSizer(Fr, Sz),
        F = if
            Dir > 0 -> fun ?MODULE:comp/2;
            true -> fun ?MODULE:rcomp/2
        end,
        Ud = F(Sub, #context {parent=Fr, 
                           szflags=[{proportion, 1}, {flag, 0}, {border, 0}]}),
        wxFrame:connect(Fr, close_window),
        {Fr, Ud}
        end),
    wxWindow:show(Frame),
    loop(Frame, Udata),
    wx:destroy(),
    ok.

%% @doc Create a panel (box) with given sizer orientation (either vertical or horizontal; 
%% wxBoxSizer will be used). This widget honors the sign of the orientation flag: negative
%% values cause reverse order of placement (right to left for <tt>?wxHORIZONTAL</tt>,
%% and bottom to top for <tt>?wxVERTICAL</tt>).

panel(Dir, Sub) -> fun(C = #context{parent = X, szflags = F}) ->
    P = wxPanel:new(X),
    Sz = wxBoxSizer:new(abs(Dir)),
    wxWindow:setSizer(P, Sz),
    Ud = if
      Dir > 0 -> comp(Sub, C#context{parent = P});
      true -> rcomp(Sub, C#context{parent = P})
    end,
    addSelf(X, P, F),
    Ud
end.

%% @doc Create a panel without sizer.

panel(Sub) -> fun(C = #context{parent = X, szflags = F}) ->
    P = wxPanel:new(X),
    Ud = comp(Sub, C#context{parent = P}),
    addSelf(X, P, F),
    Ud
end.

%% @doc Create a panel with GridSizer. Number of columns
%% is specified upon creation; rows are added automatically
%% as children are added. This widget does not allow reverse
%% placement of its subordinates.

grid(Cols, Sub) -> fun (C = #context{parent = X, szflags = F}) ->
    P = wxPanel:new(X),
    Sz = wxGridSizer:new(Cols),
    wxWindow:setSizer(P, Sz),
    Ud = comp(Sub, C#context{parent = P}),
    addSelf(X, P, F),
    Ud
end.

%% @doc Connect the parent to the list of events.

catchEvents(Es) -> fun (#context{parent = X, evtlink = E}) ->
    linkEvent(X, E, Es),
    ok
end.

%% @doc Connect the parent to the list of events explicitly setting parent window Id.
%% This may be useful when setting events capture for a panel which was created
%% without window Id specified.

catchEvents(Es, Id) -> fun (#context{parent = X, evtlink = E}) ->
    wxWindow:setId(X, Id),
    linkEvent(X, E, Es),
    ok
end.

%% @doc Create a button with given label and numeric ID. Mouse clicks on the button
%% will cause a <tt>command_button_clicked</tt> message to be passed to its event link.

button(T, I) -> fun (#context {parent = X, szflags = F, evtlink = E}) ->
    B = wxButton:new(X, I, [{label, T}]),
    addSelf(X, B, F),
    linkEvent(B, E, [command_button_clicked]),
    ok
end.

%% @doc Create a text label that can be updated. Any event received will be formatted
%% as specified by the first argument and displayed. The second argument specifies the
%% initial text displayed.

textLabel(Fmt, T) -> fun (#context {parent = X, szflags = F}) ->
    Tx = wxStaticText:new(X, -1, T),
    wxStaticText:wrap(Tx, -1),
    addSelf(X, Tx, F),
    fun(R, _) ->
        Z = io_lib:format(Fmt, [R]),
        wxStaticText:setLabel(Tx, Z),
        wxWindow:fit(X),
        P = wxWindow:getParent(X),
        if
          P /= null -> wxWindow:fit(P),
                       ok;
          true -> ok
        end
    end
end.

%% @doc Apply the given function to any event received, and send the result to the event link.

map(F) -> fun (#context {evtlink = E}) ->
    fun (R, _) ->
        Z = F(R),
        passEvent(Z, E)
    end
end.

%% @doc Apply the given function to any event received, but pass the event to the event
%% if the function returns a tuple {'just', E} where E is the value to be passed.

maybe(F) -> fun (#context {evtlink = E}) ->
    fun (R, _) ->
    Z = F(R),
        case Z of
            {'just', EE} -> passEvent(EE, E);
            _ -> ok
        end
    end
end.

%% @doc Always pass any event received unchanged.

always() -> fun(#context {evtlink = E}) -> E end.

%% @doc Never pass any event.

never() -> fun(#context {}) ->
    fun (_, _) -> ok end
end.

%% @doc Apply the given function fo any event received and the encapsulated state.
%% The widget keeps the state between messages. The value returned from the function
%% will be sent to the event link of this widget.

mapState(F, S) -> fun (#context {evtlink = E}) ->
    W = wx:get_env(),
    spawn_link(fun() -> wx:set_env(W), maploop(F, S, E) end)
end.

maploop(F, S0, E) ->
    receive
        Msg ->
            S1 = F(Msg, S0),
            passEvent(S1, E),
            maploop(F, S1, E)
end.

%% Not exported functions.

sercomp([H], X = #context {parent = P}, Pns) ->
    Z = comp(H, X),
    Szf = [{flag, ?wxALL bor ?wxALIGN_CENTER_VERTICAL}, {border, 0}, {proportion, 1}],
    [addSelf(P, Pn, Szf) || Pn <- Pns],
    Z;

sercomp([H|T], X = #context {parent = P}, Pns) ->
    Pn = wxPanel:new(P),
    Sz = wxBoxSizer:new(?wxHORIZONTAL),
    wxWindow:setSizer(Pn, Sz),
    Z = comp(H, X#context {parent = Pn}),
    Ch = wxWindow:getChildren(Pn),
    Pnss = if
      length(Ch) == 0 -> wxWindow:destroy(Pn), Pns;
      true -> [Pn|Pns]
    end,
    sercomp(T, X#context {evtlink = Z}, Pnss).

sercompr([H], X = #context {}) ->
    comp(H, X);

sercompr([H|T], X = #context {}) ->
    Z = comp(H, X),
    sercompr(T, X#context {evtlink = Z}).

parcomp([], _, Els) -> fun (R, _) -> 
    F = fun (D) -> passEvent(R, D) end,
    lists:foreach(F, Els)
end;

parcomp([H|T], X, Els) -> 
    Z = comp(H, X),
    parcomp(T, X, [Z|Els]).

hasSizer(F) ->
    S = wxWindow:getSizer(F),
    case S of
        {wx_ref, N, wxSizer, _} -> N /= 0;
        _ -> false
    end.

loop(Frame, Udata) ->
    receive
        #wx{event=#wxClose{}} ->
            wxWindow:destroy(Frame),
            ok;
        Msg ->
            io:format("Got ~p ~n", [Msg]),
            loop(Frame, Udata)
    end.



