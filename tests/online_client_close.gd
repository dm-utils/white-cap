extends Node
## OnlineClient gets the lobby's match message when the server closes a moment later (as the relay does, ADR 009).
## A local websocket server plays the lobby; no internet needed. Closing in the same tick loses the message in native
## Godot (WebSocketPeer drops it), which is why the relay waits.
##   godot --headless --path . res://tests/online_client_close.tscn

const PORT := 18765

var server := TCPServer.new()
var peer: WebSocketPeer
var client: OnlineClient
var got: Array = []
var closed_code := -99
var sent := false
var sent_at := 0
var t0 := 0


func _ready() -> void:
	t0 = Time.get_ticks_msec()
	if server.listen(PORT, "127.0.0.1") != OK:
		print("FAIL cannot listen on ", PORT)
		get_tree().quit(1)
		return
	client = OnlineClient.new()
	add_child(client)
	client.message.connect(func(m: Dictionary) -> void: got.append(m))
	client.closed.connect(func(c: int) -> void: closed_code = c)
	client.open("ws://127.0.0.1:%d" % PORT)


func _process(_d: float) -> void:
	if peer == null and server.is_connection_available():
		peer = WebSocketPeer.new()
		peer.accept_stream(server.take_connection())
	if peer != null:
		peer.poll()
		if not sent and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			sent = true
			sent_at = Time.get_ticks_msec()
			peer.send_text(JSON.stringify({"type": "waiting", "players": 1}))
			peer.send_text(JSON.stringify({"type": "match", "room": "r", "slot": 0}))
		if sent and Time.get_ticks_msec() - sent_at > 300 and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.close(1000, "match found")
	if closed_code != -99 or Time.get_ticks_msec() - t0 > 5000:
		var types := got.map(func(m: Dictionary) -> String: return str(m.get("type")))
		var ok := types == ["waiting", "match"] and closed_code == 1000
		print(("ok   " if ok else "FAIL ") + "waiting and match delivered, then closed 1000: ", types, " ", closed_code)
		get_tree().quit(0 if ok else 1)
