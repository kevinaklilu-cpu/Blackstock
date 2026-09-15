from pathlib import Path

path = Path('Sources/Blackstock/Services/MasterVideoService.swift')
text = path.read_text()

old = '''    var audioParameters: [AVAudioMixInputParameters] = []
    if let originalAudio {
      let p = AVMutableAudioMixInputParameters(track: originalAudio)
      let profile = AudioMixProfileService.shared.profile(hasVoiceover: optionen.voiceover != nil, format: optionen.format)
      p.setVolume(profile.originalVolume, at: .zero)
      audioParameters.append(p)
    }
'''
new = '''    let audioProfile = AudioMixProfileService.shared.profile(
      hasVoiceover: optionen.voiceover != nil, format: optionen.format)
    var audioParameters: [AVAudioMixInputParameters] = []
    if let originalAudio {
      let p = AVMutableAudioMixInputParameters(track: originalAudio)
      p.setVolume(audioProfile.originalVolume, at: .zero)
      audioParameters.append(p)
    }
'''
if old not in text:
    raise SystemExit('Blackstock 100 audio profile anchor not found')
text = text.replace(old, new, 1)

old_voice = '        p.setVolume(1.0, at: .zero)\n        mixParameters.append(p)\n'
if old_voice not in text:
    raise SystemExit('Blackstock 100 voice mix anchor not found')
text = text.replace(old_voice, '        p.setVolume(audioProfile.voiceVolume, at: .zero)\n        mixParameters.append(p)\n', 1)

old_music = '        p.setVolume(0.10, at: .zero)\n        mixParameters.append(p)\n'
if old_music not in text:
    raise SystemExit('Blackstock 100 music mix anchor not found')
text = text.replace(old_music, '        p.setVolume(audioProfile.musicVolume, at: .zero)\n        mixParameters.append(p)\n', 1)

path.write_text(text)
print('BLACKSTOCK_100_AUDIO_HOTFIX_APPLIED')

player_path = Path('Sources/Blackstock/Views/YouTubePlayerView.swift')
player = player_path.read_text()
old_status = '          status = .failed(message)\n'
old_pattern = '      if case .failed(let message) = status {\n'
if old_status not in player or old_pattern not in player:
    raise SystemExit('Blackstock 100 player failure-state anchors not found')
player = player.replace(old_status, '          status = .failed(message, code)\n', 1)
player = player.replace(old_pattern, '      if case .failed(let message, _) = status {\n', 1)
player_path.write_text(player)
print('BLACKSTOCK_100_PLAYER_HOTFIX_APPLIED')

audit_path = Path('Build/Release-Audit.sh')
audit = audit_path.read_text()
old_models = 'MODELS=("$ROOT/Sources/Blackstock/Models/Models.swift" "$ROOT/Sources/Blackstock/Models/V11Models.swift" "$ROOT/Sources/Blackstock/Models/V12Models.swift")'
new_models = 'MODELS=("$ROOT/Sources/Blackstock/Models/Models.swift" "$ROOT/Sources/Blackstock/Models/V11Models.swift" "$ROOT/Sources/Blackstock/Models/V12Models.swift" "$ROOT/Sources/Blackstock/Models/Blackstock100Models.swift")'
if old_models not in audit:
    raise SystemExit('Blackstock 100 release audit model anchor not found')
audit_path.write_text(audit.replace(old_models, new_models, 1))
print('BLACKSTOCK_100_AUDIT_MODELS_HOTFIX_APPLIED')
