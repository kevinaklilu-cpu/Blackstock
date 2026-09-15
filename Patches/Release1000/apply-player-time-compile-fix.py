from pathlib import Path

path = Path.cwd() / "Sources/Blackstock/Views/YouTubePlayerView.swift"
text = path.read_text()

wrong = '''  enum PlayerStatus: Equatable {\n    case loading\n    case ready\n    case playing\n    case paused\n    case time(Double)\n    case failed(String, Int?)\n  }'''
right = '''  enum PlayerStatus: Equatable {\n    case loading\n    case ready\n    case playing\n    case paused\n    case failed(String, Int?)\n  }'''
if wrong in text:
    text = text.replace(wrong, right, 1)
elif right not in text:
    raise SystemExit("PlayerStatus block missing")

event_old = '''  enum Event {\n    case ready\n    case playing\n    case paused\n    case failed(String, Int?)\n  }'''
event_new = '''  enum Event {\n    case ready\n    case playing\n    case paused\n    case time(Double)\n    case failed(String, Int?)\n  }'''
if event_new not in text:
    if event_old not in text:
        raise SystemExit("YouTubeEmbeddedPlayer.Event block missing")
    text = text.replace(event_old, event_new, 1)

path.write_text(text)
print("BLACKSTOCK_PLAYER_TIME_COMPILE_FIX_OK")
